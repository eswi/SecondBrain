#!/usr/bin/env swift
//
//  measure-frames.swift — 스크린샷에서 **색 띠의 자리와 줄 간격(pitch)**을 픽셀로 센다 (2026-08-20)
//
//  ⚠️ **이것은 앱 코드가 아니다.** `native/tools/ghostlab/`의 계측 도구다.
//     앱 빌드에 안 섞인다(앱은 `Sources/App`만 컴파일한다 — `native/project.yml`).
//
//  ── 무엇에 쓰나 ────────────────────────────────────────────────
//  `ghostlab` 앱을 시뮬레이터에서 UI 시험으로 끌어 놓고, 그 동안 찍은 스크린샷을 이걸로 잰다.
//  줄마다 **색 표식**(사각형)을 두었기 때문에, 그 표식의 y 자리를 세면
//  **① 잔상이 있나**(같은 색 띠가 둘인가) **② 줄 간격이 얼마인가**를 숫자로 얻는다.
//
//  ── 두 모드 — 값을 비교하려면 **모드를 바꾸지 말 것** ─────────────────
//    measure-frames.swift bands <png>
//      화면 가로 전체(좌우 100px 제외)에서 **빨강·초록** 띠를 따로 센다.
//      2026-08-20에 이 모드로 **그릇의 여백**을 쟀다:
//        SwiftUI List(.plain) + 줄에 .padding(.vertical,5) → 줄 간격 **60.0pt**
//        (높이 20pt 줄이므로 List가 스스로 주는 여백은 한쪽 **15pt**)
//        UIHostingConfiguration 셀 + margins(.vertical,6)  → **52.3pt**
//
//    measure-frames.swift marks <png>
//      **왼쪽 표식 칸만**(x 40~125px) 훑어 **진한 색 아무 것이나** 센다(색이 줄마다 다를 때).
//      2026-08-20에 이 모드로 **실제 줄로 여백을 닫았다**:
//        옛 그릇 **104.7pt** · 새 그릇 여백 10 → **84.7pt** · 여백 **20 → 104.7pt(일치)**
//
//  ⚠️ **`marks`는 줄 왼쪽에 「색 사각형」이 있는 꼴만 잰다** — 카드 꼴(K·H)은 표식이 **숫자**라
//     띠가 0개로 나온다(정상이다). 줄 간격을 잴 때는 사각형이 있는 꼴(F·J)을 쓴다.
//
//  ⛔ **문턱을 고치지 말 것.** 이번 값들과 비교가 안 된다(사용자 지시 2026-08-21:
//     *"픽셀 판정기가 같은 기준으로 재야 이번 값과 비교가 된다"*).
//
//  ── ⚠️ 이 도구의 한계 — 한 번 **틀린 답**을 냈다 ────────────────────
//  잔상은 **흐리게** 그려진다. 처음 쓴 판정은 빨강 문턱을 `r>200`으로 잡아
//  **흐린 잔상을 「없음」으로 읽었다**(띠가 1개로 나왔고 실제로는 둘이었다).
//  **눈으로 본 프레임이 그 판정을 뒤집었다.**
//  → **색이 옅어질 수 있는 것을 셀 때는 이 도구를 「후보 좁히기」로만 쓰고,
//     결론은 프레임을 눈으로 보고 닫는다**(`CLAUDE.md` 계측 규칙 4의 같은 형태).
//
//  ── 쓰는 법 ──────────────────────────────────────────────────
//    swift native/tools/ghostlab/measure-frames.swift marks shots/T_150.png
//    for f in shots/T_*.png; do swift …/measure-frames.swift marks "$f"; done
//  (여러 장을 돌릴 때는 `swiftc -O`로 한 번 컴파일해 두는 것이 훨씬 빠르다 —
//   `swift`는 파일마다 새로 컴파일해서 수백 장이면 수 분씩 걸린다.)
//
import CoreGraphics
import Foundation
import ImageIO

let args = CommandLine.arguments
guard args.count >= 3, ["bands", "marks"].contains(args[1]) else {
    print("쓰기: measure-frames.swift <bands|marks> <png>")
    exit(2)
}
let mode = args[1]
let url = URL(fileURLWithPath: args[2])

guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
      let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    print("열 수 없다: \(url.lastPathComponent)"); exit(1)
}
let w = img.width, h = img.height
var buf = [UInt8](repeating: 0, count: w * h * 4)
guard let ctx = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8,
                          bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))

/// 화면은 3배 해상도다 — pt로 바꿔 적는다(계측 규칙: 값에 단위를 붙인다).
let scale = 3.0

func report(_ name: String, bands: [(Int, Int)]) {
    print("\(url.lastPathComponent) · \(name): 띠 \(bands.count)개")
    for (i, b) in bands.enumerated() {
        print(String(format: "   %d: %.1f–%.1f pt (높이 %.1f)",
                     i + 1, Double(b.0)/scale, Double(b.1)/scale, Double(b.1 - b.0)/scale))
    }
    if bands.count >= 2 {
        let tops = bands.map { Double($0.0)/scale }
        let pitches = (1..<tops.count).map { tops[$0] - tops[$0 - 1] }
        print("   pitch: " + pitches.map { String(format: "%.1f", $0) }.joined(separator: " / ") + " pt")
    }
}

/// 행마다 조건을 만족하는 픽셀을 세고, 이어지는 행을 하나의 「띠」로 묶는다.
func scan(xFrom: Int, xTo: Int, step: Int, minHits: Int, minHeight: Int,
          test: (Int, Int, Int) -> Bool) -> [(Int, Int)] {
    var rows = [Bool](repeating: false, count: h)
    for y in 0..<h {
        var n = 0
        for x in stride(from: xFrom, to: min(xTo, w), by: step) {
            let i = (y * w + x) * 4
            if test(Int(buf[i]), Int(buf[i+1]), Int(buf[i+2])) { n += 1 }
        }
        rows[y] = n > minHits
    }
    var bands: [(Int, Int)] = []
    var start = -1
    for y in 0..<h {
        if rows[y] { if start < 0 { start = y } }
        else if start >= 0 { if y - start > minHeight { bands.append((start, y)) }; start = -1 }
    }
    return bands
}

switch mode {
case "bands":
    // ⛔ 이 넷(범위·간격·문턱·최소높이)이 2026-08-20에 쓴 값이다. 고치면 비교가 깨진다.
    report("빨강", bands: scan(xFrom: 100, xTo: w - 100, step: 8, minHits: 20, minHeight: 5) {
        r, g, b in r > 200 && g < 90 && b < 90
    })
    report("초록", bands: scan(xFrom: 100, xTo: w - 100, step: 8, minHits: 20, minHeight: 5) {
        r, g, b in g > 150 && r < 120 && b < 120
    })
default:
    report("표식", bands: scan(xFrom: 40, xTo: 125, step: 2, minHits: 15, minHeight: 12) { r, g, b in
        let hi = max(r, max(g, b)), lo = min(r, min(g, b))
        return hi - lo > 90 && hi > 120        // 진한 색 = 채도가 높고 어둡지 않다
    })
}
