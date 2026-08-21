import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// **좌우 맞춤 + 단어 중간 끊기**로 그리는 글. 원칙 문장 전용(2026-08-21 사용자 결정 — 랩에서 넷을 재고 D를 골랐다).
///
/// ## 왜 UIKit인가 — SwiftUI로는 안 된다 (2026-08-20 실측)
/// `Text`의 `.multilineTextAlignment`에는 **좌우 맞춤이 아예 없고**, `AttributedString`에
/// 문단 정렬(`.justified`)을 실어도 **SwiftUI가 무시한다.** 그래서 글자만 `UILabel`로 바꾼다.
///
/// ## 왜 「단어 중간 끊기」를 함께 거나 — **둘은 대체가 아니라 짝이다**
/// 좌우 맞춤만 켜면 남는 폭을 **빈칸 몇 개에 몰아서** 벌린다. 단어 중간 끊기를 함께 걸면
/// **벌릴 폭 자체가 줄어** 덜 벌어진다. 랩 픽셀 실측(폭 298pt · 18pt medium · 2026-08-21):
///
/// | 꼴 | 오른쪽 남는 폭(최대) | 빈칸 폭(최대) |
/// |---|---|---|
/// | A 왼쪽·어절 *(옛 상태)* | 28.0 / **47.0**(102자) | 6.7 / 7.3 |
/// | B 좌우·어절 | ~1.0 | 11.7 / **11.7** |
/// | C 왼쪽·단어중간 | 15.3 / 12.7 | 7.0 / 7.7 |
/// | **D 좌우·단어중간** ← 이것 | **~1.0** | **10.7 / 9.7** (최악 줄 11.7 → 8.0) |
///
/// ⚠️ **「0에 가깝게」는 아니다** — 한글 한 글자가 **15.6pt**라 그보다 작은 남는 폭은
/// 글자로 못 메우고 빈칸으로 간다. D도 자연 폭보다 **최대 3pt쯤** 넓다.
///
/// ## ⛔ 재는 법 — 계산하지 말고 픽셀로 볼 것
/// **`CTFramesetter`는 `lineBreakMode`·`lineBreakStrategy`를 무시하고 `UILabel`은 지킨다.**
/// 계산으로 재면 A와 C가 **같게 나오는데 화면은 다르다.** 같은 iOS 안에서 엔진이 갈린 자리다.
/// → 재려면 `native/tools/ghostlab/measure-justify-px.swift`(스크린샷 픽셀)를 쓴다.
///
/// ## 맥은 왼쪽 맞춤으로 남는다
/// `UILabel`은 iOS 전용이다. 맥은 `Text` 그대로다 — **두 플랫폼이 갈리는 것을 알고 받아들였다.**
///
/// ## ⚠️ 아직 판정 안 된 것 — 줄 앞의 빈칸
/// 줄바꿈이 빈칸 자리에서 일어나면 **그 빈칸이 다음 줄 앞에 남는다**(랩에서 보였다:
/// 「…몇 번 / ␣그러는 그러는데」). 고치려면 TextKit을 직접 다뤄야 해서 **손대지 않았다.**
struct JustifiedText: View {
    let text: String
    /// 이미 계산된 글자 크기(pt). 쓰는 쪽이 `PrincipleFont.size` 같은 값을 준다 —
    /// ⚠️ **여기서 계산하지 않는다.** 단계가 바뀔 때 다시 그리는 의존(`@Environment`)은 쓰는 쪽에 있다.
    let size: CGFloat
    let color: Color

    var body: some View {
        #if os(iOS)
        JustifiedLabel(text: text, size: size, color: color)
        #else
        // 맥: 좌우 맞춤 없음(UILabel이 iOS 전용). 글꼴·색은 같게 둔다.
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if os(iOS)
/// `UILabel` 하나. 굵기는 **medium 하나뿐**이다 — 쓰는 자리 둘이 다 medium이다(늘면 인자로 뺀다).
private struct JustifiedLabel: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: Color

    private func attributed() -> NSAttributedString {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .justified
        // ⚠️ 둘을 함께 켜야 한다 — `byCharWrapping`만으로는 한글 어절 우선(`.standard`)이 남아 안 쪼갠다.
        ps.lineBreakMode = .byCharWrapping
        ps.lineBreakStrategy = []
        return NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium),
            .foregroundColor: UIColor(color),
            .paragraphStyle: ps,
        ])
    }

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.backgroundColor = .clear
        l.attributedText = attributed()
        return l
    }

    func updateUIView(_ v: UILabel, context: Context) { v.attributedText = attributed() }

    /// 여러 줄 높이를 SwiftUI에 알려준다. 이게 없으면 한 줄로 잘린다.
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0, w < .infinity else { return nil }
        uiView.preferredMaxLayoutWidth = w
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: ceil(h))
    }
}
#endif
