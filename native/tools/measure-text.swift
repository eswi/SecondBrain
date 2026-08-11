#!/usr/bin/env swift
// **글자·SF Symbol 치수 실측.** (2026-08-12 신설 — CLAUDE.md 「계측 규칙」)
//
// 쓰는 법:
//   swift native/tools/measure-text.swift text   "주차 위치" 17 19 21 23 [--semibold]
//   swift native/tools/measure-text.swift symbol mappin.and.ellipse 17 30 40 44
//
// **왜 있나:** 레이아웃이 들어갈지 계산할 때 글자 폭·심볼 치수를 **기억으로 쓰다가 세 번 틀렸다**
// (전말: `docs/lessons/2026-08-12-measure-then-use.md`). 한 줄 재면 되는 값은 잰다.
//
// ⚠️ **심볼은 폭과 높이가 다르고 심볼마다도 다르다.** 그래서 이 도구는 **`폭 x 높이`를 함께** 찍는다 —
//    폭 표의 숫자를 높이에 갖다 쓰는 실수를 막기 위한 것이다(계측 규칙 2 「폭/높이 딱지」).
//    예: `mappin.and.ellipse` @40pt = **45 x 52** (높이가 폭보다 크다).
//
// ⚠️ **macOS 메트릭이다.** iOS와 같은 SF Pro + Apple SD Gothic Neo라 실무상 일치했지만
//    (「반복 주기」 계산 59.5 vs 실측 59.6, 「주차 위치」 계산 77.2 vs 화면 78.6),
//    **계산은 실측보다 2~3pt 낙관적인 편향**이 있었다. **결론은 화면에서 닫을 것**(계측 규칙 4).
//
// ⚠️ **Dynamic Type 단계 크기는 이 도구가 모른다.** 크기를 직접 넘겨야 한다.
//    시뮬레이터에서 단계를 바꿔 실제로 확인하는 길이 있다:
//      xcrun simctl ui booted content_size <extra-small|small|medium|large|extra-large
//                                          |extra-extra-large|extra-extra-extra-large|accessibility-*>
//    그 뒤 스크린샷을 `measure-ui.swift`로 재면 **단계별 실측**이 된다.

import AppKit

let argv = Array(CommandLine.arguments.dropFirst())
let semibold = argv.contains("--semibold")
let pos = argv.filter { !$0.hasPrefix("--") }

guard pos.count >= 3 else {
    print("""
    쓰는 법:
      swift measure-text.swift text   "<문자열>" <크기…> [--semibold]
      swift measure-text.swift symbol <심볼이름>  <크기…>
    """)
    exit(1)
}
let mode = pos[0], subject = pos[1]
let sizes = pos.dropFirst(2).compactMap { Double($0) }.map { CGFloat($0) }
guard !sizes.isEmpty else { print("크기를 하나 이상 넘길 것"); exit(1) }

switch mode {
case "text":
    print("글자 「\(subject)」\(semibold ? " (semibold)" : "") — 폭 pt")
    for s in sizes {
        let f = semibold ? NSFont.systemFont(ofSize: s, weight: .semibold) : NSFont.systemFont(ofSize: s)
        let a = NSAttributedString(string: subject, attributes: [.font: f])
        let w = ceil(a.size().width * 10) / 10
        // 줄 높이도 함께 — 「폭/높이 딱지」
        let lh = ceil((f.ascender - f.descender + f.leading) * 10) / 10
        print("  \(Int(s))pt → 폭 \(w) · 줄높이 \(lh)")
    }
case "symbol":
    print("심볼 `\(subject)` — 폭 x 높이 pt")
    for s in sizes {
        let cfg = NSImage.SymbolConfiguration(pointSize: s, weight: .regular)
        guard let i = NSImage(systemSymbolName: subject, accessibilityDescription: nil)?
            .withSymbolConfiguration(cfg) else {
            print("  \(Int(s))pt → (심볼을 못 찾음)"); continue
        }
        print("  \(Int(s))pt → \(ceil(i.size.width*10)/10) x \(ceil(i.size.height*10)/10)")
    }
default:
    print("mode 는 text 또는 symbol"); exit(1)
}
