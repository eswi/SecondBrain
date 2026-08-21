import SwiftUI
import UIKit

//  ── 금칙 처리 — **단어 중간 끊기를 켜면 문장부호가 줄 앞으로 넘어가나** (2026-08-21 신설)
//
//  ⛔ 계기: 셀 시험(K 카드)에서 봤다 — *"…요구를 줄이지 않는다 / **.** 못 하면 못 한다고 말한다."*
//  마침표가 **다음 줄 맨 앞**에 왔다. 한국어 조판에서 하면 안 되는 것이고, 줄 앞의 **빈칸**도 같은 종류다.
//
//  가설: `lineBreakStrategy = []`가 **금칙 처리까지 끈다.** `byCharWrapping`은 그대로 두고
//  전략만 바꿔 셋을 나란히 본다 — 단어 중간 끊기를 **지키면서** 부호만 안 넘어가는 값이 있나.
//
//    ㉠ []          ← 지금 앱에 넣은 것
//    ㉡ .pushOut
//    ㉢ .standard   ← 기본값(한글 어절 우선이 여기 들어 있다)
//
//  ⚠️ **셋 다 「단어 중간에서 끊기나」를 함께 봐야 한다** — 부호가 안 넘어가는 대신
//  줄이 다시 일찍 끝나 버리면 D를 고른 뜻이 없어진다.

private let textPrimary = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let textSecond = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let bgc = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let pTint = Color(red: 0x22/255, green: 0xD3/255, blue: 0xEE/255)

/// 부호가 여러 개 든 표본 둘. 위는 K 카드에서 실제로 깨진 그 문장.
private let punctSamples = [
    "할 수 있는 것에 맞춰 요구를 줄이지 않는다. 못 하면 못 한다고 말한다.",
    "먼저 사람을 본다 — 문제보다 사람이 앞이다. 급할수록 그렇다. 쉼표, 마침표. 물음표? 느낌표!",
]

private struct Strat: Identifiable {
    let id: String
    let value: NSParagraphStyle.LineBreakStrategy
}
private let strats: [Strat] = [
    Strat(id: "㉠ []  ← 지금 앱", value: []),
    Strat(id: "㉡ .pushOut", value: .pushOut),
    Strat(id: "㉢ .standard (기본)", value: .standard),
]

struct PunctProbe: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("금칙 — 부호가 줄 앞으로 넘어가나 · 폭 298pt · 좌우 맞춤 + byCharWrapping 고정")
                    .font(.caption2).foregroundStyle(pTint)
                ForEach(Array(punctSamples.enumerated()), id: \.offset) { i, s in
                    Text("표본 \(i + 1)").font(.caption.weight(.semibold)).foregroundStyle(textSecond)
                    ForEach(strats) { st in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(st.id).font(.caption2).foregroundStyle(textSecond)
                            PunctLabel(text: s, strategy: st.value)
                                .frame(width: 298)
                                .overlay(alignment: .trailing) {
                                    Rectangle().fill(pTint.opacity(0.35)).frame(width: 1)
                                }
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgc.ignoresSafeArea())
    }
}

private struct PunctLabel: UIViewRepresentable {
    let text: String
    let strategy: NSParagraphStyle.LineBreakStrategy
    private var size: CGFloat { UIFont.preferredFont(forTextStyle: .callout).pointSize + 2 }

    private func attributed() -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .justified
        ps.lineBreakMode = .byCharWrapping
        ps.lineBreakStrategy = strategy
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: UIColor(textPrimary),
            .paragraphStyle: ps,
        ])
    }
    func makeUIView(context: Context) -> UILabel {
        let l = UILabel(); l.numberOfLines = 0; l.backgroundColor = .clear
        l.attributedText = attributed(); return l
    }
    func updateUIView(_ v: UILabel, context: Context) { v.attributedText = attributed() }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0, w < .infinity else { return nil }
        uiView.preferredMaxLayoutWidth = w
        return CGSize(width: w, height: ceil(uiView.sizeThatFits(
            CGSize(width: w, height: .greatestFiniteMagnitude)).height))
    }
}
