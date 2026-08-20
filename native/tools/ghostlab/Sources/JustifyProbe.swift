import SwiftUI
import UIKit

private let sample = "매일 저녁에 차를 어디다 주차 하는지에 대해서 자동으로 기록해놓거나 또는 기억할 수 있는 방법을 만들어야 됩니다 그리고 한 줄 더"
private var fsize: CGFloat { UIFont.preferredFont(forTextStyle: .callout).pointSize + 2 }

/// 좌우 맞춤이 되는 길이 있나 — 세 가지를 나란히 그려 오른쪽 끝을 본다.
struct JustifyProbe: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("① SwiftUI Text (기본 왼쪽 맞춤)").font(.caption2).foregroundStyle(.blue)
            Text(sample).font(.system(size: fsize, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)

            Text("② SwiftUI Text + AttributedString(paragraphStyle .justified)")
                .font(.caption2).foregroundStyle(.blue)
            Text(justifiedAttributed())
                .fixedSize(horizontal: false, vertical: true)

            Text("③ UILabel(textAlignment = .justified) via UIViewRepresentable")
                .font(.caption2).foregroundStyle(.blue)
            JustifiedLabel(text: sample)
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func justifiedAttributed() -> AttributedString {
        var a = AttributedString(sample)
        let ps = NSMutableParagraphStyle()
        ps.alignment = .justified
        ps.lineBreakMode = .byWordWrapping
        a.paragraphStyle = ps
        a.font = .system(size: fsize, weight: .medium)
        return a
    }
}

/// UIKit 라벨을 그대로 쓴다. `sizeThatFits`로 여러 줄 높이를 SwiftUI에 알려준다.
struct JustifiedLabel: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.lineBreakMode = .byWordWrapping
        l.textAlignment = .justified
        l.text = text
        l.font = .systemFont(ofSize: fsize, weight: .medium)
        l.textColor = .label
        return l
    }
    func updateUIView(_ v: UILabel, context: Context) {
        v.text = text
        v.font = .systemFont(ofSize: fsize, weight: .medium)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let w = proposal.width ?? UIScreen.main.bounds.width - 32
        uiView.preferredMaxLayoutWidth = w
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: h)
    }
}
