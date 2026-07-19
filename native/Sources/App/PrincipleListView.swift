import SwiftUI
import SecondBrainCore

/// 원칙 목록 화면 (memory-philosophy.md §3 — **신규 설계 화면**).
/// 전체 원칙을 순서대로(위=고순위). 꾹 눌러 드래그로 순서 변경, 항목 터치 → 상세(DetailView 재사용).
/// **순서 상위 N개가 각인 동작**(상단 원칙 영역에 노출). N은 설정에서(기본 3, 상한이지 강제 아님).
struct PrincipleListView: View {
    @ObservedObject var model: InboxModel
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    var body: some View {
        let items = model.orderedPrinciples
        let n = max(1, min(activeN, items.count))   // 동작 개수(상한, 최소 1)
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                    NavigationLink(value: p) {   // 상세는 InboxView 스택의 ResolvedItem destination이 처리
                        row(p, active: idx < n)
                    }
                    .listRowBackground(Palette.bg)
                    .listRowSeparator(.hidden)
                }
                .onMove { from, to in
                    var reordered = items
                    reordered.move(fromOffsets: from, toOffset: to)
                    model.reorderPrinciples(reordered)
                }
            } header: {
                Text(items.isEmpty ? "원칙 없음"
                     : "위 \(n)개가 각인 동작 — 상단 원칙 영역에 노출")
                    .font(.footnote).foregroundStyle(Palette.textSecondary).textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("원칙")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// 원칙 한 줄. 동작(상위 N)이 아니면 흐리게 + "대기" 표시.
    private func row(_ item: ResolvedItem, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "star.fill").font(.caption2)
                .foregroundStyle(TypeCatalog.meta("principle").color).padding(.top, 3)
            Text(item.raw ?? "")
                .font(.callout.weight(.medium)).foregroundStyle(Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !active {
                Text("대기").font(.caption2).foregroundStyle(Palette.textTertiary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Palette.surface, in: Capsule())
            }
        }
        .padding(.vertical, 5)
        .opacity(active ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}

/// 상단 원칙 밴드 터치 → 원칙 목록 화면으로 가는 내비 경로.
struct PrincipleListRoute: Hashable {}

/// 원칙 각인 동작 개수(N) 설정 — 로컬(@AppStorage). 데이터 아님.
enum PrincipleSettings {
    static let activeCountKey = "principleActiveCount"
    static let defaultActiveCount = 3
    static let maxActiveCount = 10
}
