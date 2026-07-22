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

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                List {
                    Section {
                        row("연결된 폴더", model.needsFolder ? "미선택" : model.sourceLabel)
                        Button {
                            showPicker = true
                        } label: {
                            Label(model.needsFolder ? "폴더 선택" : "폴더 변경", systemImage: "folder")
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

                    Section {
                        NavigationLink {
                            ClassificationManagerView()
                        } label: {
                            Label("분류 관리", systemImage: "square.grid.2x2")
                                .foregroundStyle(Palette.textPrimary)
                        }
                        .listRowBackground(Palette.surface)
                    } header: { header("분류") } footer: {
                        Text("지금은 보기용 — 실제 분류(§2)는 읽기 전용이고, 재설계 후보는 검토 중 메모로 저장만 됩니다(자동 분류엔 안 쓰임).")
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
                        Button {
                            Task { await model.classifyUnclassified() }
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
                        .disabled(!keySaved || model.unclassifiedItems.isEmpty || {
                            if case .running = model.classifyPhase { return true } else { return false }
                        }())
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
    }

    /// 자동 분류 안내 + 마지막 실행 결과. 키는 이 기기 Keychain에만 저장(§7).
    private var classifyFooter: String {
        let base = "미분류를 Claude가 종류·시점으로 분류합니다. 키는 이 기기 Keychain에만 저장되고 파일·iCloud엔 안 담깁니다. \"새로운 기억\" 화면을 아래로 당겨도 분류할 수 있습니다."
        switch model.classifyPhase {
        case .done(let n):     return n > 0 ? "\(base)\n방금 \(n)개를 분류했습니다." : base
        case .failed(let msg): return "\(base)\n실패: \(msg)"
        default:               return base
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
