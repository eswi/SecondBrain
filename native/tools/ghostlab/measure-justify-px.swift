#!/usr/bin/env swift
//
//  measure-justify-px.swift — **좌우 맞춤을 「그려진 픽셀」로 잰다** (2026-08-21 신설)
//
//  ⛔⛔ **왜 픽셀이어야 하나 — 계산이 화면과 갈렸다.**
//  `CTFramesetter`로 재면 한글에서 **A(어절) == C(단어중간)**으로 나온다. 그런데 **`UILabel`이 그린 화면은
//  다르다** — C는 「…하는지에 대 / 해서…」로 **단어 중간에서 끊긴다.**
//  즉 **`CTFramesetter`는 `lineBreakMode`·`lineBreakStrategy`를 무시하고 `UILabel`은 지킨다.**
//  ⚠️ 맥이냐 iOS냐의 차이가 아니다 — **엔진이 다른 것이다**(같은 iOS 안에서 갈렸다).
//  → **그래서 계산을 버리고 스크린샷을 잰다.** 계측 규칙 4의 「결론은 화면에서 닫는다」가 이 자리다.
//
//  무엇을 재나 (JustifyProbe 화면 한 장에서):
//    · 글자 칸 오른쪽 끝에 그은 **청록 안내선**으로 네 블록(A·B·C·D)의 줄들을 찾는다.
//    · 줄마다 **오른쪽에 남는 폭**(안내선 − 마지막 글자) → 왼쪽 맞춤의 「들쭉날쭉」 크기.
//    · 줄 안의 **빈칸 폭**(글자 사이 배경이 이어지는 구간) → 좌우 맞춤이 얼마나 벌렸나.
//
//  쓰는 법:
//      swift native/tools/ghostlab/measure-justify-px.swift <스크린샷.png>
//
//  ⚠️ **읽기 좋은가는 여기서 안 나온다** — 한글을 단어 중간에서 끊는 것이 어떤지는 사용자가 판정한다.
//
import Foundation
import AppKit

let args = CommandLine.arguments
guard args.count > 1, let img = NSImage(contentsOfFile: args[1]),
      let tiff = img.tiffRepresentation, let bmp = NSBitmapImageRep(data: tiff) else {
    print("쓰는 법: swift measure-justify-px.swift <스크린샷.png>"); exit(1)
}
let W = bmp.pixelsWide, H = bmp.pixelsHigh
let scale = CGFloat(W) / 402.0            // iPhone 16 Pro 논리 폭 402pt → 배율(@3x면 3.0)

func px(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
    guard let c = bmp.colorAt(x: x, y: y) else { return (0,0,0) }
    return (Int(c.redComponent*255), Int(c.greenComponent*255), Int(c.blueComponent*255))
}
/// 청록 안내선(0x22D3EE를 배경에 0.35로 얹은 것) — 파랑·초록이 높고 빨강이 낮다.
func isGuide(_ p: (r: Int, g: Int, b: Int)) -> Bool {
    p.b > 70 && p.g > 55 && p.r < p.g - 25
}
/// 글자(밝은 회백색 0xECEBF1). 배경은 0x131218.
func isInk(_ p: (r: Int, g: Int, b: Int)) -> Bool { p.r > 110 && p.g > 110 && p.b > 110 }

// ── 1) 안내선의 x — 오른쪽 절반에서 청록이 가장 많이 쌓인 열
var guideCount = [Int: Int]()
for x in (W/2)..<W { for y in 0..<H where isGuide(px(x, y)) { guideCount[x, default: 0] += 1 } }
guard let guideX = guideCount.max(by: { $0.value < $1.value })?.key, guideCount[guideX]! > 40 else {
    print("⛔ 안내선을 못 찾았다 — JustifyProbe 화면인지 확인할 것"); exit(1)
}
print("안내선 x = \(guideX)px (= \(String(format: "%.1f", CGFloat(guideX)/scale))pt) · 배율 \(String(format: "%.1f", scale))×\n")

// ── 2) 안내선이 그려진 y 구간 = 라벨 블록. 끊긴 곳으로 블록을 가른다.
var rows = [Int]()
for y in 0..<H where isGuide(px(guideX, y)) { rows.append(y) }
var blocks = [[Int]]()
for y in rows {
    if var last = blocks.last, let ly = last.last, y - ly <= 4 { last.append(y); blocks[blocks.count-1] = last }
    else { blocks.append([y]) }
}
blocks = blocks.filter { $0.count > 20 }
let names = ["A 왼쪽 · 어절", "B 좌우 · 어절", "C 왼쪽 · 단어중간", "D 좌우 · 단어중간"]
print("라벨 블록 \(blocks.count)개 (기대 4)\n")

// ── 3) 블록마다: 글자 줄을 찾아 남는 폭과 빈칸 폭을 잰다
let leftX = Int(16 * scale)               // 화면 왼쪽 여백 16pt
for (bi, block) in blocks.enumerated() {
    let y0 = block.first!, y1 = block.last!
    // 글자가 있는 y를 모아 줄로 가른다
    var inkRows = [Int]()
    for y in y0...y1 {
        var has = false
        for x in leftX..<guideX where isInk(px(x, y)) { has = true; break }
        if has { inkRows.append(y) }
    }
    var lines = [[Int]]()
    for y in inkRows {
        if var last = lines.last, let ly = last.last, y - ly <= 3 { last.append(y); lines[lines.count-1] = last }
        else { lines.append([y]) }
    }
    lines = lines.filter { $0.count > 5 }

    print("■ \(bi < names.count ? names[bi] : "블록 \(bi+1)") — 줄 \(lines.count)개")
    var slacks = [CGFloat](), gaps = [CGFloat]()
    for (li, line) in lines.enumerated() {
        // 이 줄의 열 프로필: 글자가 있는 x
        var inkCols = [Bool](repeating: false, count: guideX - leftX + 1)
        for y in line { for x in leftX...guideX where isInk(px(x, y)) { inkCols[x - leftX] = true } }
        guard let lastInk = inkCols.lastIndex(of: true), let firstInk = inkCols.firstIndex(of: true) else { continue }
        let slack = CGFloat(inkCols.count - 1 - lastInk) / scale
        let isLast = (li == lines.count - 1)
        if !isLast { slacks.append(slack) }
        // 빈칸: 글자 사이 배경이 이어지는 구간(줄 끝 여백은 뺀다)
        var runs = [Int](); var run = 0
        for i in firstInk...lastInk {
            if inkCols[i] { if run > 0 { runs.append(run); run = 0 } } else { run += 1 }
        }
        // 한글 글자 사이의 자잘한 틈을 걸러낸다 — 빈칸은 그보다 넓다(문턱 = 6px @3x = 2pt)
        let spaceRuns = runs.filter { CGFloat($0)/scale >= 2.0 }.map { CGFloat($0)/scale }
        if !isLast { gaps.append(contentsOf: spaceRuns) }
        print(String(format: "   %d줄: 남는 폭 %5.1fpt · 빈칸 %d개 %@", li+1, slack, spaceRuns.count,
                     spaceRuns.map { String(format: "%.1f", $0) }.joined(separator: " ")))
    }
    func f(_ v: [CGFloat]) -> String {
        v.isEmpty ? "—" : String(format: "최대 %.1f · 평균 %.1f", v.max()!, v.reduce(0,+)/CGFloat(v.count))
    }
    print("   → 남는 폭(마지막 줄 제외) \(f(slacks))")
    print("   → 빈칸 폭 \(f(gaps))\n")
}
