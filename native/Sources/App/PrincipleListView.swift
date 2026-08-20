import SwiftUI
import SecondBrainCore

/// 원칙 목록 화면 (memory-philosophy.md §3 — **신규 설계 화면**).
/// 전체 원칙을 순서대로(위=고순위). 꾹 눌러 드래그로 순서 변경, 항목 터치 → 상세(DetailView 재사용).
/// **순서 상위 N개가 각인 동작**(상단 원칙 영역에 노출). N은 설정에서(기본 3, 상한이지 강제 아님).
struct PrincipleListView: View {
    @ObservedObject var model: InboxModel
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    // MARK: - ⛔ 「끄는 동안 그 줄만 테두리」는 **못 했다 — 없앴다** (2026-08-20 사용자 결정)
    //
    // 사용자 판정(실기기): *"테두리가 사라지는 시간은 그때 그때 달라. 어떤 때는 바로 사라지고
    // 어떤 때는 1초 좀 더 지나서 사라지고, 누르고만 있으면 아직 손을 떼지 않았는데도 사라지고 그래.
    // 테두리는 없애자. 너가 못 하는 것으로 생각해."*
    //
    // ### 무엇을 시도했나 (전부 뺐다)
    // | 시도 | 넣은 것 | 실기기 결과 |
    // |---|---|---|
    // | 1차 `d1749e2` | `LongPressGesture` + `DragGesture(0)`을 `simultaneousGesture`로 · 뜸·그림자·햅틱 | ⛔ **드래그가 안 됐다** |
    // | 2차 `7e643f4` | `DragGesture`만 뺐다 | ⛔ 여전히. 게다가 **떼도 그림자가 남았다** |
    // | 되돌림 `4b20926` | 제스처 통째로 제거 | ✅ 드래그 복구 (**지금 이 상태다**) |
    // | 3차 `11fd8cb` | **`.onDrag`**로 끌기 시작을 잡아 그 줄에만 테두리 | ✅ 켜지긴 했다 |
    // | `5a9c934` | `.onDrop(isTargeted:)`로 **끌기 끝**을 잡아 테두리를 끈다 | ⛔ **끄는 시점이 안 맞았다**(위 인용) |
    //
    // ### ★ 왜 못 했나 — **`List`는 「지금 끌린다」를 안 알려준다**
    // 켜는 신호(`.onDrag`)는 있는데 **끄는 신호가 없다.** `.onMove`는 **순서가 실제로 바뀔 때만**
    // 불리고(제자리에 놓으면 안 불린다), `.onDrop(isTargeted:)`는 드래그 세션의 **영역 출입**을
    // 볼 뿐 손을 뗀 순간이 아니다. 그래서 **1.5초 안전망**을 함께 뒀는데, 그 셋이 서로 다른
    // 시점에 걸려 **끄는 시각이 매번 달라졌다** — 손을 떼기도 전에 꺼지는 것이 그 안전망이다.
    // 1·2차가 **켜는 쪽**에서 깨졌다면, 3차는 **끄는 쪽**에서 깨졌다.
    //
    // ⛔ **다시 시도하지 말 것.** 하려면 `List`를 버리고 `ScrollView` + 직접 만든 순서 바꾸기로
    // 가야 한다 — **지금 잘 되는 것(순서 바꾸기·자동 스크롤·들어올림·접근성)을 통째로 갈아엎는 값이다.**
    // ⛔ **`LongPressGesture`로 돌아가지 말 것** — 드래그를 두 번 죽였다(`d1749e2`·`7e643f4`).
    //
    // ### 지금 남은 신호 — 「끌 수 있다」까지만
    // **머리글 둘째 줄(「눌러 끌어서 순서를 바꾸세요」) + iOS 기본 들어올림**뿐이다.
    // ≡ 손잡이는 **`30e2d91`에서 뺐다**(사용자: *"이거 뭐야?"* — `NavigationLink`의 `>` 옆이라
    // 내비게이션 표시처럼 보였다). **되살리지 말 것 — 사용자가 없애기로 한 것이다.**

    // MARK: - ⛔ 「끌 때 원래 자리의 잔상을 없앤다」도 **안 된다** (2026-08-20에 두 번 시도)
    //
    // 사용자가 본 것: *"드래그로 살짝 이동하면 … 원래 있던 텍스트 잔상이 아래에 남아 있어."*
    // 시스템이 들어올리는 것은 **사본**이고 **원본은 제자리에 그대로 있다.**
    //
    // | 시도 | 무엇을 | 결과 |
    // |---|---|---|
    // | `4dc8b9c` | 원본에 `.opacity(0)` — 사본 스냅샷을 피하려고 **한 박자 뒤**(`main.async`)에 | ⛔ *"선택된 것 자체가 사라져 버렸어. 손을 떼야 나타나"* |
    // | `e2e4dfb` | `.onDrag(_:preview:)`로 **사본을 직접 그리고** 원본은 즉시 숨김 | ⛔ *"아래 잔상과 함께 끌리는 사본도 사라져"* |
    //
    // ### ★ 무엇을 배웠나 — **사본은 원본에 매여 있다**
    // 사본을 `preview:`로 **직접 그려도** 원본을 숨기면 사본이 같이 죽는다.
    // 즉 사본은 원본의 스냅샷일 뿐 아니라 **원본이 보이는 동안만 산다.**
    // ⛔ **그래서 「원본을 숨겨서 잔상을 없앤다」는 이 구조에서 성립하지 않는다.**
    //
    // ⚠️ **다음 세션이 다시 시도하지 말 것.** 위 테두리와 **탈출구가 같다**(`List`를 버리는 것) —
    // 둘을 함께 값에 넣어 사용자가 정한다.

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
                    // ⛔ 여기 `.onDrag`가 있었다 — **테두리를 켜려고** 넣은 것이라 함께 뺐다.
                    // 순서 바꾸기는 아래 `.onMove`가 하고, `List` 기본 동작이 더 안전하다.
                }
                .onMove { from, to in
                    var reordered = items
                    reordered.move(fromOffsets: from, toOffset: to)
                    model.reorderPrinciples(reordered)
                }
            } header: {
                // **두 줄을 항상 보인다**(사용자 결정 2026-08-20) — 무엇이 각인되는지 + 어떻게 순서를 바꾸는지.
                // ★ 테두리·손잡이를 뺀 지금 **끄는 법을 아는 길은 이 줄뿐이다.** 지우지 말 것.
                VStack(alignment: .leading, spacing: 2) {
                    Text(items.isEmpty ? "원칙 없음"
                         : "아래 \(n)개가 원칙 영역에 노출됩니다")   // 문구는 사용자가 정했다(2026-08-20)
                    if !items.isEmpty {
                        Text("눌러 끌어서 순서를 바꾸세요")   // 문구는 사용자가 정했다(2026-08-20)
                    }
                }
                .font(.footnote).foregroundStyle(Palette.textSecondary).textCase(nil)
                .frame(maxWidth: .infinity, alignment: .leading)
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
            // ⛔ **여기 ≡ 손잡이(`line.3.horizontal`)가 있었다 — 뺐다** (2026-08-20 `30e2d91`).
            // `4b20926`에서 넣었다. **그때는 집힘 신호를 못 만들던 때**라
            // 「이 줄은 끌 수 있다」를 알릴 길이 그것뿐이었다.
            // ⚠️ **자리가 나빴다** — `NavigationLink`의 `>` 바로 옆이라
            // **내비게이션 표시의 일부처럼 보였다.** 사용자가 *"이거 뭐야?"*라고 물었다.
            // ★ **못 하던 때의 임시방편이 되던 뒤에도 남아 있었다.**
        }
        // ⚠️ **이 여백은 고정이다 — 끌 때만 바꾸면 안 된다** (2026-08-20 사용자:
        // *"테두리를 그리면 공간의 크기가 변해서 그런지 안의 텍스트가 줄바꿈이 일어나네"*).
        // 옛 코드는 `dragging ? 11 : 0`으로 **좌우 22pt를 뺏어** 글자 폭을 줄였고,
        // 그래서 **집는 순간 줄바꿈 자리가 달라졌다.** 테두리는 이제 없지만
        // ★ **교훈은 남는다: 보이는 것(그림)을 바꾸려다 재는 것(레이아웃)까지 바꾸지 않는다.**
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
