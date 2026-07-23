import SwiftUI
import SecondBrainCore
#if os(iOS)
import UIKit
#endif

/// 앱 안 수집 시트. iOS: 열리면 바로 한국어 STT 시작 → 실시간 전사 → 정지·교정 → [저장].
/// macOS: STT 없이 텍스트 입력. 저장 = 네이티브 항목 생성(미분류 → "새 기억들").
struct CaptureSheet: View {
    @ObservedObject var model: InboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saved = false   // [저장]으로 확정됐는지 — onDisappear의 임시 음성·사진 정리 판단용
    #if os(iOS)
    @StateObject private var speech = SpeechCapture()
    @State private var showCamera = false
    @State private var photoTemp: URL?                       // 촬영한 임시 사진(저장 시 확정 / 취소 시 삭제)
    @StateObject private var location = LocationProvider()   // 촬영 위치(사진 EXIF에만 · 그릇엔 안 감)
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
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("저장") { save() }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .onAppear { speech.start() }                          // 열리면 바로 STT(+ 원본 음성 녹음)
        .onChange(of: speech.transcript) { _, t in text = t } // 실시간 전사를 편집칸에
        .onDisappear {                                        // 미저장 종료 → 임시 음성·사진 삭제
            location.stop()
            if !saved {
                speech.cancelAndDiscard()
                if let p = photoTemp { PhotoStore.deleteTemp(p) }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraCapture { img in
                if let old = photoTemp { PhotoStore.deleteTemp(old) }   // 다시 찍기 → 이전 임시 삭제(고아 방지)
                // 촬영마다 **고유** 임시 경로 → photoTemp(URL)이 바뀌어 SwiftUI가 새 썸네일을 다시 그린다.
                // (같은 경로에 덮으면 URL 불변 → 재렌더 안 돼 옛 썸네일이 남는 버그.)
                // 촬영 위치를 사진 EXIF에 박는다(있으면). 없으면 GPS 없이 저장(graceful).
                photoTemp = PhotoStore.saveCaptured(img, location: location.last, sessionId: UUID().uuidString)
            }
            .ignoresSafeArea()
        }
        #endif
    }

    private func save() {
        // source: iOS는 음성 수집이 기본, macOS는 텍스트.
        #if os(iOS)
        // 엔진 정지 + 세션 음성 파일 닫기 → 임시 URL(모든 take 이어진 하나). capture가 <uuid>.m4a로 확정.
        let audioURL = speech.finishAndURL()
        model.capture(text: text, source: "voice", audioTemp: audioURL, photoTemp: photoTemp)
        #else
        model.capture(text: text, source: "text")
        #endif
        saved = true
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
                    showCamera = true
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
