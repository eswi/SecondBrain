import SwiftUI
import SecondBrainCore
#if os(iOS)
import UIKit
#endif

/// 앱 안 수집 시트. iOS: 열리면 바로 한국어 STT 시작 → 실시간 전사 → 정지·교정 → [저장].
/// macOS: STT 없이 텍스트 입력. 저장 = 네이티브 항목 생성(미분류 → "새 기억들").
///
/// **[저장]은 여기서 끝나지 않는다** — 그 기억의 **상세 화면**으로 이어진다(2026-08-30 사용자 결정):
/// *"저장하기 누르면 지금 저장된 기억의 '상세 화면'으로 넘어가게 해줘. 거기서 내용이나 자료 추가하고
/// '기억하기'까지 선택하게 이어지는 것이 좋겠어."* 미는 것은 `InboxView`다(`model.openDetailId`).
///
/// ## ⛔⛔ 이 시트의 `onAppear`·`onDisappear`는 **「열림·닫힘」이 아니다** (2026-08-30에 물렸다)
///
/// 사진을 찍으면 **`UIImagePickerController`가 `.fullScreen` 모달로** 이 시트를 덮는다.
/// 그러면 UIKit이 밑에 있는 호스팅 컨트롤러에 `viewDidDisappear`를 주고, 닫힐 때 `viewDidAppear`를
/// 준다 → SwiftUI가 그것을 **`onDisappear` / `onAppear`로 그대로 흘린다.**
///
/// | 언제 | 무엇이 불렸나 | 무슨 일이 났나 |
/// |---|---|---|
/// | 카메라가 **열릴 때** | `onDisappear` | `speech.cancelAndDiscard()`가 돌아 **녹음한 원본 음성이 지워졌다** · 먼저 붙인 사진도 |
/// | 카메라가 **닫힐 때** | `onAppear` | `speech.start()`가 다시 돌아 `transcript`가 `""`로 리셋 → **받아쓰기한 글이 사라졌다** |
///
/// 사용자 신고(2026-08-30): *"음성을 녹음한 후 사진을 추가하면 … 저장되어 있던 내용들이 사라짐.
/// 그래서 기록을 다시 해야 함."* **텍스트만이 아니라 음성 파일까지 잃고 있었다.**
///
/// ✅ **그래서 둘을 표시 둘로 갈랐다:** `didStart`(시작은 한 번만) · `cameraOpen`(덮는 동안은 종료가 아니다).
/// ⛔ **`onAppear`에서 다시 `start()`하게 되돌리지 말 것** — 그 한 줄이 이 버그였다.
/// ★ **그리고 정리를 [취소] 버튼이 직접 한다** — 수명 콜백에만 맡기면 이런 식으로 조용히 어긋난다.
struct CaptureSheet: View {
    @ObservedObject var model: InboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = false   // [저장]으로 확정됐는지 — 임시 음성·사진 정리 판단용
    #if os(iOS)
    @StateObject private var speech = SpeechCapture()
    @State private var photoTemp: URL?                       // 촬영한 임시 사진(저장 시 확정 / 취소 시 삭제)
    @StateObject private var location = LocationProvider()   // 촬영 위치(사진 EXIF에만 · 그릇엔 안 감)
    /// STT를 **한 번만** 시작하려는 표시 — `onAppear`는 카메라가 닫힐 때도 다시 온다(위 ⛔ 표).
    @State private var didStart = false
    /// 카메라가 이 시트를 **덮고 있나** — 덮는 동안 오는 `onDisappear`는 **종료가 아니다**(위 ⛔ 표).
    @State private var cameraOpen = false
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                #if os(iOS)
                statusLine
                if speech.isRecording && speech.autoStopEnabled {
                    SilenceBar(progress: speech.silenceProgress)
                }
                #endif
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border))
                    .frame(minHeight: 160)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("말하거나 입력하세요").font(.body)
                                .foregroundStyle(Palette.textTertiary).padding(18).allowsHitTesting(false)
                        }
                    }
                #if os(iOS)
                micControl
                photoControl
                #endif
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Palette.bg.ignoresSafeArea())
            .navigationTitle("새 기억")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        // ⛔ **아래로 쓸어 닫는 것을 막는다** (2026-08-30 사용자 지시: *"수집 화면 어디를 누르든
        //    터치하여 아래로 스와이프하면 화면이 취소되고 사라짐. 취소 버튼이 있으니 이 기능은 지워버리세요."*)
        //    ★ 이것이 **데이터를 잃는 길이기도 했다** — 쓸어 닫히면 받아쓰기·녹음이 그대로 버려졌다.
        //    나가는 길은 **[취소]와 [저장] 둘뿐**이다.
        .interactiveDismissDisabled(true)
        #if os(iOS)
        .onAppear {
            // ⛔ **카메라가 닫힐 때도 여기 온다**(머리주석 표) — 그때 다시 start()하면 받아쓰기가 지워진다.
            guard !didStart else { return }
            didStart = true
            speech.start()                                    // 열리면 바로 STT(+ 원본 음성 녹음)
        }
        .onChange(of: speech.transcript) { _, t in text = t } // 실시간 전사를 편집칸에
        .onDisappear {
            // ⛔ **카메라가 열릴 때도 여기 온다**(머리주석 표) — 그때 정리하면 녹음·사진이 사라진다.
            guard !cameraOpen else { return }
            location.stop()
            if !saved { discardTemps() }                      // 미저장 종료 → 임시 음성·사진 삭제
        }
        #endif
    }

    private func save() {
        // source: iOS는 음성 수집이 기본, macOS는 텍스트.
        #if os(iOS)
        // 엔진 정지 + 세션 음성 파일 닫기 → 임시 URL(모든 take 이어진 하나). capture가 <uuid>.m4a로 확정.
        let audioURL = speech.finishAndURL()
        let newId = model.capture(text: text, source: "voice", audioTemp: audioURL, photoTemp: photoTemp)
        #else
        let newId = model.capture(text: text, source: "text")
        #endif
        saved = true
        // 저장한 그 기억의 **상세 화면**으로 이어 간다(머리주석) — 미는 것은 `InboxView`다.
        // ⚠️ `model`은 이 시트보다 오래 살므로 dismiss 뒤에도 신호가 남는다.
        if let newId { model.openDetailId = newId }
        dismiss()
    }

    /// [취소] — 임시 음성·사진을 **여기서 직접** 버리고 닫는다.
    /// ⛔ `onDisappear`에만 맡기지 않는다 — 그 콜백은 카메라가 덮을 때도 오기 때문이다(머리주석 표).
    private func cancel() {
        #if os(iOS)
        discardTemps()
        #endif
        dismiss()
    }

    #if os(iOS)
    @ViewBuilder private var statusLine: some View {
        switch speech.status {
        case .recording:
            Label("듣는 중…", systemImage: "waveform").font(.callout).foregroundStyle(Palette.accent)
        case .authDenied:
            Text("마이크·음성 인식 권한이 필요해요. 설정에서 허용해 주세요.")
                .font(.callout).foregroundStyle(Palette.overdue)
        case .onDeviceUnavailable:
            Text("이 기기에서 온디바이스 한국어 인식이 안 돼요. 음성은 기기 밖으로 보내지 않으니, 텍스트로 입력해 주세요.")
                .font(.callout).foregroundStyle(Palette.today).fixedSize(horizontal: false, vertical: true)
        case .unavailable:
            Text("음성 인식을 사용할 수 없어요. 텍스트로 입력해 주세요.")
                .font(.callout).foregroundStyle(Palette.today)
        case .failed(let msg):
            Text("음성 인식 오류: \(msg)").font(.caption).foregroundStyle(Palette.overdue)
        case .idle:
            EmptyView()
        }
    }

    /// 침묵 진행 막대 — 받아쓰기 네모 바로 위. 왼→오로 채워지며 자동 종료까지 남은 시간을 보여준다.
    /// 발화가 다시 시작되면 progress가 0으로 리셋되어 막대가 왼쪽으로 되돌아간다(반복).
    /// 끝에 가까우면(임박) 색을 경고색으로 바꿔 곧 종료됨을 알린다.
    private struct SilenceBar: View {
        let progress: Double
        var body: some View {
            let p = min(max(progress, 0), 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface)
                    Capsule()
                        .fill(p >= 0.75 ? Palette.overdue : Palette.accent)
                        .frame(width: geo.size.width * p)
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.05), value: p)
            .accessibilityLabel("자동 종료까지 남은 시간")
        }
    }

    @ViewBuilder private var micControl: some View {
        HStack {
            Spacer()
            Button {
                if speech.isRecording { speech.stop() } else { speech.resume(seed: text) }
            } label: {
                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(speech.isRecording ? Palette.overdue : Palette.accent)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }

    // MARK: 사진 첨부 (본문 먼저 → 그 위에 사진. photo-capture-design.md §4)
    // 활성 조건 = 본문 있음 + 녹음 중 아님. "원문 없는 기억"을 원천 차단(저장 버튼·capture guard와 3중).

    /// 본문(원문)이 있는가 — 공백만이면 없음으로 본다.
    private var hasText: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 카메라 활성 조건: 본문 있음 + 녹음 중 아님(오디오 세션 충돌·발화 끊김 방지 → "말 멈추면 활성화").
    private var canAttachPhoto: Bool { hasText && !speech.isRecording }

    /// 미저장 종료 → 임시 음성·사진 삭제. **[취소]와 `onDisappear` 둘이 부른다.**
    /// ⚠️ `photoTemp`를 nil로 내려 **두 번 지우려 들지 않게** 한다.
    private func discardTemps() {
        speech.cancelAndDiscard()
        if let p = photoTemp { PhotoStore.deleteTemp(p); photoTemp = nil }
    }

    /// 왜 못 누르는지 안내(활성일 땐 nil).
    private var photoHint: String? {
        if !hasText { return "먼저 말하거나 입력하세요" }
        if speech.isRecording { return "녹음을 멈춘 뒤 사진을 찍어요" }
        return nil
    }

    @ViewBuilder private var photoControl: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Button {
                    if speech.isRecording { speech.stop() }   // 방어(활성 조건상 이미 정지)
                    location.begin()                          // 프레이밍하는 동안 촬영 위치 취득(EXIF용)
                    // ⛔⛔ **present보다 먼저 올린다** — 카메라가 뜨는 순간 이 시트의 `onDisappear`가
                    //    불리고, 그때 이 표시가 아직 false면 **받아쓰기·녹음이 지워진다**(머리주석 표).
                    cameraOpen = true
                    // ⛔ **커버로 감싸지 않는다 — 모달로 띄운다**(2026-08-24 · `SystemCamera` 머리주석).
                    //    임베드하면 **가로에서 미리보기가 띠로 눌려 촬영이 안 된다.**
                    SystemCamera.present { img in
                        if let old = photoTemp { PhotoStore.deleteTemp(old) }   // 다시 찍기 → 이전 임시 삭제(고아 방지)
                        // 촬영마다 **고유** 임시 경로 → photoTemp(URL)이 바뀌어 SwiftUI가 새 썸네일을 다시 그린다.
                        // (같은 경로에 덮으면 URL 불변 → 재렌더 안 돼 옛 썸네일이 남는 버그.)
                        // 촬영 위치를 사진 EXIF에 박는다(있으면). 없으면 GPS 없이 저장(graceful).
                        photoTemp = PhotoStore.saveCaptured(img, location: location.last,
                                                            sessionId: UUID().uuidString)
                    } onFinish: {
                        // 찍었든 취소했든 · 못 띄웠든 반드시 온다 → 덮는 구간이 여기서 끝난다.
                        cameraOpen = false
                    }
                } label: {
                    Label(photoTemp == nil ? "사진 찍기" : "다시 찍기", systemImage: "camera.fill")
                        .font(.callout)
                }
                .buttonStyle(.bordered)
                .disabled(!canAttachPhoto)

                if let url = photoTemp, let thumb = UIImage(contentsOfFile: url.path) {
                    Image(uiImage: thumb).resizable().scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    Text("사진 1장 첨부됨").font(.caption).foregroundStyle(Palette.textSecondary)
                    Button {
                        PhotoStore.deleteTemp(url); photoTemp = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            if let hint = photoHint {
                Text(hint).font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
    }
    #endif
}
