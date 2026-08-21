import SwiftUI
import UniformTypeIdentifiers
import SecondBrainCore

extension View {
    /// 내비게이션 바 숨김(iOS 전용 placement — macOS에선 무시).
    @ViewBuilder func hiddenNavBar() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

/// "새로운 기억" 화면(다크) — 일상 화면(memory-philosophy.md §5).
/// 위→아래: 원칙 띠 · 지금 챙길 것 · 대시보드 · 새 기억들(미확정, 기본 오래된 순 · 역순 보기 토글).
/// 필터는 여기 없다 — 살아있는 기억 탭의 몫.
struct InboxView: View {
    @ObservedObject var model: InboxModel
    @State private var showPicker = false
    @State private var showCapture = false
    @State private var path = NavigationPath()
    // "새 기억들" 표시 순서 뒤집기 토글. **세션 한정**(탭 전환엔 유지, 앱 재실행 시 기본=오래된 순).
    // 데이터·성역은 불변 — model.newTab.newMemories는 늘 오래된 순(선입선출)이고, 여기서 보기 순서만 뒤집는다.
    @State private var reverseNewOrder = false
    /// 자동 분류 일시 중지 안내(2026-08-18). `ClassifyPause` 참조.
    @State private var showClassifyPaused = false
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                headerRow
                mediaMigrationBanner        // 자료를 iCloud로 옮기는 중(§8) — 목록 위. 없으면 자리도 안 차지한다
                if model.needsFolder {
                    folderPrompt
                    Spacer(minLength: 0)
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.bg.ignoresSafeArea())
            .hiddenNavBar()
            .navigationDestination(for: ResolvedItem.self) { DetailView(item: $0, model: model) }
            .navigationDestination(for: PrincipleListRoute.self) { _ in PrincipleListView(model: model, path: $path) }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
        .sheet(isPresented: $showCapture) { CaptureSheet(model: model) }
    }

    /// **자료 옮기기 배너** — 설계 `media-icloud-design.md` §8. **자리는 목록 위**(사용자가 고른 자리).
    ///
    /// 문구는 `MediaMigrationText`(Core)에서 온다 — **사용자가 고른 말이라 여기서 짓지 않는다.**
    /// 대개의 실행에서는 `mediaMigration`이 nil이라 **아무것도 안 보인다.**
    @ViewBuilder private var mediaMigrationBanner: some View {
        if let m = model.mediaMigration {
            HStack(spacing: 8) {
                if m.cappedDone {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent)
                } else {
                    ProgressView().controlSize(.small)
                }
                Text(m.cappedDone ? MediaMigrationText.cappedDone(moved: m.moved)
                                  : MediaMigrationText.progress(moved: m.moved, total: m.total))
                    .font(.callout).foregroundStyle(Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(Palette.surface2)
            .transition(.opacity)
        }
    }

    private var content: some View {
        let tab = model.newTab
        // 데이터는 그대로(오래된 순) — 토글이 켜지면 보기 순서만 뒤집는다.
        let orderedNew = reverseNewOrder ? Array(tab.newMemories.reversed()) : tab.newMemories
        return List {
            if !model.orderedPrinciples.isEmpty {
                Section {
                    // 밴드 전체가 하나의 버튼 — 아무 데나 터치 → 원칙 목록(§3). 상위 N개만, 순서대로 번호.
                    // (NavigationLink 대신 Button+path — List 자동 chevron(>) 제거.)
                    Button {
                        path.append(PrincipleListRoute())
                    } label: {
                        VStack(spacing: 6) {
                            ForEach(Array(model.orderedPrinciples.prefix(activeN).enumerated()), id: \.element.id) { idx, p in
                                PrincipleRow(item: p, number: idx + 1)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                    .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                } header: {
                    sectionTitle("원칙", count: model.principleCount,
                                 symbol: "star.fill", symbolColor: TypeCatalog.meta("principle").color)
                        .listRowInsets(EdgeInsets())
                }
            }

            if !tab.upcoming.isEmpty {
                Section {
                    ForEach(tab.upcoming, id: \.item.id) { entry in
                        UpcomingCard(entry: entry, model: model)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(entry.item) }
                            .swipeActions(edge: .leading) { doneDeferActions(entry.item) }
                            .contextMenu { itemActions(entry.item) }
                    }
                } header: {
                    sectionTitle("지금 챙길 것", count: tab.upcoming.count).listRowInsets(EdgeInsets())
                }
            }

            Section {
                DashboardRow(model: model)
                    .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Palette.bg).listRowSeparator(.hidden)
            }

            Section {
                if tab.newMemories.isEmpty {
                    emptyNewRow
                } else {
                    ForEach(orderedNew, id: \.id) { item in
                        MemoryRow(item: item, model: model, provisional: true)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) { confirmAction(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(item) }
                            .contextMenu { newItemActions(item) }
                    }
                }
            } header: {
                // 항목이 둘 이상일 때만 역순 토글을 보인다(하나 이하면 순서 의미 없음).
                sectionTitle("새 기억들", count: tab.newMemories.count,
                             trailing: tab.newMemories.count > 1 ? AnyView(reverseOrderToggle) : nil)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        // **당겨서 분류(pull-to-classify)는 일시 중지됐다** (2026-08-18 사용자 결정 — `ClassifyPause`).
        // 옛 동작: `await model.classifyUnclassified(auto: true, runningToast: false)`.
        // **호출만 막는다** — `classifyUnclassified`는 그대로 살아 있다(재개발 예정).
        .refreshable { showClassifyPaused = true }
        .alert(ClassifyPause.title, isPresented: $showClassifyPaused) {
            Button("확인", role: .cancel) {}
        }
    }

    // MARK: 헤더 (제목 + 폴더 아이콘, 한 줄)

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("새로운 기억").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
            // 폴더 관리는 설정으로 이관 — 여기는 수집(마이크). 폴더 없으면 온보딩 프롬프트가 처리.
            // ⚠️ **"비었다"에서도 마이크는 있어야 한다** — 그 화면이 "아래 마이크를 눌러"라고 말한다(§0-A-1).
            if model.folderLink.canCapture {
                Button { showCapture = true } label: {
                    Image(systemName: "mic.fill").font(.title3).foregroundStyle(Palette.accent)
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    // MARK: 스와이프 / 컨텍스트 액션

    @ViewBuilder private func confirmAction(_ item: ResolvedItem) -> some View {
        Button { model.confirm(item) } label: { Label("기억하기", systemImage: "checkmark.seal.fill") }.tint(Palette.accent)
    }
    @ViewBuilder private func deleteAction(_ item: ResolvedItem) -> some View {
        Button(role: .destructive) { model.pendingDelete = item } label: { Label("삭제", systemImage: "trash") }
            .tint(Palette.overdue)   // 전역 .tint(Palette.accent)(RootView)가 destructive 기본 빨강을 덮는다
    }
    /// 「지금 챙길 것」 왼쪽 스와이프: 완료(했어요)·미루기.
    ///
    /// **★ 완료·미루기 둘 다 확정 항목에만 그린다 (2026-08-18 사용자 결정).**
    /// 옛 주석은 *"완료·삭제는 그대로 둔다(§3이 미기억 항목에도 명시 허용)"* 였다. **그 근거가 바뀌었다** —
    /// `edit-policy.md` §3이 **[삭제]만 허용하는 것으로 좁혀졌다.** 임시 항목은 **상세에서 원문·성역·분류를
    /// 보고 판단한 뒤** [기억하기]를 누르는 구조인데, 목록에서 바로 완료가 되면 **아무것도 안 보고 처리**하게 된다.
    /// **버릴 길은 [삭제]가 지킨다** — 그건 미확정에도 남는다.
    ///
    /// ⚠️ **이건 방어선이다.** `InboxModel.partition`이 미확정을 「지금 챙길 것」에서 빼므로(2026-08-18)
    /// 정상 경로로는 미확정 항목이 여기 도달하지 않는다. 파티션이 바뀌어도 이 자리가 홀로 새지 않게 둔다.
    @ViewBuilder private func doneDeferActions(_ item: ResolvedItem) -> some View {
        if item.confirmed, !cycleAlreadyDone(item) {   // 이번 회차를 이미 닫았으면 안 그린다(dead action 방지)
            Button { model.markDone(item) } label: { Label(item.type == "recurrence" ? "했어요" : "완료", systemImage: "checkmark") }.tint(.green)
        }
        // 시점은 기억하기 뒤에만 정한다 (edit-policy §1-A).
        if item.confirmed {
            Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
        }
    }
    /// 시점 있는 항목(지금 챙길 것) 컨텍스트: 완료·미루기·삭제.
    /// **완료·미루기는 확정 항목만** — 근거·방어선 설명은 위 `doneDeferActions`와 같다.
    @ViewBuilder func itemActions(_ item: ResolvedItem) -> some View {
        if item.confirmed, !cycleAlreadyDone(item) {   // 이번 회차를 이미 닫았으면 안 그린다(dead action 방지)
            Button { model.markDone(item) } label: { Label(item.type == "recurrence" ? "했어요" : "완료", systemImage: "checkmark") }
        }
        if item.confirmed {   // 임시면 미루기 없음 (edit-policy §1-A)
            Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }
        }
        Button(role: .destructive) { model.pendingDelete = item } label: { Label("삭제", systemImage: "trash") }
            .tint(Palette.overdue)
    }
    /// 새 기억(미확정) 컨텍스트: **기억하기 · 삭제 둘뿐.**
    ///
    /// **★ 「미루기 (시점 붙임)」을 없앴다 (2026-08-14, 사용자 결정).** 이 섹션은 **전부 임시**이고
    /// 임시 항목에 시점을 붙이는 것이 정확히 `edit-policy.md` §1-A가 금지한 것이라, 남겨두면
    /// **절대 눌리지 않는 메뉴**가 된다(§7(a): 못 쓰는 칸은 회색으로 두지 않고 없앤다 — 같은 규칙의 적용).
    ///
    /// **★ 「완료」도 뺐다 (2026-08-18, 사용자 결정).** 임시 항목에서 사람이 할 일은 **살릴지 버릴지 정하는 것**
    /// 하나다. 목록에서 완료가 되면 **아무것도 안 보고 처리**하게 되고, 상세가 [삭제하기]·[기억하기] 둘만
    /// 내밀어 결정을 강요하는 구조를 목록이 우회한다.
    ///
    /// **⚠️ 이 변경으로 임시 항목을 완료할 길이 아예 없어진다.** 상세에도 없다 — 상세의 완료(`completionRow`)는
    /// **되풀이 분류 + 확정** 둘 다여야 그려진다(`DetailView.swift`의 `recurrenceSection`).
    /// **사용자가 그 편의를 포기하기로 정했다**(2026-08-18). `edit-policy.md` §3을 그에 맞춰 좁혔다.
    /// 버릴 길은 [삭제]가 지키고, 완료하려면 먼저 [기억하기]를 누른다.
    @ViewBuilder private func newItemActions(_ item: ResolvedItem) -> some View {
        Button { model.confirm(item) } label: { Label("기억하기 (살아있는 기억으로)", systemImage: "checkmark.seal.fill") }
        Button(role: .destructive) { model.pendingDelete = item } label: { Label("삭제", systemImage: "trash") }
            .tint(Palette.overdue)
    }

    func sectionTitle(_ title: String, count: Int,
                      symbol: String? = nil, symbolColor: Color = Palette.textSecondary,
                      trailing: AnyView? = nil) -> some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.caption).foregroundStyle(symbolColor)
            }
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            Spacer()
            trailing
        }
        .textCase(nil)
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
    }

    /// "새 기억들" 정렬 방향 토글 — 표시 순서만 뒤집는다(데이터·성역 불변). 세션 한정.
    /// 아이콘 = **현재** 보기 방향: 기본 오래된 순(오름차순)=arrow.up, 역순 최신 순(내림차순)=arrow.down.
    /// 역순(비기본)일 때 accent로 틴트해 "지금 뒤집혀 있음"을 알린다.
    private var reverseOrderToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { reverseNewOrder.toggle() }
        } label: {
            Image(systemName: reverseNewOrder ? "arrow.down" : "arrow.up")
                .font(.footnote.weight(.bold))
                .foregroundStyle(reverseNewOrder ? Palette.accent : Palette.textSecondary)
                .frame(width: 28, height: 22)   // 넉넉한 탭 타깃
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(reverseNewOrder ? "최신 순으로 보는 중 — 오래된 순으로" : "오래된 순으로 보는 중 — 최신 순으로")
    }

    private var emptyNewRow: some View {
        Text("새 기억이 없어요")
            .font(.callout).foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
    }

    /// **폴더 연결 안내 — 네 상태를 갈라 말한다**(사양서 §0-A-1, 문구 확정 2026-08-06).
    ///
    /// 여기가 하나였을 때 **연결이 끊긴 것과 비어 있는 것이 같게 보였다** —
    /// 정확히는 "못 연다"가 이 화면에 **도달조차 못 하고** 빈 목록만 떠서 **기억이 사라진 것처럼** 보였다.
    ///
    /// ⚠️ **"기억은 안전합니다"는 못 연다·받는 중에만 쓴다.** 비었다에 대고 말하면 **거짓일 수 있다** —
    /// 폴더는 열렸는데 파일이 사라진 경우도 그 상태로 오기 때문이다.
    /// ⚠️ **비었다는 사고가 아니다.** 새 폴더를 막 골랐을 때의 정상 상태이므로 경고하지 않는다.
    private var folderPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: promptIcon).font(.system(size: 44)).foregroundStyle(Palette.textTertiary)
            Text(promptTitle).font(.headline).foregroundStyle(Palette.textPrimary)
                .multilineTextAlignment(.center)
            Text(promptBody)
                .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            // 고르는 버튼은 폴더가 필요한 두 상태에만. 받는 중·비었다는 사람이 할 일이 없다.
            if model.folderLink == .notChosen || model.folderLink == .unreachable {
                Button(model.folderLink == .notChosen ? "폴더 선택" : "폴더 다시 선택") { showPicker = true }
                    .buttonStyle(.borderedProminent).tint(Palette.accent)
            }
            Spacer()
        }
        .padding()
    }

    private var promptIcon: String {
        switch model.folderLink {
        case .notChosen:   return "folder.badge.questionmark"
        case .unreachable: return "folder.badge.minus"
        case .downloading: return "icloud.and.arrow.down"
        default:           return "tray"
        }
    }
    private var promptTitle: String {
        switch model.folderLink {
        case .notChosen:   return "기억을 담을 폴더를 골라주세요"
        // 안심을 **제목 첫 줄**에 둔다 — 이 화면을 보는 사람은 기억이 사라진 것으로 보이는 순간에 있고,
        // 놀란 사람은 첫 줄만 읽는다.
        case .unreachable: return "기억은 안전합니다. 폴더 연결이 끊겼어요"
        case .downloading: return "아직 다 받아오지 못했어요"
        default:           return "아직 담은 기억이 없어요"
        }
    }
    private var promptBody: String {
        switch model.folderLink {
        case .notChosen:   return "iCloud Drive의 SecondBrain 폴더를 고르면\n기억이 이 기기에서도 열립니다."
        case .unreachable: return "파일은 iCloud에 그대로 있습니다.\n폴더를 다시 골라주세요."
        // **왜 비어 보이는지**를 말하는 유일한 자리 — 새 기기에서 처음 겪는 상태다.
        case .downloading: return "폴더는 열렸는데 파일이 아직 iCloud에서\n안 내려왔습니다. 곧 나타납니다."
        default:           return "아래 마이크를 눌러 말하거나 적어보세요."
        }
    }
}

// MARK: - 대시보드 (5숫자 가로: 원칙 · 챙길 것 · 새 기억 · 살아있는 기억 · 총 기억)
//          라벨 = 세 영역 이름과 일치(각 영역 개수를 세므로).

struct DashboardRow: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        HStack(spacing: 6) {
            tile("원칙", model.principleCount, TypeCatalog.meta("principle").color)
            tile("챙길 것", model.upcomingCount, Palette.overdue)
            tile("새 기억", model.unconfirmedCount, Palette.today)
            tile("살아있는 기억", model.confirmedCount, Palette.accent)
            tile("총 기억", model.totalMemoryCount, Palette.textSecondary)
        }
    }

    private func tile(_ label: String, _ n: Int, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(n)").font(.title3.weight(.bold)).monospacedDigit().foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 9).padding(.horizontal, 2)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
    }
}

// MARK: - 원칙 한 줄 (ambient) — 각자 cyan 박스

struct PrincipleRow: View {
    let item: ResolvedItem
    var number: Int? = nil            // 순서 번호(1,2,3…). 별 아이콘은 섹션 제목으로 옮김.
    /// ⚠️ **단계가 바뀔 때 다시 그리는 의존.** 글자를 `UILabel`로 바꾼 뒤로는 이게 없으면
    /// 접근성에서 글자 크기를 올려도 **이 줄만 안 커진다**(`PrincipleFont.size`가 안 갱신된다).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private var tint: Color { TypeCatalog.meta("principle").color }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            if let number {
                Text("\(number)").font(.callout.weight(.bold)).monospacedDigit()
                    .foregroundStyle(tint).frame(minWidth: 16, alignment: .trailing).padding(.top, 1)
            }
            // 좌우 맞춤 + 단어 중간 끊기 — **원칙 목록과 같은 짜임**(둘이 갈리면 두 화면이 갈린다).
            // 여기 글자 크기는 `.callout` 그대로다(목록은 +2pt다 — 그 차이는 유지한다).
            JustifiedText(text: item.raw ?? "", size: PrincipleFont.size - 2,
                          color: Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 그라데이션 대신 틴트 색을 균일하게 깐다(원칙 항목 전용).
        .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: Palette.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Palette.radius, style: .continuous).strokeBorder(tint.opacity(0.28)))
    }
}

// MARK: - 필터 칩 한 줄 (살아있는 기억 탭에서 사용)

struct FilterChipsBar: View {
    /// 필터 상태를 **바인딩으로** 받는다 → 살아있는 기억(model.filter)과 검색(독립 상태)이 같은 UI를
    /// 각자의 상태에 물려 재사용. 거르는 대상은 각 화면이 정한다(살아있는 기억 / 검색 결과 전체).
    @Binding var filter: TypeFilter

    /// **실제 존재하는 분류만** 칩으로 — 각 화면이 필터 전 데이터의 distinct 타입을 넘긴다.
    /// (고정 목록 아님 → 데이터에 주차위치가 있으면 자동으로 칩이 뜬다. `84f3152` 표시·메뉴 통일과 같은 뿌리.)
    let presentTypes: [String?]

    /// 노출 칩 순서: `ClassRegistry` 정본 순(기본층 6 → 유연층 주차), 미분류는 끝.
    /// 현재 선택된 타입이 present에서 사라져도(마지막 기억이 바뀜) **계속 노출** → 보이지 않는 필터에 갇히지 않게.
    private var orderedTypes: [String?] {
        var keys = Set(presentTypes)
        if case .type(let k) = filter { keys.insert(k) }   // 선택된 필터는 present 여부와 무관하게 유지
        let order = ClassRegistry.assignable.map { $0.key }         // 기본층 → 유연층
        let typed = order.filter { keys.contains($0) }              // 정본 순서로 정렬된 실재 분류
        let untyped: [String?] = keys.contains(nil) ? [nil] : []    // 미분류(있으면) 끝에
        return typed + untyped
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: "전체", color: Palette.accent)
                ForEach(orderedTypes, id: \.self) { key in
                    let m = ClassRegistry.meta(key)
                    chip(.type(key), label: m.label, color: m.color)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Palette.bg)
    }

    private func chip(_ f: TypeFilter, label: String, color: Color) -> some View {
        let on = filter == f
        return Button { filter = f } label: {
            Text(label)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(on ? Palette.bg : color)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(on ? color : color.opacity(0.14), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "지금 챙길 것" 카드

struct UpcomingCard: View {
    let entry: UpcomingEntry
    @ObservedObject var model: InboxModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TypeMenuButton(item: entry.item) { model.changeType(entry.item, to: $0) }   // 글리프 = 인라인 분류변경
            NavigationLink(value: entry.item) {                                          // 나머지 = 상세 화면
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(entry.item.raw ?? "(내용 없음)")
                            .font(.body).foregroundStyle(Palette.textPrimary).lineLimit(3)
                        HStack(spacing: 6) {
                            SourceBadge(source: entry.item.source)
                            // 캡션 색 = 원문과 같은 textPrimary(밝게). 크기(.caption)로 이미 비중을 죽이므로 색만 올린다.
                            // 지금 챙길 것: 수집 시각은 빼고(상세에 남음) 스케줄 위주 + 연도 생략 — 미리 알림 시각까지 한 줄에 보이게.
                            Text(itemCaption(entry.item, showCaptureTime: false)).font(.caption).foregroundStyle(Palette.textPrimary).lineLimit(1)
                            // **「임시」는 이 캡션 줄에 붙인다 (2026-08-18 사용자 결정) — 검색·새 기억들과 같은 자리.**
                            // **이 섹션에 미확정이 들어온다** — `InboxModel.partition`이 시점 있는 항목을 **확정 무관**으로
                            // 여기로 보낸다. 그런데 표시가 없어서 **같은 미확정 항목이 화면마다 달라 보였다**
                            // (`2026-08-14-macbook.md` §14-3에서 걸린 구멍 — 시뮬 4개가 전부 미확정인데 표시가 없었다).
                            // **★ 앞으로 늘어나는 자리다** — 자동 분류가 `due`를 붙이면 미확정이 여기로 온다.
                            // 원문 줄(`lineLimit(3)`)은 안 건드린다.
                            if !entry.item.confirmed { ProvisionalBadge() }
                        }
                    }
                    Spacer(minLength: 4)
                    // 오른쪽: D-day 배지(마감 있을 때) + 시각 칩(§6-B 보조 시각) — 캡션 잘림과 무관하게 여기서 보인다.
                    VStack(alignment: .trailing, spacing: 4) {
                        if let dday = entry.dday { DDayBadge(dday: dday) }
                        if let chip = scheduleTimeChip(entry.item) {
                            // 색 위계(2026-08-03 #3): "지남"은 **오늘 마감이 지난 상태만** 뜨고(withinDayCaption=당일 한정),
                            // D-day 버킷이 .today라 이미 amber(`ddayTint`). **빨강(overdue/coral)은 과거 날짜=진짜 놓침에만.**
                            // 되풀이는 하루 대부분이 "오늘 지남"이라 이걸 빨강으로 올리면 신호가 상시화돼 죽는다 —
                            // amber(주의) vs coral(경고=놓침)의 한 단계 위계를 **일부러 유지**한다(되풀이만 특례 아님, 전 항목 동일).
                            Text(chip).font(.caption2.weight(.semibold)).monospacedDigit().foregroundStyle(ddayTint)
                        }
                        // 되풀이 놓침(§4) — 지금 챙길 것에 남아 쌓인 항목에 "N일 놓침"(coral)
                        if let rc = statusChip(entry.item) {
                            Text(rc.text).font(.caption2.weight(.semibold))
                                .foregroundStyle(rc.tint)
                                .fixedSize(horizontal: true, vertical: false)   // 잘리는 쪽은 언제나 원문
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 색조·강조도 마감(dday) 기준. 마감 없는 항목(미리 알림만)은 무채색·약한 톤.
        .areaStyle(tint: ddayTint, strong: (entry.dday?.bucket ?? .future) != .future)
    }

    private var ddayTint: Color {
        switch entry.dday?.bucket {
        case .overdue: return Palette.overdue
        case .today:   return Palette.today
        case .future, nil: return Palette.neutral
        }
    }
}

// MARK: - 기억 한 줄 (새 기억 = 임시 배지 / 살아있는 기억 = 배지 없음)

struct MemoryRow: View {
    let item: ResolvedItem
    @ObservedObject var model: InboxModel
    var provisional: Bool = false   // 미확정이면 "임시" 배지

    var body: some View {
        HStack(spacing: 10) {
            TypeMenuButton(item: item) { model.changeType(item, to: $0) }   // 글리프 탭 = 인라인 분류변경
            NavigationLink(value: item) {                                    // 나머지 탭 = 상세 화면
                // **★ 두 줄 구조로 바꿨다 (2026-08-18 사용자 결정) — 원문 줄 + 캡션 줄.**
                //
                // **왜:** 「임시」 배지와 `SourceBadge`가 **원문과 같은 줄에서 폭을 나눠 쓰고 있었다.**
                // 원문은 `lineLimit(2)`라 **잘리는 쪽이 언제나 원문**이다 → 배지를 아래 캡션 줄로 내려
                // **원문 폭을 되찾았다.** 동시에 **수집 날짜가 이 목록에도 생긴다** — 검색·보관·지금 챙길 것에는
                // 이미 있던 것이라 **화면끼리 일관해진다**(사용자: *"원문 공간을 추가 확보하고, 일관성 유지에도 좋을 듯"*).
                //
                // **캡션 = 수집 시각만 나온다.** 이 행이 쓰이는 두 섹션(**새 기억들 · 살아있는 기억**)은 둘 다
                // **정의상 「시점 없음」**이라(`InboxModel.partition`) `itemCaption`의 마감·미리 알림 조각이 비어 있다.
                //
                // ⚠️ **`MemoryRow`는 살아있는 기억도 쓴다**(`LivingView.swift:43`) — **그 화면에도 날짜 줄이 함께 생긴다.**
                //    일관성 쪽으로 판단했다. 새 기억들만 원하면 `provisional`처럼 플래그로 가르면 된다.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        Text(item.raw ?? "(내용 없음)")
                            .font(.callout).foregroundStyle(Palette.textPrimary).lineLimit(2)   // 원문 2줄까지(넘치면 …)
                        Spacer(minLength: 4)
                        // 상태 칩(§4 + D) — 완료 후 살아있는 기억으로 와도 "완료"/"N일 놓침"이 보이고,
                        // **늦었는데 숨겨진 것**은 여기서 「8/14에 다시 · 7일 늦음」(amber)으로 드러난다.
                        // ⚠️ `.fixedSize` — 이 칩은 최장 114pt로 기존(≤47pt)의 두 배가 넘어, 안 붙이면
                        //    원문이 긴 줄에서 **SwiftUI가 원문 대신 칩을 줄인다.** 잘리는 쪽은 언제나 원문이어야 한다.
                        // (**이 칩은 안 내렸다** — 상태는 「지금 이 항목이 어떤가」라 원문과 같은 눈높이에 있어야 한다.)
                        if let rc = statusChip(item) {
                            Text(rc.text).font(.caption2.weight(.semibold))
                                .foregroundStyle(rc.tint)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    // 캡션 줄 — `UpcomingCard`·`SearchView`와 **같은 배치**(출처 · 날짜 · 임시).
                    HStack(spacing: 6) {
                        SourceBadge(source: item.source)
                        Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        if provisional { ProvisionalBadge() }
                        Spacer(minLength: 0)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
    }
}

/// 아직 확정 안 됨(자동분류=임시) 표시.
struct ProvisionalBadge: View {
    var body: some View {
        Text("임시")
            .font(.caption2.weight(.semibold)).foregroundStyle(Palette.today)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Palette.today.opacity(0.14), in: Capsule())
    }
}
