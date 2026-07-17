import SwiftUI
import UniformTypeIdentifiers
import SecondBrainCore

/// 받은함 첫 화면(다크): 원칙 띠(ambient) + 필터 칩 + "곧 닥칠 것"(카드) + "최근 들어온 것"(줄).
/// 스와이프로 삭제·완료·미루기, 종류 아이콘 탭으로 분류 변경(엔진 재사용).
struct InboxView: View {
    @ObservedObject var model: InboxModel
    var goToPrinciples: () -> Void = {}
    @State private var showPicker = false

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if model.needsFolder {
                    folderPrompt
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("받은함")
            .toolbar {
                Button { showPicker = true } label: { Image(systemName: "folder") }
                    .tint(Palette.accent)
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { model.setFolder(url) }
        }
    }

    // MARK: 내용

    private var content: some View {
        let sections = model.sections
        return VStack(spacing: 0) {
            if !model.principles.isEmpty {
                PrincipleBand(principles: model.principles, onTap: goToPrinciples)
            }
            FilterChipsBar(model: model)

            if sections.upcoming.isEmpty && sections.recent.isEmpty {
                emptyState
                Spacer(minLength: 0)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
            Text(model.filter == .all ? "받은함이 비었어요" : "이 종류가 없어요")
                .font(.callout).foregroundStyle(Palette.textSecondary)
            Spacer()
        }
    }

    private var folderPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.questionmark").font(.system(size: 44)).foregroundStyle(Palette.textTertiary)
            Text("받은함 폴더를 선택하세요").font(.headline).foregroundStyle(Palette.textPrimary)
            Text("iCloud Drive의 SecondBrain 폴더를 고르면\ninbox.md와 조각 파일들을 함께 읽습니다.")
                .font(.callout).foregroundStyle(Palette.textSecondary).multilineTextAlignment(.center)
            Button("폴더 선택") { showPicker = true }.buttonStyle(.borderedProminent).tint(Palette.accent)
        }
        .padding()
    }
}

// MARK: - 원칙 띠 (ambient)

struct PrincipleBand: View {
    let principles: [ResolvedItem]
    var onTap: () -> Void = {}
    @State private var idx = 0
    private let timer = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        let current = principles[min(idx, principles.count - 1)]
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(TypeCatalog.meta("principle").color)
                Text(current.raw ?? "")
                    .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id(current.id)                       // 전환 시 애니메이션
                    .transition(.opacity)
                if principles.count > 1 {
                    Text("\(min(idx, principles.count - 1) + 1)/\(principles.count)")
                        .font(.caption2).foregroundStyle(Palette.textTertiary).monospacedDigit()
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Palette.band)
        }
        .buttonStyle(.plain)
        .onReceive(timer) { _ in
            guard principles.count > 1 else { return }
            withAnimation(.easeInOut(duration: 0.4)) { idx = (idx + 1) % principles.count }
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
