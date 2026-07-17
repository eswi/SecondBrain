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

/// 받은함 첫 화면(다크). 상단 고정: 제목+폴더 · 원칙 · 곧 닥칠 것 · 필터 칩.
/// 최근 목록을 스크롤하면 그 양에 비례해 원칙 → 곧 닥칠 것 순서로 표시 개수가 **한 개씩 단계적으로** 줄고,
/// 각각 최소 1개는 남아 사라지지 않는다.
struct InboxView: View {
    @ObservedObject var model: InboxModel
    var goToPrinciples: () -> Void = {}
    @State private var showPicker = false
    @State private var pHideRaw = 0     // 스크롤로 숨긴 원칙 수
    @State private var uHideRaw = 0     // 스크롤로 숨긴 곧닥칠 수

    private let pStep: CGFloat = 44     // 원칙 한 개 줄이는 데 필요한 스크롤(px)
    private let uStep: CGFloat = 88     // 곧닥칠 한 개 줄이는 데 필요한 스크롤(px)

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
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
    }

    /// 전체가 하나의 List. 원칙·곧닥칠·필터는 **고정 섹션 헤더**(sticky)로, 최근은 rows.
    /// → 어디서 스와이프해도 전체가 스크롤되고, 스크롤 양이 헤더의 단계적 접힘을 구동.
    private var content: some View {
        let sections = model.sections
        let pCount = model.principles.count
        let uCount = sections.upcoming.count
        let pRed = max(0, pCount - 1)
        let uRed = max(0, uCount - 1)
        let pHide = min(pRed, pHideRaw)
        let uHide = min(uRed, uHideRaw)
        return List {
            Section {
                if sections.recent.isEmpty {
                    emptyRecentRow
                } else {
                    ForEach(sections.recent, id: \.id) { item in
                        RecentRow(item: item, model: model)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(Palette.bg)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading) {
                                Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }.tint(.green)
                                Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
                            }
                            .contextMenu { itemActions(item) }
                    }
                }
            } header: {
                stickyHeader(pShown: pCount - pHide, uShown: uCount - uHide,
                             upcoming: sections.upcoming, recentCount: sections.recent.count)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
            let yy = max(0, y)
            let ph = min(pRed, Int(yy / pStep))
            let uh = ph >= pRed ? min(uRed, Int(max(0, yy - CGFloat(pRed) * pStep) / uStep)) : 0
            // withAnimation 없이, 값이 바뀔 때만 갱신 → 각 영역이 value:shown 애니메이션으로 자기 항목만 부드럽게 전환.
            if ph != pHideRaw { pHideRaw = ph }
            if uh != uHideRaw { uHideRaw = uh }
        }
    }

    // 고정 섹션 헤더: 회계 · 원칙 · 곧닥칠 · 필터 · "최근" 제목 (불투명 배경으로 rows 가림)
    @ViewBuilder private func stickyHeader(pShown: Int, uShown: Int,
                                           upcoming: [UpcomingEntry], recentCount: Int) -> some View {
        VStack(spacing: 0) {
            accountingBar
            if !model.principles.isEmpty {
                PrincipleBand(principles: model.principles, shown: pShown, onTap: goToPrinciples)
            }
            if !upcoming.isEmpty {
                UpcomingArea(entries: upcoming, shown: uShown, model: model)
            }
            FilterChipsBar(model: model)
            sectionHeader("최근 들어온 것", count: recentCount)
                .padding(.horizontal, 10).padding(.bottom, 4)
        }
        .background(Palette.bg)
        .listRowInsets(EdgeInsets())
    }

    private var emptyRecentRow: some View {
        Text(model.filter == .all ? "최근 들어온 것이 없어요" : "이 종류가 없어요")
            .font(.callout).foregroundStyle(Palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
            .listRowBackground(Palette.bg)
            .listRowSeparator(.hidden)
    }

    // MARK: 헤더 (제목 + 폴더 아이콘, 한 줄)

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("받은함").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button { showPicker = true } label: {
                Image(systemName: "folder").font(.title3).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    // 항목 행동(고정 영역용 컨텍스트 메뉴 = 스와이프 대체)
    @ViewBuilder func itemActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .textCase(nil)
        .padding(.top, 2)
    }

    // 회계 요약
    private var accountingBar: some View {
        HStack(spacing: 4) {
            Text("합계 \(model.totalCount)").foregroundStyle(Palette.textSecondary)
            Text("· 표시 \(model.liveNonDone.count - model.principles.count)")
            Text("· 원칙 \(model.principles.count)")
            Text("· 완료 \(model.doneItems.count)")
            Text("· 삭제 \(model.deletedCount)")
            Spacer()
        }
        .font(.caption2).foregroundStyle(Palette.textTertiary).monospacedDigit()
        .padding(.horizontal, 16).padding(.bottom, 6)
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

// MARK: - 원칙 띠 (ambient) — shown 개수만큼 표시, 1개면 회전

struct PrincipleBand: View {
    let principles: [ResolvedItem]
    let shown: Int
    var onTap: () -> Void = {}

    private var tint: Color { TypeCatalog.meta("principle").color }
    private var count: Int { principles.count }
    private var visibleItems: [ResolvedItem] { Array(principles.prefix(max(1, shown))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(visibleItems, id: \.id) { p in
                row(p).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            if shown < count {
                Text("+\(count - shown)").font(.caption2).monospacedDigit()
                    .foregroundStyle(Palette.textTertiary)
                    .padding(.top, 12).padding(.trailing, 12)
            }
        }
        .areaStyle(tint: tint)
        .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .animation(.easeInOut(duration: 0.25), value: shown)
    }

    private func row(_ p: ResolvedItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "star.fill").font(.caption2).foregroundStyle(tint).padding(.top, 3)
            Text(p.raw ?? "")
                .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - 곧 닥칠 것 영역 — shown 개수만큼 표시, 제목에 +N

struct UpcomingArea: View {
    let entries: [UpcomingEntry]
    let shown: Int
    @ObservedObject var model: InboxModel

    private var visibleEntries: [UpcomingEntry] { Array(entries.prefix(max(1, shown))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(visibleEntries, id: \.item.id) { entry in
                card(entry).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 10).padding(.bottom, 4)
        .animation(.easeInOut(duration: 0.25), value: shown)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("곧 닥칠 것").font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(entries.count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            if shown < entries.count {
                Text("+\(entries.count - shown)")
                    .font(.caption2.weight(.bold)).foregroundStyle(Palette.today)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.today.opacity(0.16), in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private func card(_ entry: UpcomingEntry) -> some View {
        UpcomingCard(entry: entry, model: model)
            .contextMenu {
                Button { model.markDone(entry.item) } label: { Label("완료", systemImage: "checkmark") }
                Button { model.defer7(entry.item) } label: { Label("미루기", systemImage: "clock") }
                Button(role: .destructive) { model.delete(entry.item) } label: { Label("삭제", systemImage: "trash") }
            }
    }
}

// MARK: - 필터 칩 한 줄

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

// MARK: - "곧 닥칠 것" 카드

struct UpcomingCard: View {
    let entry: UpcomingEntry
    @ObservedObject var model: InboxModel

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TypeMenuButton(item: entry.item) { model.changeType(entry.item, to: $0) }
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

// MARK: - "최근 들어온 것" 얇은 줄

struct RecentRow: View {
    let item: ResolvedItem
    @ObservedObject var model: InboxModel

    var body: some View {
        HStack(spacing: 10) {
            TypeMenuButton(item: item) { model.changeType(item, to: $0) }
            Text(item.raw ?? "(내용 없음)")
                .font(.callout).foregroundStyle(Palette.textPrimary).lineLimit(1)
            Spacer(minLength: 4)
            SourceBadge(source: item.source)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
    }
}
