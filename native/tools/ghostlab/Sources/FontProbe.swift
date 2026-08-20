import SwiftUI
import UIKit

/// 글자 크기 계측 — **SwiftUI 직접** vs **`UIHostingConfiguration` 셀 안**.
/// 둘 다 `.callout.weight(.medium)`으로 같은 글을 그린다. 다르면 환경이 안 흐른 것이다.
struct FontProbe: View {
    @Environment(\.dynamicTypeSize) private var dts

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("① SwiftUI 직접")
                .font(.caption).foregroundStyle(.secondary)
            Text("주차 위치 AAAA")
                .font(.callout.weight(.medium))
            Text(readout(label: "SwiftUI"))
                .font(.caption2).foregroundStyle(.blue)

            Divider()

            Text("② UIHostingConfiguration 셀 안")
                .font(.caption).foregroundStyle(.secondary)
            ProbeCollection().frame(height: 120)

            Divider()
            Text("표: 단계별 callout / body")
                .font(.caption).foregroundStyle(.secondary)
            Text(table()).font(.system(.caption2, design: .monospaced))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func readout(label: String) -> String {
        let f = UIFont.preferredFont(forTextStyle: .callout)
        let cat = UITraitCollection.current.preferredContentSizeCategory.rawValue
            .replacingOccurrences(of: "UICTContentSizeCategory", with: "")
        return "\(label): callout=\(String(format: "%.1f", f.pointSize))pt · trait=\(cat) · dts=\(dts)"
    }

    private func table() -> String {
        let cats: [(String, UIContentSizeCategory)] = [
            ("L ", .large), ("XL", .extraLarge), ("XXL", .extraExtraLarge), ("XXXL", .extraExtraExtraLarge),
        ]
        return cats.map { name, c in
            let t = UITraitCollection(preferredContentSizeCategory: c)
            let callout = UIFont.preferredFont(forTextStyle: .callout, compatibleWith: t).pointSize
            let plus2 = UIFontMetrics(forTextStyle: .callout).scaledValue(for: 18, compatibleWith: t)
            return "\(name) callout \(String(format: "%.0f", callout))  +2안 \(String(format: "%.1f", plus2))"
        }.joined(separator: "\n")
    }
}

/// 셀 안에서 같은 것을 그린다.
struct ProbeCollection: UIViewRepresentable {
    func makeUIView(context: Context) -> UICollectionView {
        var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
        cfg.showsSeparators = false
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, _, _ in
            cell.contentConfiguration = UIHostingConfiguration { CellProbe() }
                .margins(.horizontal, 0).margins(.vertical, 4)
        }
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, v in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: v)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0]); snap.appendItems([0])
        ds.apply(snap, animatingDifferences: false)
        context.coordinator.ds = ds
        return cv
    }
    func updateUIView(_ v: UICollectionView, context: Context) {}
    func makeCoordinator() -> C { C() }
    final class C { var ds: UICollectionViewDiffableDataSource<Int, Int>? }
}

struct CellProbe: View {
    @Environment(\.dynamicTypeSize) private var dts
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("주차 위치 AAAA").font(.callout.weight(.medium))
            let f = UIFont.preferredFont(forTextStyle: .callout)
            let cat = UITraitCollection.current.preferredContentSizeCategory.rawValue
                .replacingOccurrences(of: "UICTContentSizeCategory", with: "")
            Text("셀: callout=\(String(format: "%.1f", f.pointSize))pt · trait=\(cat) · dts=\(dts)")
                .font(.caption2).foregroundStyle(.red)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
