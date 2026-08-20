import SwiftUI
import SecondBrainCore
#if os(iOS)
import UIKit   // 햅틱(UIImpactFeedbackGenerator)만 쓴다
#endif

/// 원칙 목록 화면 (memory-philosophy.md §3 — **신규 설계 화면**).
/// 전체 원칙을 순서대로(위=고순위). 꾹 눌러 드래그로 순서 변경, 항목 터치 → 상세(DetailView 재사용).
/// **순서 상위 N개가 각인 동작**(상단 원칙 영역에 노출). N은 설정에서(기본 3, 상한이지 강제 아님).
struct PrincipleListView: View {
    @ObservedObject var model: InboxModel
    @AppStorage(PrincipleSettings.activeCountKey) private var activeN = PrincipleSettings.defaultActiveCount

    /// **지금 집힌 줄** — 길게 눌러 「순서 이동 가능한 상태」가 된 것을 **화면으로 보이게** 한다(2026-08-20).
    ///
    /// **왜 편집 모드 버튼이 아닌가:** 길게 눌러 바로 끄는 조작이 **이미 되고 있었다**(실기기 확인 2026-08-20).
    /// 버튼을 두면 단계가 하나 늘고 그 조작을 대체한다. **없던 것은 조작이 아니라 신호였다.**
    ///
    /// ⚠️ **실험적이다** — 제스처를 얹어 SwiftUI 기본 드래그와 다툴 수 있다(사용자 판단 2026-08-20:
    /// *"안전보다는 실험적으로 가보자. 이상하면 안전하게 바꾸면 되니까."*).
    /// **드래그가 여전히 되는지는 실기기에서만 판정된다** — `simultaneousGesture`를 쓴 것이 그 대비다
    /// (제스처를 **가로채지 않고 나란히** 받는다).
    @State private var grabbedID: String?

    var body: some View {
        let items = model.orderedPrinciples
        let n = max(1, min(activeN, items.count))   // 동작 개수(상한, 최소 1)
        List {
            Section {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, p in
                    NavigationLink(value: p) {   // 상세는 InboxView 스택의 ResolvedItem destination이 처리
                        row(p, active: idx < n)
                    }
                    .listRowBackground(grabbedID == p.id ? Palette.surface2 : Palette.bg)
                    .listRowSeparator(.hidden)
                    // ★ 집힌 줄을 눈에 보이게 — 살짝 뜨고, 그림자가 진다.
                    .scaleEffect(grabbedID == p.id ? 1.03 : 1, anchor: .leading)
                    .shadow(color: .black.opacity(grabbedID == p.id ? 0.45 : 0), radius: 8, y: 3)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: grabbedID)
                    // ⚠️ 둘 다 `simultaneousGesture` — 드래그를 **가로채지 않는다.**
                    // 길게 누르면 집힘 신호를 켜고, 손을 떼면(드래그 끝) 끈다.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.3).onEnded { _ in grab(p.id) }
                    )
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0).onEnded { _ in grabbedID = nil }
                    )
                }
                .onMove { from, to in
                    var reordered = items
                    reordered.move(fromOffsets: from, toOffset: to)
                    model.reorderPrinciples(reordered)
                    grabbedID = nil
                }
            } header: {
                // **두 줄을 항상 보인다**(사용자 결정 2026-08-20) — 무엇이 각인되는지 + 어떻게 순서를 바꾸는지.
                // 편집 모드 버튼을 안 두기로 했으므로 **끄는 법을 아는 길은 이 줄뿐이다.**
                VStack(alignment: .leading, spacing: 2) {
                    Text(items.isEmpty ? "원칙 없음"
                         : "위 \(n)개가 각인 동작 — 상단 원칙 영역에 노출")
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

    /// **집혔다**를 켠다 — 화면(뜸·그림자·배경)과 **손**(햅틱) 둘로 알린다.
    /// 햅틱은 iOS만 — macOS엔 `UIImpactFeedbackGenerator`가 없다.
    private func grab(_ id: String) {
        guard grabbedID != id else { return }   // 같은 줄에 두 번 울리지 않는다
        grabbedID = id
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
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
