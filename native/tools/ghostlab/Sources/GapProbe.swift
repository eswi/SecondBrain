import SwiftUI
import UIKit

/// 여백 계측 — **진짜 줄 모양 그대로** 옛 그릇(SwiftUI List)과 새 그릇(UIHostingConfiguration 셀)에 넣고
/// **줄 간격(pitch)**을 잰다. 줄 내용이 같아야 그릇 차이만 남는다.
private let gapRows: [(String, Color)] = [
    ("AAAA 첫째줄 — 이 문장은 일부러 길게 써서 두 줄 이상으로 접히게 만든 것이다. 여러 줄로 접히는 줄.", .red),
    ("BBBB 둘째줄 — 이것도 길게 써서 접히게 한다. 실제 원칙 문장들이 대체로 이 정도 길이다. 여러 줄로.", .red),
    ("CCCC 셋째줄 — 세 번째 줄도 마찬가지로 여러 줄이 되도록 길게 적어 둔다. 같은 길이로 맞춘다 여기.", .red),
]

/// 진짜 줄과 같은 구성 — 표식(사각형) + `.callout + 2pt` 여러 줄.
struct GapRow: View {
    let text: String
    let mark: Color
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Rectangle().fill(mark).frame(width: 22, height: 22).padding(.top, 3)
            Text(text)
                .font(.system(size: UIFont.preferredFont(forTextStyle: .callout).pointSize + 2, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct GapProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            Text("① 옛 그릇: SwiftUI List(.plain) + 줄에 .padding(.vertical,5)")
                .font(.caption2).frame(maxWidth: .infinity, alignment: .leading).padding(4)
            List {
                ForEach(0..<3, id: \.self) { i in
                    GapRow(text: gapRows[i].0, mark: .red)
                        .padding(.vertical, 5)
                        .listRowBackground(Color.white)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .frame(height: 330)

            Text("② 새 그릇: UIHostingConfiguration 셀 + margins(.vertical, 20)")
                .font(.caption2).frame(maxWidth: .infinity, alignment: .leading).padding(4)
            GapCollection(margin: 20).frame(height: 330)
        }
    }
}

struct GapCollection: UIViewRepresentable {
    let margin: CGFloat
    func makeUIView(context: Context) -> UICollectionView {
        var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
        cfg.showsSeparators = false
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
        let m = margin
        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, ip, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                GapRow(text: gapRows[ip.item].0, mark: .green)
            }
            .margins(.horizontal, 16).margins(.vertical, m)
            cell.accessories = [.disclosureIndicator()]
        }
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, v in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: v)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0]); snap.appendItems([0,1,2])
        ds.apply(snap, animatingDifferences: false)
        context.coordinator.ds = ds
        return cv
    }
    func updateUIView(_ v: UICollectionView, context: Context) {}
    func makeCoordinator() -> C { C() }
    final class C { var ds: UICollectionViewDiffableDataSource<Int, Int>? }
}
