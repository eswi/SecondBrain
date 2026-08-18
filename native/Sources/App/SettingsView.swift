import SwiftUI
import UniformTypeIdentifiers
import SecondBrainCore

extension View {
    /// 그룹 리스트 스타일 — iOS는 insetGrouped, macOS는 지원되는 inset.
    /// (insetGrouped는 macOS 미지원 → 플랫폼별로 맞는 스타일을 쓴다.)
    @ViewBuilder func groupedListStyle() -> some View {
        #if os(iOS)
        self.listStyle(.insetGrouped)
        #else
        self.listStyle(.inset)
        #endif
    }
}

/// 설정 — 폴더 연결·데이터 현황·앱 정보. (기존 "원칙" 탭 자리를 대체)
/// 수집([+])은 하단 버튼으로 풀지 않는다(별도 설계, 보류) — 이 탭은 운영·정보용.
struct SettingsView: View {
    @ObservedObject var model: InboxModel
    @State private var showPicker = false
    @AppStorage(PrincipleSettings.activeCountKey) private var principleN = PrincipleSettings.defaultActiveCount
    #if os(iOS)
    @AppStorage(SpeechSettings.autoStopKey) private var sttAutoStop = SpeechSettings.defaultAutoStop
    #endif
    @State private var apiKeyInput = ""
    @State private var keySaved = KeychainStore.hasKey
    /// 자동 분류 일시 중지 안내(2026-08-18). `ClassifyPause` 참조.
    @State private var showClassifyPaused = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                List {
                    Section {
                        row("연결된 폴더", folderStatusLabel)
                        Button {
                            showPicker = true
                        } label: {
                            Label(model.folderLink.isLinked ? "폴더 변경" : "폴더 선택", systemImage: "folder")
                                .foregroundStyle(Palette.accent)
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("데이터") }

                    Section {
                        Stepper(value: $principleN, in: 1...PrincipleSettings.maxActiveCount) {
                            HStack {
                                Text("각인 동작 개수").foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text("\(principleN)").foregroundStyle(Palette.textSecondary).monospacedDigit()
                            }
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("원칙") } footer: {
                        Text("상단 원칙 영역에 노출되는 상위 개수. 원칙이 이보다 적으면 있는 만큼만.")
                            .font(.caption2).foregroundStyle(Palette.textTertiary)
                    }

                    #if os(iOS)
                    Section {
                        Stepper(value: $sttAutoStop, in: SpeechSettings.minAutoStop...SpeechSettings.maxAutoStop) {
                            HStack {
                                Text("받아쓰기 자동 종료").foregroundStyle(Palette.textPrimary)
                                Spacer()
                                Text(sttAutoStop == 0 ? "끄기" : "\(sttAutoStop)초")
                                    .foregroundStyle(Palette.textSecondary).monospacedDigit()
                            }
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("음성") } footer: {
                        Text("마지막 말이 끝난 뒤 이만큼 침묵이 지속되면 자동으로 받아쓰기를 끝냅니다. 말하는 중이나 짧은 멈춤은 안 끊고 이어갑니다. 0(끄기)이면 침묵으로 끝내지 않고 [완료] 버튼으로만 종료합니다.")
                            .font(.caption2).foregroundStyle(Palette.textTertiary)
                    }
                    #endif

                    Section {
                        row("Claude API 키", keySaved ? "저장됨" : "미설정")
                        HStack {
                            SecureField("API 키 붙여넣기", text: $apiKeyInput)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                #endif
                                .disableAutocorrection(true)
                                .foregroundStyle(Palette.textPrimary)
                            Button("저장") {
                                KeychainStore.saveAPIKey(apiKeyInput)
                                keySaved = KeychainStore.hasKey
                                apiKeyInput = ""
                            }
                            .foregroundStyle(Palette.accent)
                            .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        .listRowBackground(Palette.surface)
                        if keySaved {
                            Button(role: .destructive) {
                                KeychainStore.deleteAPIKey(); keySaved = false
                            } label: { Text("키 지우기") }
                            .listRowBackground(Palette.surface)
                        }
                        // **일시 중지됐다** (2026-08-18 · `ClassifyPause`). 옛 동작:
                        // `Task { await model.classifyUnclassified() }`. **호출만 막는다** — 기능은 살아 있다.
                        //
                        // ⚠️ **`.disabled(...)`를 뗐다.** 옛 조건(키 없음·미분류 0·진행 중)으로 회색이 되면
                        // **눌러도 안내가 안 뜬다** — "왜 안 되나"를 사람이 알 길이 없어진다. 지금은
                        // 눌리는 것이 안내를 내미는 유일한 길이므로 열어 둔다.
                        // 진행 표시(`classifyPhase == .running`) 가지는 남겼다 — 재개할 때 그대로 쓴다.
                        Button {
                            showClassifyPaused = true
                        } label: {
                            HStack {
                                if case .running = model.classifyPhase {
                                    ProgressView().controlSize(.small)
                                    Text("분류 중…").foregroundStyle(Palette.textSecondary)
                                } else {
                                    Label("지금 분류하기 (\(model.unclassifiedItems.count))",
                                          systemImage: "sparkles")
                                        .foregroundStyle(Palette.accent)
                                }
                            }
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("지능 (자동 분류)") } footer: {
                        Text(classifyFooter).font(.caption2).foregroundStyle(Palette.textTertiary)
                    }

                    Section {
                        row("총 기억", "\(model.totalMemoryCount)")
                        row("새 기억 · 살아있는 기억", "\(model.unconfirmedCount) · \(model.confirmedCount)")
                        row("완료 · 삭제", "\(model.doneItems.count) · \(model.deletedCount)")
                        row("이 기기", model.deviceId)
                    } header: { header("현황") }

                    Section {
                        row("SecondBrain", "네이티브 v1")
                    } header: { header("앱") }
                }
                .groupedListStyle()
                .scrollContentBackground(.hidden)
                .background(Palette.bg)
            }
            .navigationTitle("설정")
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
        // 자동 분류 일시 중지 안내(2026-08-18) — 문구는 `ClassifyPause` 한 곳에 둔다(당겨서 분류와 공유).
        .alert(ClassifyPause.title, isPresented: $showClassifyPaused) {
            Button("확인", role: .cancel) {}
        }
    }

    /// 자동 분류 안내 + 마지막 실행 결과. 키는 이 기기 Keychain에만 저장(§7).
    private var classifyFooter: String {
        // **문구는 사용자가 정한다**(2026-08-18). 옛 마지막 문장 *"「새로운 기억」 화면을 아래로 당겨도
        // 분류할 수 있습니다"*는 **1-D가 그 경로를 막아 사실이 아니게 됐다** → 중지 안내로 갈았다.
        let base = "미분류를 Claude가 종류·시점으로 분류합니다. 키는 이 기기 Keychain에만 저장되고 파일·iCloud엔 안 담깁니다. 자동 분류는 다시 만드는 중이라 지금은 멈춰 있어요."
        switch model.classifyPhase {
        case .done(let n):     return n > 0 ? "\(base)\n방금 \(n)개를 분류했습니다." : base
        case .failed(let msg): return "\(base)\n실패: \(msg)"
        default:               return base
        }
    }

    /// **「연결된 폴더」 — 다섯 상태를 갈라 보인다**(사양서 §0-A-1, 문구 확정 2026-08-06).
    /// 옛 `(빈 폴더)` 하나가 **못 연다·받는 중·비었다·정상을 전부 덮고 있었다.**
    ///
    /// **개수를 보이는 이유:** 잘 돌고 있다는 것이 한눈에 보이고, **숫자가 줄면 그 자체가 신호**가 된다
    /// (일부만 내려받힌 경우도 여기서 작은 수로 드러난다).
    /// **"못 연다"에만 안심을 붙인다** — 좁은 줄에 넣는 것은 보통 과하지만,
    /// **이 줄을 보러 온 사람은 이미 놀란 뒤**다.
    private var folderStatusLabel: String {
        switch model.folderLink {
        case .notChosen:        return "안 골랐음"
        case .unreachable:      return "연결 안 됨 — 기억은 안전"
        case .downloading:      return "내려받는 중"
        case .empty:            return "\(model.folderName) · 비어 있음"
        // **"파일"을 붙인다** — "3개"만 있으면 무엇이 3개인지 화면에서 알 수 없다.
        // 줄 이름이 「연결된 폴더」이므로 세는 것은 파일 수가 맞다.
        case .ok(let files):    return "\(model.folderName) · 파일 \(files)개"
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(Palette.textPrimary)
            Spacer()
            Text(value).foregroundStyle(Palette.textSecondary).font(.callout).lineLimit(1)
        }
        .listRowBackground(Palette.surface)
    }

    private func header(_ t: String) -> some View {
        Text(t).font(.caption).foregroundStyle(Palette.textTertiary).textCase(nil)
    }
}
