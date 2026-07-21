#if os(iOS)
import Foundation
import Speech
import AVFoundation

/// 실시간 한국어 STT — 온디바이스 강제(프라이버시: 음성이 기기를 안 떠남, 사양서 §7).
/// 온디바이스 미지원이면 서버로 안 보내고 막고, UI가 텍스트 입력으로 유도한다.
///
/// **두 메커니즘 분리(세션 끊김 ≠ 받아쓰기 끝):**
/// 1) `isFinal`(짧은 침묵·온디바이스 길이한계 ~1분) = "한 조각 완성" 신호 → 조각을 `committedText`에
///    누적하고 **오디오 엔진은 살린 채 request+task만 재생성**. 이어 말하면 앞 내용이 안 사라지고 이어짐.
/// 2) 침묵 타이머(`autoStopSeconds`) = 사용자 대면 "말 끝남" 감지 → 자동 [완료]. **새 발화(텍스트 증가)에서만
///    리셋**하므로 짧은 멈춤은 안 끊고, 긴 침묵만 종료. `0`이면 타이머를 안 걸고 [완료]로만 종료.
///
/// **동시성(중요)**: `@MainActor`를 **쓰지 않는다**. @MainActor로 두면 이 클래스 안에서 만든
/// 콜백 클로저(오디오 탭·인식 완료·권한 완료)가 MainActor에 격리돼, AVFoundation/Speech가
/// 그걸 자기 스레드(concurrent 큐)에서 호출할 때 `dispatch_assert_queue_fail`로 크래시한다.
/// 대신 비격리 클래스로 두고 — @Published 갱신과 엔진 조작을 **전부 메인 큐로** 보낸다.
/// `@unchecked Sendable`: 위 규율(상태·엔진·조각 상태는 메인에서만 만짐)로 스레드 안전을 보장한다.
final class SpeechCapture: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case idle, recording, authDenied, unavailable, onDeviceUnavailable, failed(String)
    }

    @Published private(set) var transcript = ""
    @Published private(set) var status: Status = .idle
    /// 자동 종료까지의 침묵 진행률 0…1(마지막 발화 이후 경과 / autoStopSeconds). 새 발화면 0으로 리셋.
    /// UI 막대가 이 값으로 왼→오 채워진다. 자동 종료 꺼짐(0초)이면 항상 0.
    @Published private(set) var silenceProgress: Double = 0
    var isRecording: Bool { status == .recording }
    /// 자동 종료가 켜져 있는가(0=끄기). UI가 침묵 막대 노출 여부를 정할 때 쓴다.
    var autoStopEnabled: Bool { autoStopSeconds > 0 }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    // 원본 음성 녹음(설계 audio-capture-design §2) — **시트 세션 전체를 하나의 파일로**.
    // 조각 회전(tap 재설치)·[정지]→[재개](엔진 재시작)를 다 넘어 같은 파일에 이어 쓴다.
    // 파일은 [저장]/[취소] 때만 닫는다(그 전엔 계속 append = 모든 take 시간순 보존).
    private var audioTempURL: URL?
    private var audioFile: AVAudioFile?

    // 조각 누적 상태(전부 메인에서만 접근). transcript = committedText + (partial 있으면 " " + partial).
    private var committedText = ""            // isFinal로 확정된 이전 조각들
    private var partial = ""                   // 현재 조각의 진행 중 전사
    private var autoStopSeconds = SpeechSettings.defaultAutoStop
    private var lastActivity = Date()          // 마지막 새 발화 시각(침묵 경과 기준점)
    private var ticker: DispatchSourceTimer?   // 진행률 갱신 + 만료 감지 + 조각 회전(메인 큐, ~20fps)
    private let tickInterval = 0.05
    private var segmentGen = 0                  // 조각 세대 — 회전으로 취소된 옛 task의 낡은 콜백 무시용
    /// 이만큼 무성장(침묵)이면 조각을 **먼저** 커밋·회전. 버퍼 요청은 짧은 침묵에 isFinal을 안 주고,
    /// 온디바이스 인식기가 ~3초 침묵 뒤 자기 가설을 리셋한다 → 그 전에 우리가 커밋해야 내용이 안 사라진다.
    private let commitDebounce = 1.2

    /// ko-KR 온디바이스 인식 가능 여부.
    var onDeviceSupported: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    // MARK: 공개 제어 (콜백은 임의 큐에서 옴 → 엔진/상태는 메인으로 보낸다)

    /// 새 수집 시작 — 누적을 비우고 처음부터. (수집 시트 열릴 때)
    func start() { begin(seed: "", reset: true) }

    /// 재개 — 앞 내용을 유지하고 이어 듣는다. seed로 현재 편집칸 텍스트를 받아 수동 교정분도 보존.
    func resume(seed: String) { begin(seed: seed, reset: false) }

    func stop() {
        DispatchQueue.main.async {
            self.stopSilenceTicker()
            self.teardown()
            if self.status == .recording { self.status = .idle }
        }
    }

    private func begin(seed: String, reset: Bool) {
        let seededCommit = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        DispatchQueue.main.async {
            self.committedText = reset ? "" : seededCommit
            self.partial = ""
            self.transcript = self.committedText
            self.autoStopSeconds = SpeechSettings.autoStopSeconds
            if reset {
                // 새 수집 세션: 임시 오디오 파일 하나 준비(이후 정지/재개/조각회전 다 여기에 이어 씀).
                if let old = self.audioTempURL { AudioStore.deleteTemp(old) }
                self.audioFile = nil
                self.audioTempURL = AudioStore.newTempURL(sessionId: UUID().uuidString)
            }
        }
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            guard let self else { return }
            guard auth == .authorized else { self.set(.authDenied); return }
            AVAudioApplication.requestRecordPermission { [weak self] micOK in
                guard let self else { return }
                guard micOK else { self.set(.authDenied); return }
                DispatchQueue.main.async { self.beginOnMain() }
            }
        }
    }

    // MARK: 내부 — 엔진 조작은 항상 메인에서

    private func beginOnMain() {
        guard let recognizer, recognizer.isAvailable else { status = .unavailable; return }
        guard onDeviceSupported else { status = .onDeviceUnavailable; return }   // 서버로 안 보냄
        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .default)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            // startSegment가 inputNode를 접근·탭 설치 → 그래프에 노드가 생긴다. 이걸 prepare/start보다
            // **먼저** 해야 한다. 노드 없이 prepare/start하면 AVAudioEngine Initialize가
            // `inputNode != nullptr || outputNode != nullptr` assertion으로 크래시한다.
            openAudioFileIfNeeded()       // 세션 첫 진입에만 파일 생성(재개 땐 기존 파일 유지해 이어 씀)
            try startSegment()            // 첫 조각(request+task+tap) — 반드시 start 전에
            engine.prepare()
            try engine.start()
            status = .recording
            startSilenceTicker()          // 말이 없으면 autoStopSeconds 뒤 자동 [완료] + 진행률 갱신
        } catch {
            status = .failed(error.localizedDescription); teardown()
        }
    }

    /// 한 인식 조각 시작 — 이전 조각을 정리하고 새 request+task+tap 설치. 엔진은 살아있다고 가정
    /// (첫 조각·isFinal 재생성·침묵 회전 공용). 이전 task는 cancel하고, 그 낡은 콜백은 세대(gen)로 무시한다.
    private func startSegment() throws {
        guard let recognizer else { throw SpeechError.unavailable }
        let input = engine.inputNode
        input.removeTap(onBus: 0)          // 이전 조각 tap 정리(첫 조각이면 no-op)
        request?.endAudio()                // 이전 request 종료
        task?.cancel()                     // 이전 task 취소(그 콜백은 낡은 gen이라 handle에서 무시됨)

        segmentGen &+= 1
        let gen = segmentGen
        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = true   // 온디바이스 강제(외부 전송 없음)
        request = req

        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw SpeechError.badFormat
        }
        // 탭 콜백은 오디오 스레드에서 돈다 — 클래스가 비격리라 클로저도 비격리(안전).
        // req.append(STT) + 같은 버퍼를 세션 오디오 파일에도 기록(원본 보존). 파일은 이미 열려 있고,
        // 닫기(nil)는 항상 tap 제거 뒤에만 하므로 이 시점 audioFile은 유효하거나 nil(무시).
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            req.append(buffer)
            self?.writeAudio(buffer)
        }
        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            let text = result?.bestTranscription.formattedString   // Sendable 값만 취함
            let isFinal = result?.isFinal ?? false
            self.handle(gen: gen, text: text, isFinal: isFinal, error: error != nil)
        }
    }

    /// 인식 콜백 처리(메인으로). 낡은 세대(gen) 콜백은 무시(회전으로 취소된 옛 task의 잔여·취소 콜백).
    /// partial 갱신 → 표시 재계산 → 새 텍스트면 침묵 기준점 리셋. isFinal(SFSpeech 자체 엔드포인트·
    /// ~1분 한계)이면 커밋 후 재생성. 침묵으로 인한 커밋은 티커의 회전이 담당한다.
    private func handle(gen: Int, text: String?, isFinal: Bool, error: Bool) {
        DispatchQueue.main.async {
            guard self.status == .recording, gen == self.segmentGen else { return }
            if error {
                self.status = .failed("음성 인식이 중단됐어요")
                self.stopSilenceTicker(); self.teardown(); return
            }
            let seg = text ?? ""
            // 새 발화(현재 조각 텍스트 증가)에서만 침묵 기준점 리셋 — 짧은 멈춤은 안 끊고 긴 침묵만 종료.
            let grew = seg.count > self.partial.count
            self.partial = seg
            self.transcript = self.display()
            if !isFinal {
                if grew { self.resetSilence() }
                return
            }
            self.commitSegment()
            do { try self.startSegment() }
            catch { self.status = .failed("이어 듣기 재시작 실패"); self.stopSilenceTicker(); self.teardown() }
        }
    }

    /// 현재 조각(partial)을 committedText에 접어 넣는다. 표시값은 그대로 유지(깜빡임 없음).
    private func commitSegment() {
        let seg = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if !seg.isEmpty {
            committedText = committedText.isEmpty ? seg : committedText + " " + seg
        }
        partial = ""
        transcript = display()
    }

    private func display() -> String {
        let p = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        if p.isEmpty { return committedText }
        return committedText.isEmpty ? p : committedText + " " + p
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)   // 항상 먼저 — in-flight 콜백 차단 후에 파일을 닫는다
        if engine.isRunning { engine.stop() }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: 원본 음성 파일 (세션 전체 하나 · 정지/재개 넘어 이어 씀)

    /// 세션 오디오 파일을 (없으면) 연다 — 첫 start에만 생성, 재개 땐 기존 파일 유지해 이어 쓴다.
    private func openAudioFileIfNeeded() {
        guard audioFile == nil, let url = audioTempURL else { return }
        let fmt = engine.inputNode.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { return }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: fmt.sampleRate,
            AVNumberOfChannelsKey: fmt.channelCount,
        ]
        audioFile = try? AVAudioFile(forWriting: url, settings: settings)
    }

    /// tap 버퍼를 세션 오디오 파일에 기록(오디오 스레드). **1차: 직접 쓰기.** 파일 포맷은 첫 start의
    /// 입력 포맷으로 고정 → 같은 기기에서 정지→재개하면 포맷이 일치해 그대로 이어 쓴다(연속 단일 파일).
    /// 만약 재개 중 오디오 경로가 바뀌어 포맷이 달라지면 그 조각은 건너뛴다(드문 경우) — 이 상황이
    /// 실기기에서 실제로 문제되면 설계 §2 폴백(재개 구간별 세그먼트 → [저장] 때 이어붙이기)으로 전환한다.
    private func writeAudio(_ buffer: AVAudioPCMBuffer) {
        guard let file = audioFile, buffer.format == file.processingFormat else { return }
        try? file.write(from: buffer)
    }

    /// [저장](메인 호출): 엔진 정지·파일 닫기(flush·moov) 후 임시 URL 반환(내용 없으면 nil).
    /// 이후 caller가 `AudioStore.finalize`로 `<uuid>.m4a`에 확정(불변)한다.
    func finishAndURL() -> URL? {
        stopSilenceTicker()
        teardown()                 // tap 제거 포함 → 이제 파일 닫아도 안전
        audioFile = nil            // 닫기(release = m4a 컨테이너 마무리·flush)
        if status == .recording { status = .idle }
        defer { audioTempURL = nil }
        guard let url = audioTempURL else { return nil }
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0 ? url : nil
    }

    /// [취소]/미저장 종료(메인 호출): 엔진 정지·파일 닫기·임시 삭제.
    func cancelAndDiscard() {
        stopSilenceTicker()
        teardown()
        audioFile = nil
        if status == .recording { status = .idle }
        if let url = audioTempURL { AudioStore.deleteTemp(url) }
        audioTempURL = nil
    }

    // MARK: 침묵 티커 (메인 큐 — 조각 회전 + 진행률 갱신 + 자동 [완료])

    /// ~20fps 티커. **항상** 돈다(자동종료 0이어도 조각 회전은 필요). 진행률 계산·자동종료만
    /// autoStopSeconds>0일 때. 0초(끄기)면 막대는 0 고정, 침묵으론 안 끝냄([완료] 버튼으로만).
    private func startSilenceTicker() {
        stopSilenceTicker()
        lastActivity = Date()
        silenceProgress = 0
        let t = DispatchSource.makeTimerSource(queue: .main)
        t.schedule(deadline: .now() + tickInterval, repeating: tickInterval)
        t.setEventHandler { [weak self] in self?.tick() }
        ticker = t
        t.resume()
    }

    /// 매 틱: ① 침묵 commitDebounce 지나고 partial 있으면 **먼저 커밋·회전**(내용 보존 — 원인 수정).
    /// ② autoStopSeconds>0이면 진행률 갱신, 다 차면 자동 [완료].
    private func tick() {
        guard status == .recording else { return }
        let elapsed = Date().timeIntervalSince(lastActivity)

        // ① SFSpeech 리셋(~3초) 전에 우리가 조각을 커밋·회전 → 이어 말해도 앞 내용 유지.
        if !partial.isEmpty && elapsed >= commitDebounce {
            commitSegment()                 // partial → committedText (표시 그대로)
            do { try startSegment() }        // 새 request로 회전(옛 task는 낡은 gen이라 무시됨)
            catch { status = .failed("이어 듣기 재시작 실패"); stopSilenceTicker(); teardown(); return }
        }

        // ② 자동 종료 진행률(꺼져 있으면 막대 없음).
        guard autoStopSeconds > 0 else { return }
        let limit = Double(autoStopSeconds)
        silenceProgress = min(1, elapsed / limit)
        if elapsed >= limit { stop() }
    }

    /// 새 발화 감지 → 침묵 기준점(lastActivity)을 지금으로. **항상** 갱신해야 한다
    /// (조각 회전·자동종료 둘 다 이 기준점을 쓰므로 — 안 갱신하면 발화 중에도 회전이 폭주).
    /// 진행률 0 리셋(막대가 왼쪽으로)은 자동종료 켜졌을 때만 의미.
    private func resetSilence() {
        lastActivity = Date()
        if autoStopSeconds > 0 { silenceProgress = 0 }
    }

    private func stopSilenceTicker() {
        ticker?.cancel()
        ticker = nil
        silenceProgress = 0
    }

    // MARK: @Published 갱신은 메인 큐로

    private func set(_ s: Status) { DispatchQueue.main.async { self.status = s } }

    private enum SpeechError: Error { case unavailable, badFormat }
}
#endif
