import SwiftUI
import UIKit

//
//  MediaCardProbe — **자료 카드**를 여러 꼴로 그려 놓고 재는 꼴 (2026-08-22 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** `native/tools/ghostlab/`이고 `SecondBrain` 빌드에 안 섞인다.
//  색은 앱에서 **값만 베껴** 뒀다(`Palette`를 안 쓴다 — 랩 규칙).
//
//  ── 무엇을 재려고 만들었나 (`media-expansion-design.md` §3-A) ──────────
//  사용자 방향: **종류 다섯**(음성/사운드 · 사진/이미지 · URL · PDF · 기타)마다 **정사각형 하나**,
//  왼쪽부터 그 순서. 0개면 안 보이고, 여럿이면 **좌상단에 개수**, 폭을 넘으면 **가로 스크롤**.
//
//  이 프로브가 답하는 것 셋 (§3-A-6):
//    ② **음성이 맨 앞인 것** — 음성만 미리보기가 없어 아이콘뿐인데 1번 자리다. **화면으로 보고 정한다.**
//    ③ **네모 한 변을 얼마로 잡으면 다섯이 한 화면에 들어가나** → `sizes` 꼴.
//    그리고 **「못 만들었다」와 「자료가 없다」를 갈라 보이는 꼴**(§3-A-3) — 문구 후보 셋을 나란히.
//
//  ⛔ **네모 안의 사진·페이지는 실물이 아니다.** 표본 `82B1044B`는 이 기기에서 dataless이고
//     **파일은 받지 않는다**(사용자 2026-08-22). **정사각형이면 실물 비율이 필요 없다** —
//     그래서 여기 그려진 것은 **자리를 차지하는 대역**이고, 재는 것은 **네모의 자리와 크기**다.
//
//  ── 폭 계산 (앱 코드에서 읽은 상수 · 2026-08-22) ──────────────────────
//    화면 402pt(iPhone 16 Pro · 1206px @3x 실측) − `ScrollView` 안쪽 `.padding(16)`×2
//      − 카드 `.padding(14)`×2 = **내용 폭 342pt**
//    (`DetailView.swift:194` `.padding(16)` · `:811` 등 `.padding(14).card()`)
//

// 앱에서 값만 베낀 색 (Theme.swift)
private let cBg        = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let cSurface   = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let cSurface2  = Color(red: 0x26/255, green: 0x23/255, blue: 0x2F/255)
private let cBorder    = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)
private let cText      = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let cText2     = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let cText3     = Color(red: 0x74/255, green: 0x6F/255, blue: 0x82/255)
private let cAccent    = Color(red: 0x8B/255, green: 0x87/255, blue: 0xF5/255)
private let cOverdue   = Color(red: 0xFB/255, green: 0x73/255, blue: 0x85/255)

/// 종류 다섯 — **순서가 방향에 박혀 있다**(§3-A-1). 이 배열 순서가 곧 화면 순서다.
enum MediaKind: Int, CaseIterable, Identifiable {
    case voice = 0, photo, url, pdf, other
    var id: Int { rawValue }

    /// 계측용 딱지 — 화면 문구가 아니다(랩에서 어느 네모인지 가리키려고 쓴다).
    var tag: String {
        switch self {
        case .voice: return "음성"
        case .photo: return "사진"
        case .url:   return "URL"
        case .pdf:   return "PDF"
        case .other: return "기타"
        }
    }
    var symbol: String {
        switch self {
        case .voice: return "waveform"
        case .photo: return "photo"
        case .url:   return "link"
        case .pdf:   return "doc.richtext"
        case .other: return "doc"
        }
    }
    /// 네모를 픽셀로 가려내려고 종류마다 다른 색을 준다(`measure-frames.swift`의 그 수법).
    var probeTint: Color {
        switch self {
        case .voice: return cAccent
        case .photo: return .green
        case .url:   return .cyan
        case .pdf:   return .orange
        case .other: return cText3
        }
    }
}

/// 네모 하나의 상태 — **「있다」와 「못 만들었다」를 갈라야 한다**(§3-A-3).
enum ThumbState { case ok, failed }

struct MediaTile: View {
    let kind: MediaKind
    let count: Int
    let side: CGFloat
    var state: ThumbState = .ok
    /// 「못 만들었다」 문구 후보 — ⛔ **화면 문구는 사용자가 정한다.** 여기 것은 **후보**다.
    var failText: String = ""

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(cSurface2)
            inner
            if count > 1 { badge }
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(state == .failed ? cOverdue.opacity(0.55) : cBorder))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder private var inner: some View {
        if state == .failed { failedFace } else { okFace }
    }

    /// 「있다」 — 종류마다 무엇을 보이나(§3-A-2).
    @ViewBuilder private var okFace: some View {
        switch kind {
        case .voice:
            // ★ 음성만 **미리보기가 없다** — 아이콘 + 메타. 이 꼴이 ②의 판정 재료다.
            VStack(spacing: max(1, side * 0.04)) {
                Image(systemName: "waveform")
                    .font(.system(size: side * 0.34, weight: .regular))
                    .foregroundStyle(cAccent)
                Text("0:37").font(.system(size: max(8, side * 0.15), weight: .semibold))
                    .foregroundStyle(cText)
                Text("8/7").font(.system(size: max(7, side * 0.12)))
                    .foregroundStyle(cText3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .photo:
            // 대역 — **사진의 중앙이 포함되는 정사각형**을 잘라낸 것을 흉내낸다.
            ZStack {
                LinearGradient(colors: [.teal.opacity(0.85), .indigo.opacity(0.9)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "mountain.2.fill")
                    .font(.system(size: side * 0.42)).foregroundStyle(.white.opacity(0.85))
            }
        case .url:
            // 대역 — **페이지 축소의 윗쪽**. 위에 제목 줄, 아래로 본문 줄.
            pageFace(top: Color.white.opacity(0.92), accent: .cyan, mark: nil)
        case .pdf:
            pageFace(top: Color.white.opacity(0.92), accent: .orange, mark: "PDF")
        case .other:
            VStack(spacing: side * 0.05) {
                Image(systemName: "doc")
                    .font(.system(size: side * 0.36)).foregroundStyle(cText2)
                Text("ZIP").font(.system(size: max(7, side * 0.13), weight: .semibold))
                    .foregroundStyle(cText3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// URL·PDF 대역 — 「윗쪽이 포함되는 정사각형」이라 **위가 잘리지 않고 아래가 잘린다.**
    private func pageFace(top: Color, accent: Color, mark: String?) -> some View {
        ZStack(alignment: .topLeading) {
            top
            VStack(alignment: .leading, spacing: side * 0.055) {
                RoundedRectangle(cornerRadius: 1).fill(accent).frame(width: side * 0.5, height: side * 0.085)
                ForEach(0..<4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 1).fill(Color.black.opacity(0.35))
                        .frame(width: side * (i == 3 ? 0.45 : 0.72), height: side * 0.05)
                }
            }
            .padding(side * 0.1)
            if let mark {
                Text(mark).font(.system(size: max(7, side * 0.13), weight: .heavy))
                    .foregroundStyle(accent)
                    .padding(side * 0.06)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    /// 「못 만들었다」 — ⛔ **「자료가 없다」와 갈라 보인다**(§3-A-3).
    private var failedFace: some View {
        VStack(spacing: max(2, side * 0.05)) {
            Image(systemName: kind.symbol)
                .font(.system(size: side * 0.26)).foregroundStyle(cText3)
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: side * 0.16)).foregroundStyle(cOverdue)
            if !failText.isEmpty {
                Text(failText)
                    .font(.system(size: max(7, side * 0.115)))
                    .foregroundStyle(cText2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2).minimumScaleFactor(0.8)
                    .padding(.horizontal, side * 0.06)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// 여럿이면 **좌상단에 개수를 숫자로**(§3-A-1).
    private var badge: some View {
        Text("\(count)")
            .font(.system(size: max(9, side * 0.19), weight: .bold)).monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, max(3, side * 0.07)).padding(.vertical, max(1, side * 0.03))
            .background(Capsule().fill(Color.black.opacity(0.72)))
            .padding(max(2, side * 0.05))
    }
}

/// 자료 카드 하나 — **폭 전체**(§3-2) · 네모 한 줄 · 넘치면 가로 스크롤(§3-A-1).
struct MediaCard: View {
    let items: [(MediaKind, Int, ThumbState, String)]
    let side: CGFloat
    var showEdge: Bool = true          // 좌/우에 더 있음 표시
    var label: String = ""             // 랩 딱지(계측용 · 화면 문구 아님)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !label.isEmpty {
                Text(label).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(cText3)
            }
            GeometryReader { geo in
                let need = CGFloat(items.count) * side + CGFloat(max(0, items.count - 1)) * gap
                let overflows = need > geo.size.width + 0.5
                ZStack(alignment: .trailing) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: gap) {
                            ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                                MediaTile(kind: it.0, count: it.1, side: side,
                                          state: it.2, failText: it.3)
                            }
                        }
                    }
                    if overflows && showEdge { edgeHint }
                }
                .overlay(alignment: .bottomLeading) {
                    // 계측 딱지 — 폭이 얼마고 몇 개가 들어갔나를 화면에서도 읽게 한다.
                    Text("폭 \(Int(geo.size.width)) · 한 변 \(Int(side)) · \(items.count)개 · 필요 \(Int(need))\(overflows ? " ⟶ 넘침" : "")")
                        .font(.system(size: 9)).foregroundStyle(cText3)
                        .offset(y: 11)
                }
            }
            .frame(height: side + 14)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(cBorder))
    }

    private var gap: CGFloat { 8 }

    /// 「우쪽에 더 있음」 — 흐림 + chevron. ⛔ **문구가 아니라 표시다**(사용자 방향).
    private var edgeHint: some View {
        HStack(spacing: 0) {
            LinearGradient(colors: [cSurface.opacity(0), cSurface], startPoint: .leading, endPoint: .trailing)
                .frame(width: 26)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(cText2)
                .frame(width: 14).background(cSurface)
        }
        .frame(height: side)
        .allowsHitTesting(false)
    }
}

// MARK: - 꼴 Q: 종류 1~5개 · 개수 표시 · 「못 만들었다」

struct MediaCardProbe: View {
    /// ③의 계산값 — 342pt 안에 여백 8로 다섯이 들어가는 최대 한 변은 **62.0pt**다.
    /// (5S + 4×8 ≤ 342 → S ≤ 62.0) 계산은 후보 좁히기고 **결론은 픽셀로 닫는다**(계측 규칙 4).
    private let side: CGFloat = 62
    /// ⚠️ **한 화면에 다 안 들어가서 둘로 갈랐다** — 스크롤 없이 찍으려면 이 길뿐이다
    /// (`sim-input.swift`는 사용자가 명시할 때만 쓴다 — `CLAUDE.md` 계측 규칙 5).
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if page == 1 { pageOne } else { pageTwo }
            }
            .padding(16)
        }
        .background(cBg)
        .foregroundStyle(cText)
    }

    @ViewBuilder private var pageOne: some View {
        Group {
                MediaCard(items: [(.voice, 1, .ok, "")], side: side, label: "종류 1 — 음성만")
                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 3, .ok, "")],
                          side: side, label: "종류 2 — 음성 + 사진 3장(개수 배지)")
                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 3, .ok, ""), (.url, 1, .ok, "")],
                          side: side, label: "종류 3")
                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 3, .ok, ""), (.url, 1, .ok, ""),
                                  (.pdf, 2, .ok, "")],
                          side: side, label: "종류 4")
                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 3, .ok, ""), (.url, 1, .ok, ""),
                                  (.pdf, 2, .ok, ""), (.other, 1, .ok, "")],
                          side: side, label: "종류 5 — 다섯 다")
        }
    }

    @ViewBuilder private var pageTwo: some View {
        Group {
                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 12, .ok, ""), (.url, 4, .ok, ""),
                                  (.pdf, 9, .ok, ""), (.other, 25, .ok, "")],
                          side: side, label: "개수가 두 자리일 때 (배지 폭)")

                // 「못 만들었다」 — 문구 후보 셋을 **한 카드에 나란히** 두어 눈으로 고르게 한다.
                MediaCard(items: [(.url, 1, .failed, "미리보기\n없음"),
                                  (.url, 1, .failed, "못 불러옴"),
                                  (.pdf, 1, .failed, "표지\n못 만듦"),
                                  (.other, 1, .failed, "미리보기\n안 됨")],
                          side: side, label: "못 만들었다 — 문구 후보 넷 (⛔ 문구는 사용자가 정한다)")

                MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 2, .ok, ""),
                                  (.url, 1, .failed, "미리보기\n없음"), (.pdf, 1, .ok, "")],
                          side: side, label: "섞임 — 된 것 셋 + 못 만든 것 하나")

                // 「자료가 없다」와의 대조 — ⛔ 이 둘이 같게 보이면 안 된다(§3-A-3).
                MediaCard(items: [(.voice, 1, .ok, "")], side: side,
                          label: "대조 — 그 종류가 0개면 네모가 아예 없다(음성만 남는다)")
        }
    }
}

// MARK: - 꼴 R: 네모 한 변 스윕 — 다섯이 한 화면에 들어가나 (§3-A-6 ③)

struct MediaSizeProbe: View {
    private let sides: [CGFloat] = [56, 62, 68, 76, 88, 100]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("342pt 안에 여백 8 · 다섯 개 → 한 변 62.0이 상한 (계산)")
                    .font(.system(size: 11)).foregroundStyle(cText2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sides, id: \.self) { s in
                    MediaCard(items: MediaKind.allCases.map { ($0, $0 == .photo ? 3 : 1, ThumbState.ok, "") },
                              side: s, label: "한 변 \(Int(s))")
                }
            }
            .padding(16)
        }
        .background(cBg)
        .foregroundStyle(cText)
    }
}
