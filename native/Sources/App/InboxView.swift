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

/// 받은함 첫 화면(다크): 제목+폴더(한 줄) · 원칙 띠(고정, 스크롤 시 축소) · 필터 칩 · 회계 ·
/// "곧 닥칠 것"(카드) · "최근 들어온 것"(줄). 스와이프 삭제·완료·미루기, 종류 아이콘으로 분류 변경.
struct InboxView: View {
    @ObservedObject var model: InboxModel
    var goToPrinciples: () -> Void = {}
    @State private var showPicker = false
    @State private var scrolled = false          // 목록을 위로 올렸는지 → 원칙 띠 축소

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                headerRow
                if model.needsFolder {
                    folderPrompt
                    Spacer(minLength: 0)
                } else {
                    if !model.principles.isEmpty {
                        PrincipleBand(principles: model.principles, collapsed: scrolled, onTap: goToPrinciples)
                    }
                    FilterChipsBar(model: model)
                    accountingBar
                    listArea
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

    // MARK: 헤더 (제목 + 폴더 아이콘, 한 줄)

    private var headerRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("받은함").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button { showPicker = true } label: {
                Image(systemName: "folder").font(.title3).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 6)
    }

    // MARK: 목록

    private var listArea: some View {
        let sections = model.sections
        return Group {
            if sections.upcoming.isEmpty && sections.recent.isEmpty {
                emptyState
            } else {
                List {
                    if !sections.upcoming.isEmpty {
                        Section {
                            ForEach(sections.upcoming, id: \.item.id) { entry in
                                UpcomingCard(entry: entry, model: model)
                                    .listRowInsets(EdgeInsets(top: 5, leading: 14, bottom: 5, trailing: 14))
                                    .listRowBackground(Palette.bg)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(entry.item) }
                                    .swipeActions(edge: .leading) { doneDeferActions(entry.item) }
                            }
                        } header: { sectionHeader("곧 닥칠 것", count: sections.upcoming.count) }
                    }
                    if !sections.recent.isEmpty {
                        Section {
                            ForEach(sections.recent, id: \.id) { item in
                                RecentRow(item: item, model: model)
                                    .listRowInsets(EdgeInsets(top: 2, leading: 14, bottom: 2, trailing: 14))
                                    .listRowBackground(Palette.bg)
                                    .listRowSeparator(.hidden)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(item) }
                                    .swipeActions(edge: .leading) { doneDeferActions(item) }
                            }
                        } header: { sectionHeader("최근 들어온 것", count: sections.recent.count) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Palette.bg)
                .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 16 } action: { _, s in
                    if s != scrolled { withAnimation(.easeInOut(duration: 0.22)) { scrolled = s } }
                }
            }
        }
    }

    // MARK: 스와이프 액션

    @ViewBuilder private func deleteAction(_ item: ResolvedItem) -> some View {
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }
    @ViewBuilder private func doneDeferActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }.tint(.green)
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Palette.textSecondary)
            Text("\(count)").font(.caption2).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .textCase(nil)
        .padding(.top, 4)
    }

    // 회계 요약: 표시·원칙·완료·삭제·합계. 합계가 원본(inbox.md)과 같으면 파싱 누락 없음.
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
        .padding(.horizontal, 14).padding(.bottom, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
            Text(model.filter == .all ? "받은함이 비었어요" : "이 종류가 없어요")
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

// MARK: - 원칙 띠 (ambient) — 펼침(전부) / 접힘(1개 회전)

struct PrincipleBand: View {
    let principles: [ResolvedItem]
    var collapsed: Bool
    var onTap: () -> Void = {}
    @State private var idx = 0
    private let timer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    private var star: Color { TypeCatalog.meta("principle").color }

    var body: some View {
        Group {
            if collapsed { compact } else { expanded }
        }
        .background(Palette.band)
        .onReceive(timer) { _ in
            guard collapsed, principles.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.4)) { idx = (idx + 1) % principles.count }
        }
    }

    // 펼침: 원칙 전부
    private var expanded: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(principles, id: \.id) { p in
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(star).padding(.top, 3)
                    Text(p.raw ?? "")
                        .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    // 접힘: 1개씩 회전(공간 절약, 스크롤해도 사라지지 않음)
    private var compact: some View {
        let cur = principles[min(idx, principles.count - 1)]
        return Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(star)
                Text(cur.raw ?? "")
                    .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    .id(cur.id).transition(.opacity)
                if principles.count > 1 {
                    Text("\(min(idx, principles.count - 1) + 1)/\(principles.count)")
                        .font(.caption2).foregroundStyle(Palette.textTertiary).monospacedDigit()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
        }
        .buttonStyle(.plain)
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
                        .background(Palette.card, in: Capsule())
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
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
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.cardStroke))
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
        .padding(.vertical, 4)
    }
}
