import Foundation
import CoreText

//  ══════════════════════════════════════════════════════════════════════════════════
//  줄 나누기 — **사용자 줄바꿈 원칙 셋을 구현한다** (2026-08-21 · Core로 옮김)
//
//  ## 왜 Core에 있나
//  **순수 계산이라 화면 없이 검증할 수 있다.** 이 프로젝트가 계속 해온 방식이다
//  (`MediaPlace` · `MapsLink` · `MediaMigrationText`). **줄바꿈 규칙은 화면 없이도 검증돼야 하는 종류다**
//  (2026-08-21 사용자 결정 — App 층에 있던 것을 옮겼다).
//  그리는 쪽(`JustifiedText`·`JustifiedTextView`)은 App에 남는다 — `UIView`가 iOS 전용이다.
//
//  ## ★ 사용자 원칙 셋 (2026-08-21)
//  **①** 부호가 줄 앞에 오려 하면 **부호 바로 앞 글자를 함께 내린다** — 그래서 **글자가 줄 시작**이 된다.
//      ⚠️ **그 글자가 한글일 때만.** 한글이 아니면 **부호가 앞에 오는 것을 허용한다.**
//      ⚠️ **「바로 앞」이다 — 빈칸이 끼면 규칙 밖이다.** 「본다 **—** 문제」처럼 **빈칸으로 떨어진 부호**는
//      줄 앞에 올 수 있다(그때 부호의 바로 앞은 글자가 아니라 빈칸이다).
//      **2026-08-21에 Core 시험이 이 경계를 잡았다** — `test원칙1경계_빈칸으로떨어진부호는규칙밖이다`가
//      지금 동작을 못 박고 있다. ⛔ **넓히려면 원칙 ①의 범위를 다시 정하는 결정이 필요하다**(사용자 사안).
//  **②** **어떤 경우에도 줄 앞에 빈칸이 오면 안 된다.** 앞 빈칸을 **없애고 나서** 맞추기를 계산한다.
//      예외: **첫 줄**(원문이 빈칸으로 시작하는 경우).
//  **③** **한글이 아닌 것(영어·숫자 등)은 단어 안에서 자르지 않는다.** 한글만 글자 단위로 끊는다.
//      예외 하나 — **폭보다 긴 한 덩어리**(URL 같은 것)는 쪼갠다. 안 쪼개면 넘쳐서 잘린다.
//
//  ## ⛔ 왜 시스템 줄바꿈으로 안 하나
//  `lineBreakMode`·`lineBreakStrategy`로는 ①②를 못 고친다 — 세 전략(`[]`·`.pushOut`·`.standard`)이
//  **화면에서 전부 같았다**(2026-08-21 랩 실측). 그래서 줄을 직접 나눈다.
//  ⚠️ **`CTFramesetter`는 `lineBreakMode`를 무시하고 `UILabel`은 지킨다** — 그래서 「계산해서 확인」이
//  **반대 결론**을 낸 적이 있다. 그리는 것을 잴 때는 **픽셀로** 본다
//  (`native/tools/ghostlab/measure-justify-px.swift`).
//  ══════════════════════════════════════════════════════════════════════════════════

/// 글자 갈래 — 원칙 ①③이 이 구분 위에 서 있다.
public enum JustifyCharKind: Sendable {
    case space          // 빈칸 (원칙 ②)
    case hangul         // 한글 — **글자 단위로 끊을 수 있다** (원칙 ③의 「한글만」)
    case other          // 그 밖 — 영어·숫자·부호. **덩어리로 붙어 다닌다** (원칙 ③)

    public static func of(_ c: Character) -> JustifyCharKind {
        if c.isWhitespace { return .space }
        guard let u = c.unicodeScalars.first else { return .other }
        // 한글: 완성형 음절 · 자모 · 호환 자모
        if (0xAC00...0xD7A3).contains(u.value)
            || (0x1100...0x11FF).contains(u.value)
            || (0x3130...0x318F).contains(u.value) { return .hangul }
        return .other
    }

    /// 부호인가 — 원칙 ①이 「줄 앞에 오면 안 되는 것」으로 보는 것.
    public static func isPunct(_ c: Character) -> Bool { c.isPunctuation || c.isSymbol }
}

/// **줄을 직접 나눈다.** 순수 계산 — 그리기와 섞지 않는다(재기·시험을 위해).
/// ⚠️ `Sendable`을 안 붙인다 — `CTFont`가 `Sendable`이 아니다(Core Text는 그 표시가 없다).
/// 이 구조체는 만들어 쓰고 버리는 계산기라 스레드를 넘길 일이 없다.
public struct JustifiedLineBreaker {
    public let font: CTFont
    public let width: CGFloat

    public init(font: CTFont, width: CGFloat) {
        self.font = font
        self.width = width
    }

    /// 한 덩어리 — 빈칸 하나 · 한글 한 글자 · 그 밖의 이어붙은 덩어리(원칙 ③).
    private struct Atom { let text: String; let kind: JustifyCharKind }

    public struct Line: Sendable, Equatable {
        public let text: String
        /// 문단의 마지막 줄인가 — **좌우 맞춤을 걸지 않는 줄**이다(정의상 왼쪽 맞춤).
        public let isParagraphEnd: Bool
        public init(text: String, isParagraphEnd: Bool) {
            self.text = text
            self.isParagraphEnd = isParagraphEnd
        }
    }

    public func lines(_ source: String) -> [Line] {
        // 원문의 줄바꿈은 문단 경계로 지킨다.
        source.components(separatedBy: "\n").flatMap { paragraph -> [Line] in
            var out = breakParagraph(paragraph)
            if out.isEmpty { out = [Line(text: "", isParagraphEnd: true)] }
            return out
        }
    }

    /// 「…」을 붙여 폭에 맞춘다 — 뒤에서 한 글자씩 덜어낸다. 줄 제한이 걸린 목록 줄에서 쓴다.
    public func truncated(_ s: String, suffix: String) -> String {
        var head = s
        while !head.isEmpty, !fits(head + suffix) { head.removeLast() }
        while let l = head.last, l.isWhitespace { head.removeLast() }
        return head + suffix
    }

    /// 한 줄의 자연 폭 — 그리는 쪽이 「너무 짧은 줄은 안 맞춘다」를 판단할 때 쓴다.
    public func naturalWidth(_ s: String) -> CGFloat { measure(s) }

    // MARK: - 안쪽

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
        // ⚠️ `.font`는 UIKit/AppKit 키다 — **Core에는 없다.** Core Text 키를 직접 쓴다.
        let key = NSAttributedString.Key(kCTFontAttributeName as String)
        let a = NSAttributedString(string: s, attributes: [key: font])
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
                // 한 덩어리가 혼자서도 폭을 넘으면(아주 긴 영문·URL) 그때는 쪼갠다 — 원칙 ③의 예외.
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
        } else if let last = out.popLast() {
            out.append(Line(text: last.text, isParagraphEnd: true))
        }
        return out
    }

    /// 남은 덩어리들로 이어서 나눈다(긴 덩어리를 쪼갠 뒤 재진입용).
    private func breakRemainder(_ items: [Atom], from index: Int) -> [Line] {
        breakParagraph(items[index...].map(\.text).joined())
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
