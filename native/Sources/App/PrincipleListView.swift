import SwiftUI
import SecondBrainCore

/// 원칙 목록 화면 (memory-philosophy.md §3 — **신규 설계 화면**).
/// 전체 원칙을 순서대로(위=고순위). 꾹 눌러 드래그로 순서 변경, 항목 터치 → 상세(DetailView 재사용).
/// **순서 상위 N개가 각인 동작**(상단 원칙 영역에 노출). N은 설정에서(기본 3, 상한이지 강제 아님).
///
/// ## ★ 순서 바꾸기는 iOS와 macOS가 서로 다른 길로 간다 (2026-08-20)
/// - **iOS: `PrincipleReorderList`** — `UICollectionView`의 **대화식 이동**.
///   **잔상 때문이다** — SwiftUI `List`는 첫 교체 전까지 **원본을 흐리게 남긴다**(실측).
///   전말·잰 값·「편집모드도 안 된다」는 `PrincipleReorderList`의 머리 주석에 있다.
/// - **macOS: 아래 `List`** — 맥에서는 잔상이 제기된 적이 없고 `UIViewRepresentable`을 못 쓴다.
struct PrincipleListView: View {
    @ObservedObject var model: InboxModel
    /// 줄을 눌렀을 때 상세로 밀어 넣을 자리. iOS 경로는 `NavigationLink`가 없어서 직접 민다.
    @Binding var path: NavigationPath
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    // MARK: - ⛔ 「끄는 동안 그 줄만 테두리」는 **못 했다 — 없앴다** (2026-08-20 사용자 결정)
    //
    // 사용자 판정(실기기): *"테두리가 사라지는 시간은 그때 그때 달라. 어떤 때는 바로 사라지고
    // 어떤 때는 1초 좀 더 지나서 사라지고, 누르고만 있으면 아직 손을 떼지 않았는데도 사라지고 그래.
    // 테두리는 없애자. 너가 못 하는 것으로 생각해."*
    //
    // | 시도 | 넣은 것 | 실기기 결과 |
    // |---|---|---|
    // | 1차 `d1749e2` | `LongPressGesture` + `DragGesture(0)`을 `simultaneousGesture`로 | ⛔ **드래그가 안 됐다** |
    // | 2차 `7e643f4` | `DragGesture`만 뺐다 | ⛔ 여전히. 게다가 **떼도 그림자가 남았다** |
    // | 되돌림 `4b20926` | 제스처 통째로 제거 | ✅ 드래그 복구 |
    // | 3차 `11fd8cb` | **`.onDrag`**로 끌기 시작을 잡아 그 줄에만 테두리 | ✅ 켜지긴 했다 |
    // | `5a9c934` | `.onDrop(isTargeted:)`로 **끌기 끝**을 잡아 테두리를 끈다 | ⛔ **끄는 시점이 안 맞았다** |
    //
    // ### ★ 왜 못 했나 — 켜는 신호는 있는데 **끄는 신호가 없다**
    // `.onMove`는 순서가 **실제로 바뀔 때만** 불리고, `.onDrop(isTargeted:)`는 **영역 출입**일 뿐
    // 손을 뗀 순간이 아니며, **1.5초 안전망**은 손을 떼기 전에 걸린다. 셋이 서로 다른 시점에 걸려
    // **끄는 시각이 매번 달라졌다.** 1·2차가 **켜는 쪽**에서 깨졌다면 3차는 **끄는 쪽**에서 깨졌다.
    // ⛔ **`LongPressGesture`로 돌아가지 말 것** — 드래그를 두 번 죽였다.
    //
    // ⚠️ **「끌 수 있다」를 알리는 것은 머리글 둘째 줄 하나뿐이다.** ≡ 손잡이는 `30e2d91`에서 뺐다
    // (사용자: *"이거 뭐야?"* — `>` 옆이라 내비게이션 표시처럼 보였다). **그 줄을 지우면 아무 신호도 안 남는다.**

    var body: some View {
        let items = model.orderedPrinciples
        let n = max(1, min(activeN, items.count))   // 동작 개수(상한, 최소 1)
        VStack(spacing: 0) {
            header(items: items, n: n)
            listBody(items: items, n: n)
        }
        .background(Palette.bg.ignoresSafeArea())
        .navigationTitle("원칙")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    /// **두 줄을 항상 보인다**(사용자 결정 2026-08-20) — 무엇이 각인되는지 + 어떻게 순서를 바꾸는지.
    /// ★ 테두리·손잡이를 뺀 지금 **끄는 법을 아는 길은 이 줄뿐이다.** 지우지 말 것.
    private func header(items: [ResolvedItem], n: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(items.isEmpty ? "원칙 없음"
                 : "아래 \(n)개가 원칙 영역에 노출됩니다")   // 문구는 사용자가 정했다(2026-08-20)
            if !items.isEmpty {
                Text("눌러 끌어서 순서를 바꾸세요")           // 문구는 사용자가 정했다(2026-08-20)
            }
        }
        .font(.footnote).foregroundStyle(Palette.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
    }

    @ViewBuilder
    private func listBody(items: [ResolvedItem], n: Int) -> some View {
        #if os(iOS)
        // ★ 잔상 때문에 `List`를 안 쓴다 — `PrincipleReorderList` 머리 주석에 잰 값이 있다.
        PrincipleReorderList(
            items: items,
            activeCount: n,
            onReorder: { model.reorderPrinciples($0) },
            onSelect: { path.append($0) }
        )
        #else
        List {
            ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                NavigationLink(value: p) {
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
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        #endif
    }

    /// 원칙 한 줄(맥 경로). **iOS는 `PrincipleReorderRow`가 같은 모양을 그린다** — 둘을 함께 고칠 것.
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
        // ⚠️ **이 여백은 고정이다 — 끌 때만 바꾸면 안 된다** (2026-08-20 사용자:
        // *"테두리를 그리면 공간의 크기가 변해서 그런지 안의 텍스트가 줄바꿈이 일어나네"*).
        // ★ **보이는 것(그림)을 바꾸려다 재는 것(레이아웃)까지 바꾸지 않는다.**
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
