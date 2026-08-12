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
// ⚠️ **★ 편향의 방향은 재는 대상에 따라 반대다 (2026-08-12 맥북).**
//    **글자 폭에서는 이 도구가 오히려 크게 나온다** — 「주차 위치」를 픽셀로 재니
//    Large **60.0** / XXL **74.0** / XXXL **81.0**pt인데, 이 도구는 17/21/23pt에서
//    **63.2 / 77.6 / 84.8**을 준다. **일정하게 3.2~3.8pt 크다.**
//    (픽셀 쪽이 양끝 안티에일리어싱을 놓쳐 조금 덜 잡는 계통 오차로 보인다.)
//    → **「계산은 낙관적이니 깎아 읽어라」를 글자 폭에 그대로 적용하지 말 것.**
//      카드·블록 높이에서는 계산이 작게(낙관적), **글자 폭에서는 계산이 크게(보수적)** 나온다.
//      **글자 폭은 계산값을 그대로 쓰는 쪽이 안전하다.**
//
// ✅ **이 도구로 Dynamic Type 단계 크기가 확인됐다 (2026-08-12).**
//    위 픽셀 실측의 **비율**이 74.0/60.0 = **1.233**(↔ 21/17 = 1.235),
//    81.0/60.0 = **1.350**(↔ 23/17 = 1.353)으로 맞았다.
//    코드가 `.font(.body)`를 명시하고 `.body`가 Large에서 17pt이므로,
//    **「XXL = 21pt · XXXL = 23pt」가 공표 표가 아니라 화면에서 확인된 값**이 됐다.
//    (아래 「Dynamic Type 단계 크기는 이 도구가 모른다」는 그대로다 — 크기는 여전히 직접 넘겨야 한다.)
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
