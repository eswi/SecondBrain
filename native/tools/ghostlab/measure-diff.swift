#!/usr/bin/env swift
//
//  measure-diff.swift — **스크린샷 두 장의 다른 픽셀을 센다** (2026-08-23 신설)
//
//  ⚠️ **앱 코드가 아니다.** `native/tools/ghostlab/`의 계측 도구다.
//
//  ── 왜 만들었나 ────────────────────────────────────────────────
//  「이 리팩터가 화면을 안 바꿨나」를 눈이 아니라 픽셀로 판정하려고(설계 §3-I-4의 ㉠).
//  기존 도구로는 안 된다 — `measure-frames`는 색 띠, `measure-ui`는 카드 경계, `measure-justify-px`는 글자다.
//
//  ── 쓰는 법 ────────────────────────────────────────────────
//    swift measure-diff.swift a.png b.png [--tol 2] [--skip-y 0,240]
//      `--tol`    : 채널 차이 문턱(기본 2 — 압축·안티에일리어싱 흔들림 흡수)
//      `--skip-y` : 무시할 y 구간(px). 상태바·시계처럼 **시각 때문에 달라지는 자리**를 뺀다.
//
//  ⛔ **「다른 픽셀 0」을 함부로 요구하지 말 것** — 시각·D-day 색처럼 **시간이 바꾸는 자리**가 있으면
//     거짓 실패가 난다. **어디가 달라졌나(y 구간)를 보고 판정한다**(설계 §3-I-4의 그 경고).
//
import CoreGraphics
import ImageIO
import Foundation

func load(_ p: String) -> (Int, Int, [UInt8])? {
    guard let s = CGImageSourceCreateWithURL(URL(fileURLWithPath: p) as CFURL, nil),
          let i = CGImageSourceCreateImageAtIndex(s, 0, nil) else { return nil }
    let w = i.width, h = i.height
    var buf = [UInt8](repeating: 0, count: w*h*4)
    guard let c = CGContext(data: &buf, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w*4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
    c.draw(i, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (w, h, buf)
}

let args = CommandLine.arguments
guard args.count >= 3, let a = load(args[1]), let b = load(args[2]) else {
    print("쓰는 법: measure-diff.swift a.png b.png [--tol 2] [--skip-y 0,240]"); exit(1)
}
var tol = 2
var skip: [(Int, Int)] = []
var i = 3
while i < args.count {
    if args[i] == "--tol", i+1 < args.count { tol = Int(args[i+1]) ?? 2; i += 2 }
    else if args[i] == "--skip-y", i+1 < args.count {
        let p = args[i+1].split(separator: ",").compactMap { Int($0) }
        if p.count == 2 { skip.append((p[0], p[1])) }
        i += 2
    } else { i += 1 }
}
guard a.0 == b.0, a.1 == b.1 else { print("⛔ 크기가 다르다: \(a.0)x\(a.1) vs \(b.0)x\(b.1)"); exit(2) }
let w = a.0, h = a.1
var diff = 0, firstY = -1, lastY = -1
var rowsWithDiff: [Int] = []
for y in 0..<h {
    if skip.contains(where: { y >= $0.0 && y <= $0.1 }) { continue }
    var rowDiff = 0
    for x in 0..<w {
        let k = (y*w + x)*4
        if abs(Int(a.2[k]) - Int(b.2[k])) > tol
            || abs(Int(a.2[k+1]) - Int(b.2[k+1])) > tol
            || abs(Int(a.2[k+2]) - Int(b.2[k+2])) > tol { rowDiff += 1 }
    }
    if rowDiff > 0 {
        diff += rowDiff; rowsWithDiff.append(y)
        if firstY < 0 { firstY = y }
        lastY = y
    }
}
let total = w*h
print("크기 \(w)x\(h) · 문턱 \(tol)\(skip.isEmpty ? "" : " · 건너뛴 y \(skip.map { "\($0.0)~\($0.1)" }.joined(separator: ","))")")
if diff == 0 {
    print("✅ **다른 픽셀 0** — 두 장이 같다")
} else {
    print("⛔ 다른 픽셀 \(diff) (\(String(format: "%.4f", Double(diff)/Double(total)*100))%) · 줄 \(rowsWithDiff.count)개")
    print("   달라진 y: \(firstY)~\(lastY)px  (논리 \(String(format: "%.1f", Double(firstY)/3))~\(String(format: "%.1f", Double(lastY)/3))pt)")
}
