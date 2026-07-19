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
/// 위→아래: 원칙 띠 · 지금 챙길 것 · 대시보드 · 새 기억들(미확정, 오래된 순).
/// 필터는 여기 없다 — 살아있는 기억 탭의 몫.
struct InboxView: View {
    @ObservedObject var model: InboxModel
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
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
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
    }

    private var content: some View {
        let tab = model.newTab
        return List {
            if !model.principles.isEmpty {
                Section {
                    ForEach(model.principles, id: \.id) { p in
                        PrincipleRow(item: p)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                    }
                } header: {
                    sectionTitle("원칙", count: model.principles.count).listRowInsets(EdgeInsets())
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
                    ForEach(tab.newMemories, id: \.id) { item in
                        MemoryRow(item: item, model: model, provisional: true)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) { confirmAction(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(item) }
                            .contextMenu { newItemActions(item) }
                    }
                }
            } header: {
                sectionTitle("새 기억들", count: tab.newMemories.count)
                    .listRowInsets(EdgeInsets())
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
    }

    // MARK: 헤더 (제목 + 폴더 아이콘, 한 줄)

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("새로운 기억").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button { showPicker = true } label: {
                Image(systemName: "folder").font(.title3).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    // MARK: 스와이프 / 컨텍스트 액션

    @ViewBuilder private func confirmAction(_ item: ResolvedItem) -> some View {
        Button { model.confirm(item) } label: { Label("기억하기", systemImage: "checkmark.seal.fill") }.tint(Palette.accent)
    }
    @ViewBuilder private func deleteAction(_ item: ResolvedItem) -> some View {
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }
    @ViewBuilder private func doneDeferActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }.tint(.green)
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
    }
    /// 시점 있는 항목(지금 챙길 것) 컨텍스트: 완료·미루기·삭제.
    @ViewBuilder func itemActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }
    /// 새 기억(미확정) 컨텍스트: 확정을 맨 앞에.
    @ViewBuilder private func newItemActions(_ item: ResolvedItem) -> some View {
        Button { model.confirm(item) } label: { Label("기억하기 (살아있는 기억으로)", systemImage: "checkmark.seal.fill") }
        Button { model.defer7(item) } label: { Label("미루기 (시점 붙임)", systemImage: "clock") }
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }

    func sectionTitle(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .textCase(nil)
        .padding(.horizontal, 12).padding(.top, 6).padding(.bottom, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.bg)
    }

    private var emptyNewRow: some View {
        Text("새 기억이 없어요")
            .font(.callout).foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
    }

    private var folderPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.questionmark").font(.system(size: 44)).foregroundStyle(Palette.textTertiary)
            Text("받은함 폴더를 선택하세요").font(.headline).foregroundStyle(Palette.textPrimary)
            Text("iCloud Drive의 SecondBrain 폴더를 고르면\ninbox.md와 조각 파일들을 함께 읽습니다.")
                .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Button("폴더 선택") { showPicker = true }.buttonStyle(.borderedProminent).tint(Palette.accent)
            Spacer()
        }
        .padding()
    }
}

// MARK: - 대시보드 (5숫자 가로: 원칙 · 챙길 것 · 미기억 · 기억함 · 총 기억)

struct DashboardRow: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        HStack(spacing: 6) {
            tile("원칙", model.principleCount, TypeCatalog.meta("principle").color)
            tile("챙길 것", model.upcomingCount, Palette.overdue)
            tile("미기억", model.unconfirmedCount, Palette.today)
            tile("기억함", model.confirmedCount, Palette.accent)
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
    private var tint: Color { TypeCatalog.meta("principle").color }

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(tint).padding(.top, 3)
            Text(item.raw ?? "")
                .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .areaStyle(tint: tint)
    }
}

// MARK: - 필터 칩 한 줄 (살아있는 기억 탭에서 사용)

struct FilterChipsBar: View {
    @ObservedObject var model: InboxModel

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(.all, label: "전체", color: Palette.accent)
                ForEach(TypeCatalog.primaryFilters, id: \.self) { key in
                    let m = TypeCatalog.meta(key)
                    chip(.type(key), label: m.label, color: m.color)
                }
                Menu {
                    ForEach(TypeCatalog.overflowFilters, id: \.self) { f in
                        Button { model.filter = f } label: {
                            if case .type(let k) = f { Label(TypeCatalog.meta(k).label, systemImage: TypeCatalog.meta(k).symbol) }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold)).foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Palette.surface, in: Capsule())
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
        .background(Palette.bg)
    }

    private func chip(_ f: TypeFilter, label: String, color: Color) -> some View {
        let on = model.filter == f
        return Button { model.filter = f } label: {
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
                            Text(itemCaption(entry.item)).font(.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 4)
                    DDayBadge(dday: entry.dday)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .areaStyle(tint: ddayTint, strong: entry.dday.bucket != .future)
    }

    private var ddayTint: Color {
        switch entry.dday.bucket {
        case .overdue: return Palette.overdue
        case .today:   return Palette.today
        case .future:  return Palette.neutral
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
                HStack(spacing: 10) {
                    Text(item.raw ?? "(내용 없음)")
                        .font(.callout).foregroundStyle(Palette.textPrimary).lineLimit(1)
                    Spacer(minLength: 4)
                    if provisional { ProvisionalBadge() }
                    SourceBadge(source: item.source)
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
