#if os(iOS)
import Foundation
import Speech
import AVFoundation

/// 실시간 한국어 STT — 온디바이스 강제(프라이버시: 음성이 기기를 안 떠남, 사양서 §7).
/// 온디바이스 미지원이면 서버로 안 보내고 막고, UI가 텍스트 입력으로 유도한다.
///
/// **동시성(중요)**: `@MainActor`를 **쓰지 않는다**. @MainActor로 두면 이 클래스 안에서 만든
/// 콜백 클로저(오디오 탭·인식 완료·권한 완료)가 MainActor에 격리돼, AVFoundation/Speech가
/// 그걸 자기 스레드(concurrent 큐)에서 호출할 때 `dispatch_assert_queue_fail`로 크래시한다.
/// 대신 비격리 클래스로 두고 — @Published 갱신과 엔진 조작을 **전부 메인 큐로** 보낸다.
/// `@unchecked Sendable`: 위 규율(상태·엔진은 메인에서만 만짐)로 스레드 안전을 보장한다.
final class SpeechCapture: ObservableObject, @unchecked Sendable {
    enum Status: Equatable {
        case idle, recording, authDenied, unavailable, onDeviceUnavailable, failed(String)
    }

    @Published private(set) var transcript = ""
    @Published private(set) var status: Status = .idle
    var isRecording: Bool { status == .recording }

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    /// ko-KR 온디바이스 인식 가능 여부.
    var onDeviceSupported: Bool { recognizer?.supportsOnDeviceRecognition ?? false }

    // MARK: 공개 제어 (콜백은 임의 큐에서 옴 → 엔진/상태는 메인으로 보낸다)

    func start() {
        setTranscript("")
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

    func stop() {
        DispatchQueue.main.async {
            self.teardown()
            if self.status == .recording { self.status = .idle }
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

            let req = SFSpeechAudioBufferRecognitionRequest()
            req.shouldReportPartialResults = true
            req.requiresOnDeviceRecognition = true   // 온디바이스 강제(외부 전송 없음)
            request = req

            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                status = .failed("마이크 입력 형식을 읽을 수 없어요"); teardown(); return
            }
            // 탭 콜백은 오디오 스레드에서 돈다 — 클래스가 비격리라 클로저도 비격리(안전). 로컬 req만 만짐.
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                req.append(buffer)
            }
            engine.prepare()
            try engine.start()

            task = recognizer.recognitionTask(with: req) { [weak self] result, error in
                guard let self else { return }
                let text = result?.bestTranscription.formattedString   // Sendable 값만 취함
                let done = error != nil || (result?.isFinal ?? false)
                if let text { self.setTranscript(text) }
                if done { self.stop() }
            }
            status = .recording
        } catch {
            status = .failed(error.localizedDescription); teardown()
        }
    }

    private func teardown() {
        if engine.isRunning {
            engine.stop()
            engine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: @Published 갱신은 메인 큐로

    private func set(_ s: Status) { DispatchQueue.main.async { self.status = s } }
    private func setTranscript(_ t: String) { DispatchQueue.main.async { self.transcript = t } }
}
#endif
