#!/usr/bin/env swift
//
//  sim-input.swift — 시뮬레이터를 CLI로 탭·드래그한다 (2026-08-14)
//
//  ⚠️⚠️ **먼저 읽을 것 — 「항시 규칙」 7과의 관계.**
//  `CLAUDE.md` 「항시 규칙」 7은 **화면을 눌러 여는 것은 사용자가 한다**로 정해 두었다
//  (Claude Code가 하는 것은 부팅·설치·설정 변경·스크린샷·계측).
//  **이 도구는 그 규칙을 바꾸지 않는다.** 사용자가 *"직접 열어서 스스로 확인해봐"* 처럼
//  **명시적으로 지시한 경우**에만 쓴다. 기본은 여전히 「…을 열어주세요」로 부탁하는 것이다.
//  (2026-08-14에 사용자가 chevron 실태를 그렇게 지시해서 만들었다.)
//
//  ── 왜 이 도구가 필요한가: 안 되는 방법이 여럿이었다 ──────────────────
//  ⛔ `xcrun simctl`에 탭·드래그 명령이 **없다**(스크린샷·content_size·부팅만 있다).
//  ⛔ `idb`(fb-idb) 미설치.
//  ⛔ AppleScript `tell process "Simulator" to click at {x,y}` — **안 먹는다.**
//     반환값은 클릭한 요소를 그럴듯하게 뱉는데 앱은 반응하지 않는다.
//  ⛔ CGEvent **scrollWheel** — 시뮬레이터에 **전달되지 않는다**(리스트가 안 움직였다).
//  ✅ CGEvent **mouseDown → mouseUp** = 탭.
//  ✅ CGEvent **mouseDown → mouseDragged 여러 번 → mouseUp** = 드래그(스크롤).
//
//  ── 좌표를 얻는 법 (이게 핵심이다) ────────────────────────────────
//  창 좌상단에서 계산하지 말 것. **툴바(높이 44)가 있어서 y가 어긋난다** —
//  2026-08-14에 이것 때문에 첫 탭이 헛나갔다(38px 위를 눌렀다).
//  **접근성 트리에서 요소의 실제 화면 좌표를 그대로 읽는 것이 정확하고 빠르다:**
//
//    osascript -e 'tell application "System Events" to tell process "Simulator"
//      set out to {}
//      repeat with e in (entire contents of window 1)
//        try
//          set d to description of e
//          if d is not missing value and d is not "" then
//            set p to position of e
//            set s to size of e
//            set end of out to (d & " @ " & (item 1 of p) & "," & (item 2 of p) & _
//                               " [" & (item 1 of s) & "x" & (item 2 of s) & "]")
//          end if
//        end try
//      end repeat
//      return out
//    end tell'
//
//  → `아이 학원 등록 마감, ~07-14, D+31 @ 3396,466 [233x29]` 처럼 나온다.
//    **가운데를 눌러라:** x + w/2, y + h/2.
//  ⚠️ 접근성 description은 **화면 글자가 그대로** 나오므로 항목을 이름으로 찾을 수 있다.
//
//  ── 드래그 주의 ──────────────────────────────────────────────
//  ⚠️ **시작점이 탭바에 닿으면 탭이 바뀐다.** 탭바는 창 아래쪽 약 60px 띠다
//     (2026-08-14에 y=820에서 끌다가 「살아있는 기억」 탭으로 넘어갔다).
//     리스트를 끌 때는 **본문 한가운데**에서 시작한다(예: y=700 → 380).
//  ⚠️ 한 번에 조금씩만 움직인다. 리스트가 짧으면 곧 바닥이라 여러 번 끌어도 안 움직인다 —
//     **같은 스크린샷이 두 번 나오면 바닥**이다(더 끌지 말 것).
//
//  ── 쓰는 법 ─────────────────────────────────────────────────
//    swiftc -O sim-input.swift -o sim-input
//    osascript -e 'tell application "Simulator" to activate'   # 먼저 앞으로
//    ./sim-input tap  3512 480
//    ./sim-input drag 3500 700 380        # (x, y시작, y끝) — 아래로 끌면 콘텐츠가 위로
//
//  스크린샷은 이 도구가 아니라 `xcrun simctl io <UDID> screenshot out.png`로 찍는다.
//  **찍고 나서 반드시 눈으로 확인한다** — 탭이 헛나가도 조용히 실패한다(오류가 안 난다).
//
//  일회용이 아니라 **방법을 남기는 도구**다. 스크립트가 사라져도 위 주석이 남으면 다시 만들 수 있다.
//

import CoreGraphics
import Foundation

func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?
        .post(tap: .cghidEventTap)
}

func tap(x: Double, y: Double) {
    let p = CGPoint(x: x, y: y)
    post(.mouseMoved, p);      usleep(120_000)
    post(.leftMouseDown, p);   usleep(90_000)
    post(.leftMouseUp, p)
}

/// 세로 드래그(리스트 스크롤). `y2 < y1`이면 위로 끌어 콘텐츠가 올라간다(= 아래로 스크롤).
func drag(x: Double, y1: Double, y2: Double, steps: Int = 28) {
    post(.mouseMoved,     CGPoint(x: x, y: y1)); usleep(150_000)
    post(.leftMouseDown,  CGPoint(x: x, y: y1)); usleep(120_000)
    for i in 1...steps {
        let t = Double(i) / Double(steps)
        post(.leftMouseDragged, CGPoint(x: x, y: y1 + (y2 - y1) * t))
        usleep(12_000)   // 너무 빠르면 관성 스크롤이 과하게 걸린다
    }
    usleep(60_000)
    post(.leftMouseUp, CGPoint(x: x, y: y2))
}

let a = CommandLine.arguments
func die(_ m: String) -> Never { FileHandle.standardError.write(Data((m + "\n").utf8)); exit(2) }

guard a.count >= 2 else {
    die("""
    사용법:
      sim-input tap  <x> <y>
      sim-input drag <x> <y시작> <y끝>
    좌표는 **화면 절대 좌표**다 — 접근성 트리에서 읽는다(파일 머리주석 참조).
    """)
}

switch a[1] {
case "tap":
    guard a.count == 4, let x = Double(a[2]), let y = Double(a[3]) else { die("tap <x> <y>") }
    tap(x: x, y: y)
case "drag":
    guard a.count == 5, let x = Double(a[2]), let y1 = Double(a[3]), let y2 = Double(a[4])
    else { die("drag <x> <y시작> <y끝>") }
    drag(x: x, y1: y1, y2: y2)
default:
    die("알 수 없는 명령: \(a[1]) — tap 또는 drag")
}
