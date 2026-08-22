import SwiftUI

//
//  MoveProbe2 — **확정될 때 화면 전체가 어떻게 재배치되나** (2026-08-23 신설)
//
//  ⚠️⚠️ **앱 코드가 아니다.** 랩이다.
//
//  ── 왜 (사용자 2026-08-23) ─────────────────────────────────────
//  *"이미 있던 것(자료 카드)만 미끄러지고, 새로 생기는 것(배너 다섯·시간 설정·반복 설정·수정 이력)은
//    나타난다. 없던 것이 나타나는 것은 자연스럽다. ★ 이것이 코드로 갈리나 조사해줘."*
//  *"랩 mock이 블록 하나였으니 여덟을 실제로 그려야 비교가 된다."*
//
//  ── ★ 그리면서 갈린 것 (설계 §3-H) ────────────────────────────
//  **새로 생기는 것의 「자리」가 둘로 갈린다:**
//    · **배너 다섯 = 성역 위** → 나타나면 **자료 카드를 아래로 민다**
//    · **시간 설정·반복 설정·수정 이력 = 카드 아래** → 나타나도 **카드 자리에 영향이 없다**
//  그래서 세 꼴을 나란히 둔다:
//    ① 전형(배너 0) · 한 단계     ② 최악(배너 둘) · 한 단계     ③ 최악(배너 둘) · 두 단계
//

private let nBg      = Color(red: 0x13/255, green: 0x12/255, blue: 0x18/255)
private let nSurface = Color(red: 0x1D/255, green: 0x1B/255, blue: 0x25/255)
private let nBorder  = Color(red: 0x32/255, green: 0x2E/255, blue: 0x3D/255)
private let nText    = Color(red: 0xEC/255, green: 0xEB/255, blue: 0xF1/255)
private let nText2   = Color(red: 0xA7/255, green: 0xA4/255, blue: 0xB3/255)
private let nAccent  = Color(red: 0x8B/255, green: 0x87/255, blue: 0xF5/255)
private let nAmber   = Color(red: 0xFB/255, green: 0xBF/255, blue: 0x24/255)

private struct Blk: View {
    let t: String
    var h: CGFloat = 20
    var tint: Color = nSurface
    var body: some View {
        Text(t).font(.system(size: 8)).foregroundStyle(nText2)
            .frame(maxWidth: .infinity, minHeight: h, alignment: .leading)
            .padding(.horizontal, 4)
            .background(tint, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(nBorder))
    }
}

/// 보조 자료 카드 대역 — 왼쪽 초록 띠가 픽셀 표식이다.
private struct MediaBlk: View {
    var body: some View {
        HStack(spacing: 4) {
            Rectangle().fill(Color.green).frame(width: 8, height: 16)
            Text("보조 자료").font(.system(size: 8, weight: .semibold)).foregroundStyle(nText)
            Spacer(minLength: 0)
        }
        .padding(4)
        .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
        .background(nSurface, in: RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(nBorder))
    }
}

struct MoveProbe2: View {
    /// 순서·`decideRow` — **있던 것의 이동**을 만든다.
    @State private var remembered = false
    /// 새로 생기는 것 — 꼴 ③에서만 따로 늦춘다.
    @State private var extras = false
    private let slide = Animation.easeInOut(duration: 1.2)      // ⚠️ 재려고 늘린 값
    private let fade  = Animation.easeIn(duration: 0.5)
    private let tick = Timer.publish(every: 4.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text((remembered ? "확정" : "미확정") + " · 새것 \(extras ? "있음" : "없음")")
                .font(.system(size: 11, weight: .bold)).foregroundStyle(nAccent)
            HStack(alignment: .top, spacing: 6) {
                col("① 전형(배너 0)\n한 단계", body: column(banners: 0, twoPhase: false))
                col("② 최악(배너 둘)\n한 단계", body: column(banners: 2, twoPhase: false))
                col("③ 최악(배너 둘)\n두 단계", body: column(banners: 2, twoPhase: true))
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(nBg)
        .onReceive(tick) { _ in
            if !remembered {
                withAnimation(slide) { remembered = true }
                // 두 단계 — **미끄러짐이 끝난 뒤** 새것이 나타난다.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation(fade) { extras = true }
                }
            } else {
                withAnimation(fade) { extras = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(slide) { remembered = false }
                }
            }
        }
    }

    private func col(_ name: String, body: some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name).font(.system(size: 9, weight: .bold)).foregroundStyle(nText)
                .fixedSize(horizontal: false, vertical: true)
            body
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    /// 한 꼴 — **순서 배열(B 방법)로 그린다**(§3-G-4에서 이것이 답으로 갈렸다).
    private enum Sec: String, Identifiable {
        case raw, b1, b2, meta, decide, media, time, recur, hist
        var id: String { rawValue }
    }

    private func order(banners: Int, showExtras: Bool) -> [Sec] {
        var a: [Sec] = [.raw]
        if remembered && showExtras {
            if banners >= 1 { a.append(.b1) }
            if banners >= 2 { a.append(.b2) }
        }
        a.append(.meta)
        if !remembered { a.append(.decide) }
        a.append(.media)
        if remembered && showExtras { a += [.time, .recur, .hist] }
        return a
    }

    @ViewBuilder private func column(banners: Int, twoPhase: Bool) -> some View {
        let showExtras = twoPhase ? extras : remembered
        VStack(spacing: 4) {
            ForEach(order(banners: banners, showExtras: showExtras)) { s in
                switch s {
                case .raw:    Blk(t: "원문", h: 24)
                case .b1:     Blk(t: "배너1", h: 18, tint: nAmber.opacity(0.18))
                case .b2:     Blk(t: "배너2", h: 18, tint: nAmber.opacity(0.18))
                case .meta:   Blk(t: "성역+분류", h: 28)
                case .decide: Blk(t: "[기억하기]", h: 20, tint: nAccent.opacity(0.25))
                case .media:  MediaBlk()
                case .time:   Blk(t: "시간 설정", h: 18)
                case .recur:  Blk(t: "반복 설정", h: 18)
                case .hist:   Blk(t: "수정 이력", h: 16)
                }
            }
        }
    }
}
