import SwiftUI
import SecondBrainCore

/// 검색(pull) — 원문 부분일치로 걸러 본다. v1 최소 동작(완료 포함 전체 대상).
struct SearchView: View {
    @ObservedObject var model: InboxModel
    @State private var query = ""

    private var results: [ResolvedItem] {
        let all = model.liveNonDone + model.doneItems
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return [] }
        return all.filter { ($0.raw ?? "").lowercased().contains(q) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.bg.ignoresSafeArea()
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    hint
                } else if results.isEmpty {
                    Text("결과 없음").font(.callout).foregroundStyle(Palette.textSecondary)
                } else {
                    List(results, id: \.id) { item in
                        HStack(spacing: 10) {
                            TypeGlyph(type: item.type)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.raw ?? "").font(.callout).foregroundStyle(Palette.textPrimary).lineLimit(2)
                                Text(itemCaption(item)).font(.caption2).foregroundStyle(Palette.textTertiary).lineLimit(1)
                            }
                        }
                        .listRowBackground(Palette.bg)
                        .listRowSeparatorTint(Palette.cardStroke)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Palette.bg)
                }
            }
            .navigationTitle("검색")
        }
        .searchable(text: $query, prompt: "원문 검색")
    }

    private var hint: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(Palette.textTertiary)
            Text("원문으로 찾기").font(.callout).foregroundStyle(Palette.textSecondary)
        }
    }
}
