import SwiftUI
import UIKit

/// 진짜 앱의 `PrincipleReorderList`와 같은 짜임 — 끌기 도중 번호·바탕색이 따라오는지 보려는 것.
struct UIKitList: UIViewRepresentable {
    @Binding var rows: [ReplicaRow]
    var activeCount = 3

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UICollectionView {
        var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
        cfg.backgroundColor = UIColor(red: 0x13/255, green: 0x12/255, blue: 0x18/255, alpha: 1)
        cfg.showsSeparators = false
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
        cv.backgroundColor = cfg.backgroundColor
        cv.delegate = context.coordinator

        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, ReplicaRow> { cell, ip, item in
            let visual = context.coordinator.visualIndex(ip.item)
            let active = visual < context.coordinator.parent.activeCount
            cell.contentConfiguration = UIHostingConfiguration {
                CardProbeRow(text: item.text, number: visual + 1, active: active)
            }
            .margins(.horizontal, 16).margins(.vertical, 3)
            var b = UIBackgroundConfiguration.listPlainCell()
            b.backgroundColor = cfg.backgroundColor
            cell.backgroundConfiguration = b
        }
        let ds = UICollectionViewDiffableDataSource<Int, String>(collectionView: cv) { cv, ip, id in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip,
                                             item: context.coordinator.parent.rows.first { $0.id == id })
        }
        ds.reorderingHandlers.canReorderItem = { _ in true }
        ds.reorderingHandlers.didReorder = { [weak coord = context.coordinator] tx in
            guard let coord else { return }
            let byID = Dictionary(uniqueKeysWithValues: coord.parent.rows.map { ($0.id, $0) })
            let ordered = tx.finalSnapshot.itemIdentifiers.compactMap { byID[$0] }
            coord.dragFrom = nil; coord.dragTo = nil
            DispatchQueue.main.async { coord.reconfigureAll() }
            coord.parent.rows = ordered
        }
        context.coordinator.dataSource = ds
        context.coordinator.collectionView = cv
        context.coordinator.apply(rows)

        let lp = UILongPressGestureRecognizer(target: context.coordinator,
                                              action: #selector(Coordinator.handleLongPress(_:)))
        lp.minimumPressDuration = 0.35
        cv.addGestureRecognizer(lp)
        return cv
    }

    func updateUIView(_ uiView: UICollectionView, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isMoving else { return }
        context.coordinator.apply(rows)
    }

    final class Coordinator: NSObject, UICollectionViewDelegate {
        var parent: UIKitList
        var dataSource: UICollectionViewDiffableDataSource<Int, String>!
        weak var collectionView: UICollectionView?
        var isMoving = false
        var appliedIDs: [String] = []
        var dragFrom: Int?
        var dragTo: Int?
        init(_ p: UIKitList) { parent = p }

        func visualIndex(_ dataIndex: Int) -> Int {
            guard let f = dragFrom, let t = dragTo, f != t else { return dataIndex }
            if dataIndex == f { return t }
            var i = dataIndex
            if dataIndex > f { i -= 1 }
            if i >= t { i += 1 }
            return i
        }

        func reconfigureAll() {
            guard let ds = dataSource else { return }
            var snap = ds.snapshot()
            guard !snap.itemIdentifiers.isEmpty else { return }
            snap.reconfigureItems(snap.itemIdentifiers)
            ds.apply(snap, animatingDifferences: false)
        }

        func apply(_ rows: [ReplicaRow]) {
            let ids = rows.map(\.id)
            guard ids != appliedIDs else { return }
            appliedIDs = ids
            var snap = NSDiffableDataSourceSnapshot<Int, String>()
            snap.appendSections([0]); snap.appendItems(ids)
            dataSource.apply(snap, animatingDifferences: false)
        }

        @objc func handleLongPress(_ g: UILongPressGestureRecognizer) {
            guard let cv = collectionView else { return }
            let p = g.location(in: cv)
            switch g.state {
            case .began:
                guard let ip = cv.indexPathForItem(at: p) else { return }
                isMoving = cv.beginInteractiveMovementForItem(at: ip)
                if isMoving { dragFrom = ip.item; dragTo = ip.item }
            case .changed:
                guard isMoving else { return }
                cv.updateInteractiveMovementTargetPosition(p)
            case .ended:
                guard isMoving else { return }
                cv.endInteractiveMovement(); isMoving = false
            default:
                guard isMoving else { return }
                cv.cancelInteractiveMovement(); isMoving = false
                dragFrom = nil; dragTo = nil; reconfigureAll()
            }
        }

        func collectionView(_ collectionView: UICollectionView,
                            targetIndexPathForMoveOfItemFromOriginalIndexPath original: IndexPath,
                            atCurrentIndexPath current: IndexPath,
                            toProposedIndexPath proposed: IndexPath) -> IndexPath {
            if dragFrom == nil { dragFrom = original.item }
            if dragTo != proposed.item { dragTo = proposed.item; reconfigureAll() }
            return proposed
        }
    }
}

struct UIKitListScreen: View {
    @State private var rows = replicaSeed
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("아래 3개가 원칙 영역에 노출됩니다")
            Text("눌러 끌어서 순서를 바꾸세요")
        }
        .font(.footnote).foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.top, 8)
        UIKitList(rows: $rows)
            .background(Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255))
    }
}
