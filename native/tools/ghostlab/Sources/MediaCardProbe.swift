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
    /// ★ **여섯이다**(2026-08-22 사용자) — 동영상이 **사진 다음, URL 앞**이다.
    /// ⛔ 이 배열 순서가 곧 화면 순서다.
    case voice = 0, photo, video, url, pdf, other
    var id: Int { rawValue }

    /// 계측용 딱지 — 화면 문구가 아니다(랩에서 어느 네모인지 가리키려고 쓴다).
    var tag: String {
        switch self {
        case .voice: return "음성"
        case .photo: return "사진"
        case .video: return "동영상"
        case .url:   return "URL"
        case .pdf:   return "PDF"
        case .other: return "기타"
        }
    }
    var symbol: String {
        switch self {
        case .voice: return "waveform"
        case .photo: return "photo"
        case .video: return "video"
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
        case .video: return .pink
        case .url:   return .cyan
        case .pdf:   return .orange
        case .other: return cText3
        }
    }
}

/// 네모 하나의 상태 — **「있다」와 「못 만들었다」를 갈라야 한다**(§3-A-3).
enum ThumbState { case ok, failed }

/// ★ 실패의 **세 상태**(2026-08-22 사용자) — 랩에서 「아이콘을 갈라 주면 구분이 되나」를 본다.
/// ⛔ 이름은 랩 딱지다. 화면에 나올 말은 사용자가 고른다.
enum FailKind {
    case cannotDraw      // ① 자료는 있고 그림만 못 만들었다 — 눌러 들어가면 볼 수 있다
    case notFetched      // ② 가져오지 못했다 — 다시 시도할 값이 있다
    case unsupported     // ③ 포맷 지원이 안 된다 — 다시 시도할 것이 없다
    case generic         // 딱지 없음(옛 꼴 · 셋을 한 아이콘으로 덮은 것)

    var symbol: String {
        switch self {
        case .cannotDraw:  return "hand.tap.fill"
        case .notFetched:  return "icloud.and.arrow.down"
        case .unsupported: return "nosign"
        case .generic:     return "exclamationmark.triangle.fill"
        }
    }
}

struct MediaTile: View {
    let kind: MediaKind
    let count: Int
    let side: CGFloat
    var state: ThumbState = .ok
    var fail: FailKind = .generic
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
            // ★ 음성만 **미리보기가 없다** — 아이콘 + 길이. **②는 「그대로 좋다」로 닫혔다**(2026-08-22 사용자).
            //
            // ⛔ **글자를 고쳤다 (2026-08-22 밤 사용자)** — 옛 꼴은 **두 줄**이었다:
            //    · 길이 `0:37` = `side * 0.15` → **62pt에서 9.3pt**
            //    · 날짜 `8/7`  = `side * 0.12` → **62pt에서 7.4pt**
            //    새 꼴은 **날짜를 뺐고**(네모에서 보여줄 필요가 없다) **길이를 2pt 키웠다** →
            //    `side * 0.15 + 2` → **62pt에서 11.3pt**. **두 줄이 한 줄이 된다.**
            VStack(spacing: max(1, side * 0.04)) {
                Image(systemName: "waveform")
                    .font(.system(size: side * 0.34, weight: .regular))
                    .foregroundStyle(cAccent)
                Text("0:37").font(.system(size: side * 0.15 + 2, weight: .semibold))
                    .foregroundStyle(cText)
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
        case .video:
            // 대역 — **첫 프레임(장면)의 중앙**을 자른 것을 흉내낸다.
            // ★ 사진과 같은 「중앙」이므로 **재생 표시가 없으면 사진과 구분이 안 된다** — 그것이 이 꼴의 논점.
            ZStack {
                LinearGradient(colors: [.pink.opacity(0.75), .purple.opacity(0.9)],
                               startPoint: .top, endPoint: .bottom)
                Image(systemName: "figure.walk")
                    .font(.system(size: side * 0.40)).foregroundStyle(.white.opacity(0.8))
                Image(systemName: "play.circle.fill")
                    .font(.system(size: side * 0.30))
                    .foregroundStyle(.white, .black.opacity(0.45))
                Text("1:02").font(.system(size: max(7, side * 0.13), weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3).padding(.vertical, 1)
                    .background(Capsule().fill(.black.opacity(0.5)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(side * 0.05)
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
            Image(systemName: fail.symbol)
                .font(.system(size: side * 0.17))
                .foregroundStyle(fail == .notFetched ? cText2 : cOverdue)
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
    /// 항목마다의 실패 종류 — 비어 있으면 전부 `.generic`.
    var fails: [FailKind] = []
    let side: CGFloat
    var showEdge: Bool = true          // 좌/우에 더 있음 표시
    var edgeStyle: Int = 0             // 0=흐림+chevron(겹침) · 1=흐림만 · 2=아래 점(안 겹친다)
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
                                          state: it.2,
                                          fail: fails.isEmpty ? .generic : fails[min(fails.count - 1, items.firstIndex(where: { $0.0 == it.0 && $0.3 == it.3 }) ?? 0)],
                                          failText: it.3)
                            }
                        }
                    }
                    if overflows && showEdge && edgeStyle != 2 { edgeHint }
                }
                .overlay(alignment: .bottom) {
                    // edgeStyle 2 — **네모를 안 덮는 표시.** 카드가 12pt 높아진다.
                    if edgeStyle == 2 && overflows {
                        HStack(spacing: 4) {
                            Circle().fill(cText2).frame(width: 5, height: 5)
                            Circle().fill(cText3.opacity(0.5)).frame(width: 5, height: 5)
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8, weight: .bold)).foregroundStyle(cText3)
                        }
                        .offset(y: 24)
                    }
                }
                .overlay(alignment: .bottomLeading) {
                    // 계측 딱지 — 폭이 얼마고 몇 개가 들어갔나를 화면에서도 읽게 한다.
                    Text("폭 \(Int(geo.size.width)) · 한 변 \(Int(side)) · \(items.count)개 · 필요 \(Int(need))\(overflows ? " ⟶ 넘침" : "")")
                        .font(.system(size: 9)).foregroundStyle(cText3)
                        .offset(y: 11)
                }
            }
            .frame(height: side + 14 + (edgeStyle == 2 ? 12 : 0))
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
            if edgeStyle == 0 {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold)).foregroundStyle(cText2)
                    .frame(width: 14).background(cSurface)
            }
        }
        .frame(height: side)
        .allowsHitTesting(false)
    }
}

// MARK: - 꼴 Q: 종류 1~6개 · 개수 표시 (2026-08-22 · 여섯으로 늘었다)

struct MediaCardProbe: View {
    /// ③의 답 — 342pt 안에 여백 8이면 **62pt에서 다섯**이 들어간다(5×62+32 = 342).
    /// ★ **여섯째부터 넘친다**(6×62+40 = 412) — 사용자가 62을 유지하고 **스크롤로 해결**하기로 했다.
    private let side: CGFloat = 62
    var page: Int = 1

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                switch page {
                case 1: pageOne
                case 2: pageTwo
                case 3: pageThree
                default: pageFour
                }
            }
            .padding(16)
        }
        .background(cBg)
        .foregroundStyle(cText)
    }

    private func all(_ n: Int) -> [(MediaKind, Int, ThumbState, String)] {
        Array(MediaKind.allCases.prefix(n)).map { k in
            (k, k == .photo ? 3 : 1, ThumbState.ok, "")
        }
    }

    /// 종류 1~6 — **여섯째에서 넘친다.**
    @ViewBuilder private var pageOne: some View {
        Group {
            MediaCard(items: all(1), side: side, label: "종류 1 — 음성만")
            MediaCard(items: all(3), side: side, label: "종류 3 — 음성 · 사진3 · 동영상")
            MediaCard(items: all(5), side: side, label: "종류 5 — 다섯 (딱 맞는다 · 표시 없음)")
            MediaCard(items: all(6), side: side, edgeStyle: 2,
                      label: "✅ 종류 6 — 정해진 꼴: 표시 ㉰ 아래 점 (네모를 안 덮는다)")
            MediaCard(items: all(6), side: side,
                      label: "(안 고른 것) 표시 ㉮ 흐림+chevron — 다섯째를 덮는다")
            MediaCard(items: all(6), side: side, edgeStyle: 1,
                      label: "(안 고른 것) 표시 ㉯ 흐림만")
        }
    }

    /// 배지 · 「자료가 없다」 대조
    @ViewBuilder private var pageTwo: some View {
        Group {
            MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 12, .ok, ""), (.video, 3, .ok, ""),
                              (.url, 4, .ok, ""), (.pdf, 9, .ok, ""), (.other, 25, .ok, "")],
                      side: side, label: "개수가 두 자리일 때 (배지가 네모를 덮는다)")
            MediaCard(items: [(.voice, 1, .ok, ""), (.photo, 2, .ok, ""), (.video, 1, .ok, "")],
                      side: side, label: "대조 — 없는 종류는 네모가 아예 없다 (URL·PDF·기타 0개)")
            MediaCard(items: [(.video, 1, .ok, "")], side: side,
                      label: "동영상만 — 재생 표시가 없으면 사진과 구분이 안 된다")
        }
    }

    /// ★ 문구 셋 — **말끝이 달라야 다른 상태로 보인다**(사용자 2026-08-22).
    /// ⛔ 여기 것은 **후보**다. 화면에 나올 말은 사용자가 고른다.
    @ViewBuilder private var pageThree: some View {
        Group {
            MediaCard(items: [(.url, 1, .failed, "눌러서\n보기"),
                              (.url, 1, .failed, "미리보기만\n없음"),
                              (.pdf, 1, .failed, "그림만\n없음")],
                      side: side, label: "① 자료는 있고 그림만 못 만들었다 — 눌러 들어가면 볼 수 있다")
            MediaCard(items: [(.photo, 1, .failed, "아직\n못 받음"),
                              (.photo, 1, .failed, "다시\n시도"),
                              (.video, 1, .failed, "못 찾음")],
                      side: side, label: "② 가져오지 못했다 — 기존 세 갈래와 같은 층")
            MediaCard(items: [(.other, 1, .failed, "지원\n안 함"),
                              (.other, 1, .failed, "볼 수\n없음"),
                              (.other, 1, .failed, "미리보기\n없는 형식")],
                      side: side, label: "③ 포맷 지원이 안 된다 — 다시 시도할 것이 없다")
            MediaCard(items: [(.url, 1, .failed, "눌러서\n보기"),
                              (.photo, 1, .failed, "아직\n못 받음"),
                              (.other, 1, .failed, "지원\n안 함"),
                              (.voice, 1, .ok, ""), (.video, 1, .ok, "")],
                      side: side, label: "★ 셋을 나란히 — 서로 구분되나 (뒤 둘은 정상)")
        }
    }
}

extension MediaCardProbe {
    /// ★ 꼴 X — **아이콘을 상태마다 갈라 준 꼴.** V(글자만 다름)와 나란히 놓고 고른다.
    @ViewBuilder var pageFour: some View {
        Group {
            MediaCard(items: [(.url, 1, .failed, "눌러서\n보기"),
                              (.photo, 1, .failed, "아직\n못 받음"),
                              (.other, 1, .failed, "지원\n안 함"),
                              (.voice, 1, .ok, ""), (.video, 1, .ok, "")],
                      fails: [.cannotDraw, .notFetched, .unsupported, .generic, .generic],
                      side: 62,
                      label: "★ 아이콘을 갈랐다 — ① 손가락 · ② 구름 화살표 · ③ 금지")
            MediaCard(items: [(.url, 1, .failed, ""),
                              (.photo, 1, .failed, ""),
                              (.other, 1, .failed, "")],
                      fails: [.cannotDraw, .notFetched, .unsupported],
                      side: 62,
                      label: "★ 글자를 아예 뺐다 — 아이콘만으로 갈리나 (긴 말은 뷰어에서)")
            MediaCard(items: [(.url, 1, .failed, "눌러서\n보기"),
                              (.photo, 1, .failed, "아직\n못 받음"),
                              (.other, 1, .failed, "지원\n안 함")],
                      side: 62,
                      label: "대조 — 같은 삼각형 하나로 덮은 옛 꼴 (V와 같다)")
        }
    }
}

/// ★ 꼴 Y — **「더 있음」 세 꼴의 카드 높이만 갈라 재는 대조군** (2026-08-22 저녁).
/// ⛔ **딱지를 한 글자로 맞췄다** — 꼴 Q는 딱지 길이가 달라 **줄바꿈이 높이를 흔든다.**
/// 그러면 「표시가 높이를 바꿨나」와 「글자가 한 줄 늘었나」가 안 갈린다.
struct EdgeHeightProbe: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                let six = MediaKind.allCases.map { ($0, 1, ThumbState.ok, "") }
                MediaCard(items: six, side: 62, edgeStyle: 2, label: "㉰")
                MediaCard(items: six, side: 62, label: "㉮")
                MediaCard(items: six, side: 62, edgeStyle: 1, label: "㉯")
                MediaCard(items: Array(six.prefix(5)), side: 62, label: "五")   // 안 넘치는 대조
            }
            .padding(16)
        }
        .background(cBg)
        .foregroundStyle(cText)
    }
}

// MARK: - 꼴 R: 네모 한 변 스윕 — 여섯이 몇 개까지 보이나

struct MediaSizeProbe: View {
    private let sides: [CGFloat] = [50, 56, 62, 68, 76, 88]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("342pt · 여백 8 — 다섯은 62까지, 여섯은 50.3까지 (계산)")
                    .font(.system(size: 11)).foregroundStyle(cText2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(sides, id: \.self) { s in
                    MediaCard(items: MediaKind.allCases.map { ($0, $0 == .photo ? 3 : 1, ThumbState.ok, "") },
                              side: s, label: "한 변 \(Int(s)) · 종류 6")
                }
            }
            .padding(16)
        }
        .background(cBg)
        .foregroundStyle(cText)
    }
}
