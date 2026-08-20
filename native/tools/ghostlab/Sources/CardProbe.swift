import SwiftUI
import UIKit

/// 진짜 앱의 새 카드 그대로 — 색·여백을 눈으로 보려는 것.
private let pTint = Color(red: 0x22/255, green: 0xD3/255, blue: 0xEE/255)   // principle 0x22D3EE
private let surface = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let bg = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let textPrimary = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let textTertiary = Color(red: 0x74/255, green: 0x6F/255, blue: 0x82/255)

private let pBorder = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)

struct CardProbeRow: View {
    let text: String
    let number: Int
    let active: Bool
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Text("\(number)")
                .font(.system(size: UIFont.preferredFont(forTextStyle: .callout).pointSize + 2, weight: .bold))
                .monospacedDigit().foregroundStyle(pTint)
                .frame(minWidth: 16, alignment: .trailing).padding(.top, 1)
            Text(text)
                .font(.system(size: UIFont.preferredFont(forTextStyle: .callout).pointSize + 2, weight: .medium))
                .foregroundStyle(textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold))
                .foregroundStyle(textTertiary).padding(.top, 3)
        }
        .opacity(active ? 1 : 0.55)
        .padding(.horizontal, 14).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? pTint.opacity(0.14) : surface,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(active ? pTint.opacity(0.28) : pBorder))
        .contentShape(Rectangle())
    }
}

private let cardTexts = [
    "먼저 사람을 본다 — 문제보다 사람이 앞이다. 급할수록 그렇다.",
    "짐작한 값과 잰 값을 같은 말투로 말하지 않는다.",
    "할 수 있는 것에 맞춰 요구를 줄이지 않는다. 못 하면 못 한다고 말한다.",
    "조작 하나에 기록 한 줄. 나중에 몰아 쓰지 않는다.",
    "축을 바꿨으면 문서를 훑는다.",
]

struct CardProbe: View {
    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("아래 3개가 원칙 영역에 노출됩니다")
                Text("눌러 끌어서 순서를 바꾸세요")
            }
            .font(.footnote).foregroundStyle(Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 6)
            CardCollection()
        }
        .background(bg.ignoresSafeArea())
    }
}

struct CardCollection: UIViewRepresentable {
    func makeUIView(context: Context) -> UICollectionView {
        var cfg = UICollectionLayoutListConfiguration(appearance: .plain)
        cfg.backgroundColor = UIColor(bg); cfg.showsSeparators = false
        let cv = UICollectionView(frame: .zero,
                                  collectionViewLayout: UICollectionViewCompositionalLayout.list(using: cfg))
        cv.backgroundColor = UIColor(bg)
        let reg = UICollectionView.CellRegistration<UICollectionViewListCell, Int> { cell, ip, _ in
            cell.contentConfiguration = UIHostingConfiguration {
                CardProbeRow(text: cardTexts[ip.item], number: ip.item + 1, active: ip.item < 3)
            }
            .margins(.horizontal, 16).margins(.vertical, 3)
            var b = UIBackgroundConfiguration.listPlainCell(); b.backgroundColor = UIColor(bg)
            cell.backgroundConfiguration = b
        }
        let ds = UICollectionViewDiffableDataSource<Int, Int>(collectionView: cv) { cv, ip, v in
            cv.dequeueConfiguredReusableCell(using: reg, for: ip, item: v)
        }
        var snap = NSDiffableDataSourceSnapshot<Int, Int>()
        snap.appendSections([0]); snap.appendItems([0,1,2,3,4])
        ds.apply(snap, animatingDifferences: false)
        context.coordinator.ds = ds
        return cv
    }
    func updateUIView(_ v: UICollectionView, context: Context) {}
    func makeCoordinator() -> C { C() }
    final class C { var ds: UICollectionViewDiffableDataSource<Int, Int>? }
}
