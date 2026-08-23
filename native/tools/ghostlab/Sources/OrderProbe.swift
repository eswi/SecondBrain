import SwiftUI

//
//  OrderProbe — **「if/else 구조」와 「순서 배열」이 같은 픽셀을 내나** (2026-08-23 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** 랩이다.
//
//  ── 왜 (자료 확장 ② 커밋 ①의 확인 ㉠) ─────────────────────────
//  `DetailView` 본문을 **순서 배열**로 바꿨다(설계 §3-G-4의 B안). **화면이 안 바뀌어야 한다.**
//  순서가 같다는 것은 **㉡ 코드 대조**에서 네 상태 전부 확인했다.
//  **여기서 보는 것은 그리기다** — `ForEach`로 그리면 **여백이 달라지지 않나**.
//
//  ⛔ **진짜 위험은 「아무것도 안 그리는 자식」이다.** 배너 다섯은 조건이 안 맞으면 `EmptyView`를 낸다.
//     옛 구조에서는 `VStack`의 자식으로 있다가 사라지고, 새 구조에서는 `ForEach`의 한 칸이 된다.
//     **둘이 여백을 다르게 먹으면 화면이 밀린다** — 그것을 픽셀로 본다.
//
//  ── 쓰는 법 ────────────────────────────────────────────────
//    -ghostmode OA  (옛꼴: if/else)   ·   -ghostmode OB  (새꼴: 순서 배열)
//    두 장을 찍어 `measure-diff.swift`로 비교한다. **다른 픽셀 0이어야 한다.**
//

private let oBg      = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let oSurface = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let oBorder  = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)
private let oText    = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)

/// 앱의 자식들을 흉내낸 블록. **일부는 조건이 안 맞아 `EmptyView`를 낸다** — 그것이 이 실험의 핵심이다.
private struct Child: View {
    let name: String
    let show: Bool
    let h: CGFloat
    @ViewBuilder var body: some View {
        if show {
            Text(name).font(.system(size: 11)).foregroundStyle(oText)
                .frame(maxWidth: .infinity, minHeight: h, alignment: .leading)
                .padding(.horizontal, 10)
                .background(oSurface, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(oBorder))
        }
    }
}

struct OrderProbe: View {
    /// 새꼴이면 `ForEach` + 고정 id, 옛꼴이면 `if`/`else`.
    let useArray: Bool

    /// 앱과 같은 조건 조합 — **배너 다섯 중 둘만 뜬다**(나머지 셋은 `EmptyView`).
    private let isRemembered = true
    private let hasQuestion = true
    private let bannerShown: [Bool] = [true, false, true, false, false]

    private enum Sec: String, Identifiable, CaseIterable {
        case b0, b1, b2, b3, b4, metaType, question, time, recurrence, history, decide
        var id: String { rawValue }
    }
    private var order: [Sec] {
        var o: [Sec] = []
        if isRemembered { o += [.b0, .b1, .b2, .b3, .b4] }
        o.append(.metaType)
        if hasQuestion { o.append(.question) }
        if isRemembered { o += [.time, .recurrence, .history] } else { o.append(.decide) }
        return o
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Child(name: "원문", show: true, h: 90)          // 배열 밖(앱의 rawSection과 같은 자리)
                VStack(alignment: .leading, spacing: 14) {
                    if useArray { arrayBody } else { ifElseBody }
                }
                .contentShape(Rectangle())
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(oBg)
    }

    /// 옛꼴 — 지금 앱이 하던 그대로.
    @ViewBuilder private var ifElseBody: some View {
        if isRemembered {
            Child(name: "배너1", show: bannerShown[0], h: 40)
            Child(name: "배너2", show: bannerShown[1], h: 40)
            Child(name: "배너3", show: bannerShown[2], h: 40)
            Child(name: "배너4", show: bannerShown[3], h: 40)
            Child(name: "배너5", show: bannerShown[4], h: 40)
        }
        Child(name: "성역+분류", show: true, h: 120)
        if hasQuestion { Child(name: "재확인 질문", show: true, h: 50) }
        if isRemembered {
            Child(name: "시간 설정", show: true, h: 60)
            Child(name: "반복 설정", show: true, h: 60)
            Child(name: "수정 이력", show: true, h: 30)
        } else {
            Child(name: "[삭제하기]·[기억하기]", show: true, h: 44)
        }
    }

    /// 새꼴 — 고정 id를 가진 배열.
    @ViewBuilder private var arrayBody: some View {
        ForEach(order) { s in
            switch s {
            case .b0: Child(name: "배너1", show: bannerShown[0], h: 40)
            case .b1: Child(name: "배너2", show: bannerShown[1], h: 40)
            case .b2: Child(name: "배너3", show: bannerShown[2], h: 40)
            case .b3: Child(name: "배너4", show: bannerShown[3], h: 40)
            case .b4: Child(name: "배너5", show: bannerShown[4], h: 40)
            case .metaType: Child(name: "성역+분류", show: true, h: 120)
            case .question: Child(name: "재확인 질문", show: true, h: 50)
            case .time: Child(name: "시간 설정", show: true, h: 60)
            case .recurrence: Child(name: "반복 설정", show: true, h: 60)
            case .history: Child(name: "수정 이력", show: true, h: 30)
            case .decide: Child(name: "[삭제하기]·[기억하기]", show: true, h: 44)
            }
        }
    }
}
