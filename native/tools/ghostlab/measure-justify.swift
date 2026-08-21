#!/usr/bin/env swift
//
//  measure-justify.swift — **좌우 맞춤을 pt로 잰다** (2026-08-21 신설)
//
//  §18(2026-08-20)에는 「단어 사이가 눈에 띄게 벌어진다」가 **눈으로 본 값**만 있었다.
//  이 스크립트가 그 자리를 숫자로 채운다 — CoreText로 줄을 짜고 **줄마다**:
//    · 오른쪽 여백에 **몇 pt가 남나**(왼쪽 맞춤이면 그게 들쭉날쭉의 크기다)
//    · 공백 하나가 **몇 pt로 벌어졌나**(좌우 맞춤이면 자연 폭보다 늘어난다)
//
//  네 꼴을 같은 폭·같은 글꼴로 잰다:
//    A 왼쪽·어절 / B 좌우·어절 / C 왼쪽·단어중간 / **D 좌우·단어중간**
//
//  쓰는 법:
//      swift native/tools/ghostlab/measure-justify.swift [폭pt] [글꼴pt]
//      (기본 298 18 — 진짜 카드의 글자 칸. 계산 근거는 JustifyProbe.swift 머리주석)
//
//  ⚠️ **맥의 CoreText로 잰다.** 글꼴(SF Pro)·줄짜기 엔진은 iOS와 같은 것이지만
//     **화면 판정은 시뮬/실기기에서 해야 한다**(계측 규칙 4 — 계산은 후보를 좁히고,
//     결론은 화면에서 닫는다). 이 숫자는 **후보를 좁히는 쪽**이다.
//  ⚠️ **읽기 좋은가는 여기서 안 나온다** — 한글을 단어 중간에서 끊는 것이 어떤지는 pt로 못 잰다.
//
import Foundation
import AppKit
import CoreText

let args = CommandLine.arguments
let width = args.count > 1 ? CGFloat(Double(args[1]) ?? 298) : 298
let fsize = args.count > 2 ? CGFloat(Double(args[2]) ?? 18) : 18

let samples: [(String, String)] = [
    ("표본 ① 83703F8E · 62자 (원칙 4번)",
     "매일 저녁에 차를 어디다 주차 하는지에 대해서 자동으로 기록해놓거나 또는 기억할 수 있는 방법을 만들어야 됩니다"),
    ("표본 ② AA228D58 · 102자 (가장 긴 원칙)",
     "아침에 일어날 때 존재하지 않던 없던 급한 일정이 머릿속에 있도록 와 일어나는 나를 괴롭히고 서두르게 만든다 그런데 그 일정은 존재하지 않는 일정이다 이게 뭐지 몇 번 그러는 그러는데"),
]

struct Form { let name: String; let justified: Bool; let midWord: Bool }
let forms = [
    Form(name: "A 왼쪽 · 어절",      justified: false, midWord: false),
    Form(name: "B 좌우 · 어절",      justified: true,  midWord: false),
    Form(name: "C 왼쪽 · 단어중간",  justified: false, midWord: true),
    Form(name: "D 좌우 · 단어중간",  justified: true,  midWord: true),
]

let font = NSFont.systemFont(ofSize: fsize, weight: .medium)

/// 자연 공백 폭 — 좌우 맞춤이 얼마나 늘렸는지 견주는 기준.
func naturalSpaceWidth() -> CGFloat {
    let a = NSAttributedString(string: " ", attributes: [.font: font])
    let line = CTLineCreateWithAttributedString(a)
    var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
    return CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
}
let natSpace = naturalSpaceWidth()

func attributed(_ text: String, _ f: Form) -> NSAttributedString {
    let ps = NSMutableParagraphStyle()
    ps.alignment = f.justified ? .justified : .natural
    ps.lineBreakMode = f.midWord ? .byCharWrapping : .byWordWrapping
    if #available(macOS 12.0, *) {
        ps.lineBreakStrategy = f.midWord ? [] : .standard
    }
    return NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: ps])
}

func measure(_ text: String, _ f: Form) {
    let attr = attributed(text, f)
    let setter = CTFramesetterCreateWithAttributedString(attr)
    let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 10_000), transform: nil)
    let frame = CTFramesetterCreateFrame(setter, CFRangeMake(0, 0), path, nil)
    let lines = CTFrameGetLines(frame) as! [CTLine]
    let ns = text as NSString

    var slacks: [CGFloat] = []
    var spaceWidths: [CGFloat] = []

    for (i, line) in lines.enumerated() {
        var a: CGFloat = 0, d: CGFloat = 0, l: CGFloat = 0
        let w = CGFloat(CTLineGetTypographicBounds(line, &a, &d, &l))
        let isLast = (i == lines.count - 1)
        if !isLast { slacks.append(width - w) }        // 마지막 줄은 정의상 왼쪽 맞춤 — 뺀다

        // 이 줄 안의 공백들이 실제로 몇 pt를 차지하나 (좌우 맞춤이면 늘어나 있다)
        let r = CTLineGetStringRange(line)
        if !isLast, r.length > 1 {
            for idx in r.location..<(r.location + r.length - 1) {
                if ns.character(at: idx) == 32 {       // ' '
                    let x0 = CTLineGetOffsetForStringIndex(line, idx, nil)
                    let x1 = CTLineGetOffsetForStringIndex(line, idx + 1, nil)
                    spaceWidths.append(x1 - x0)
                }
            }
        }
    }

    func f2(_ v: CGFloat) -> String { String(format: "%.1f", v) }
    let slackTxt = slacks.isEmpty ? "—"
        : "최대 \(f2(slacks.max()!)) · 평균 \(f2(slacks.reduce(0,+)/CGFloat(slacks.count)))"
    let spaceTxt: String
    if spaceWidths.isEmpty { spaceTxt = "—" }
    else {
        let mx = spaceWidths.max()!, av = spaceWidths.reduce(0,+)/CGFloat(spaceWidths.count)
        spaceTxt = "평균 \(f2(av)) · 최대 \(f2(mx))  (자연 \(f2(natSpace)) → +\(f2(av - natSpace)) / 최대 +\(f2(mx - natSpace)))"
    }
    print("  \(f.name.padding(toLength: 18, withPad: " ", startingAt: 0)) 줄 \(lines.count)개")
    print("      오른쪽 남는 폭(마지막 줄 제외): \(slackTxt)")
    print("      공백 하나의 폭:                \(spaceTxt)")
}

print("── 좌우 맞춤 계측 · 폭 \(Int(width))pt · 글꼴 \(Int(fsize))pt medium · 자연 공백 \(String(format: "%.1f", natSpace))pt")
print("   ⚠️ 맥 CoreText 기준 — 화면 판정은 시뮬/실기기에서(계측 규칙 4)\n")
for (cap, text) in samples {
    print("■ \(cap)")
    for f in forms { measure(text, f) }
    print("")
}
