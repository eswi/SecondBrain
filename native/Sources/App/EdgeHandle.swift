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
///      둘째 판(`2b53a7a`) 지수 감속 → 셋째 판(`1b0fa24`) 동영상 실측 스프링 → **애니메이션이 안 걸리던 배선을 고친 뒤(`a83e86f`)**
///      **사용자가 속도 곡선을 직접 정했다**(19:0x · `glideProfile` 위 표) — 스프링은 걷었다.
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
    /// A/B 스위치(§5-10) — false = 불투명(지금) · true = 재질 + 덮기(17:39~19:3x 빌드).
    private let useMaterial = false
    private var tintGradient: LinearGradient {
        LinearGradient(stops: [
            .init(color: Color(hex: 0x393E3F), location: 0),
            .init(color: Color(hex: 0x313635), location: 0.5),
            .init(color: Color(hex: 0x444F55), location: 1),
        ], startPoint: .top, endPoint: .bottom)
    }
    private let tintOpacity: Double = 0.7   // 0.6으로 재니 밝기 50~57(참고 60~76)이라 0.7로 올렸다(17:4x 시뮬 실측)
    // MARK: 튕기기 — 유튜브 손잡이 **동영상을 재서** 맞췄다 (2026-09-21 18:2x · 설계 §5-4)
    //
    // 사용자의 화면 녹화(60fps · 세게 한 번 · 약하게 한 번)에서 손잡이 중심 y를 프레임마다 읽어 놓은 뒤 구간을 두 모델에 맞췄다:
    // | 튕김 | 놓는 속도 | 간 거리 | 거리/속도 | 멈추기까지 | 지수 감속 RMS | **임계감쇠 스프링 RMS** |
    // |---|---|---|---|---|---|---|
    // | 세게(아래로) | 2229 pt/s | 300 pt | **0.135 s** | **342 ms** | 13.6 pt | **8.8 pt** (ω 13.75) |
    // | 약하게(위로) | 1337 pt/s | 200 pt | **0.150 s** | **358 ms** | 9.5 pt | **5.6 pt** (ω 13.50) |
    // ★ **세기와 무관하게 ~350ms에 멈춘다** = 스프링의 특징(지수 감속이면 빠른 쪽이 더 오래 간다) · 프레임마다 속도 비율이
    //   0.97 → 0.8로 **점점 작아진다** = 스프링(지수 감속이면 일정). 그래서 **도착점 = 놓은 자리 + 속도 × 0.14s** ·
    //   **애니메이션 = 초기 속도를 이어받는 임계감쇠 스프링(ω ≈ 13.6/s)**. 정규화 초기속도 = v/d = 1/0.14 ≈ 7.1/s(항상 같다).
    // ⛔ 앞 판(`2b53a7a` · 지수 감속 r=0.995 · 거리 = v×0.199s)은 **거리가 1.4배 멀고 빠른 튕김이 더 오래 갔다** — 잰 뒤에 갈렸다(계측 규칙 4).
    // MARK: 튕기기 — 사용자가 정한 속도 곡선 (2026-09-21 19:0x · 설계 §5-8)
    //
    // 사용자: *"과정이 보인다. 이제 버튼이 이동하는 속도를 30% 정도 올려주고, 이동거리 50% 지금까지는 그대로 유지 후 50% 이후 부터
    //   남은 거리가 5% 줄어들 때 마다 속도를 5%씩 줄여줘. 그래서 도착할 때 속도가 0이 되도록."*
    // → 스프링(§5-4~5-7)을 걷고 **직접 정의한 프로파일**(거리-시각 표 · `StepGlide`)로 간다. 표의 꼴은 사용자가 정한다(아래 · 설계 §5-8·§5-9).
    //   | 숫자 | 뜻 | 지금 |
    //   |---|---|---|
    //   | `projection` | 얼마나 멀리 — 도착점 = 놓은 자리 + 속도 × 이 값(초). 튕기는 순간 정해진다 | 0.14 |
    //   | `baseDuration` | 기준 시간 — 「지금 속도」의 기준(§5-6의 0.8초) | 0.80 |
    //   | `speedBoost` | 앞 절반의 일정 속도 = 거리/기준시간 × 이 값 | **1.3**(30% 올림) |
    //   | `fastFraction` | 빠른 속도로 가는 거리 비율(19:2x 사용자) | 0.9 |
    //   | `tailSpeedRatio` | 남은 거리의 속도(빠른 속도 대비) | 0.5 |
    //   *(19:0x~19:1x의 계단식 — 앞 절반 일정 · 5%마다 10%씩 감속 · 도착 0 — 은 19:2x에 사용자가 걷었다: "위치에 따라 속도를 조절하지 말고".
    //   전말은 설계 §5-8 · `aadf8b5`·`a8edc6b`. 되살리려면 그 커밋의 `glideProfile`.)*
    private let projection: CGFloat = 0.14
    private let baseDuration: Double = 0.80
    private let speedBoost: Double = 3.9   // 1.3 → 2.6(19:1x 2배) → 3.9(19:3x 사용자: "지금보다 50% 더 빠르게") · 전체 ≈0.23초
    /// **빠른 속도로 가는 거리 비율** — 그 뒤 남은 거리는 `tailSpeedRatio` 속도로(2026-09-21 19:2x 사용자: *"위치에 따라 속도를 조절하지 말고,
    /// 그냥 전체 거리의 90%는 빠르게 가고, 마지막 10% 남은 거리는 2분의 1 속도로"*). 계단 셋(`cruiseFraction`·`stepFraction`·`decrementPerStep`)은 걷었다.
    private let fastFraction: Double = 0.9
    private let tailSpeedRatio: Double = 0.5
    /// 이보다 느리게 놓으면 튕긴 것이 아니다 — 그 자리(60pt/s × 0.14 = 8pt 미만은 움직이지 않는 편이 낫다).
    private let flickThreshold: CGFloat = 60

    // MARK: 튕기기 곡선 — **유튜브(시스템 PiP 탭) 화면 녹화의 프레임별 이동량과 맞췄다** (2026-09-21 19:1x · 설계 §5-12)
    //
    // 두 앱을 한 녹화에 담아 `track-edge-handle.swift`로 프레임(16.7ms)마다 위치를 읽었다:
    //   유튜브(놓은 뒤): 48 47 44 41 37 34 30 26 23 20 17 14 12 10 8 7 5 4 3 2 1 … pt/프레임 — **정지 프레임 0 · 매 프레임 조금씩 줄어 0으로**
    //   우리(`3c550d5`):  32 43 25 **0 0** 38 25 25 25 25 25 25 25 25 25 20 13 12 — **놓는 순간 두 프레임 정지 → 점프 → 일정 → 급정지**
    // ★ 「드드득」 = ① 놓는 순간의 정지+점프(배선: 다음 턴으로 미룬 애니메이션 + `@AppStorage` 쓰기가 목록 전체를 재평가) ② 속도의 급변 셋(출발·90%·도착).
    // ★ 유튜브 곡선 = **임계감쇠 스프링 ω 13.6/s · 초기속도 = 손가락 속도 · 도착점 = 놓은 자리 + 속도 × 0.14~0.15s** — RMS **1.1pt/프레임**(§5-4의 실측과 같다).
    //   ⚠️ 그 스프링(`1b0fa24`)이 「느낌이 다르다」고 판정된 것은 **애니메이션이 아예 안 걸리던 배선(§5-7) 아래**였다 — 값이 아니라 배선이 틀렸던 것.
    // `glideStyle`로 두 구간 꼴(§5-9 · 사용자가 정한 것)로 돌릴 수 있다.
    private enum GlideStyle { case spring, twoStep }
    private let glideStyle: GlideStyle = .spring
    private let springOmega: Double = 13.6        // 1/s · 유튜브 실측(13.75 · 13.50 · 프레임 곡선 RMS 1.1)

    /// 놓은 자리 `from`에서 속도 `vy`(pt/s)로 튕겼을 때의 **도착점과 애니메이션**. 도착점은 튕기는 순간 정해진다(경계 안).
    private func glide(from: CGFloat, velocity vy: CGFloat, maxTop: CGFloat) -> (target: CGFloat, animation: Animation)? {
        guard abs(vy) >= flickThreshold else { return nil }
        let target = min(max(from + vy * projection, 0), maxTop)
        let d = target - from
        guard abs(d) > 0.5 else { return nil }
        switch glideStyle {
        case .twoStep:
            return (target, Animation(glideProfile))
        case .spring:
            // 거리 대비 정규화 초기속도(1/s). 경계에 잘렸으면 ω·0.95까지 — 임계감쇠는 v0 > ω일 때 목표를 넘어간다(제목·탭바 침범).
            let v0 = min(Double(vy / d), springOmega * 0.95)
            return (target, .interpolatingSpring(mass: 1, stiffness: springOmega * springOmega, damping: 2 * springOmega, initialVelocity: v0))
        }
    }

    /// 거리 비율(0~1)과 시각의 표 — **두 구간**: 앞 `fastFraction`은 빠른 속도 · 남은 거리는 `tailSpeedRatio` 속도. 거리와 무관하게 같은 꼴.
    /// 지금 값(3.9 · 0.9 · 0.5): 앞 90% 0.18s + 꼬리 10% 0.04s = **0.23s**. (2.6일 때 0.34s)
    private var glideProfile: StepGlide {
        let v0 = speedBoost / baseDuration                    // 거리 1 기준 속도(1/s)
        let tFast = fastFraction / v0
        let tTail = (1 - fastFraction) / (v0 * tailSpeedRatio)
        return StepGlide(times: [tFast, tFast + tTail], dists: [fastFraction, 1])
    }

    /// **화면에 그리는 위치**(pt · 얹힌 영역 위에서부터). 저장값 `topOffset`과 갈라 둔다(§5-7).
    /// ★ **2026-09-21 19:1x — 끌기도 이 값에 직접 쓴다**(`@GestureState dragY`를 걷었다). 그래야 놓는 순간 **쓰기가 하나**다:
    ///   옛 꼴은 「dragY 0으로 리셋 + visualTop을 놓인 자리로 + 다음 턴에 애니메이션」이라 **두 프레임 정지 뒤 점프**가 났다(녹화 실측 §5-12).
    ///   저장(`topOffset`)은 **애니메이션이 끝난 뒤** 한 번 — 튕기는 프레임에 `@AppStorage`를 쓰면 `InboxView` 본문(목록 전체)이 재평가된다.
    @State private var visualTop: CGFloat = -1   // 음수 = 아직 안 정함(저장값 또는 가운데로 채운다)
    @State private var dragBase: CGFloat? = nil  // 끌기 시작 때의 위치

    var body: some View {
        GeometryReader { geo in
            let maxTop = max(0, geo.size.height - height)
            let settled: CGFloat = visualTop >= 0 ? visualTop : (topOffset < 0 ? maxTop / 2 : CGFloat(topOffset))
            shape
                .frame(width: width, height: height)
                .contentShape(Rectangle())
                .offset(y: min(max(settled, 0), maxTop))   // 제목 아래 ~ 탭바 위 — 영역 밖으로 못 나간다
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in
                            let base = dragBase ?? settled
                            if dragBase == nil { dragBase = base }
                            var still = Transaction(); still.disablesAnimations = true
                            withTransaction(still) { visualTop = min(max(base + v.translation.height, 0), maxTop) }   // 세로만 · 손가락을 따라간다
                        }
                        .onEnded { v in
                            let base = dragBase ?? settled
                            dragBase = nil
                            let lifted = min(max(base + v.translation.height, 0), maxTop)
                            guard let g = glide(from: lifted, velocity: v.velocity.height, maxTop: maxTop) else {
                                var still = Transaction(); still.disablesAnimations = true
                                withTransaction(still) { visualTop = lifted }
                                topOffset = Double(lifted)
                                return
                            }
                            // **쓰기 하나로 애니메이션 시작** — 지금 값(= 마지막 onChanged의 lifted)에서 목표까지. 저장은 끝난 뒤.
                            withAnimation(g.animation, completionCriteria: .logicallyComplete) {
                                visualTop = g.target
                            } completion: {
                                topOffset = Double(g.target)
                            }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .onAppear { if visualTop < 0 { visualTop = topOffset < 0 ? maxTop / 2 : CGFloat(topOffset) } }
        }
    }

    private var shape: some View {
        ZStack {
            let r = UnevenRoundedRectangle(topLeadingRadius: radius, bottomLeadingRadius: radius,
                                           bottomTrailingRadius: 0, topTrailingRadius: 0, style: .circular)
            // 바탕 = 비치는 재질(어두운 판) + 스크린샷에서 잰 회색 그라데이션을 `tintOpacity`만큼 덮는다. 테두리·그림자 없음(스크린샷에 없다).
            // *(09-21 17:17 빌드는 그라데이션만 불투명으로 — 잰 색은 그대로고 덮는 비율만 더해졌다.)*
            // ⚠️ **A/B 중(2026-09-21 19:4x · 설계 §5-10):** 재질(`.regularMaterial`)을 **잠시 걷고 불투명 그라데이션만**.
            //   사용자: *"애니메이션이 부드럽지 않아. 드드드득~"* — 움직이는 재질은 매 프레임 밑을 다시 블러해 프레임을 떨군다(짚인 원인).
            //   부드러워지면 원인이 재질이다 → 비침을 포기하거나 덜 비싼 재질로(사용자가 고른다). `useMaterial`을 true로 돌리면 09-21 17:39 꼴.
            if useMaterial {
                r.fill(.regularMaterial)
                    .environment(\.colorScheme, .dark)   // 재질의 어두운 판을 고정한다(이 앱은 늘 어둡다)
                    .overlay(r.fill(tintGradient).opacity(tintOpacity))
            } else {
                r.fill(tintGradient)
            }
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

/// **거리-시각 표를 따라가는 애니메이션** — 표의 점 사이는 직선(일정 속도)이라 구간마다 속도가 계단으로 바뀐다. `EdgeHandle.glideProfile`이 만든다.
private struct StepGlide: CustomAnimation {
    let times: [Double]   // 구간 끝 시각(초 · 누적)
    let dists: [Double]   // 구간 끝 거리 비율(누적 · 마지막은 1)
    func animate<V: VectorArithmetic>(value: V, time: TimeInterval, context: inout AnimationContext<V>) -> V? {
        let total = times.last ?? 0
        guard time < total else {
            GlideLog.shared.finish(distance: value.magnitudeSquared.squareRoot(), total: total, times: times, dists: dists)
            return nil   // nil = 끝났다(목표값으로)
        }
        var i = 0
        while i < times.count - 1 && times[i] <= time { i += 1 }
        let t0 = i == 0 ? 0 : times[i - 1], d0 = i == 0 ? 0 : dists[i - 1]
        let f = t0 == times[i] ? dists[i] : d0 + (dists[i] - d0) * ((time - t0) / (times[i] - t0))
        GlideLog.shared.record(time: time, fraction: f)
        return value.scaled(by: f)
    }
}

/// **튕기기 프레임 계측**(2026-09-21 19:4x · 설계 §5-10 · `CLAUDE.md` 빌드 ⓒ — *"적게 만드는 것이 절반이다"*).
/// `StepGlide.animate`가 불릴 때마다 (시각, 진행률)을 **메모리에** 모으고, 끝날 때 한 번에 `Application Support/SecondBrain/edge-handle/glide.log`에 쓴다
/// (프레임마다 I/O를 하면 그 자체가 프레임을 떨군다). 폰에서 가져와 **프레임 간격(FPS)**과 **진행률의 직선성(같은 속도인가)**을 숫자로 본다.
/// 상태를 안 바꾼다(읽기 전용 계측). 사용자 판정이 끝나면 걷는다.
final class GlideLog: @unchecked Sendable {
    static let shared = GlideLog()
    private let lock = NSLock()
    private var samples: [(t: Double, f: Double)] = []
    private var wall = Date()

    func record(time: Double, fraction: Double) {
        lock.lock(); defer { lock.unlock() }
        if samples.isEmpty { wall = Date() }
        samples.append((time, fraction))
    }
    func finish(distance: Double, total: Double, times: [Double], dists: [Double]) {
        lock.lock(); let s = samples; samples = []; let started = wall; lock.unlock()
        guard !s.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async {
            let f = DateFormatter(); f.dateFormat = "MM-dd HH:mm:ss.SSS"
            var out = "glide \(f.string(from: started)) distance=\(String(format: "%.1f", distance))pt frames=\(s.count) total=\(String(format: "%.3f", total))s profile=\(zip(times, dists).map { String(format: "%.3f@%.2f", $0, $1) }.joined(separator: ","))\n"
            for x in s { out += String(format: "  %.4f %.4f\n", x.t, x.f) }
            guard let base = try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true) else { return }
            let dir = base.appendingPathComponent("SecondBrain/edge-handle", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("glide.log")
            if let h = try? FileHandle(forWritingTo: url) { defer { try? h.close() }; _ = try? h.seekToEnd(); try? h.write(contentsOf: Data(out.utf8)) }
            else { try? Data(out.utf8).write(to: url) }
        }
    }
}
