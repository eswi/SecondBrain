import SwiftUI
import SecondBrainCore

/// 앱 안 수집 시트. iOS: 열리면 바로 한국어 STT 시작 → 실시간 전사 → 정지·교정 → [저장].
/// macOS: STT 없이 텍스트 입력. 저장 = 네이티브 항목 생성(미분류 → "새 기억들").
struct CaptureSheet: View {
    @ObservedObject var model: InboxModel
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    #if os(iOS)
    @StateObject private var speech = SpeechCapture()
    #endif

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                #if os(iOS)
                statusLine
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
        .onAppear { speech.start() }                          // 열리면 바로 STT
        .onChange(of: speech.transcript) { _, t in text = t } // 실시간 전사를 편집칸에
        .onDisappear { speech.stop() }
        #endif
    }

    private func save() {
        #if os(iOS)
        speech.stop()
        #endif
        // source: iOS는 음성 수집이 기본, macOS는 텍스트.
        #if os(iOS)
        let source = "voice"
        #else
        let source = "text"
        #endif
        model.capture(text: text, source: source)
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

    @ViewBuilder private var micControl: some View {
        HStack {
            Spacer()
            Button {
                if speech.isRecording { speech.stop() } else { speech.start() }
            } label: {
                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(speech.isRecording ? Palette.overdue : Palette.accent)
            }
            .buttonStyle(.plain)
            Spacer()
        }
    }
    #endif
}
