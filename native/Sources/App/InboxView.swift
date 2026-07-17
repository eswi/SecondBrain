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

    private var content: some View {
        let sections = model.sections
        let pCount = model.principles.count
        let uCount = sections.upcoming.count
        let pRed = max(0, pCount - 1)
        let uRed = max(0, uCount - 1)
        let pHide = min(pRed, pHideRaw)
        let uHide = min(uRed, uHideRaw)
        return VStack(spacing: 0) {
            accountingBar
            if pCount > 0 {
                PrincipleBand(principles: model.principles, shown: pCount - pHide, onTap: goToPrinciples)
            }
            if uCount > 0 {
                UpcomingArea(entries: sections.upcoming, shown: uCount - uHide, model: model)
            }
            FilterChipsBar(model: model)
            recentList(sections.recent, pRed: pRed, uRed: uRed)
        }
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

    // MARK: 최근 들어온 것 (유일한 스크롤 영역 — 스크롤 양이 상단 단계적 접힘을 구동)

    @ViewBuilder private func recentList(_ recent: [ResolvedItem], pRed: Int, uRed: Int) -> some View {
        if recent.isEmpty {
            emptyRecent
        } else {
            List {
                Section {
                    ForEach(recent, id: \.id) { item in
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
                } header: { sectionHeader("최근 들어온 것", count: recent.count) }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.bg)
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in
                let yy = max(0, y)
                let ph = min(pRed, Int(yy / pStep))
                let uh = ph >= pRed ? min(uRed, Int(max(0, yy - CGFloat(pRed) * pStep) / uStep)) : 0
                if ph != pHideRaw || uh != uHideRaw {
                    withAnimation(.easeInOut(duration: 0.2)) { pHideRaw = ph; uHideRaw = uh }
                }
            }
        }
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

    private var emptyRecent: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Palette.textTertiary)
            Text(model.filter == .all ? "최근 들어온 것이 없어요" : "이 종류가 없어요")
                .font(.callout).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @State private var idx = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var tint: Color { TypeCatalog.meta("principle").color }
    private var count: Int { principles.count }
    private var rotating: Bool { shown <= 1 && count > 1 }

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .areaStyle(tint: tint)
            .padding(.horizontal, 10).padding(.top, 4).padding(.bottom, 2)
            .onReceive(timer) { _ in
                guard rotating else { return }
                withAnimation(.easeInOut(duration: 0.4)) { idx = (idx + 1) % count }
            }
    }

    @ViewBuilder private var content: some View {
        if shown >= count {
            list(principles)
        } else if shown <= 1 {
            rotatingView
        } else {
            list(Array(principles.prefix(shown)))
                .overlay(alignment: .topTrailing) { corner("+\(count - shown)") }
        }
    }

    private func list(_ items: [ResolvedItem]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.id) { row($0) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle()).onTapGesture(perform: onTap)
    }

    private var rotatingView: some View {
        let cur = principles[min(idx, count - 1)]
        return ZStack(alignment: .topLeading) {
            ForEach(principles, id: \.id) { row($0).opacity(0).accessibilityHidden(true) }
            row(cur).id(cur.id).transition(.opacity)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { corner("\(min(idx, count - 1) + 1)/\(count)") }
        .contentShape(Rectangle()).onTapGesture(perform: onTap)
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

    private func corner(_ s: String) -> some View {
        Text(s).font(.caption2).foregroundStyle(Palette.textTertiary).monospacedDigit()
            .padding(.top, 12).padding(.trailing, 12)
    }
}

// MARK: - 곧 닥칠 것 영역 — shown 개수만큼 표시, 제목에 +N

struct UpcomingArea: View {
    let entries: [UpcomingEntry]
    let shown: Int
    @ObservedObject var model: InboxModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            ForEach(Array(entries.prefix(shown)), id: \.item.id) { card($0) }
        }
        .padding(.horizontal, 10).padding(.bottom, 4)
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
