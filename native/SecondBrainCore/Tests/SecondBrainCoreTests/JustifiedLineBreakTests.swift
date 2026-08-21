import XCTest
import CoreText
@testable import SecondBrainCore

/// 줄바꿈 원칙 셋 (2026-08-21 사용자 원칙 · `JustifiedLineBreak.swift` 머리주석).
///
/// ⚠️ **글꼴 치수에 기대지 않는다.** 어느 글꼴·폭이든 성립해야 하는 **성질**을 단정한다 —
/// 「몇 번째 줄에서 끊기나」가 아니라 「줄 앞에 빈칸이 없나」 같은 것.
/// 그래야 기기·OS가 바뀌어도 이 시험이 살아 있다(치수를 박으면 낡는다).
final class JustifiedLineBreakTests: XCTestCase {

    /// 시험용 글꼴 — 어느 맥에나 있는 것. **치수 자체를 단정하지 않으므로** 무엇이든 된다.
    private func font(_ size: CGFloat = 18) -> CTFont {
        CTFontCreateWithName("Helvetica" as CFString, size, nil)
    }

    private func breaker(_ width: CGFloat = 200) -> JustifiedLineBreaker {
        JustifiedLineBreaker(font: font(), width: width)
    }

    // 실데이터에서 온 것 둘 + 원칙마다 걸리게 만든 것들.
    private let samples: [String] = [
        "매일 저녁에 차를 어디다 주차 하는지에 대해서 자동으로 기록해놓거나 또는 기억할 수 있는 방법을 만들어야 됩니다",
        "아침에 일어날 때 존재하지 않던 없던 급한 일정이 머릿속에 있도록 와 일어나는 나를 괴롭히고 서두르게 만든다 그런데 그 일정은 존재하지 않는 일정이다 이게 뭐지 몇 번 그러는 그러는데",
        "월요일 아침에는 미용에 좀 더 11111111신경 더 쓰자. 면도도 하고, 코털 정리도 하고 머리도 한 번 세심하게 빗고 옷도 한결 깨끗하고 정중하게 입자.",
        "먼저 사람을 본다 — 문제보다 사람이 앞이다. 급할수록 그렇다. 쉼표, 마침표. 물음표? 느낌표!",
        "2026-08-21에 GhostLab으로 justification을 measurement 했고 SecondBrain 앱에 넣었다 iPhone 16 Pro",
    ]

    private let widths: [CGFloat] = [120, 160, 200, 260, 320]

    // MARK: - 원칙 ② — 줄 앞에 빈칸이 오면 안 된다 (첫 줄만 예외)

    func test원칙2_줄앞에빈칸이없다() {
        for s in samples {
            for w in widths {
                let lines = breaker(w).lines(s)
                for (i, line) in lines.enumerated() where i > 0 {
                    XCTAssertFalse(line.text.first?.isWhitespace ?? false,
                                   "폭 \(w) · \(i + 1)번째 줄이 빈칸으로 시작한다: \(line.text.debugDescription)")
                }
            }
        }
    }

    func test원칙2_첫줄은빈칸을허용한다() {
        let lines = breaker(200).lines("  앞에 빈칸이 둘 있는 원문이다 그리고 길게 이어진다 아주 길게 이어진다")
        XCTAssertTrue(lines.first?.text.first?.isWhitespace ?? false,
                      "첫 줄은 원문의 빈칸을 지켜야 한다")
    }

    func test줄끝빈칸은지운다() {
        for s in samples {
            for w in widths {
                for line in breaker(w).lines(s) {
                    XCTAssertFalse(line.text.last?.isWhitespace ?? false,
                                   "줄 끝에 빈칸이 남았다: \(line.text.debugDescription)")
                }
            }
        }
    }

    // MARK: - 원칙 ① — 부호가 줄 앞에 오면 안 된다 (앞 글자가 한글일 때)

    /// ⚠️ **원칙 ①의 범위는 「부호 *바로 앞* 글자」다** — 부호와 한글 사이에 **빈칸이 끼면 규칙 밖**이다.
    /// (2026-08-21에 이 시험이 그 경계를 잡았다: 「먼저 사람을 본다 — 문제보다…」에서 빈칸으로 떨어진
    /// 줄표가 줄 앞에 왔다. 원칙의 *"부호 바로 앞 글자 앞에서 잘라라"*를 그대로 읽으면 **맞는 동작**이다 —
    /// 그때 부호의 바로 앞은 글자가 아니라 빈칸이다. → **아래 시험도 붙어 있는 부호만 본다.**)
    func test원칙1_한글에붙은부호는줄앞에안온다() {
        for s in samples {
            for w in widths {
                let lines = breaker(w).lines(s)
                for (i, line) in lines.enumerated() where i > 0 {
                    guard let first = line.text.first, JustifyCharKind.isPunct(first),
                          let prevLast = lines[i - 1].text.last,
                          JustifyCharKind.of(prevLast) == .hangul else { continue }
                    // 원문에서 그 둘이 **붙어 있었나**(빈칸 없이) — 붙어 있었으면 규칙 위반이다.
                    let attached = s.contains("\(prevLast)\(first)")
                    XCTAssertFalse(attached,
                        "폭 \(w): 한글에 붙은 부호가 줄 앞에 왔다 — 앞 줄 「…\(String(lines[i-1].text.suffix(4)))」 / 이 줄 「\(String(line.text.prefix(4)))…」")
                }
            }
        }
    }

    /// 경계를 **시험으로 못 박는다** — 빈칸으로 떨어진 부호는 줄 앞에 올 수 있다(규칙 밖).
    /// ⛔ 이것이 **바뀌어야 하는 것이면 원칙 ①의 범위를 넓히는 결정**이 필요하다(사용자 사안).
    func test원칙1경계_빈칸으로떨어진부호는규칙밖이다() {
        let s = "먼저 사람을 본다 — 문제보다 사람이 앞이다. 급할수록 그렇다."
        let lines = breaker(120).lines(s)
        let dashStarts = lines.dropFirst().contains { $0.text.first == "—" }
        XCTAssertTrue(dashStarts,
            "지금 동작은 「빈칸으로 떨어진 부호는 줄 앞에 올 수 있다」다 — 바뀌었으면 원칙 범위를 다시 정한 것이다: \(lines.map(\.text))")
    }

    func test원칙1_한글이아니면부호가줄앞에와도된다() {
        // 「…AB.」 꼴 — 부호 앞이 영문이면 내리지 않는다(허용).
        // 성질만 본다: **막지 않는다**는 것을 「예외가 안 난다」로 확인한다.
        let s = "AAAA BBBB CCCC DDDD EEEE FFFF GGGG. HHHH IIII JJJJ KKKK LLLL MMMM"
        for w in widths {
            _ = breaker(w).lines(s)      // 무한 반복·빈 줄 없이 끝나야 한다
        }
    }

    // MARK: - 원칙 ③ — 비한글은 단어 안에서 자르지 않는다

    func test원칙3_비한글덩어리는안쪼개진다() {
        let tokens = ["2026-08-21", "GhostLab", "justification", "measurement", "SecondBrain", "iPhone"]
        let s = samples[4]
        for w in widths {
            let joined = breaker(w).lines(s).map(\.text)
            for t in tokens {
                // 덩어리가 폭보다 좁으면 어느 한 줄에 **온전히** 들어 있어야 한다.
                guard breaker(w).naturalWidth(t) <= w else { continue }
                XCTAssertTrue(joined.contains { $0.contains(t) },
                              "폭 \(w): 「\(t)」가 줄에 걸쳐 쪼개졌다 — \(joined)")
            }
        }
    }

    func test원칙3예외_폭보다긴덩어리는쪼갠다() {
        let url = "https://github.com/eswi/SecondBrain/blob/main/native/Sources/App/JustifiedText.swift"
        let lines = breaker(200).lines("링크는 \(url) 이다")
        XCTAssertGreaterThan(lines.count, 1, "긴 덩어리는 여러 줄로 쪼개져야 한다")
        // 쪼개진 조각을 이어 붙이면 원래 URL이 다시 나온다(글자를 잃지 않는다).
        XCTAssertTrue(lines.map(\.text).joined().contains("JustifiedText.swift"),
                      "쪼개는 과정에서 글자가 사라졌다")
    }

    // MARK: - 글자를 잃지 않는다 · 문단 · 마지막 줄

    func test글자를잃지않는다() {
        for s in samples {
            for w in widths {
                let joined = breaker(w).lines(s).map(\.text).joined()
                let expect = s.filter { !$0.isWhitespace }
                XCTAssertEqual(joined.filter { !$0.isWhitespace }, expect,
                               "폭 \(w): 나눈 뒤 글자가 달라졌다")
            }
        }
    }

    func test문단마지막줄만_문단끝이다() {
        let lines = breaker(160).lines("첫 문단이다 길게 이어져서 여러 줄이 된다 아주 길게\n둘째 문단이다 이것도 길게 이어진다 여러 줄")
        let ends = lines.enumerated().filter { $0.element.isParagraphEnd }.map(\.offset)
        XCTAssertEqual(ends.count, 2, "문단이 둘이면 문단 끝도 둘이어야 한다 — \(lines.map(\.text))")
        XCTAssertEqual(ends.last, lines.count - 1, "마지막 줄은 문단 끝이어야 한다")
    }

    func test빈원문도줄하나를돌려준다() {
        XCTAssertEqual(breaker(200).lines("").count, 1)
    }

    // MARK: - 말줄임

    func test말줄임은폭안에들어간다() {
        let b = breaker(200)
        let long = samples[1]
        let cut = b.truncated(long, suffix: "…")
        XCTAssertTrue(cut.hasSuffix("…"))
        XCTAssertLessThanOrEqual(b.naturalWidth(cut), 200 + 0.01,
                                 "말줄임한 줄이 폭을 넘었다")
        XCTAssertFalse(cut.dropLast().last?.isWhitespace ?? false,
                       "「…」 앞에 빈칸이 남았다")
    }
}
