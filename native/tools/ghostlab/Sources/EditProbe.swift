import SwiftUI
import UIKit

//  ── 원문 편집 칸 — **가로로 안 늘어나나** (2026-08-21 신설)
//
//  ⛔ 계기: 실기기에서 사용자가 잡았다 — *"문장이 길 경우 입력창이 가로로 너무 크게 확대되어서
//  물리적으로 한 화면에 글자가 안 보이는 현상"*. 상세 화면 전체가 좌우로 밀렸다.
//  원인: `isScrollEnabled = false`인 `UITextView`의 **본디 크기가 「한 줄로 쭉 늘어난 폭」**이고,
//  `sizeThatFits`를 안 줘서 SwiftUI가 그 폭을 그대로 받았다.
//
//  여기서 보는 것: **긴 원문을 넣어도 칸이 화면 안에 머무나 · 줄이 접히나 · 좌우 맞춤이 걸리나.**
//  ⚠️ 상세 화면은 눌러야 열려서 헤드리스로 못 본다 — 그래서 같은 뷰를 랩에 세운다(앱 코드 그대로).

private let textPrimary = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let textSecond = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let bgc = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let surface = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let pBorder = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)
private let pTint = Color(red: 0x22/255, green: 0xD3/255, blue: 0xEE/255)

struct EditProbe: View {
    // 실데이터에서 가져온 긴 원문(사용자 스샷에 나온 그 원칙).
    @State private var text = "대화를 시작할 때마다 이 대화에서의 여러 가지 공격은 나를 향한 공격이 아니라 사실을 인지하고 시작하자 그리고 또 한 줄 더 붙여서 여러 줄이 되게 한다"
    @State private var focused = false
    @State private var punct = "할 수 있는 것에 맞춰 요구를 줄이지 않는다. 못 하면 못 한다고 말한다. 그리고 또 한 줄 더 붙인다."
    @State private var focused2 = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("원문 편집 칸 — 가로로 안 늘어나나 · 좌우 맞춤이 걸리나")
                    .font(.caption2).foregroundStyle(pTint)
                Text("포커스: \(focused ? "예" : "아니오")").font(.caption2).foregroundStyle(textSecond)

                // 상세 화면과 같은 껍데기(여백 8 · 테두리 · 바탕)
                JustifiedTextEditor(text: $text, isFocused: $focused,
                                    style: .body, color: textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(bgc, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(pBorder))
                    .padding(14)
                    .background(surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("↑ 이 칸이 화면 밖으로 나가면 회귀다").font(.caption2).foregroundStyle(textSecond)

                // ★ 둘째 칸 — **부호가 든 표본.** 「줄바꿈 거부 훅」이 실제로 불리는지 보는 자리다.
                //   ① 부호가 줄 앞에 오면 훅이 안 불린 것이고, 한글이 줄 앞에 오면 불린 것이다.
                // ★★ **결정 실험** — 같은 글·같은 폭(298)·같은 크기(.body)로 둘을 나란히.
                //   위 = 편집칸(TextKit + 거부 훅) · 아래 = 그리는 쪽(우리가 줄을 나눈다).
                //   **줄이 같으면 훅이 듣는 것이고, 다르면 그 자리가 훅이 못 미치는 곳이다.**
                Text("결정 실험 — 위: 편집칸(훅) · 아래: 그리는 쪽(우리 엔진) · 같은 글·폭 298·.body")
                    .font(.caption2).foregroundStyle(pTint).padding(.top, 10)
                JustifiedTextEditor(text: $punct, isFocused: $focused2,
                                    style: .body, color: textPrimary)
                    .frame(width: 298)
                    .overlay(alignment: .trailing) { Rectangle().fill(pTint.opacity(0.35)).frame(width: 1) }
                Text("— — —").font(.caption2).foregroundStyle(textSecond)
                JustifiedText(text: punct, style: .body, delta: 0,
                              weight: .regular, color: textPrimary)
                    .frame(width: 298)
                    .overlay(alignment: .trailing) { Rectangle().fill(pTint.opacity(0.35)).frame(width: 1) }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgc.ignoresSafeArea())
    }
}
