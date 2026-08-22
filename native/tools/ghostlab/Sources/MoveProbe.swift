import SwiftUI

//
//  MoveProbe — **「기억하기」를 누를 때 보조 자료 카드가 어떻게 이동하나** (2026-08-23 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** 랩이다.
//
//  ── 왜 (사용자 2026-08-23) ─────────────────────────────────────
//  *"「기억하기」를 누르면 카드가 점프하지 말고 위로 부드럽게 미끄러지듯 이동해야 한다.
//    순간 이동으로 보이면 「뭐가 잘못됐나」로 읽힌다. 움직임이 보여야 어디서 어디로 갔는지 알 수 있다."*
//
//  ── 무엇이 문제인가 ─────────────────────────────────────────────
//  미확정에서는 카드가 **본문 맨 끝**(결정 줄 아래), 확정되면 **성역 바로 아래**다(설계 §3-F-2).
//  **자리가 다르므로 SwiftUI에서 「같은 뷰가 옮겨진 것」으로 안 보일 수 있다** —
//  그러면 **사라졌다 나타난다**(=점프). 세 방법을 같은 타이머로 동시에 돌려 비교한다:
//
//    A 두 자리   — `if remembered { 카드 } … else { 카드 }` (가장 자연스러운 구현)
//    B 순서 배열 — 한 카드를 **배열 순서**로 옮긴다(`ForEach` + 고정 id)
//    C matched   — 두 자리 + `matchedGeometryEffect`
//
//  ⛔ **탭 없이 재려고 타이머로 스스로 토글한다** — 스크린샷 여러 장을 몰아 찍으면
//     **중간 자리가 파일로 남는다**(잔상 계측에서 쓴 그 수법).
//

private let mBg      = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let mSurface = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let mBorder  = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)
private let mText    = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let mText2   = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let mAccent  = Color(red: 0x8B/255, green: 0x87/255, blue: 0xF5/255)

/// 보조 자료 카드 대역 — **왼쪽에 초록 띠**를 둔다. 픽셀로 y를 쫓기 위한 표식이다.
private struct MediaMock: View {
    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Color.green).frame(width: 10, height: 30)   // ← 계측 표식
            Text("보조 자료").font(.system(size: 11, weight: .semibold)).foregroundStyle(mText)
            Spacer()
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(mSurface, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mBorder))
    }
}

private struct Block: View {
    let title: String
    let h: CGFloat
    var tint: Color = mSurface
    var body: some View {
        Text(title).font(.system(size: 10)).foregroundStyle(mText2)
            .frame(maxWidth: .infinity, minHeight: h, alignment: .leading)
            .padding(.horizontal, 8)
            .background(tint, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(mBorder))
    }
}

struct MoveProbe: View {
    @State private var remembered = false
    @State private var ticks = 0
    @Namespace private var ns
    /// ⚠️ 값을 바꿔 보려면 여기 — 사용자에게 후보를 보이려고 **세 변형을 한 타이머로** 돌린다.
    /// ⚠️ **재려고 일부러 느리게 뒀다** — 스크린샷 한 장이 ~1초라 0.35초짜리는 중간이 안 잡힌다.
    /// **사용자에게 보일 후보 값은 이것이 아니다**(후보는 설계 문서 §3-G).
    private let dur: Double = 2.0
    private let tick = Timer.publish(every: 3.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text((remembered ? "상태: 확정(기억함)" : "상태: 미확정(임시)") + "  ·  tick \(ticks)")
                .font(.system(size: 12, weight: .bold)).foregroundStyle(mAccent)
            HStack(spacing: 8) {
                col("A 두 자리", variantA)
                col("B 순서", variantB)
                col("C matched", variantC)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(mBg)
        .onReceive(tick) { _ in
            ticks += 1
            withAnimation(.easeInOut(duration: dur)) { remembered.toggle() }
        }
    }

    private func col(_ name: String, _ content: some View) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(.system(size: 10, weight: .bold)).foregroundStyle(mText)
            content
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // A — 두 자리. **가장 자연스러운 구현이고, 여기서 점프가 나는지 본다.**
    private var variantA: some View {
        VStack(spacing: 6) {
            Block(title: "원문", h: 30)
            Block(title: "성역+분류", h: 40)
            if remembered {
                MediaMock()
                Block(title: "시간·반복", h: 34)
            } else {
                Block(title: "[기억하기]", h: 26, tint: mAccent.opacity(0.25))
                MediaMock()
            }
        }
    }

    // B — 한 카드를 **배열 순서**로 옮긴다. id가 고정이라 SwiftUI가 「같은 것」으로 본다.
    private enum Sec: String, Identifiable { case raw, meta, decide, media, time
        var id: String { rawValue } }
    private var orderB: [Sec] { remembered ? [.raw, .meta, .media, .time] : [.raw, .meta, .decide, .media] }
    private var variantB: some View {
        VStack(spacing: 6) {
            ForEach(orderB) { s in
                switch s {
                case .raw:    Block(title: "원문", h: 30)
                case .meta:   Block(title: "성역+분류", h: 40)
                case .decide: Block(title: "[기억하기]", h: 26, tint: mAccent.opacity(0.25))
                case .media:  MediaMock()
                case .time:   Block(title: "시간·반복", h: 34)
                }
            }
        }
    }

    // C — 두 자리 + matchedGeometryEffect(같은 id).
    private var variantC: some View {
        VStack(spacing: 6) {
            Block(title: "원문", h: 30)
            Block(title: "성역+분류", h: 40)
            if remembered {
                MediaMock().matchedGeometryEffect(id: "media", in: ns)
                Block(title: "시간·반복", h: 34)
            } else {
                Block(title: "[기억하기]", h: 26, tint: mAccent.opacity(0.25))
                MediaMock().matchedGeometryEffect(id: "media", in: ns)
            }
        }
    }
}
