import SwiftUI
import UIKit
import CoreText

//  ── 좌우 맞춤 — **넷을 나란히 본다 + 숫자를 iOS에서 낸다** (2026-08-21 확장)
//
//  2026-08-20에는 셋만 봤다(SwiftUI 기본 · SwiftUI+AttributedString · UILabel .justified).
//  그때 결론: **SwiftUI로는 안 되고 `UILabel`이면 된다.** 다만 *"한 줄에 단어가 4~6개뿐이라
//  단어 사이가 눈에 띄게 벌어진다"*는 걱정이 남았고 — **pt로는 안 쟀다.**
//
//  ★ 사용자 힌트(2026-08-21): **꼭 빈칸에서 줄바꿈하지 않아도 된다 — 단어 중간에서 끊어도 괜찮다.**
//     그러면 줄이 오른쪽 끝까지 차므로 **좌우 맞춤이 벌려야 할 남는 폭이 줄어든다.** 그래서 넷을 잰다:
//
//       A. 왼쪽 맞춤 + 어절 끊기        ← 지금 앱 상태
//       B. 좌우 맞춤 + 어절 끊기        ← 08-20에 본 것
//       C. 왼쪽 맞춤 + 단어 중간 끊기
//       D. **좌우 맞춤 + 단어 중간 끊기** ← 핵심. 둘은 대체가 아니라 짝이다
//
//  ⛔⛔ **숫자는 이 앱 안에서(iOS 엔진으로) 낸다 — 맥에서 잰 값은 틀렸다.**
//  `measure-justify.swift`(맥 CoreText)는 한글에서 **A==C · B==D**로 나왔다. 그런데 **화면은 달랐다** —
//  iOS에서는 `byCharWrapping`이 **줄바꿈 자리를 실제로 바꾼다**(「…하는지에 대 / 해서…」).
//  **계측 규칙 4의 그 자리다: 계산은 후보를 좁히고, 결론은 화면에서 닫는다.**
//  그래서 같은 속성 문자열로 **여기서 다시 재고**, 그 값을 화면에 함께 찍는다(스크린샷이 근거가 된다).
//
//  ⚠️ **읽기 좋은가는 pt로 못 잰다** — 한글을 단어 중간에서 끊는 것이 어떤지는 사용자가 화면을 보고 판정한다.

/// 실데이터의 원칙 문장 둘. **길이가 다르다** — 한 문장으로는 판단이 안 된다(사용자 지시).
enum JustifySample: String, CaseIterable {
    case parking   // 83703F8E · 62자 · 원칙 4번
    case morning   // AA228D58 · 102자 · 지금 가장 긴 원칙

    var text: String {
        switch self {
        case .parking:
            return "매일 저녁에 차를 어디다 주차 하는지에 대해서 자동으로 기록해놓거나 또는 기억할 수 있는 방법을 만들어야 됩니다"
        case .morning:
            return "아침에 일어날 때 존재하지 않던 없던 급한 일정이 머릿속에 있도록 와 일어나는 나를 괴롭히고 서두르게 만든다 그런데 그 일정은 존재하지 않는 일정이다 이게 뭐지 몇 번 그러는 그러는데"
        }
    }
    var caption: String {
        switch self {
        case .parking: return "표본 ① 83703F8E · 62자 (원칙 4번)"
        case .morning: return "표본 ② AA228D58 · 102자 (가장 긴 원칙)"
        }
    }
}

enum JustifyForm: String, CaseIterable, Identifiable {
    case a = "A 왼쪽 · 어절"
    case b = "B 좌우 · 어절"
    case c = "C 왼쪽 · 단어중간"
    case d = "D 좌우 · 단어중간"
    var id: String { rawValue }

    var justified: Bool { self == .b || self == .d }
    var midWord: Bool { self == .c || self == .d }
    var isKey: Bool { self == .d }
}

private let textPrimary = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let textSecond = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let bg = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let pTint = Color(red: 0x22/255, green: 0xD3/255, blue: 0xEE/255)

/// 진짜 카드의 글자 칸 폭:
/// 402(iPhone 16 Pro) − 16×2(셀 여백) − 14×2(카드 여백) − 16(번호) − 9 − 10(chevron 13pt) − 9 = **298**
let justifyTextWidth: CGFloat = 298

private var fsize: CGFloat { UIFont.preferredFont(forTextStyle: .callout).pointSize + 2 }

/// 라벨과 계측이 **같은 속성 문자열**을 쓴다 — 갈라 두면 재는 것과 보이는 것이 어긋난다.
func justifyAttributed(_ text: String, justified: Bool, midWord: Bool) -> NSAttributedString {
    let ps = NSMutableParagraphStyle()
    ps.alignment = justified ? .justified : .natural
    ps.lineBreakMode = midWord ? .byCharWrapping : .byWordWrapping
    // ⚠️ 기본값(.standard)은 한글 어절을 안 쪼갠다 — 그래서 줄이 일찍 끝난다. 그것을 끄는 것이 C·D다.
    ps.lineBreakStrategy = midWord ? [] : .standard
    return NSAttributedString(string: text, attributes: [
        .font: UIFont.systemFont(ofSize: fsize, weight: .medium),
        .foregroundColor: UIColor(textPrimary),
        .paragraphStyle: ps,
    ])
}

/// **iOS 엔진으로** 잰 값. 마지막 줄은 정의상 왼쪽 맞춤이라 남는 폭 계산에서 뺀다.
struct JustifyMetrics {
    let lines: Int
    let slackMax: CGFloat, slackAvg: CGFloat        // 오른쪽 여백에 남는 폭
    let spaceAvg: CGFloat, spaceMax: CGFloat        // 공백 하나의 폭
    let natSpace: CGFloat                           // 자연 공백 폭(견줄 기준)

    init(text: String, justified: Bool, midWord: Bool, width: CGFloat) {
        let attr = justifyAttributed(text, justified: justified, midWord: midWord)
        let setter = CTFramesetterCreateWithAttributedString(attr)
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, nil)
        let ctLines = (CTFrameGetLines(frame) as? [CTLine]) ?? []
        let ns = text as NSString

        var slacks: [CGFloat] = [], spaces: [CGFloat] = []
        for (i, line) in ctLines.enumerated() where i < ctLines.count - 1 {
            var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
            slacks.append(width - CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l)))
            let r = CTLineGetStringRange(line)
            guard r.length > 1 else { continue }
            for idx in r.location..<(r.location + r.length - 1) where ns.character(at: idx) == 32 {
                spaces.append(CTLineGetOffsetForStringIndex(line, idx + 1, nil)
                            - CTLineGetOffsetForStringIndex(line, idx, nil))
            }
        }
        lines = ctLines.count
        slackMax = slacks.max() ?? 0
        slackAvg = slacks.isEmpty ? 0 : slacks.reduce(0, +) / CGFloat(slacks.count)
        spaceMax = spaces.max() ?? 0
        spaceAvg = spaces.isEmpty ? 0 : spaces.reduce(0, +) / CGFloat(spaces.count)

        let sp = NSAttributedString(string: " ",
            attributes: [.font: UIFont.systemFont(ofSize: fsize, weight: .medium)])
        var a2: CGFloat = 0, d2: CGFloat = 0, l2: CGFloat = 0
        natSpace = CGFloat(CTLineGetTypographicBounds(
            CTLineCreateWithAttributedString(sp), &a2, &d2, &l2))
    }

    var readout: String {
        func f(_ v: CGFloat) -> String { String(format: "%.1f", v) }
        return "줄 \(lines) · 남는 폭 최대 \(f(slackMax)) 평균 \(f(slackAvg))"
             + " · 공백 \(f(spaceAvg))/\(f(spaceMax)) (자연 \(f(natSpace)))"
    }
}

struct JustifyProbe: View {
    let sample: JustifySample

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(sample.caption).font(.caption.weight(.semibold)).foregroundStyle(pTint)
                Text("글자 칸 폭 \(Int(justifyTextWidth))pt · 글꼴 \(Int(fsize))pt medium · 숫자는 iOS에서 쟀다")
                    .font(.caption2).foregroundStyle(textSecond)
            }

            ForEach(JustifyForm.allCases) { form in
                let m = JustifyMetrics(text: sample.text, justified: form.justified,
                                       midWord: form.midWord, width: justifyTextWidth)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(form.rawValue)
                            .font(.caption2.weight(form.isKey ? .bold : .regular))
                            .foregroundStyle(form.isKey ? pTint : textSecond)
                        if form.isKey { Text("← 핵심").font(.caption2).foregroundStyle(pTint) }
                    }
                    Text(m.readout).font(.system(size: 9)).foregroundStyle(textSecond)
                    // 오른쪽 끝을 눈으로 보게 — 글자 칸의 경계선을 얇게 긋는다.
                    JustifiedLabel(text: sample.text, justified: form.justified, midWord: form.midWord)
                        .frame(width: justifyTextWidth)
                        .overlay(alignment: .trailing) {
                            Rectangle().fill(pTint.opacity(0.35)).frame(width: 1)
                        }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16).padding(.top, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(bg.ignoresSafeArea())
    }
}

/// `UILabel`을 그대로 쓴다 — SwiftUI `Text`에는 좌우 맞춤이 **없다**(08-20 실측).
struct JustifiedLabel: UIViewRepresentable {
    let text: String
    let justified: Bool
    let midWord: Bool

    func makeUIView(context: Context) -> UILabel {
        let l = UILabel()
        l.numberOfLines = 0
        l.attributedText = justifyAttributed(text, justified: justified, midWord: midWord)
        return l
    }
    func updateUIView(_ v: UILabel, context: Context) {
        v.attributedText = justifyAttributed(text, justified: justified, midWord: midWord)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UILabel, context: Context) -> CGSize? {
        let w = proposal.width ?? justifyTextWidth
        uiView.preferredMaxLayoutWidth = w
        let h = uiView.sizeThatFits(CGSize(width: w, height: .greatestFiniteMagnitude)).height
        return CGSize(width: w, height: h)
    }
}
