import SwiftUI
import UIKit

//  ── 줄바꿈 원칙 셋을 **앱 코드 그대로** 확인한다 (2026-08-21 신설)
//
//  ⚠️⚠️ **이 꼴만 예외적으로 앱 파일을 함께 컴파일한다** — `project.yml`이
//  `../../Sources/App/JustifiedText.swift`를 랩 타깃에 넣는다.
//  **랩 규칙(⛔ 앱에서 랩을 참조 금지)의 반대 방향이라 괜찮다** — 랩이 앱을 보는 것이고,
//  그래야 **내가 재는 것이 앱이 그리는 것과 같다**(베끼면 갈린다).
//
//  보는 것 셋:
//    ① 부호가 줄 앞에 오나 — 한글 앞 부호는 함께 내려와야 하고, **비한글 앞 부호는 허용**이다.
//    ② 줄 앞에 빈칸이 있나 — 첫 줄 말고는 **없어야 한다.**
//    ③ 영어·숫자가 단어 안에서 잘리나 — **잘리면 안 된다**(폭보다 긴 한 덩어리만 예외).

private let textPrimary = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let textSecond = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let bgc = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let pTint = Color(red: 0x22/255, green: 0xD3/255, blue: 0xEE/255)

/// 원칙마다 걸리게 만든 표본. 앞의 둘은 실데이터, 나머지는 일부러 만든 것.
private let ruleSamples: [(String, String)] = [
    ("① 부호 — 한글 앞",
     "할 수 있는 것에 맞춰 요구를 줄이지 않는다. 못 하면 못 한다고 말한다. 그리고 또 한 줄 더 붙인다."),
    ("① 부호 — 여러 개",
     "먼저 사람을 본다 — 문제보다 사람이 앞이다. 급할수록 그렇다. 쉼표, 마침표. 물음표? 느낌표!"),
    ("② 빈칸 — 줄 앞에 오나",
     "아침에 일어날 때 존재하지 않던 없던 급한 일정이 머릿속에 있도록 와 일어나는 나를 괴롭히고 서두르게 만든다 그런데 그 일정은 존재하지 않는 일정이다 이게 뭐지 몇 번 그러는 그러는데"),
    ("③ 영어·숫자 — 안 잘려야 한다",
     "2026-08-21에 GhostLab으로 justification을 measurement 했고 SecondBrain 앱에 넣었다 iPhone 16 Pro"),
    ("③ 아주 긴 덩어리 (예외)",
     "링크는 https://github.com/eswi/SecondBrain/blob/main/native/Sources/App/JustifiedText.swift 이다"),
]

struct RulesProbe: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("줄바꿈 원칙 셋 · 앱 코드(JustifiedText) 그대로 · 폭 298pt")
                    .font(.caption2).foregroundStyle(pTint)
                ForEach(Array(ruleSamples.enumerated()), id: \.offset) { _, s in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(s.0).font(.caption.weight(.semibold)).foregroundStyle(textSecond)
                        // 앱이 원칙 목록에서 쓰는 그 값 — `.callout + 2` · medium.
                        JustifiedText(text: s.1, style: .callout, delta: 2,
                                      weight: .medium, color: textPrimary)
                            .frame(width: 298)
                            .overlay(alignment: .trailing) {
                                Rectangle().fill(pTint.opacity(0.35)).frame(width: 1)
                            }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgc.ignoresSafeArea())
    }
}
