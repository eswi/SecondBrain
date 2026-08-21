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
//  ## 어디에 쓰나 — **원문이 보이는 곳 전부** (2026-08-21 사용자 요구)
//  원칙 목록·원칙 영역 · 지금 챙길 것 · 새 기억들/살아있는 기억(`MemoryRow`) · 검색 · 보관함 ·
//  **상세의 원문(편집 중에도)**.
//  ⛔ **수집 창(`CaptureSheet`)에는 넣지 않는다** — 사용자가 명시적으로 뺐다.
//  글꼴·굵기·줄 제한이 자리마다 다르므로 **글자 크기를 여기서 계산한다**(`style` + `delta`) —
//  그래야 `@Environment(\.dynamicTypeSize)` 의존을 **이 뷰 하나가** 들고 있으면 된다.
//  (전엔 크기를 쓰는 쪽이 계산해서, 쓰는 쪽마다 그 의존을 심어야 했다.)
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

    /// 「…」을 붙여 폭에 맞춘다 — 뒤에서 한 글자씩 덜어낸다. 줄 제한이 걸린 목록 줄에서 쓴다.
    func truncated(_ s: String, suffix: String) -> String {
        var head = s
        while !head.isEmpty, !fits(head + suffix) { head.removeLast() }
        while let l = head.last, l.isWhitespace { head.removeLast() }
        return head + suffix
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

/// 글꼴 갈래 — 자리마다 다르다(목록은 `.body`/`.callout`, 원칙 목록은 `.callout+2`).
/// 플랫폼마다 타입이 갈려서(`UIFont.TextStyle` ↔ `NSFont.TextStyle`) 우리 것으로 하나 둔다.
enum JustifiedStyle {
    case body, callout

    var pointSize: CGFloat {
        #if canImport(UIKit)
        switch self {
        case .body:    return UIFont.preferredFont(forTextStyle: .body).pointSize
        case .callout: return UIFont.preferredFont(forTextStyle: .callout).pointSize
        }
        #else
        switch self {
        case .body:    return NSFont.preferredFont(forTextStyle: .body).pointSize
        case .callout: return NSFont.preferredFont(forTextStyle: .callout).pointSize
        }
        #endif
    }
}

/// 굵기 — 쓰는 자리가 둘뿐이다(목록은 보통, 원칙은 medium).
enum JustifiedWeight { case regular, medium }

/// 원문을 그린다. iOS는 직접 그리고, 맥은 `Text`(왼쪽 맞춤).
struct JustifiedText: View {
    let text: String
    var style: JustifiedStyle = .callout
    /// 갈래 기준 크기에 더할 값. 원칙 목록이 **+2**다(`PrincipleFont`와 같은 셈).
    var delta: CGFloat = 0
    var weight: JustifiedWeight = .medium
    let color: Color
    /// 0이면 제한 없음. 목록 줄은 2~3줄에서 자른다(넘치면 마지막 줄에 「…」).
    var maxLines: Int = 0

    /// ★ **단계가 바뀔 때 다시 그리는 의존은 이 뷰가 들고 있다** — 크기를 여기서 계산하기 때문이다.
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var size: CGFloat { style.pointSize + delta }

    var body: some View {
        #if os(iOS)
        JustifiedTextRepresentable(text: text, size: size, weight: weight,
                                   color: color, maxLines: maxLines)
        #else
        Text(text)
            .font(.system(size: size, weight: weight == .medium ? .medium : .regular))
            .foregroundStyle(color)
            .lineLimit(maxLines == 0 ? nil : maxLines)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }
}

#if os(iOS)
private struct JustifiedTextRepresentable: UIViewRepresentable {
    let text: String
    let size: CGFloat
    let weight: JustifiedWeight
    let color: Color
    let maxLines: Int

    func makeUIView(context: Context) -> JustifiedTextView {
        let v = JustifiedTextView()
        v.configure(text: text, size: size, weight: weight, color: UIColor(color), maxLines: maxLines)
        return v
    }
    func updateUIView(_ v: JustifiedTextView, context: Context) {
        v.configure(text: text, size: size, weight: weight, color: UIColor(color), maxLines: maxLines)
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
    private var weight: JustifiedWeight = .medium
    private var color: UIColor = .label
    /// 0이면 제한 없음. 넘치면 **마지막 보이는 줄에 「…」**을 붙이고 그 줄은 안 맞춘다.
    private var maxLines = 0
    private var lastWidth: CGFloat = 0
    private var cached: [JustifiedLineBreaker.Line] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isOpaque = false
        isAccessibilityElement = true        // 글을 직접 그리므로 접근성은 우리가 알려야 한다
    }
    required init?(coder: NSCoder) { fatalError("스토리보드로 안 쓴다") }

    func configure(text: String, size: CGFloat, weight: JustifiedWeight,
                   color: UIColor, maxLines: Int) {
        guard self.text != text || self.size != size || self.weight != weight
                || self.color != color || self.maxLines != maxLines else { return }
        self.text = text; self.size = size; self.weight = weight
        self.color = color; self.maxLines = maxLines
        accessibilityLabel = text
        cached = []; lastWidth = 0
        setNeedsDisplay(); invalidateIntrinsicContentSize()
    }

    private var font: UIFont {
        .systemFont(ofSize: size, weight: weight == .medium ? .medium : .regular)
    }
    private var lineHeight: CGFloat { ceil(font.lineHeight) }

    private func lines(forWidth w: CGFloat) -> [JustifiedLineBreaker.Line] {
        if w == lastWidth, !cached.isEmpty { return cached }
        let breaker = JustifiedLineBreaker(font: font as CTFont, width: w)
        var broken = breaker.lines(text)
        // 줄 제한 — 넘치면 **마지막 보이는 줄에 「…」**. 그 줄은 맞추지 않는다(끝이 아니니까).
        if maxLines > 0, broken.count > maxLines {
            var kept = Array(broken.prefix(maxLines))
            if let last = kept.popLast() {
                kept.append(JustifiedLineBreaker.Line(
                    text: breaker.truncated(last.text, suffix: "…"), isParagraphEnd: true))
            }
            broken = kept
        }
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

#if os(iOS)
/// **원문 편집 — 편집 중에도 좌우 맞춤** (2026-08-21 사용자 요구).
///
/// ## 왜 `UITextView`인가
/// 그리는 쪽(`JustifiedTextView`)은 **고르기·커서가 없다.** 편집은 텍스트 뷰가 해야 한다.
/// `TextField(axis: .vertical)`(옛것)은 좌우 맞춤을 못 준다 — SwiftUI에 그 정렬이 없다.
///
/// ## ⚠️ 원칙 셋을 **어절 끊기로** 지킨다 — 여기서는 줄을 우리가 못 나눈다
/// 편집 중에는 TextKit이 줄을 나눈다.
///
/// ### ⛔ 1차 시도는 실패했다 — **거부 훅은 부호에 안 들었다** (2026-08-21 실기기)
/// `byCharWrapping` + `NSLayoutManagerDelegate.layoutManager(_:shouldBreakLineByWordBeforeCharacterAt:)`로
/// **못 끊게 막으려** 했다. 사용자 판정: *"우측 맞춤을 하는 것 같아. 줄 제일 앞에 빈칸을 넣어도
/// 처음에 빈칸이 안 오게 하는 조정도 하고 있어. **그런데 부호가 앞으로 오지 않게 방지하지는 않아.**"*
/// → 화면에 「…더 쓰자 / **.** 면도도」가 나왔다. **글자 단위 끊기는 그 훅을 안 거친다**(이름이 `ByWord`다).
/// ★ **랩의 결정 실험은 이것을 못 잡았다** — 그 표본에서는 끊는 자리가 부호에 안 걸려
/// **두 쪽이 우연히 같게 나왔다.** 「같다」를 「원칙이 지켜진다」로 읽으면 안 되는 자리였다.
///
/// ### ✅ 그래서 **어절 끊기(`byWordWrapping`)로 바꿨다** — 원칙 셋이 저절로 지켜진다
///   **①** 부호는 **앞 어절에 붙어** 다니므로 줄 앞에 안 온다.
///   **②** 어절 끊기는 **빈칸을 앞 줄 끝에** 남긴다.
///   **③** 영어·숫자도 어절이라 **단어 안에서 안 잘린다.**
/// ⚠️ **대가:** 한글 어절을 안 쪼개므로 **빈칸이 더 벌어진다**(그리는 쪽보다 티가 난다).
/// **한글 단어 중간 끊기는 원칙이 아니라 「빈칸 벌어짐을 줄이는 수단」이었다** — 편집 중에는 그 수단을 포기하고
/// **원칙 셋을 지키는 쪽**을 골랐다. 저장하면 표시 쪽(우리 엔진)이 다시 제대로 나눈다.
/// ⛔ 거부 훅은 **남겨 뒀다** — 어절 끊기에서도 부호 앞 거부가 한 번 더 걸릴 수 있고 해가 없다.
///
/// ## 자체 스크롤은 끈다
/// 옛 `TextField(axis:.vertical)`의 성질을 지킨다 — **내용만큼 높이가 늘고 바깥 `ScrollView`가 스크롤한다**
/// (긴 원문 위를 드래그해도 페이지가 넘어간다). `isScrollEnabled = false`가 그것이다.
struct JustifiedTextEditor: UIViewRepresentable {
    @Binding var text: String
    /// 포커스 — `@FocusState`는 `UIViewRepresentable`에 안 걸린다. Bool로 주고받는다.
    @Binding var isFocused: Bool
    var style: JustifiedStyle = .body
    var color: Color
    /// **보이는 줄 수 상한.** 넘으면 칸이 더 안 자라고 **안에서 스크롤한다**(2026-08-21 사용자 요구).
    /// ⛔ **옛 결정이 뒤집혔다** — 전엔 *"자체 스크롤이 없어 바깥 `ScrollView`가 그대로 스크롤된다"*가
    /// 원문 칸의 성질이었다(그래서 `TextEditor` 대신 `TextField(axis:)`를 골랐다). 긴 원문에서
    /// **칸이 화면을 다 먹어** 성역·분류가 안 보이는 것을 사용자가 잡았다.
    /// **넘치지 않는 동안은 옛 성질이 그대로다** — 스크롤을 켜지 않으므로 바깥이 스크롤한다.
    var maxVisibleLines: Int = 6

    private var font: UIFont { .systemFont(ofSize: style.pointSize) }

    private var paragraph: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.alignment = .justified
        // ★ **어절 끊기다**(글자 끊기가 아니다) — 위 주석의 이유. 원칙 셋이 이 한 줄로 지켜진다.
        ps.lineBreakMode = .byWordWrapping
        ps.lineBreakStrategy = []
        return ps
    }

    func makeUIView(context: Context) -> UITextView {
        // ⚠️ TextKit 1로 만든다 — `NSLayoutManager` 대리자(줄바꿈 거부 훅)가 필요하다.
        //    기본값(TextKit 2)에는 그 훅이 없다.
        let tv = UITextView(usingTextLayoutManager: false)
        tv.isScrollEnabled = false
        tv.backgroundColor = .clear
        tv.textContainerInset = .zero
        tv.textContainer.lineFragmentPadding = 0
        tv.delegate = context.coordinator
        tv.layoutManager.delegate = context.coordinator
        tv.font = font
        tv.textColor = UIColor(color)
        tv.typingAttributes = [.font: font, .foregroundColor: UIColor(color),
                               .paragraphStyle: paragraph]
        tv.text = text
        apply(tv)
        return tv
    }

    func updateUIView(_ tv: UITextView, context: Context) {
        context.coordinator.text = $text
        context.coordinator.isFocused = $isFocused
        if tv.text != text { tv.text = text; apply(tv) }
        if tv.font != font || tv.textColor != UIColor(color) {
            tv.font = font; tv.textColor = UIColor(color); apply(tv)
        }
        // 포커스 맞추기 — 밖을 눌러 내리는 길(상세의 세 자리)이 이걸로 산다.
        if isFocused, !tv.isFirstResponder { tv.becomeFirstResponder() }
        if !isFocused, tv.isFirstResponder { tv.resignFirstResponder() }
    }

    /// 문단 속성을 글 전체에 다시 입힌다(타이핑 속성만으로는 붙여넣기·초기값에 안 걸린다).
    private func apply(_ tv: UITextView) {
        let sel = tv.selectedRange
        tv.attributedText = NSAttributedString(string: tv.text, attributes: [
            .font: font, .foregroundColor: UIColor(color), .paragraphStyle: paragraph,
        ])
        tv.typingAttributes = [.font: font, .foregroundColor: UIColor(color),
                               .paragraphStyle: paragraph]
        tv.selectedRange = sel
    }

    /// ⛔⛔ **이게 없으면 편집 칸이 가로로 무한히 늘어난다** (2026-08-21 실기기에서 사용자가 잡았다).
    /// `isScrollEnabled = false`인 `UITextView`의 **본디 크기(intrinsic)는 「한 줄로 쭉 늘어난 폭」**이라,
    /// SwiftUI가 그 폭을 그대로 받아 **화면 밖까지 넓어지고 상세 화면 전체가 좌우로 밀렸다.**
    /// → **제안된 폭을 받아 그 폭에서의 높이를 돌려준다**(그리는 쪽 `JustifiedTextView`와 같은 방식).
    func sizeThatFits(_ proposal: ProposedViewSize, uiView tv: UITextView,
                      context: Context) -> CGSize? {
        guard let w = proposal.width, w > 0, w < .infinity else { return nil }
        let content = ceil(tv.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height)
        let cap = ceil(font.lineHeight * CGFloat(maxVisibleLines))
        // 넘칠 때만 **안에서** 스크롤한다 — 안 넘치면 바깥 `ScrollView`가 스크롤한다(옛 성질 유지).
        tv.isScrollEnabled = content > cap
        tv.alwaysBounceVertical = false      // 안 넘치는 동안 드래그를 가로채지 않게
        return CGSize(width: w, height: min(content, cap))
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, isFocused: $isFocused) }

    /// ⚠️ `nonisolated`가 붙어 있는 이유: `NSLayoutManagerDelegate`는 메인 액터 밖에서도 불릴 수 있어
    /// 그대로 두면 **데이터 경합 경고로 빌드가 막힌다**(Swift 6 격리 검사).
    /// 줄바꿈 판단은 **넘겨받은 문자열만** 보므로 상태를 안 건드린다 — 그래서 안전하다.
    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>
        var isFocused: Binding<Bool>
        init(text: Binding<String>, isFocused: Binding<Bool>) {
            self.text = text; self.isFocused = isFocused
        }

        func textViewDidChange(_ tv: UITextView) {
            if text.wrappedValue != tv.text { text.wrappedValue = tv.text }
        }
        func textViewDidBeginEditing(_ tv: UITextView) {
            if !isFocused.wrappedValue { isFocused.wrappedValue = true }
        }
        func textViewDidEndEditing(_ tv: UITextView) {
            if isFocused.wrappedValue { isFocused.wrappedValue = false }
        }

    }
}

/// ★ 원칙 셋 — **여기서 끊는 것을 거부한다.** (메인 액터 밖에서 불릴 수 있어 `nonisolated`)
extension JustifiedTextEditor.Coordinator: NSLayoutManagerDelegate {
    nonisolated func layoutManager(_ layoutManager: NSLayoutManager,
                                   shouldBreakLineByWordBeforeCharacterAt charIndex: Int) -> Bool {
        guard let s = layoutManager.textStorage?.string else { return true }
        let chars = Array(s)
        guard charIndex > 0, charIndex < chars.count else { return true }
        let here = chars[charIndex], prev = chars[charIndex - 1]
        let kHere = JustifyCharKind.of(here), kPrev = JustifyCharKind.of(prev)

        // ② 빈칸이 줄 앞에 오면 안 된다 → 빈칸 앞에서 안 끊는다(빈칸은 앞 줄 끝에 남는다).
        if kHere == .space { return false }
        // ① 부호 앞에서 안 끊는다 — **앞이 한글일 때만**(아니면 허용).
        if JustifyCharKind.isPunct(here), kPrev == .hangul { return false }
        // ③ 비한글 덩어리 안에서 안 끊는다(영어·숫자가 단어 중간에서 안 잘린다).
        if kHere == .other, kPrev == .other { return false }
        return true
    }
}
#endif
