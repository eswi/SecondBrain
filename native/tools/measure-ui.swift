#!/usr/bin/env swift
// 스크린샷 픽셀에서 **카드·블록 경계**를 읽는다. (2026-08-12 신설 — CLAUDE.md 「계측 규칙」)
//
// 쓰는 법:
//   swift native/tools/measure-ui.swift <스크린샷.png> <x열…> [--scale 3] [--y 600,1150] [--bg x,y] [--eps 0.005]
//
// 예 (iPhone 16 Pro 스크린샷에서 나란히 선 두 카드의 높이):
//   swift native/tools/measure-ui.swift /tmp/shot.png 727 830
//
// **왜 이 방법인가 — 접근성 좌표보다 안정적이다.**
// 시뮬레이터 접근성 좌표(AppleScript/System Events)로도 위치·크기를 읽을 수 있지만 2026-08-12에 두 가지로 막혔다:
//   ⓐ **작업 중 시뮬레이터 창이 움직이면** 좌표가 통째로 어긋난다(원점을 매번 다시 읽어야 한다).
//   ⓑ 같은 화면에서 트리 읽기가 **성공/실패를 반복**한다(이유 불명).
// 픽셀 측정은 창 위치와 무관하고 실패하지 않는다. **그래서 결론을 닫는 데는 이걸 쓴다**(계측 규칙 4).
//
// **원리:** 카드 배경(`Palette.surface`)은 화면 배경(`Palette.bg`)보다 살짝 밝다. 세로 한 열을 훑어
// 배경과 밝기가 다른 **연속 구간**의 시작·끝을 카드의 위·아래 경계로 읽는다.
//
// ⚠️ 논리 pt = 픽셀 / scale. iPhone 16 Pro는 **@3x**라 기본값 3.
//
// ============================================================================
// ★ 걸린 함정 넷 (2026-08-12 맥북, Dynamic Type 9단계 계측 중 실제로 다 걸렸다)
//   넷 다 「재는 법」이 아니라 **「나온 값을 읽는 법」**이 틀린 것이다.
//   공통 처방: **한 카드를 여러 열로 재서 값이 일치하는지 본다.** 안 맞으면 아래 중 하나다.
// ----------------------------------------------------------------------------
// ① **둥근 모서리에 걸린 열** — 카드 좌우 끝에서 ~50px(논리 ~17pt) 안쪽이 아니면
//    모서리 곡선이 위아래를 깎아 **짧게** 읽힌다.
//    신호: 열마다 값이 조금씩 다르다(92.3 / 93.7 / 94.3 / 95.0 …).
//
// ② **배경 표본이 카드 안에 들어감** — 기본 배경은 `x=15` 열의 중앙값인데,
//    **큰 Dynamic Type에서 카드가 화면 끝까지 붙으면 그 열이 카드가 된다.** 배경과 카드가
//    뒤바뀌어 검출이 통째로 뒤집힌다.
//    신호: **글자를 키웠는데 카드가 오히려 작아진다**(원문 카드 88.0 → 40.0pt).
//    처방: `--bg <x>,<y>`로 진짜 배경 한 점을 준다.
//
// ③ **`--bg` 점을 카드 위에 찍음** — ②를 고치려다 카드 표면을 배경으로 준 것.
//    처방: **출력되는 「배경 표본 … 밝기」를 반드시 눈으로 확인한다.**
//    이 앱 다크 모드 기준 **화면 배경 ≈ 0.0744 · 카드 표면 ≈ 0.1127**. 0.11이 찍히면 잘못 짚은 것이다.
//
// ④ **`--y` 창의 끝을 카드의 끝으로 읽음** — 도구는 창 경계에서 구간을 자르면서
//    **잘렸다고 말해주지 않는다.** 그러면 「창의 길이」를 카드 높이로 적게 된다.
//    (2026-08-12: AX5 성역 카드를 이렇게 「≈393pt」로 적었다. 실제로는 **하단 바에 가려 밑변이
//    화면에 없어 잴 수 없는** 카드였다.)
//    판별: **구간의 끝값 == `--y`의 끝값이면 그건 잘린 값이다.**
//    처방: 창을 넓혀 다시 잰다. 넓혀도 이미지 끝에 닿으면 **「못 잼」으로 적는다** — 값을 만들지 않는다.
// ----------------------------------------------------------------------------
// ★ 열 고르기 — 예전 주석의 「글자 없는 열을 골라야 한다」는 **틀렸다(2026-08-12 정정).**
//   글자·아이콘은 배경과 밝기가 다르므로 **카드로 셈되어 구간을 안 쪼갠다.** 지나가도 된다.
//   진짜 문제는 둘이다:
//   - **이웃 요소와 이어붙는 것** — 열이 다이내믹 아일랜드(검정)나 하단 바를 지나면 한 덩어리가 된다.
//     → **`--y`를 관심 있는 행만 담게 좁힌다.**
//   - **카드 안의 어두운 박스** — 원문 입력칸처럼 배경과 밝기가 비슷한 것은 구간을 끊는다.
//     → 그런 박스를 피한 열을 쓰거나, 카드 좌우 여백 쪽 열을 쓴다(단 ①을 피할 만큼 안쪽으로).

import AppKit

let argv = Array(CommandLine.arguments.dropFirst())
func opt(_ name: String) -> String? {
    guard let i = argv.firstIndex(of: name), i + 1 < argv.count else { return nil }
    return argv[i + 1]
}
let positional = { () -> [String] in
    var out: [String] = []; var skip = false
    for a in argv {
        if skip { skip = false; continue }
        if a.hasPrefix("--") { skip = true; continue }
        out.append(a)
    }
    return out
}()

guard positional.count >= 2 else {
    print("쓰는 법: swift measure-ui.swift <스크린샷.png> <x열…> [--scale 3] [--y 600,1150] [--bg x,y] [--eps 0.005]")
    exit(1)
}
let path = positional[0]
let columns = positional.dropFirst().compactMap { Int($0) }
let scale = Double(opt("--scale") ?? "3") ?? 3
let eps = Double(opt("--eps") ?? "0.005") ?? 0.005

guard let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation,
      let bmp = NSBitmapImageRep(data: tiff) else {
    print("이미지를 못 읽었다: \(path)"); exit(1)
}
let W = bmp.pixelsWide, H = bmp.pixelsHigh
print("이미지 \(W)x\(H)px · scale \(scale) → 논리 \(Int(Double(W)/scale))x\(Int(Double(H)/scale))pt")

func lum(_ x: Int, _ y: Int) -> Double {
    guard x >= 0, x < W, y >= 0, y < H, let c = bmp.colorAt(x: x, y: y) else { return -1 }
    return 0.299 * Double(c.redComponent) + 0.587 * Double(c.greenComponent) + 0.114 * Double(c.blueComponent)
}

var yRange = (0, H - 1)
if let s = opt("--y") {
    let p = s.split(separator: ",").compactMap { Int($0) }
    if p.count == 2 { yRange = (max(0, p[0]), min(H - 1, p[1])) }
}

// **배경 밝기 = 왼쪽 여백 열의 중앙값.** 한 점만 찍으면 하필 하단 바·배너 같은 밝은 자리를 집을 수 있다
// (이 도구를 만들던 날 기본값이 하단 바를 찍어 0.1575가 나왔고, 그러면 카드가 아예 안 잡힌다).
// 중앙값은 그런 일부 구간에 안 흔들린다. --bg 로 한 점을 직접 줄 수도 있다.
let bg: Double
if let s = opt("--bg") {
    let p = s.split(separator: ",").compactMap { Int($0) }
    bg = p.count == 2 ? lum(p[0], p[1]) : 0
    print("배경 표본 (지정) 밝기 \(String(format: "%.4f", bg)) · 임계 \(eps)")
} else {
    let col = (yRange.0...yRange.1).map { lum(15, $0) }.sorted()
    bg = col[col.count / 2]
    print("배경 = 왼쪽 여백(x=15) 중앙값 \(String(format: "%.4f", bg)) · 임계 \(eps)")
}

let minRun = Int(20 * scale)   // 논리 20pt 미만은 카드로 안 본다(구분선·글자 조각 걸러내기)

for x in columns {
    print("\n열 x=\(x)px (논리 \(String(format: "%.1f", Double(x)/scale))pt)")
    var runs: [(Int, Int)] = []
    var start: Int? = nil
    for y in yRange.0...yRange.1 {
        let isCard = abs(lum(x, y) - bg) > eps
        if isCard, start == nil { start = y }
        if !isCard, let s = start {
            if y - s >= minRun { runs.append((s, y - 1)) }
            start = nil
        }
    }
    if let s = start, yRange.1 - s >= minRun { runs.append((s, yRange.1)) }
    if runs.isEmpty { print("  (구간 없음 — 글자를 지나는 열이거나 --eps 를 낮춰야 한다)") }
    for (a, b) in runs {
        let h = Double(b - a + 1) / scale
        print("  y \(a)~\(b)px · 높이 \(b - a + 1)px = \(String(format: "%.1f", h))pt"
              + "  (위 \(String(format: "%.1f", Double(a)/scale))pt · 아래 \(String(format: "%.1f", Double(b)/scale))pt)")
    }
}
