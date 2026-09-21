import SwiftUI

/// **「새로운 기억」 우측 가장자리 버튼** (2026-09-18 사용자 지시 · 정본 = `docs/native/edge-handle-design.md`).
///
/// ## 2026-09-21 사용자 지시로 바뀐 것 (설계 §5 · 말 그대로 있다)
/// - **펼침 꼴(`#` + `»`)을 없앴다** — *"눌렀을 때 나타나는 버튼은 새로 디자인할 것이니 일단 없애자."*
///   그래서 **좌우로 끌어 접고 펼치는 것도 없다**(접힐 것이 없다). 지금은 **가장자리에 물린 손잡이 하나**다.
/// - **눌러서 위아래로만 옮긴다** — *"이동 방향은 위/아래로만 … 최상단 제목 영역으로 침범하지 않도록 그리고 최하단 탭바를
///   침범하지 않도록."* → 이 뷰는 **얹힌 영역의 높이 안에서만** 움직인다. 그 영역 = `InboxView`의 `content`(머리줄 아래 · 탭바 위).
/// - ✅ **모양·크기·색 = 사용자 스크린샷(09-21 17:0x · 홈 화면 오른쪽 가장자리의 손잡이)을 픽셀로 재서 맞췄다**
///   (사용자 17:1x: *"내가 준 스크린샷의 모양 그대로 할 수 없을까? 우선은 바탕색을 같게 해주고, 그 안의 < 모양 도형도 똑같이 맞춰줘."*).
///   잰 값(`images/2.png` 920×2000 · 0.437pt/px · 근거 = 설계 §5-1):
///   | 무엇 | 값 |
///   |---|---|
///   | 보이는 폭 × 높이 | **24 × 96** pt |
///   | 왼쪽 모서리 반지름 | **14** pt **원호**(`.circular`) — 참고의 모서리 프로파일이 반지름 14 원과 맞았다(dy 0.9pt→dx 9.1 · 1.75→7.2 · 4.4→3.8 · 셋 다 ±0.3pt). `.continuous` 15로 그리면 곡선이 22pt까지 퍼져 다르게 보였다(17:2x 실측) |
///   | 바탕 | 세로 그라데이션 **위 `#393E3F` → 가운데 `#313635` → 아래 `#444F55`** · 테두리·그림자 없음 |
///   | 화살표 `<` | 상자 **10 × 27.5** pt · 획 **5.5** pt 둥근 끝(참고의 수평 단면 5.7 · 5로 그리니 5.3이라 올렸다) · 색 **`#BDC1C7`** · 좌우 여백 7·7(정확히 가운데) |
///   ⚠️ 첫 시도(17:07 빌드)는 SF 심볼 `chevron.left` 22pt에 팔레트 색이었다 — 사용자가 「그대로」를 원해 **직접 그린다**(`ChevronMark`).
/// - ✅ **비치는 재질 + 튕겨서 보내기**(09-21 17:3x 사용자 물음 둘 → *"ㅇㅇ 폰에 올려줘. 비율 들은 네가 알아서 해."*):
///   ① 바탕 = **`.regularMaterial`(어두운 판) 위에 잰 회색 그라데이션을 `tintOpacity`만큼 덮는다** — 재질만 쓰면 이 앱 바탕(`#131218`)을 따라
///      너무 어두워져 스크린샷의 회색이 안 나오고, 덮기만 하면 비치지 않는다. **0.7은 Claude가 골랐다**(사용자가 맡김 · 0.6은 참고보다 어두웠다 · 폰에서 다듬는다).
///      비치는 것 = 목록을 스크롤할 때 카드 테두리·글자가 손잡이 안에서 흐리게 지나간다.
///   ② 놓는 순간의 속도로 **예상 도착점**까지 미끄러진다 — 경계(제목 아래·탭바 위)에서 멈춘다.
///      손가락이 놓인 자리에 먼저 (애니메이션 없이) 놓고 그다음 목표로 보낸다 — `@GestureState`가 0으로 돌아가며 튀는 것을 막는다.
///      ⛔ **첫 판(17:39 `5d0f1ac`)은 `predictedEndTranslation` + 고정 0.55초 스프링이었다** — 사용자(17:5x): *"너무 민감하게 튕겨나가고
///      세게 튕겨나가고 미끄러지는 느낌이 없어."* 원인 둘: ⓐ 그 예측은 스크롤 뷰의 「보통」 감속률 **0.998**(속도 × 499)이라
///      어떤 튕김도 거의 끝까지 갔다 ⓑ 시간이 거리·속도와 무관한 고정값이라 감속 곡선이 아니었다.
///      ✅ 지금은 **손가락 속도(`velocity`)를 직접 읽어 지수 감속 모델로 거리와 시간을 함께 계산한다**(`glide(from:velocity:maxTop:)` 주석).
/// - 위치는 **기기에 남는다**(`@AppStorage` · 음수 = 아직 안 옮김 → 세로 가운데).
///
/// ## 옛 꼴 (지우지 않는다 · 09-18 `823beae`)
/// `#`+`»` 반알약 → 오른쪽으로 끌면 곡선 부분만 남고 `«` → 누르거나 왼쪽으로 끌면 펼침. **동작했고 사용자가 거둔 것**이다 —
/// 「안 됐다」가 아니라 **「새로 디자인한다」**(기록 규칙 9의 셋째 갈래 ②). ⛔ **되살리지 말 것.**
///
/// ## 색 (Claude가 골랐다 — 09-18 사용자가 맡겼다)
/// 카드 바탕(`surface2`) + hairline(`border`) · 화살표 `textSecondary`.
struct EdgeHandle: View {
    /// 얹힌 영역의 **위에서부터의 거리**(pt). **음수 = 아직 안 옮김** → 세로 가운데에 둔다.
    @Binding var topOffset: Double

    /// 스크린샷에서 **잰** 치수(머리주석 표). 옛 값: 09-18 접힌 꼴 높이 52 · 반지름 26 · 폭 30 → 09-21 17:07 92·14·24(추정).
    private let height: CGFloat = 96
    private let radius: CGFloat = 14
    private let width: CGFloat = 24
    /// 화살표 획 두께 — `ChevronMark`와 같은 값을 써야 상자가 꼭 10 × 27.5가 된다.
    private let chevronStroke: CGFloat = 5.5
    /// 재질 위에 덮는 회색의 비율(0 = 재질만 · 1 = 09-21 17:17의 불투명 회색). **Claude가 고른 값** — 폰에서 다듬는다.
    private let tintOpacity: Double = 0.7   // 0.6으로 재니 밝기 50~57(참고 60~76)이라 0.7로 올렸다(17:4x 시뮬 실측)
    // MARK: 튕기기 — 지수 감속 모델 (UIScrollView와 같은 꼴 · 값만 다르다)
    //
    // 속도 v(pt/ms)가 1ms마다 r배로 줄면 **가는 거리 = v · r/(1−r)** · **멈추는 시간 = ln(stop/v)/ln(r)** ms.
    // | r | 배율 r/(1−r) | 1500pt/s 튕김이 가는 거리 |
    // |---|---|---|
    // | 0.998 (스크롤 「보통」 · 17:39 판) | 499 | **749pt** — 화면 끝까지(사용자: 세게 튕겨나간다) |
    // | 0.995 (지금) | 199 | 299pt |
    // | 0.99 (스크롤 「빠름」) | 99 | 149pt |
    // 시간은 같은 모델에서 나오므로 **빠르게 튕기면 멀리·오래**, 살짝 튕기면 **짧게·금방** 멈춘다 — 이것이 「미끄러지는」 감이다.
    // ⚠️ 셋 다 **Claude가 고른 값**이다 — 유튜브의 실제 곡선은 못 잼(사용자가 동영상을 주면 프레임을 뽑아 잰다).
    private let decelerationRate: CGFloat = 0.995
    /// 이 속도(pt/ms) 아래로 떨어지면 멈춘 것으로 본다 — 시간 계산의 끝점.
    private let stopSpeed: CGFloat = 0.02
    /// 이보다 느리게 놓으면 튕긴 것이 아니다 — 그 자리에 둔다(150pt/s · 사용자: 너무 민감하다).
    private let flickThreshold: CGFloat = 150

    /// 놓은 자리 `from`에서 속도 `vy`(pt/s)로 튕겼을 때의 **도착점과 걸리는 시간**. 경계에 잘리면 시간도 그만큼 줄인다(벽에 닿는 순간 멈춘다).
    private func glide(from: CGFloat, velocity vy: CGFloat, maxTop: CGFloat) -> (target: CGFloat, duration: Double)? {
        guard abs(vy) >= flickThreshold else { return nil }
        let v = vy / 1000                                   // pt/ms
        let r = decelerationRate, lnr = log(r)
        let full = v * r / (1 - r)                          // 부호 있는 거리
        let target = min(max(from + full, 0), maxTop)
        let actual = target - from
        guard abs(actual) > 0.5 else { return nil }
        let tFull = log(stopSpeed / abs(v)) / lnr           // ms · 다 갈 때
        // 경계에 잘렸으면: s(t) = full·(1 − r^t) 에서 s = actual 인 t
        let frac = min(abs(actual) / abs(full), 1)
        let t = frac < 1 ? log(1 - frac * (1 - pow(r, tFull))) / lnr : tFull
        return (target, max(0.12, min(t / 1000, 1.6)))
    }
    /// 지수 감속의 꼴을 닮은 곡선 — 처음 기울기가 크고(놓는 순간 속도가 이어진다) 끝은 0으로 스며든다.
    private func glideCurve(_ duration: Double) -> Animation { .timingCurve(0.1, 0.45, 0.3, 1.0, duration: duration) }

    @GestureState private var dragY: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let maxTop = max(0, geo.size.height - height)
            let base: CGFloat = topOffset < 0 ? maxTop / 2 : CGFloat(topOffset)
            let top = min(max(base + dragY, 0), maxTop)   // 제목 아래 ~ 탭바 위 — 영역 밖으로 못 나간다
            shape
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .offset(y: top)
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .updating($dragY) { v, st, _ in st = v.translation.height }   // 세로만 읽는다
                        .onEnded { v in
                            // 먼저 손가락이 놓인 자리에(애니메이션 없이) — `dragY`가 0으로 돌아가는 프레임과 맞물려 튀지 않게.
                            let lifted = min(max(base + v.translation.height, 0), maxTop)
                            var still = Transaction(); still.disablesAnimations = true
                            withTransaction(still) { topOffset = Double(lifted) }
                            // 그다음 놓는 순간의 속도만큼 미끄러진다(경계 안 · 거리와 시간을 같은 모델에서).
                            if let g = glide(from: lifted, velocity: v.velocity.height, maxTop: maxTop) {
                                withAnimation(glideCurve(g.duration)) { topOffset = Double(g.target) }
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
    }

    private var shape: some View {
        ZStack {
            let r = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: 0, topTrailingRadius: 0, style: .circular)
            // 바탕 = 비치는 재질(어두운 판) + 스크린샷에서 잰 회색 그라데이션을 `tintOpacity`만큼 덮는다. 테두리·그림자 없음(스크린샷에 없다).
            // *(09-21 17:17 빌드는 그라데이션만 불투명으로 — 잰 색은 그대로고 덮는 비율만 더해졌다.)*
            r.fill(.regularMaterial)
                .environment(\.colorScheme, .dark)   // 재질의 어두운 판을 고정한다(이 앱은 늘 어둡다)
                .overlay(
                    r.fill(LinearGradient(stops: [
                        .init(color: Color(hex: 0x393E3F), location: 0),
                        .init(color: Color(hex: 0x313635), location: 0.5),
                        .init(color: Color(hex: 0x444F55), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .opacity(tintOpacity)
                )
            ChevronMark(stroke: chevronStroke)
                .stroke(Color(hex: 0xBDC1C7), style: StrokeStyle(lineWidth: chevronStroke, lineCap: .round, lineJoin: .round))
                .frame(width: 10, height: 27.5)   // 획 포함 상자 — 스크린샷에서 잰 값
        }
    }
}

/// 스크린샷의 `<` — 상자(획 포함) 안에 **획 절반만큼 안으로 들여** 그린 꺾은선. 같은 `stroke`로 치면 상자가 꼭 프레임 크기가 된다.
private struct ChevronMark: Shape {
    var stroke: CGFloat
    func path(in rect: CGRect) -> Path {
        let t = stroke / 2   // 획 절반
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.midY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.maxY - t))
        return p
    }
}
