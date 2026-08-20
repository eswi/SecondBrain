import SwiftUI
import SecondBrainCore

/// 원칙 목록 화면 (memory-philosophy.md §3 — **신규 설계 화면**).
/// 전체 원칙을 순서대로(위=고순위). 꾹 눌러 드래그로 순서 변경, 항목 터치 → 상세(DetailView 재사용).
/// **순서 상위 N개가 각인 동작**(상단 원칙 영역에 노출). N은 설정에서(기본 3, 상한이지 강제 아님).
struct PrincipleListView: View {
    @ObservedObject var model: InboxModel
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    /// **지금 끌리고 있는 줄** — 3차 시도(2026-08-20). 신호는 `.onDrag`에서 온다.
    ///
    /// ### ★ 앞선 둘과 무엇이 다른가 — **흉내가 아니라 진짜 시작 신호다**
    /// 1·2차는 `LongPressGesture`로 「집혔겠지」를 **추측**했다. `List`의 순서 바꾸기도
    /// **같은 몸짓**으로 시작하므로 둘이 다퉜고 내 것이 이겨서 순서 바꾸기가 죽었다.
    /// `.onDrag`는 **끌기가 실제로 시작될 때** 시스템이 부른다 — 몸짓을 두고 다투지 않는다.
    ///
    /// ⚠️ **그래도 될지 모른다** — `.onDrag`를 얹으면 `List`가 순서 바꾸기 대신
    /// **바깥으로 끌어내는 드래그앤드롭**으로 해석할 수 있다. **판정은 실기기뿐이다.**
    /// 안 되면 이 상태와 `.onDrag`를 통째로 빼고 `ea97b0d`로 돌아간다.
    @State private var draggingID: String?

    // MARK: - ⛔ 「끌 때 원래 자리의 잔상을 없앤다」는 **안 된다** (2026-08-20에 두 번 시도)
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
    // ⚠️ **다음 세션이 다시 시도하지 말 것.** 하려면 `List`를 안 쓰고
    // `ScrollView`+직접 만든 순서 바꾸기로 가야 한다 — **지금 잘 되는 것을 통째로 갈아엎는 값이다.**
    // 사용자 판정: 잔상은 *"사소하지만"*이었고, `11fd8cb` 상태는 *"오! 지금 잘 돼!!!! 바로 이거야."*

    /// ## ⛔ 2026-08-20 — **집힘 신호를 두 번 시도했고 두 번 다 드래그를 깼다. 뺐다.**
    ///
    /// 사용자가 원한 것: *"길게 눌러 「순서 이동 가능한 상태」가 된 것을 화면으로 알 수 있게."*
    ///
    /// | 시도 | 넣은 것 | 실기기 결과 |
    /// |---|---|---|
    /// | 1차 (`d1749e2`) | `LongPressGesture` + `DragGesture(minimumDistance: 0)` 둘을 `simultaneousGesture`로 · 뜸·그림자·햅틱 | ⛔ **드래그가 안 됐다** — *"그림자가 나타나고 진동도 느껴지지만 드래그가 안 됨"* |
    /// | 2차 (`7e643f4`) | `DragGesture`만 뺐다 | ⛔ **여전히 안 됐다.** 게다가 **떼도 그림자가 남았다** |
    ///
    /// ### ★ 2차가 원인을 갈라 줬다 — **그림자가 아니라 제스처였다**
    /// *"떼도 그림자가 남는다"* = **내 `LongPressGesture`가 그 길게 누르기를 가져갔다**는 뜻이다.
    /// 그런데 **`List`의 순서 바꾸기도 길게 누르기로 시작한다.** 같은 몸짓 하나를 둘이 노리고,
    /// 내 것이 이기면 **`List`는 자기 차례를 못 받는다.**
    /// ⚠️ **`simultaneousGesture`가 이것을 막아 주지 않는다** — 「나란히 받는다」가
    /// 「`List` 내부 제스처와도 나란히」를 뜻하지는 않았다.
    ///
    /// ### ⛔ 그래서 시각효과를 바꾸는 것으로는 안 고쳐진다
    /// `.shadow`·`.scaleEffect`는 **그리기만** 한다. 테두리로 바꿔도 **이긴 쪽이 무엇을 그리느냐**가
    /// 바뀔 뿐 **누가 이기느냐**는 그대로다. **고칠 것은 그림이 아니라 제스처였고, 그래서 제스처를 뺐다.**
    ///
    /// ### 지금 남은 것 — 조작을 지키고 신호는 「가능하다」까지만
    /// **≡ 손잡이 상시 노출**(원칙 아이콘 색) + **머리글 둘째 줄.** 「지금 집혔다」는 **못 준다.**
    /// 주려면 **편집 모드 버튼**이 필요하다 — 그때는 순서 바꾸기가 **손잡이 드래그**로 바뀌어
    /// 길게 누르기를 두고 다툴 일이 없어진다. **단계가 하나 느는 것이 그 대가다.**

    var body: some View {
        let items = model.orderedPrinciples
        let n = max(1, min(activeN, items.count))   // 동작 개수(상한, 최소 1)
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                    NavigationLink(value: p) {   // 상세는 InboxView 스택의 ResolvedItem destination이 처리
                        row(p, active: idx < n, dragging: draggingID == p.id)
                    }
                    .listRowBackground(Palette.bg)
                    .listRowSeparator(.hidden)
                    // ★ **끌기 시작 신호.** 제스처가 아니라 드래그 시스템이 부르는 자리다.
                    .onDrag {
                        draggingID = p.id
                        // 끄기 안전망 — 끌다 놓아 `onMove`가 안 불릴 때를 시간이 받친다.
                        let mine = p.id
                        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                            if draggingID == mine { draggingID = nil }
                        }
                        return NSItemProvider(object: NSString(string: p.id))
                    }
                }
                .onMove { from, to in
                    var reordered = items
                    reordered.move(fromOffsets: from, toOffset: to)
                    model.reorderPrinciples(reordered)
                    draggingID = nil   // 순서가 정해졌다 = 끌기가 끝났다
                }
            } header: {
                // **두 줄을 항상 보인다**(사용자 결정 2026-08-20) — 무엇이 각인되는지 + 어떻게 순서를 바꾸는지.
                // 편집 모드 버튼을 안 두기로 했으므로 **끄는 법을 아는 길은 이 줄뿐이다.**
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
    private func row(_ item: ResolvedItem, active: Bool, dragging: Bool) -> some View {
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
            // **끌 수 있다는 표시** — 색은 원칙 아이콘과 같게(사용자가 그 색을 짚었다, 2026-08-20).
            // ⚠️ **이것은 「지금 집혔다」가 아니라 「끌 수 있다」다.** 앞의 것은 제스처가 필요하고,
            // 제스처는 `List`의 순서 바꾸기와 다툰다(위 주석). **그림만 두고 제스처는 안 둔다.**
            Image(systemName: "line.3.horizontal").font(.caption2)
                .foregroundStyle(TypeCatalog.meta("principle").color.opacity(0.55))
                .padding(.top, 3)
        }
        .padding(.vertical, dragging ? 9 : 5)
        .padding(.horizontal, dragging ? 11 : 0)
        // **테두리는 끌리는 그 줄에만, 끄는 동안만**(사용자 요구 2026-08-20).
        // ⛔ 한 번은 이것을 **모든 줄에 항상**으로 만들었다 — 감지가 안 되니까
        // 감지 없이 되는 쪽으로 바꿔 놓고 **요구가 그것이라고 스스로 고쳐 읽었다.**
        // ⚠️ 할 수 있는 것에 맞춰 요구를 줄이지 않는다 — 못 하면 못 한다고 말한다.
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(TypeCatalog.meta("principle").color.opacity(dragging ? 0.85 : 0),
                        lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.15), value: dragging)
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
