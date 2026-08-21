import SwiftUI
import CoreText
#if canImport(UIKit)
import UIKit
#endif

//  ══════════════════════════════════════════════════════════════════════════════════
//  좌우 맞춤 — **줄바꿈 자리를 우리가 정한다** (2026-08-21 사용자 결정)
//
//  ## 왜 직접 정하나 — 시스템 설정으로는 안 됐다
//  1차(같은 날 오전)는 `UILabel` + `lineBreakMode = .byCharWrapping` + `lineBreakStrategy = []`였다.
//  **좌우 맞춤과 단어 중간 끊기는 됐지만 대가 둘이 생겼다:**
//    ⛔ 부호가 줄 앞으로 넘어간다 — 「…요구를 줄이지 않는다 / **.** 못 하면」
//    ⛔ 줄바꿈이 빈칸 자리에서 일어나면 그 **빈칸이 다음 줄 앞에 남는다**
//  `lineBreakStrategy` 셋(`[]` · `.pushOut` · `.standard`)을 화면에서 나란히 봤는데 **전부 같았다**
//  (랩 `PunctProbe` · N 금칙). **전략으로는 못 고친다** → 그래서 줄을 직접 나눈다.
//
//  ## ★ 사용자 원칙 셋 (2026-08-21) — 이 파일이 그것을 구현한다
//  **①** 부호가 줄 앞에 오려 하면 **부호 바로 앞 글자를 함께 내린다** — 그래서 **글자가 줄 시작**이 된다.
//      ⚠️ **그 글자가 한글일 때만.** 한글이 아니면 **부호가 앞에 오는 것을 허용한다.**
//  **②** **어떤 경우에도 줄 앞에 빈칸이 오면 안 된다.** 앞 빈칸을 **없애고 나서** 맞추기를 계산한다.
//      예외: **첫 줄**은 허용(원문이 빈칸으로 시작하는 경우).
//  **③** **한글이 아닌 것(영어·숫자 등)은 단어 안에서 자르지 않는다.** 한글만 글자 단위로 끊는다.
//
//  ## 재는 법 — ⛔ 계산을 믿지 말고 픽셀로 볼 것
//  **`CTFramesetter`는 `lineBreakMode`·`lineBreakStrategy`를 무시하고 `UILabel`은 지킨다**(같은 iOS 안에서).
//  1차 때 그걸 몰라 **「단어 중간 끊기는 이득이 0」이라는 반대 결론**이 나올 뻔했다.
//  → 재려면 `native/tools/ghostlab/measure-justify-px.swift`(스크린샷 픽셀)를 쓴다.
//  랩 실측(폭 298pt · 18pt medium): 좌우 맞춤만 켜면 빈칸이 **최대 11.7pt**까지 벌어지고,
//  단어 중간 끊기를 함께 걸면 **9.7pt**로 내려간다(최악 줄 11.7 → 8.0). 한글 한 글자가 **15.6pt**라
//  그보다 작은 남는 폭은 글자로 못 메우고 빈칸으로 간다 — **「0에 가깝게」는 원리적으로 안 된다.**
//
//  ## 맥은 왼쪽 맞춤으로 남는다
//  그리는 쪽이 `UIView`(iOS 전용)다. 맥은 `Text` 그대로 — **두 플랫폼이 갈리는 것을 알고 받아들였다.**
//
//  ## ⚠️ 시험이 없다
//  줄 나누기(`JustifiedLineBreaker`)는 **순수 함수라 시험할 수 있는데 App 층에 있어서 시험이 없다.**
//  `SecondBrainCore`로 옮기면 시험이 붙는다 — **다만 그건 층을 옮기는 결정이라 사용자 사안이다.**
//  지금은 **화면·픽셀로만** 확인했다(랩 `RulesProbe` · O 원칙).
//  ══════════════════════════════════════════════════════════════════════════════════

/// 글자 갈래 — 원칙 ①③이 이 구분 위에 서 있다.
enum JustifyCharKind {
    case space          // 빈칸 (원칙 ②)
    case hangul         // 한글 — **글자 단위로 끊을 수 있다** (원칙 ③의 「한글만」)
    case other          // 그 밖 — 영어·숫자·부호. **덩어리로 붙어 다닌다** (원칙 ③)

    static func of(_ c: Character) -> JustifyCharKind {
        if c.isWhitespace { return .space }
        guard let u = c.unicodeScalars.first else { return .other }
        // 한글: 완성형 음절 · 자모 · 호환 자모
        if (0xAC00...0xD7A3).contains(u.value)
            || (0x1100...0x11FF).contains(u.value)
            || (0x3130...0x318F).contains(u.value) { return .hangul }
        return .other
    }

    /// 부호인가 — 원칙 ①이 「줄 앞에 오면 안 되는 것」으로 보는 것.
    static func isPunct(_ c: Character) -> Bool {
        c.isPunctuation || c.isSymbol
    }
}

/// **줄을 직접 나눈다.** 순수 계산 — 그리기와 섞지 않는다(재기·시험을 위해).
struct JustifiedLineBreaker {
    let font: CTFont
    let width: CGFloat

    /// 한 덩어리 — 빈칸 하나 · 한글 한 글자 · 그 밖의 이어붙은 덩어리(원칙 ③).
    private struct Atom { let text: String; let kind: JustifyCharKind }

    struct Line {
        let text: String
        /// 문단의 마지막 줄인가 — **좌우 맞춤을 걸지 않는 줄**이다(정의상 왼쪽 맞춤).
        let isParagraphEnd: Bool
    }

    func lines(_ source: String) -> [Line] {
        // 원문의 줄바꿈은 문단 경계로 지킨다.
        source.components(separatedBy: "\n").flatMap { paragraph -> [Line] in
            var out = breakParagraph(paragraph)
            if out.isEmpty { out = [Line(text: "", isParagraphEnd: true)] }
            return out
        }
    }

    private func atoms(_ s: String) -> [Atom] {
        var out: [Atom] = []
        for c in s {
            let k = JustifyCharKind.of(c)
            if k == .other, let last = out.last, last.kind == .other {
                out[out.count - 1] = Atom(text: last.text + String(c), kind: .other)   // 원칙 ③ — 붙여 둔다
            } else {
                out.append(Atom(text: String(c), kind: k))
            }
        }
        return out
    }

    private func fits(_ s: String) -> Bool { measure(s) <= width + 0.01 }

    private func measure(_ s: String) -> CGFloat {
        guard !s.isEmpty else { return 0 }
        let a = NSAttributedString(string: s, attributes: [.font: font as Any])
        var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
        return CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(a), &asc, &desc, &lead))
    }

    private func breakParagraph(_ paragraph: String) -> [Line] {
        let items = atoms(paragraph)
        guard !items.isEmpty else { return [] }

        var out: [Line] = []
        var cur = ""
        var i = 0
        var isFirstLine = true

        while i < items.count {
            let atom = items[i]

            // ── 원칙 ② — 줄 앞 빈칸은 버린다. **첫 줄만 예외**(원문이 빈칸으로 시작하는 경우).
            if cur.isEmpty, atom.kind == .space, !isFirstLine { i += 1; continue }

            let candidate = cur + atom.text
            if fits(candidate) || cur.isEmpty {
                // 한 덩어리가 혼자서도 폭을 넘으면(아주 긴 영문·URL) 그때는 쪼갠다 —
                // 원칙 ③의 예외. 쪼개지 않으면 넘쳐서 잘려 보인다.
                if cur.isEmpty, !fits(atom.text), atom.kind == .other, atom.text.count > 1 {
                    let (head, rest) = splitOversized(atom.text)
                    out.append(Line(text: head, isParagraphEnd: false))
                    var replaced = items
                    replaced[i] = Atom(text: rest, kind: .other)
                    return out + breakRemainder(replaced, from: i)
                }
                cur = candidate
                i += 1
                continue
            }

            // ── 줄을 끊는다. 먼저 원칙 ①을 본다.
            var breakAt = i
            if let first = atom.text.first, JustifyCharKind.isPunct(first),
               let lastChar = cur.last, JustifyCharKind.of(lastChar) == .hangul,
               breakAt - 1 >= 0, items[breakAt - 1].kind == .hangul,
               cur.count > 1 {
                // 부호가 줄 앞에 오려 한다 → **부호 바로 앞 한글을 함께 내린다.**
                cur.removeLast()
                breakAt -= 1
            }

            out.append(Line(text: trimTail(cur), isParagraphEnd: false))
            cur = ""
            isFirstLine = false
            i = breakAt
        }

        if !cur.isEmpty || out.isEmpty {
            out.append(Line(text: trimTail(cur), isParagraphEnd: true))
        } else if var last = out.popLast() {
            last = Line(text: last.text, isParagraphEnd: true)
            out.append(last)
        }
        return out
    }

    /// 남은 덩어리들로 이어서 나눈다(긴 덩어리를 쪼갠 뒤 재진입용).
    private func breakRemainder(_ items: [Atom], from index: Int) -> [Line] {
        let rest = items[index...].map(\.text).joined()
        return breakParagraph(rest)
    }

    /// 폭보다 긴 한 덩어리를 글자 수로 쪼갠다 — 들어가는 만큼만 앞에 남긴다.
    private func splitOversized(_ s: String) -> (String, String) {
        var head = ""
        for c in s {
            if !fits(head + String(c)), !head.isEmpty { break }
            head.append(c)
        }
        return (head, String(s.dropFirst(head.count)))
    }

    /// 줄 끝 빈칸은 지운다 — 좌우 맞춤이 **끝 빈칸까지 늘려** 오른쪽이 비어 보이는 것을 막는다.
    private func trimTail(_ s: String) -> String {
        var t = s
        while let l = t.last, l.isWhitespace { t.removeLast() }
        return t
    }
}

/// ⚠️ **내가 더한 안전장치 하나 — 「너무 짧은 줄은 맞추지 않는다」** (2026-08-21).
/// 원칙 셋에는 없는 것이다. 넣은 이유: 랩에서 **줄이 짧을 때 자간이 크게 벌어졌다** —
/// 「링　　　크　　　는」처럼(다음 덩어리가 URL이라 3글자만 남은 줄). **글자 사이가 벌어지는 것은
/// 좌우 맞춤의 목적(가지런함)과 정반대다.**
/// → **자연 폭이 칸 폭의 `justifyMinFill`(=0.85) 미만이면 그 줄은 왼쪽 맞춤으로 남긴다.**
/// 한글 줄은 남는 폭이 한 글자(15.6pt ≈ 5%)보다 작아 **거의 다 맞춰진다** — 걸리는 것은
/// **긴 영문·URL 때문에 일찍 끝난 줄**뿐이다. ⛔ **이 값은 사용자가 정할 사안이다** — 바꾸려면 여기 한 줄.
private let justifyMinFill: CGFloat = 0.85

/// 원칙 문장을 그린다. iOS는 직접 그리고, 맥은 `Text`(왼쪽 맞춤).
struct JustifiedText: View {
    let text: String
    /// 이미 계산된 글자 크기(pt) — ⚠️ **여기서 계산하지 않는다.**
    /// 단계가 바뀔 때 다시 그리는 의존(`@Environment(\.dynamicTypeSize)`)은 **쓰는 쪽**에 있다.
    let size: CGFloat
    let color: Color

    var body: some View {
        #if os(iOS)
        JustifiedTextRepresentable(text: text, size: size, color: color)
        #else
        Text(text)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if os(iOS)
private struct JustifiedTextRepresentable: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let color: Color

    func makeUIView(context: Context) -> JustifiedTextView {
        let v = JustifiedTextView()
        v.configure(text: text, size: size, color: UIColor(color))
        return v
    }
    func updateUIView(_ v: JustifiedTextView, context: Context) {
        v.configure(text: text, size: size, color: UIColor(color))
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: JustifiedTextView,
                      context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0, w < .infinity else { return nil }
        return CGSize(width: w, height: uiView.height(forWidth: w))
    }
}

/// 줄을 직접 나눠 **줄마다 좌우 맞춤으로** 그린다. 마지막 줄은 맞추지 않는다(정의상 왼쪽).
final class JustifiedTextView: UIView {
    private var text = ""
    private var size: CGFloat = 17
    private var color: UIColor = .label
    private var lastWidth: CGFloat = 0
    private var cached: [JustifiedLineBreaker.Line] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true        // 글을 직접 그리므로 접근성은 우리가 알려야 한다
    }
    required init?(coder: NSCoder) { fatalError("스토리보드로 안 쓴다") }

    func configure(text: String, size: CGFloat, color: UIColor) {
        guard self.text != text || self.size != size || self.color != color else { return }
        self.text = text; self.size = size; self.color = color
        accessibilityLabel = text
        cached = []; lastWidth = 0
        setNeedsDisplay(); invalidateIntrinsicContentSize()
    }

    private var font: UIFont { .systemFont(ofSize: size, weight: .medium) }
    private var lineHeight: CGFloat { ceil(font.lineHeight) }

    private func lines(forWidth w: CGFloat) -> [JustifiedLineBreaker.Line] {
        if w == lastWidth, !cached.isEmpty { return cached }
        let broken = JustifiedLineBreaker(font: font as CTFont, width: w).lines(text)
        cached = broken; lastWidth = w
        return broken
    }

    func height(forWidth w: CGFloat) -> CGFloat {
        CGFloat(lines(forWidth: w).count) * lineHeight
    }

    override var intrinsicContentSize: CGSize {
        let w = bounds.width > 0 ? bounds.width : UIView.noIntrinsicMetric
        guard w != UIView.noIntrinsicMetric else { return CGSize(width: w, height: lineHeight) }
        return CGSize(width: w, height: height(forWidth: w))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if bounds.width != lastWidth { cached = []; setNeedsDisplay(); invalidateIntrinsicContentSize() }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext(), bounds.width > 0 else { return }
        let w = bounds.width
        let broken = lines(forWidth: w)
        ctx.textMatrix = .identity
        ctx.translateBy(x: 0, y: bounds.height)
        ctx.scaleBy(x: 1, y: -1)

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        for (i, line) in broken.enumerated() where !line.text.isEmpty {
            let a = NSAttributedString(string: line.text, attributes: attrs)
            var ct = CTLineCreateWithAttributedString(a)
            var asc: CGFloat = 0, desc: CGFloat = 0, lead: CGFloat = 0
            let natural = CGFloat(CTLineGetTypographicBounds(ct, &asc, &desc, &lead))
            // 문단 마지막 줄은 정의상 왼쪽 맞춤. 그리고 **너무 짧은 줄도 맞추지 않는다**(위 주석).
            if !line.isParagraphEnd, natural >= w * justifyMinFill,
               let j = CTLineCreateJustifiedLine(ct, 1.0, w) { ct = j }
            let baselineFromTop = font.ascender + CGFloat(i) * lineHeight
            ctx.textPosition = CGPoint(x: 0, y: bounds.height - baselineFromTop)
            CTLineDraw(ct, ctx)
        }
    }
}
#endif
