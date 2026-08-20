#if os(iOS)
import SwiftUI
import UIKit
import SecondBrainCore

/// **원칙 목록의 순서 바꾸기 — UIKit 대화식 이동.** (2026-08-20)
///
/// ## 왜 `List`를 안 쓰나 — **잔상 때문이다. 실측으로 갈랐다.**
/// 사용자가 세 번 지적한 것: *"드래그할 항목이 선택이 되어 살짝 이동하면 그 아래에 기존 잔상이
/// 남아 있어. 위 혹은 아래 항목과 자리가 바뀌는 순간 사라져. 있던 것을 들어서 옮기는 거잖아?
/// 그럼 아래에 아무것도 없어야지."*
///
/// **조건은 「첫 교체 전」이다** — 크게 끌면 안 보이고 **살짝(22pt) 끌 때만** 보인다.
/// 시뮬레이터에서 같은 조건(22pt 끌고 12초 멈춤)으로 세 꼴을 쟀다:
///
/// | 꼴 | 원래 자리 | |
/// |---|---|---|
/// | SwiftUI `List` + `.onMove` | **흐린 사본이 남는다** | ⛔ |
/// | 같은 것 + `editMode = .active` | **똑같이 남는다** | ⛔ **편집모드는 답이 아니다** |
/// | **`UICollectionView` + `beginInteractiveMovementForItem`** | **비어 있다** | ✅ |
///
/// ⛔ **그래서 「편집 모드 버튼을 두면 된다」는 안은 죽었다.** SwiftUI `List`는 편집모드에서도
/// 순서 바꾸기를 **드래그앤드롭**으로 돌리고, 그 길이 첫 교체 전까지 원본을 흐리게 남긴다.
/// **손잡이만 얻고 잔상은 그대로였다.**
///
/// ## 무엇을 안 잃었나
/// - **줄 모양은 SwiftUI 그대로다** — `UIHostingConfiguration`에 `PrincipleListView.row`를 그대로 넣는다.
///   색·글꼴·「대기」 캡슐·흐림·Dynamic Type을 다시 만들지 않았다.
/// - **끌 때 자동 스크롤**은 `UICollectionView`가 해 준다.
/// - **≡ 손잡이가 필요 없다** — 길게 누르기로 시작한다(`30e2d91`에서 뺀 것을 되살리지 않았다).
///
/// ## ⚠️ 함정 — 조용히 실패한다
/// `UICollectionViewDiffableDataSource`는 **`reorderingHandlers.canReorderItem`을 켜야**
/// `beginInteractiveMovementForItem`이 먹는다. **안 켜면 오류도 로그도 없이 아무 일도 안 일어난다**
/// (2026-08-20에 실제로 밟았다 — 손짓은 들어오는데 셀이 안 움직였다).
///
/// ## macOS
/// `UIViewRepresentable`은 iOS 전용이다. **맥은 `PrincipleListView`의 `List` 경로를 그대로 쓴다**
/// (맥에서는 잔상 문제가 제기된 적이 없다 — 제기되면 그때 `NSCollectionView`로 같은 일을 한다).
struct PrincipleReorderList: UIViewRepresentable {
    let items: [ResolvedItem]
    /// 상위 N개가 「동작」(각인). 나머지는 흐리고 「대기」가 붙는다.
    let activeCount: Int
    /// 순서가 바뀌었을 때 — 모델에 쓴다.
    let onReorder: ([ResolvedItem]) -> Void
    /// 줄을 눌렀을 때 — 상세로 보낸다(`List`의 `NavigationLink`가 하던 일).
    let onSelect: (ResolvedItem) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
        cfg.backgroundColor = UIColor(Palette.bg)
        cfg.showsSeparators = false
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
        cv.backgroundColor = UIColor(Palette.bg)
        cv.delegate = context.coordinator
        cv.alwaysBounceVertical = true

        // 줄 모양은 SwiftUI 그대로 — 여기서 다시 만들지 않는다.
        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, ResolvedItem> { cell, indexPath, item in
            let active = indexPath.item < context.coordinator.parent.activeCount
            cell.contentConfiguration = UIHostingConfiguration {
                PrincipleReorderRow(item: item, active: active)
            }
            .margins(.horizontal, 16)
            .margins(.vertical, 6)
            var bg = UIBackgroundConfiguration.listCell()
            bg.backgroundColor = UIColor(Palette.bg)
            cell.backgroundConfiguration = bg
            cell.accessories = [.disclosureIndicator()]   // `List`의 `>`를 대신한다
        }

        let ds = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { cv, ip, id in
            let item = context.coordinator.parent.items.first { $0.id == id }
            return cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: item)
        }
        // ⚠️ 이 둘이 없으면 대화식 이동이 **조용히** 안 먹는다. 위 「함정」 참조.
        ds.reorderingHandlers.canReorderItem = { _ in true }
        ds.reorderingHandlers.didReorder = { [weak coord = context.coordinator] tx in
            guard let coord else { return }
            let byID = Dictionary(uniqueKeysWithValues: coord.parent.items.map { ($0.id, $0) })
            let ordered = tx.finalSnapshot.itemIdentifiers.compactMap { byID[$0] }
            // 화면은 이미 이 순서다 — 「넣은 것」으로 기록해 두고 모델에 쓴다.
            // 안 그러면 모델 → `updateUIView`에서 같은 순서를 **한 번 더** 넣는다.
            coord.appliedIDs = ordered.map(\.id)
            coord.appliedSig = Coordinator.signature(ordered, activeCount: coord.parent.activeCount)
            coord.parent.onReorder(ordered)
        }
        context.coordinator.dataSource = ds
        context.coordinator.collectionView = cv
        context.coordinator.apply(items, activeCount: activeCount)

        // 길게 눌러 **대화식 이동**을 시작한다 — 이것이 원본을 즉시 들어내는 길이다.
        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleLongPress(_:)))
        lp.minimumPressDuration = 0.35
        cv.addGestureRecognizer(lp)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        // 끌고 있는 동안에는 스냅샷을 갈아끼우지 않는다 — 들고 있는 셀이 튄다.
        guard !context.coordinator.isMoving else { return }
        context.coordinator.apply(items, activeCount: activeCount)
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: PrincipleReorderList
        var dataSource: UICollectionViewDiffableDataSource<Int, String>!
        weak var collectionView: UICollectionView?
        /// 대화식 이동 중인가 — 그동안 `updateUIView`가 스냅샷을 건드리지 않게 막는다.
        var isMoving = false
        /// 마지막으로 화면에 넣은 순서. 같은 것을 다시 넣지 않으려고 들고 있는다
        /// (`didReorder` → 모델 → `updateUIView`로 되돌아오는 되울림을 끊는다).
        var appliedIDs: [String] = []
        /// ⚠️ **순서만 보면 안 된다.** 상세에서 문장을 고치고 돌아오면 **id는 그대로고 내용만 바뀐다** —
        /// 순서만 비교하면 낡은 글이 그대로 남는다. 동작 개수(N)도 「대기」·흐림을 바꾸므로 함께 본다.
        var appliedSig: String = ""

        init(_ p: PrincipleReorderList) { parent = p }

        /// 순서 + 문장 + 동작 개수를 한 줄로 — 이것이 달라졌을 때만 화면을 건드린다.
        static func signature(_ items: [ResolvedItem], activeCount: Int) -> String {
            items.map { "\($0.id)\u{1}\($0.raw ?? "")" }.joined(separator: "\u{2}") + "\u{3}\(activeCount)"
        }

        func apply(_ items: [ResolvedItem], activeCount: Int) {
            let ids = items.map(\.id)
            let sig = Coordinator.signature(items, activeCount: activeCount)
            if ids != appliedIDs {                       // 순서·구성이 바뀌었다 → 스냅샷을 새로
                appliedIDs = ids
                appliedSig = sig
                var snap = NSDiffableDataSourceSnapshot<Int, String>()
                snap.appendSections([0])
                snap.appendItems(ids)
                dataSource.apply(snap, animatingDifferences: false)
            } else if sig != appliedSig {                // 같은 줄인데 내용만 바뀌었다 → 다시 그린다
                appliedSig = sig
                var snap = dataSource.snapshot()
                snap.reconfigureItems(ids)
                dataSource.apply(snap, animatingDifferences: false)
            }
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard let cv = collectionView else { return }
            let p = g.location(in: cv)
            switch g.state {
            case .began:
                guard let ip = cv.indexPathForItem(at: p) else { return }
                isMoving = cv.beginInteractiveMovementForItem(at: ip)
            case .changed:
                guard isMoving else { return }
                cv.updateInteractiveMovementTargetPosition(p)
            case .ended:
                guard isMoving else { return }
                cv.endInteractiveMovement()
                isMoving = false
            default:
                guard isMoving else { return }
                cv.cancelInteractiveMovement()
                isMoving = false
            }
        }

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: true)
            guard indexPath.item < parent.items.count else { return }
            parent.onSelect(parent.items[indexPath.item])
        }
    }
}

/// 원칙 한 줄 — **`List` 시절과 같은 모양.** 여백만 셀 쪽(`margins`)으로 옮겼다.
struct PrincipleReorderRow: View {
    let item: ResolvedItem
    let active: Bool

    var body: some View {
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
        .opacity(active ? 1 : 0.55)
        .contentShape(Rectangle())
    }
}
#endif
