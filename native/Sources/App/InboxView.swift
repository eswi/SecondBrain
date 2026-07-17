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

/// 받은함 첫 화면(다크). 전체가 하나의 네이티브 List → 어디서든 스와이프로 매끄럽게 스크롤.
/// 섹션: 원칙 · 곧 닥칠 것 · 최근(필터는 최근 섹션 고정 헤더).
struct InboxView: View {
    @ObservedObject var model: InboxModel
    var goToPrinciples: () -> Void = {}
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
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
    }

    private var content: some View {
        let sections = model.sections
        return List {
            Section {
                accountingRow
                    .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 6, trailing: 16))
                    .listRowBackground(Palette.bg).listRowSeparator(.hidden)
            }

            if !model.principles.isEmpty {
                Section {
                    ForEach(model.principles, id: \.id) { p in
                        PrincipleRow(item: p, onTap: goToPrinciples)
                            .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                    }
                } header: {
                    sectionTitle("원칙", count: model.principles.count).listRowInsets(EdgeInsets())
                }
            }

            if !sections.upcoming.isEmpty {
                Section {
                    ForEach(sections.upcoming, id: \.item.id) { entry in
                        UpcomingCard(entry: entry, model: model)
                            .listRowInsets(EdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(entry.item) }
                            .swipeActions(edge: .leading) { doneDeferActions(entry.item) }
                            .contextMenu { itemActions(entry.item) }
                    }
                } header: {
                    sectionTitle("곧 닥칠 것", count: sections.upcoming.count).listRowInsets(EdgeInsets())
                }
            }

            Section {
                if sections.recent.isEmpty {
                    emptyRecentRow
                } else {
                    ForEach(sections.recent, id: \.id) { item in
                        RecentRow(item: item, model: model)
                            .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                            .listRowBackground(Palette.bg).listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteAction(item) }
                            .swipeActions(edge: .leading) { doneDeferActions(item) }
                            .contextMenu { itemActions(item) }
                    }
                }
            } header: {
                VStack(spacing: 0) {
                    FilterChipsBar(model: model)
                    sectionTitle("최근 들어온 것", count: sections.recent.count)
                }
                .background(Palette.bg)
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
            Text("받은함").font(.largeTitle.bold()).foregroundStyle(Palette.textPrimary)
            Spacer()
            Button { showPicker = true } label: {
                Image(systemName: "folder").font(.title3).foregroundStyle(Palette.accent)
            }
        }
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    // MARK: 스와이프 / 컨텍스트 액션

    @ViewBuilder private func deleteAction(_ item: ResolvedItem) -> some View {
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }
    @ViewBuilder private func doneDeferActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }.tint(.green)
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }.tint(.orange)
    }
    @ViewBuilder func itemActions(_ item: ResolvedItem) -> some View {
        Button { model.markDone(item) } label: { Label("완료", systemImage: "checkmark") }
        Button { model.defer7(item) } label: { Label("미루기", systemImage: "clock") }
        Button(role: .destructive) { model.delete(item) } label: { Label("삭제", systemImage: "trash") }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
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

    private var accountingRow: some View {
        HStack(spacing: 4) {
            Text("합계 \(model.totalCount)").foregroundStyle(Palette.textSecondary)
            Text("· 표시 \(model.liveNonDone.count - model.principles.count)")
            Text("· 원칙 \(model.principles.count)")
            Text("· 완료 \(model.doneItems.count)")
            Text("· 삭제 \(model.deletedCount)")
            Spacer()
        }
        .font(.caption2).foregroundStyle(Palette.textTertiary).monospacedDigit()
    }

    private var emptyRecentRow: some View {
        Text(model.filter == .all ? "최근 들어온 것이 없어요" : "이 종류가 없어요")
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

// MARK: - 원칙 한 줄 (ambient) — 각자 cyan 박스

struct PrincipleRow: View {
    let item: ResolvedItem
    var onTap: () -> Void = {}
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
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
