import SwiftUI
import SecondBrainCore
#if os(iOS)
import UIKit
#endif

/// 앱 안 수집 시트. iOS: 열리면 바로 한국어 STT 시작 → 실시간 전사 → 정지·교정 → [저장].
/// macOS: STT 없이 텍스트 입력. 저장 = 네이티브 항목 생성(미분류 → "새 기억들").
///
/// **[저장]은 여기서 끝나지 않는다** — 그 기억의 **상세 화면**으로 이어진다(2026-08-30 사용자 결정):
/// *"저장하기 누르면 지금 저장된 기억의 '상세 화면'으로 넘어가게 해줘. 거기서 내용이나 자료 추가하고
/// '기억하기'까지 선택하게 이어지는 것이 좋겠어."* 미는 것은 `InboxView`다(`model.openDetailId`).
///
/// ## ⛔ 그 이동을 **두 번 틀렸다** — 왕복을 적어 둔다 (2026-08-31)
/// | 판 | 어떻게 밀었나 | 무엇이 났나 |
/// |---|---|---|
/// | `06aff97` | 닫힘 뒤 **350ms 지연**(`Task.sleep`) | ✅ 통과 — **자료가 없었을 때만** |
/// | `22d62ad` | 같은 코드 | ⛔ **깨졌다** — [저장]이 자료마다 `load()`를 돌려 그 350ms가 겹쳤고,
///   미는 것이 **반쪽만 적용**됐다: **화면은 안 넘어가고 내비 바에 `‹` 자국만 남았다**(둘로 보였다) |
/// | `821ea01` | **아예 걷어냈다** | ⛔ **내가 사용자 말을 잘못 읽었다** — *"그건 괜찮아"*는
///   **「그 순서는 괜찮다」**였고 **기능을 버리라는 뜻이 아니었다**(*"자동으로 가게 해줘"*) |
/// | 지금 | **시트가 실제로 닫힌 뒤**(`onDismiss`) | 시간 짐작이 **없다** |
/// ★ **왜 350ms가 틀렸나:** `load()`가 **몇 번 도는지가 자료 수에 걸려 있다** — 값을 늘려도 근거가 없다.
/// ⛔ **다시 `Task.sleep`으로 돌아가지 말 것.** 전말 → `InboxView.openPendingDetail`.
///
/// ## ⛔⛔ 이 시트의 `onAppear`·`onDisappear`는 **「열림·닫힘」이 아니다** (2026-08-30에 물렸다)
///
/// 사진을 찍으면 **`UIImagePickerController`가 `.fullScreen` 모달로** 이 시트를 덮는다.
/// 그러면 UIKit이 밑에 있는 호스팅 컨트롤러에 `viewDidDisappear`를 주고, 닫힐 때 `viewDidAppear`를
/// 준다 → SwiftUI가 그것을 **`onDisappear` / `onAppear`로 그대로 흘린다.**
///
/// | 언제 | 무엇이 불렸나 | 무슨 일이 났나 |
/// |---|---|---|
/// | 카메라가 **열릴 때** | `onDisappear` | `speech.cancelAndDiscard()`가 돌아 **녹음한 원본 음성이 지워졌다** · 먼저 붙인 사진도 |
/// | 카메라가 **닫힐 때** | `onAppear` | `speech.start()`가 다시 돌아 `transcript`가 `""`로 리셋 → **받아쓰기한 글이 사라졌다** |
///
/// 사용자 신고(2026-08-30): *"음성을 녹음한 후 사진을 추가하면 … 저장되어 있던 내용들이 사라짐.
/// 그래서 기록을 다시 해야 함."* **텍스트만이 아니라 음성 파일까지 잃고 있었다.**
///
/// ✅ **그래서 둘을 표시 둘로 갈랐다:** `didStart`(시작은 한 번만) · `cameraOpen`(덮는 동안은 종료가 아니다).
/// ⛔ **`onAppear`에서 다시 `start()`하게 되돌리지 말 것** — 그 한 줄이 이 버그였다.
/// ★ **그리고 정리를 [취소] 버튼이 직접 한다** — 수명 콜백에만 맡기면 이런 식으로 조용히 어긋난다.
struct CaptureSheet: View {
    @ObservedObject var model: InboxModel
    /// **어떻게 들어왔나** — 나가는 뜻이 갈린다(`CaptureOrigin` · 2026-08-31 사용자 결정).
    /// 기본값은 `.inApp`이다(앱 안의 `+`). `RootView`가 띄우는 것만 `.hotkey`다.
    var origin: CaptureOrigin = .inApp
    @Environment(\.dismiss) private var dismiss
    /// **나가는 뜻 둘** — `<`(되돌아간다)와 [취소하기](이 수집을 그만둔다).
    /// ⛔ **앱 안에서는 가는 곳이 같지만 핫키로 들어왔을 때 갈린다**(`CaptureOrigin`의 표).
    private enum LeaveKind { case back, cancel }
    /// 되묻는 중이면 **어느 뜻으로 나가려던 것인지**를 들고 있다(nil = 안 묻는 중).
    /// `model.pendingDelete`와 같은 성격이다 — 팝업의 「예」가 무엇을 할지 여기서 기억한다.
    @State private var pendingLeave: LeaveKind?
    @State private var text = ""
    @State private var saved = false   // [저장]으로 확정됐는지 — 임시 음성·사진 정리 판단용
    #if os(iOS)
    @StateObject private var speech = SpeechCapture()
    @StateObject private var location = LocationProvider()   // 촬영 위치(사진 EXIF에만 · 그릇엔 안 감)
    /// STT를 **한 번만** 시작하려는 표시 — `onAppear`는 카메라가 닫힐 때도 다시 온다(위 ⛔ 표).
    @State private var didStart = false
    /// 카메라가 이 시트를 **덮고 있나** — 덮는 동안 오는 `onDisappear`는 **종료가 아니다**(위 ⛔ 표).
    @State private var cameraOpen = false

    // MARK: 저장 전 자료 (2026-08-30 · 「보조 자료」 카드가 수집 화면으로 왔다)
    //
    // ⛔ **아직 항목이 없다** — 그래서 자료를 **임시로 여기 들고 있다가 [저장] 때 붙인다.**
    //    붙이는 모양은 **op**이다(사용자 결정 2026-08-30 · `CaptureMediaCard` 머리주석).
    // ⚠️ **순서가 뜻이 있다** — 첫째가 카드 네모의 얼굴이 된다.
    /// 임시 사진 파일들(저장 시 확정 / 취소 시 삭제).
    @State private var draftPhotos: [URL] = []
    /// 정규화를 통과한 URL 문자열들 — **파일이 없다.** 값이 자료 자신이다.
    @State private var draftURLs: [String] = []
    /// `+` 시트와 그 뒤에 열 것 — ⚠️ **시트가 닫힌 뒤에 연다**(겹쳐 띄우면 둘째가 무시된다).
    @State private var showAddSheet = false
    @State private var pendingAdd: MediaAddRoute?
    @State private var showAlbum = false
    @State private var showURLSheet = false
    /// 앱 안 보기로 열 URL.
    @State private var openingURL: OpeningURL?
    /// 크게 볼 임시 사진.
    @State private var zooming: ZoomingPhoto?

    // MARK: 녹음 단추의 자리 (2026-08-31 · 끌어 옮길 수 있다)
    //
    // ⚠️ **치수는 「글꼴 크기」가 아니라 「잰 자리」다**(계측 규칙 1·2).
    //    `mic.circle.fill`을 `.font(.system(size: 65))`로 그리면 실제로 먹는 자리는 **76 x 74pt**다
    //    (2026-08-31 맥미니 `measure-text.swift` 실측 · 52pt일 때 61 x 59).
    //    ⛔ **65를 한계 계산에 넣지 말 것** — 이동 범위가 틀린다.
    /// 글꼴 크기 — **52의 25%를 키운 값**(사용자: *"25% 정도만 키우면 딱 좋을 거 같아"*).
    private static let micFont: CGFloat = 65
    /// 잰 자리 — 폭.
    private static let micW: CGFloat = 76
    /// 잰 자리 — 높이. ⚠️ 폭과 다르다.
    private static let micH: CGFloat = 74
    /// 칸 테두리와의 거리 — **사용자가 「지금처럼 유지」라고 한 값**이다. ⛔ 바꾸지 말 것.
    private static let micPad: CGFloat = 10

    /// 지금 보이는 이동량(끌고 있는 동안 따라온다).
    @State private var micShift: EdgeSlide.Shift = .home
    /// 손을 뗀 뒤 확정된 이동량 — 다음 끌기의 시작점.
    /// ⛔ **저장하지 않는다** — 시트를 새로 열면 **늘 기본 자리(우측 하단)**다(사용자 결정).
    @State private var micBase: EdgeSlide.Shift = .home
    /// 이번 접촉이 **이동**이었나 — 이동 뒤에 오는 탭을 삼켜 녹음이 켜/꺼지지 않게 한다.
    @State private var micMoved = false
    /// **잡혔다**(끌 수 있게 됐다) — 진동을 **한 번만** 주려는 표시. 손을 떼면 내린다.
    @State private var micGrabbed = false
    /// 처음 열릴 때의 **흔들기**를 한 번만 하려는 표시.
    @State private var didHint = false
    #endif

    var body: some View {
        // 자료 추가 배선(`+` 시트 → 카메라·앨범·URL · 앱 안 보기 · 크게 보기)은 **iOS만** 있다.
        // ⛔ **`sheetBody`에 직접 붙이지 않는다** — `#if`가 수정자 사슬 가운데 들어가면
        //    맥에서 컴파일이 조용히 갈린다(`SystemCamera`·`AlbumPicker`가 iOS 전용이다).
        #if os(iOS)
        mediaAddPlumbing(sheetBody)
        #else
        sheetBody
        #endif
    }

    private var sheetBody: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                #if os(iOS)
                statusLine
                if speech.isRecording && speech.autoStopEnabled {
                    SilenceBar(progress: speech.silenceProgress)
                }
                #endif
                TextEditor(text: $text)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border))
                    // ★ **160 → 80pt** (2026-08-30 사용자: *"텍스트 화면은 높이를 절반 정도로 줄이고
                    //    그 아래에 자료 카드를 붙이는 것으로 하자."*) — **줄어든 자리에 카드가 들어간다.**
                    //    ⚠️ **`minHeight`다** — 글자가 늘면 칸도 늘어난다(줄어든 것은 시작 높이다).
                    .frame(minHeight: 80)
                    .overlay(alignment: .topLeading) {
                        if text.isEmpty {
                            Text("말하거나 입력하세요").font(.body)
                                .foregroundStyle(Palette.textTertiary).padding(18).allowsHitTesting(false)
                        }
                    }
                    // ★★ **녹음 단추를 이 칸 안에 얹는다**(2026-08-31 사용자 결정 · `micLayer`).
                    //    ⛔ **테두리 overlay보다 뒤에 온다** — 앞에 두면 테두리가 단추 위에 그려진다.
                    //    ⚠️ **뜻이 자리로 드러난다:** *"그거 눌러서 말하면 그 텍스트 박스 안으로
                    //    타이핑된다는 의미야"* — 그래서 **칸 밖이 아니라 칸 안**이다.
                    #if os(iOS)
                    .overlay { micLayer }
                    #endif
                // ★★ **[삭제하기]·[저장 후 편집하기]** — 순서는 사용자가 정했다(2026-08-31):
                //    **텍스트 → 마이크 → 버튼 둘 → 자료 카드.**
                //    ⛔ **`#if` 밖에 둔다** — 맥에도 저장 단추가 있어야 한다(옛 [저장]은 툴바에 있었다).
                decideRow
                #if os(iOS)
                // ★ **「보조 자료」 카드** — 옛 「사진 찍기」 줄이 있던 자리다(2026-08-30).
                //   ⛔ **옛 꼴(지우지 않고 적어 둔다):** `photoControl` — [사진 찍기]/[다시 찍기] 버튼 +
                //   40pt 썸네일 + 「사진 1장 첨부됨」 + X. **한 장이 상한이었고**, 못 누를 때
                //   *"먼저 말하거나 입력하세요"*·*"녹음을 멈춘 뒤 사진을 찍어요"*를 그 줄에 띄웠다.
                //   ⚠️ **그 힌트가 사라졌다** — 「원문 없는 기억」을 막는 것은 이제 **[저장] 버튼의
                //   `disabled`와 `capture`의 guard 둘**이다(전엔 셋이었다).
                captureMediaCard
                #endif
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Palette.bg.ignoresSafeArea())
            // ★★ **제목은 「기억 수집」이다** (2026-09-02 사용자가 정했다).
            //   ⛔ **옛 꼴(뒤집혔다): `.navigationTitle("새 기억")`** — 좌측 상단 `<`에 글자를 붙이니
            //   **「‹ 새 기억」과 가운데 「새 기억」이 두 번 읽혔다**(사용자 판정: *"②는 거슬려!!"*).
            //   ⚠️ **두 번 읽히는 것은 두 자리에서 났고 둘 다 고쳤다** — 제목(여기)과 `<`의 글자(아래).
            .navigationTitle("기억 수집")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                // ★ **좌측 상단 `<`** (2026-08-31 사용자: *"취소하기가 유일한 출구인 것 알고 있고
                //   그게 나의 의도야. 하지만 일관성을 위하여 좌측 상단에 < 아이콘을 넣어보자."*)
                //   **상세 화면과 같은 자리·같은 심볼·같은 색**이다(`DetailView`의
                //   `chevron.backward` + `Palette.accent`).
                //   **하는 일은 [취소하기]와 같다** — 임시를 버리고 닫는다.
                //   ⚠️ **글자를 안 붙였다** — 상세는 「‹ 기억」처럼 글자가 붙는데, 여기 제목이
                //   **「새 기억」**이라 붙이면 **제목과 나란히 두 번** 읽힌다. **바꾸라면 바꾼다.**
                //   ⛔ **`.navigationBarLeading`을 쓰지 말 것 — 맥에 없다**(2026-08-31에 맥 빌드가 잡았다:
                //   *"'navigationBarLeading' is unavailable in macOS"*). **`.cancellationAction`**은
                //   두 플랫폼에 다 있고 iOS에서 **같은 자리(좌측 상단)**다.
                //   ★ **맥을 함께 빌드하지 않으면 이 오류를 못 본다** — iOS만 초록이었다.
                //   ★ **어떻게 들어왔든 늘 있다** (2026-08-31 사용자가 다시 정했다).
                //   **가는 곳만 갈린다:** 앱 안이면 **온 화면**, 핫키면 **「새로운 기억」**.
                //   ⛔ **옛 꼴(반나절 만에 뒤집혔다):** `if origin == .inApp`으로 **핫키에서 숨겼다** —
                //   *"돌아갈 화면이 없기 때문"*이라 적었는데 **「새로운 기억」이 그 자리였다.**
                //   ★★ **글자를 붙였다 — 상세와 짝이다** (2026-08-31 사용자: *"글자 붙이자.
                //   상세화면과 같이 유지하자. 한쪽이 바뀌면 같이 바뀌기로 하고 둘이 맞추자."*)
                //   ⛔ **한쪽만 고치지 말 것 — 짝은 `DetailView`의 `chevron.backward` 툴바 항목이다.**
                //   ★★ **글자 규칙이 뒤집혔다 — 「갈 곳의 이름」을 단다** (2026-09-02 사용자 결정:
                //   *"< 누르면 나타날 화면의 이름으로 < 버튼의 제목을 달아야 한다"*).
                //   **근거는 사용자가 눌러 본 것이다** — *"눌렀더니 「새로운 기억」으로 갔거든."*
                //   ⛔ **옛 규칙(뒤집혔다):** *"글자는 **그 화면의 제목**을 쓴다(상세는 「기억」 ·
                //   여기는 「새 기억」)."* — **자기 이름을 달던 것**이라 제목과 두 번 읽혔다.
                //   ✅ **여기는 두 진입 모두 「새로운 기억」으로 간다** — 앱 안의 `+`도 그 탭에 있고
                //   (`InboxView`), 핫키로 들어온 `<`도 「새로운 기억」이 그 자리다(`CaptureOrigin`).
                //   ⛔ **짝(`DetailView`)도 같은 규칙으로 바꿨다** — 그쪽은 **온 화면이 셋이라**
                //   글자를 **밖에서 받는다**(`backTitle`). **한쪽만 고치지 말 것.**
                //   ⛔ **옛 서술(뒤집혔다):** *"글자를 안 붙였다 — 제목과 나란히 두 번 읽힌다."*
                //   ⛔⛔ **`Label`을 쓰면 글자가 안 나온다 — 쟀다**(2026-08-31 시뮬 스크린샷):
                //   iOS 26이 툴바 앞자리의 `Label`을 **동그라미 안 아이콘만**으로 그린다.
                //   ✅ **`HStack`으로 직접 놓아야 글자가 보인다**(사용자: *"< 글자는 붙이자"*).
                //   ⛔ **짝(`DetailView`)도 같은 꼴로 바꿨다 — 한쪽만 고치지 말 것.**
                ToolbarItem(placement: .cancellationAction) {
                    Button { leaveTapped(.back) } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "chevron.backward")
                            Text("새로운 기억")
                        }
                    }
                    .tint(Palette.accent)
                }
            }
            // ⛔ **오른쪽 위에는 단추가 없다** — **[저장]을 뺐다**(2026-08-31 사용자:
            //    *"일관성 차원에서는 [저장 하기] 버튼은 텍스트 바로 아랫줄에 위치되는 것이 좋겠어."*)
            //    → 본문의 `decideRow`로 내려갔다.
            //
            // ## 나가는 길 (2026-08-31에 두 번 바뀌었다 — 옛 서술을 남긴다)
            // **지금:** **[취소하기]**(본문) · **`<`**(좌측 상단) — **둘 다 같은 일**을 한다.
            //   쓸어 닫기는 막혀 있다(`.interactiveDismissDisabled(true)`).
            // ⛔ **옛 서술 ①(낡았다):** *"[취소]도 뺐다 … 그래서 나가는 길은 [삭제하기] 하나다"* —
            //   그 뒤 **[삭제하기]가 [취소하기]로 바뀌었고**, **`<`가 다시 생겼다**
            //   (사용자: *"취소하기가 유일한 출구인 것 알고 있고 그게 나의 의도야.
            //   하지만 일관성을 위하여 좌측 상단에 < 아이콘을 넣어보자."*).
            //   ★ **「유일한 출구」는 뜻이고, `<`는 그 뜻을 어기지 않는다** — 같은 일을 하는 자리가
            //   하나 더 생긴 것이지 **다른 출구가 생긴 것이 아니다.**
            // ⏸ **되묻지 않는다** — 잘못 누르면 받아쓰기·녹음이 바로 사라진다.
            //    **확인을 붙일지는 사용자 결정**(문구가 필요하다 · 항시 규칙 6).
        }
        // ⛔ **아래로 쓸어 닫는 것을 막는다** (2026-08-30 사용자 지시: *"수집 화면 어디를 누르든
        //    터치하여 아래로 스와이프하면 화면이 취소되고 사라짐. 취소 버튼이 있으니 이 기능은 지워버리세요."*)
        //    ★ 이것이 **데이터를 잃는 길이기도 했다** — 쓸어 닫히면 받아쓰기·녹음이 그대로 버려졌다.
        //    나가는 길은 **[취소]와 [저장] 둘뿐**이다.
        .interactiveDismissDisabled(true)
        // **나가면 사라져요** — 적은 것이 있을 때만 되묻는다(2026-08-31 사용자: *"두 경우 모두
        // 데이터가 입력되어 있다면 확인 팝업은 띄워야겠네"*).
        // ⚠️ **문구는 내가 골랐다 — 확정 아니다**(항시 규칙 6). 꼴은 앱에 이미 있는 것을 그대로 썼다
        //    (`ConfirmDialog` · 상세의 `discardDialog`가 [나가기]/[계속 수정하기]다).
        .overlay {
            if let kind = pendingLeave {
                ConfirmDialog(title: "나가면 지금 적은 내용이 사라져요",
                              cancelTitle: "나가기", confirmTitle: "계속 쓰기",
                              // [나가기] = 버리고 나간다. ⚠️ **어느 뜻으로 눌렀는지를 그대로 이어간다** —
                              //    `<`였으면 화면으로, [취소하기]였으면 그 뜻대로(핫키면 앱 밖).
                              onCancel: { pendingLeave = nil; leaveNow(kind) },
                              onConfirm: { pendingLeave = nil })       // [계속 쓰기] = 머무름
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: pendingLeave)
        #if os(iOS)
        .onAppear {
            // ⛔ **카메라가 닫힐 때도 여기 온다**(머리주석 표) — 그때 다시 start()하면 받아쓰기가 지워진다.
            guard !didStart else { return }
            didStart = true
            speech.start()                                    // 열리면 바로 STT(+ 원본 음성 녹음)
            // ★ **「끌 수 있다」를 몸으로 알린다** — 짧게 흔든다(2026-08-31 사용자 결정 · `micHintWiggle`).
            //   ⚠️ **녹음이 시작된 뒤다** — 사용자: *"아마 그 때는 녹음이 시작되어 있을 거야.
            //   그러니 녹음되는 중에 그렇게 동작해 달라는 의미야."*
            if !didHint { didHint = true; Task { await micHintWiggle() } }
        }
        .onChange(of: speech.transcript) { _, t in text = t } // 실시간 전사를 편집칸에
        .onDisappear {
            // ⛔ **카메라가 열릴 때도 여기 온다**(머리주석 표) — 그때 정리하면 녹음·사진이 사라진다.
            guard !cameraOpen else { return }
            location.stop()
            if !saved { discardTemps() }                      // 미저장 종료 → 임시 음성·사진 삭제
        }
        #endif
    }

    private func save() {
        // source: iOS는 음성 수집이 기본, macOS는 텍스트.
        #if os(iOS)
        // 엔진 정지 + 세션 음성 파일 닫기 → 임시 URL(모든 take 이어진 하나). capture가 <uuid>.m4a로 확정.
        let audioURL = speech.finishAndURL()
        let newId = model.capture(text: text, source: "voice", audioTemp: audioURL)
        // ★ **자료는 op으로 붙는다** (2026-08-30 사용자 결정 · 성역은 녹음 원본 `audio` 하나다).
        //   ⛔ **create 블록에 넣지 않는다** — 넣으려면 `EventWriter`의 고정 목록을 접두어로 열어야 하고
        //   (설계 §3-W-4 1번) **성역은 한번 자라면 되돌릴 수 없다.**
        //   ★ **상세에서 나중에 붙이는 것과 같은 길이다**(§3-Y-1 결정 2) — 자료가 어디서 붙었든 모양이 하나다.
        //   ⚠️ **항목이 먼저 있어야** 하므로 `capture` **뒤**에 돈다(파일 이름에 항목 id가 들어간다).
        if let newId {
            for temp in draftPhotos { model.addPhoto(to: newId, temp: temp) }
            for u in draftURLs { model.addURL(to: newId, url: u) }
            draftPhotos = []          // 확정으로 넘어갔다 — 정리가 두 번 지우려 들지 않게
            draftURLs = []
        }
        #else
        let newId = model.capture(text: text, source: "text")
        #endif
        saved = true
        // 저장한 그 기억의 **상세 화면**으로 이어 간다(머리주석) — 미는 것은 `InboxView`이고,
        // **이 시트가 실제로 닫힌 뒤**(`onDismiss`)에 민다.
        // ⚠️ `model`은 이 시트보다 오래 살므로 dismiss 뒤에도 신호가 남는다.
        // ★ **자료 붙이기(위)가 신호보다 먼저 끝나 있어야 한다** — `load()`가 다 돌고 나서 닫히도록.
        if let newId { model.openDetailId = newId }
        dismiss()
    }

    /// **[삭제하기]·[저장 후 편집하기]** — ★ **상세 화면의 `decideRow`와 같은 자리·같은 꼴**이다
    /// (2026-08-31 사용자: *"이 버튼 2개의 위치와 모양은 상세화면의 버튼 위치와 모양에 그대로 맞춰줘.
    /// 일관성이야."*).
    ///
    /// ⛔ **꼴을 여기서 바꾸지 말 것** — 상세(`DetailView.decideRow`)와 갈리면 그 일관성이 깨진다.
    /// **`HStack(spacing: 10)`** · 왼쪽 **`.bordered` + `overdue`** · 오른쪽 **`.borderedProminent` + `today`**
    /// (오른쪽은 상세의 **[기억하기]** 자리이고, 여기서는 **[저장 후 편집하기]**가 그 자리를 대신한다 —
    /// **문구는 사용자가 정했다**).
    ///
    /// ⚠️ **아이콘은 내가 골랐다 — 확정 아니다**(항시 규칙 6 · 아이콘도 사용자 사안이다).
    /// 상세의 [기억하기]는 `checkmark.seal.fill`(확정의 도장)인데 **이 단추는 확정이 아니라 「편집으로
    /// 이어진다」**라서 `square.and.pencil`로 뒀다. **바꾸라면 바꾼다.**
    ///
    /// ✅ **폭은 쟀다**(2026-08-31 맥미니 · `measure-text.swift`): 「저장 후 편집하기」 **111.7pt @17** ·
    /// 「삭제하기」 **58.9pt @17**. 왼쪽이 ≈120pt를 먹고 남는 240pt에 오른쪽 내용 ≈162pt가 든다.
    /// **XXL(21pt)에서도 222 대 190으로 남는다.** ⚠️ **계산이다 — 화면에서 닫을 값이다**(계측 규칙 4).
    @ViewBuilder private var decideRow: some View {
        HStack(spacing: 10) {
            // ★ **[취소하기]** (2026-08-31 사용자: *"[삭제하기] 버튼은 X 아이콘을 넣은
            //   [취소하기] 버튼으로 바꾸고"*). ⛔ **`role: .destructive`를 뗐고 색을 회색으로 내렸다** —
            //   **상세 하단의 [취소]가 이미 `xmark` + `textSecondary`**이고(`DetailView.bottomBar`)
            //   **일관성이 이 지시의 이유**이기 때문이다. ⚠️ **색까지 바꾸라는 말은 없었다** —
            //   빨강으로 되돌리려면 `Palette.overdue`로 되돌린다.
            Button { leaveTapped(.cancel) } label: {
                Label("취소하기", systemImage: "xmark")
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered).tint(Palette.textSecondary)

            // ★ **바탕색을 `accent`로** (2026-08-31 사용자: *"'상세화면'에 있는 활성화된 저장 버튼
            //   색깔로 바꾸자"*). 그 단추 = `DetailView.bottomBar`의 [저장] =
            //   **`.borderedProminent` + `Palette.accent`**. ⛔ 옛 값은 `Palette.today`(앰버)였다.
            Button { save() } label: {
                Label("저장 후 편집하기", systemImage: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.accent)
            // 원문이 없으면 저장할 것이 없다 — 「원문 없는 기억」을 막는 두 장치 중 하나
            // (다른 하나는 `InboxModel.capture`의 guard).
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// **적은 것이 있나** — 되물을지 가르는 값. 원문뿐 아니라 **붙여 둔 자료도** 센다
    /// (사진을 셋 찍어 두고 글은 안 쓴 경우도 잃을 것이 있다).
    private var hasSomethingToLose: Bool {
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        #if os(iOS)
        if !draftPhotos.isEmpty || !draftURLs.isEmpty { return true }
        #endif
        return false
    }

    /// **`<` 또는 [취소하기]를 눌렀다** — 적은 것이 있으면 **되묻고**, 없으면 바로 나간다.
    /// ⚠️ **되물을 때도 뜻을 잃지 않는다** — `pendingLeave`가 들고 있다가 [나가기]에서 그대로 이어간다.
    private func leaveTapped(_ kind: LeaveKind) {
        if hasSomethingToLose { pendingLeave = kind } else { leaveNow(kind) }
    }

    /// **나간다** — 임시 음성·사진을 버리고, **뜻과 들어온 길에 따라** 간다.
    ///
    /// | 뜻 | `.inApp` | `.hotkey` |
    /// |---|---|---|
    /// | **`.back`**(`<`) | 온 화면으로 | **「새로운 기억」으로** |
    /// | **`.cancel`**([취소하기]) | 온 화면으로 | **앱 밖으로** |
    ///
    /// ★ **`.back`은 둘 다 `dismiss()` 하나로 끝난다** — 핫키로 열릴 때 `RootView`가 이미
    /// **탭을 「새로운 기억」으로 옮겨 두기 때문**이다(`onChange(of: launcher.showCapture)`).
    /// ⛔ **여기서 탭을 다시 옮기지 않는다** — 두 곳이 같은 일을 하면 한쪽이 조용히 어긋난다.
    ///
    /// ⛔ `onDisappear`에만 맡기지 않는다 — 그 콜백은 카메라가 덮을 때도 오기 때문이다(머리주석 표).
    private func leaveNow(_ kind: LeaveKind) {
        #if os(iOS)
        discardTemps()
        // ★★ **「앱 밖으로」는 여기서 안 한다 — `RootView`가 한다**(2026-08-31에 옮겼다).
        //    **탭을 아는 쪽이 거기**이기 때문이다: 사용자 결정이 *"앱이 그 전에 suspend되어 있던
        //    화면 상태로"*이므로 **나가기 전에 그 탭으로 되돌려야** 하고, 탭은 `RootView`의 것이다.
        //    ⛔ **시트에서 `suspend`를 부르면** 되돌리기 전에 화면이 얼어 **수집 화면이 남은 채로 내려간다.**
        //    여기서는 **뜻만 남긴다** — `RootView`의 `onDismiss`가 읽는다.
        if kind == .cancel && origin == .hotkey { CaptureLauncher.shared.cancelledOut = true }
        // ★★ **끝내는 길에서는 이 화면을 안 내린다** (2026-09-02 · 사용자: *"종료되는 과정이라면
        //   당연히 다른 화면이 보이지 말아야 하고"*). **내리는 순간 뿌리가 목록으로 되돌아가고,
        //   `suspend`가 그 목록을 데리고 내려간다.** ⛔ **내려간 뒤에 다시 붙잡는 것으로는 안 됐다**
        //   (`holdForExit` · 하루 만에 걷어냈다). **아예 안 내리는 것이 답이다.**
        //   ⚠️ **이 길의 끝은 `exit(0)`이라 되돌아올 자리가 없다** — 안 내려도 남는 것이 없다.
        let willExitApp = kind == .cancel && CaptureLauncher.shared.wokenByHotkey
        // ★ **뿌리로 그려졌을 때는 `dismiss()`가 아무 일도 안 한다**(띄운 것이 아니다) —
        //   그래서 **신호를 직접 내린다.** 커버로 떴을 때도 이 값이 커버를 닫는다(`warmCapture`).
        if origin == .hotkey && !willExitApp { CaptureLauncher.shared.showCapture = false }
        #endif
        dismiss()
    }

    #if os(iOS)
    @ViewBuilder private var statusLine: some View {
        switch speech.status {
        case .recording:
            Label("듣는 중…", systemImage: "waveform").font(.callout).foregroundStyle(Palette.accent)
        case .authDenied:
            Text("마이크·음성 인식 권한이 필요해요. 설정에서 허용해 주세요.")
                .font(.callout).foregroundStyle(Palette.overdue)
        case .onDeviceUnavailable:
            Text("이 기기에서 온디바이스 한국어 인식이 안 돼요. 음성은 기기 밖으로 보내지 않으니, 텍스트로 입력해 주세요.")
                .font(.callout).foregroundStyle(Palette.today).fixedSize(horizontal: false, vertical: true)
        case .unavailable:
            Text("음성 인식을 사용할 수 없어요. 텍스트로 입력해 주세요.")
                .font(.callout).foregroundStyle(Palette.today)
        case .failed(let msg):
            Text("음성 인식 오류: \(msg)").font(.caption).foregroundStyle(Palette.overdue)
        case .idle:
            EmptyView()
        }
    }

    /// 침묵 진행 막대 — 받아쓰기 네모 바로 위. 왼→오로 채워지며 자동 종료까지 남은 시간을 보여준다.
    /// 발화가 다시 시작되면 progress가 0으로 리셋되어 막대가 왼쪽으로 되돌아간다(반복).
    /// 끝에 가까우면(임박) 색을 경고색으로 바꿔 곧 종료됨을 알린다.
    private struct SilenceBar: View {
        let progress: Double
        var body: some View {
            let p = min(max(progress, 0), 1)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Palette.surface)
                    Capsule()
                        .fill(p >= 0.75 ? Palette.overdue : Palette.accent)
                        .frame(width: geo.size.width * p)
                }
            }
            .frame(height: 5)
            .animation(.linear(duration: 0.05), value: p)
            .accessibilityLabel("자동 종료까지 남은 시간")
        }
    }

    /// **녹음 단추 — 텍스트 칸 우측 하단에 얹힌 꼴**(2026-08-31 사용자 결정).
    ///
    /// 사용자: *"텍스트 아래에 마이크 아이콘은 정말 안 어울린다. 조화롭지 않아. 이 버튼은
    /// 크기,모양 그대로 유지한채로 Floating Button 방식으로 바꿔서 텍스트 박스 우측 하단에
    /// 위치시키자. 그거 눌러서 말하면 그 텍스트 박으로 안으로 타이핑된다는 의미야."*
    ///
    /// ⛔ **크기·모양·색을 바꾸지 말 것** — 52pt · `mic.circle.fill` / 녹음 중 `stop.circle.fill` ·
    /// accent / 녹음 중 overdue. **바뀐 것은 자리 하나다.**
    /// ⛔ **옛 꼴:** 텍스트 칸 **아래 한 줄에 가운데 정렬**(`HStack` + `Spacer` 둘). 그 줄이 없어졌다.
    ///
    /// ⚠️ **글자와 겹칠 수 있다 — 쟀다:** 칸의 시작 높이가 **80pt**이고 안쪽 여백이 10×2라
    /// 글자가 쓰는 높이는 **≈60pt = 17pt에서 세 줄**(줄높이 20.1). 단추는 **52 + 여백 10 = 62pt**를
    /// 오른쪽 아래에서 먹으므로 **둘째·셋째 줄의 오른쪽이 가려진다.**
    /// **화면에서 판정받을 값이다**(계측 규칙 4) — 걸리면 자리를 바깥으로 반쯤 빼는 것이 다음 후보다.
    /// 단추가 얹히는 **층** — 칸 크기를 알아야 이동 한계가 나오므로 `GeometryReader`다.
    ///
    /// ⚠️ **`.position`은 「중심」을 놓는다** — 그래서 기본 자리가
    /// `(폭 − 여백 − 폭/2, 높이 − 여백 − 높이/2)`다(모서리에서 여백만큼 뗀 자리).
    /// ⛔ **층이 터치를 다 먹지 않게** `allowsHitTesting`을 층에 걸지 않는다 — 단추만 잡는다
    /// (`GeometryReader`의 빈 자리는 그림이 없어 터치가 통과한다).
    @ViewBuilder private var micLayer: some View {
        GeometryReader { geo in
            micButton
                .position(x: geo.size.width - Self.micPad - Self.micW / 2 + micShift.dx,
                          y: geo.size.height - Self.micPad - Self.micH / 2 + micShift.dy)
                .gesture(micDrag(box: geo.size))
        }
    }

    /// **녹음 단추** — 짧게 누르면 녹음 시작/정지, **꾹 눌러 끌면 자리를 옮긴다.**
    ///
    /// ⛔ **`Button`을 쓰지 않는다** — 끌기를 끝내고 손을 떼는 순간 `Button`이 자기 동작을 실행해
    /// **옮겼을 뿐인데 녹음이 켜/꺼진다.** 그래서 `onTapGesture`로 갈랐고, 그래도 새는 경우를 막으려
    /// `micMoved`로 **이동 뒤의 탭을 한 번 삼킨다.**
    /// ⚠️ **`CLAUDE.md`의 「`LongPressGesture`로 돌아가지 말 것」은 이 자리가 아니다** —
    /// 그것은 **원칙 목록의 드래그 정렬**(`List` 안의 순서 바꾸기)에서 두 번 실패한 기록이다.
    /// 여기는 **자유 캔버스 위의 단추 하나**라 그 함정(리스트가 제스처를 먹는 것)이 없다.
    ///
    /// ⛔ **크기·모양·색은 자리 말고 아무것도 바꾸지 않았다** — `mic.circle.fill` /
    /// 녹음 중 `stop.circle.fill` · accent / overdue. **글꼴만 52 → 65**(사용자가 정한 25%).
    @ViewBuilder private var micButton: some View {
        Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
            .font(.system(size: Self.micFont))
            .foregroundStyle(speech.isRecording ? Palette.overdue : Palette.accent)
            .contentShape(Circle())
            .accessibilityAddTraits(.isButton)
            .onTapGesture {
                if micMoved { micMoved = false; return }   // 방금 옮긴 것이면 녹음을 건드리지 않는다
                if speech.isRecording { speech.stop() } else { speech.resume(seed: text) }
            }
    }

    /// **꾹 눌러 끌기** — 자리는 `EdgeSlide`가 ㄴ자 길(우측 변·하단 변)로 접는다.
    /// ⚠️ **잰 자리(76 x 74)를 넘긴다** — 글꼴 65를 넘기면 한계가 틀린다.
    private func micDrag(box: CGSize) -> some Gesture {
        LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                // ★ **잡혔다 — 여기서 한 번 진동한다**(2026-08-31 사용자: *"그래그해서 이동할 수
                //   있게 잡혔다면 약간의 진동을 넣어줘"*).
                //   ⚠️ **`drag`가 nil인 첫 알림에서도 잡힌 것이다** — `minimumDistance: 0`이라
                //   손가락이 안 움직여도 끌기가 바로 시작될 수 있어 **둘 다 받아** 놓쳐지지 않게 한다.
                if !micGrabbed { micGrabbed = true; Self.grabHaptic() }
                guard let drag else { return }
                micMoved = true
                micShift = EdgeSlide.snap(base: micBase,
                                          dx: drag.translation.width, dy: drag.translation.height,
                                          boxW: box.width, boxH: box.height,
                                          itemW: Self.micW, itemH: Self.micH, pad: Self.micPad)
            }
            .onEnded { _ in micBase = micShift; micGrabbed = false }
    }

    /// 미저장 종료 → 임시 음성·사진 삭제. **[취소]와 `onDisappear` 둘이 부른다.**
    /// ⚠️ 목록을 비워 **두 번 지우려 들지 않게** 한다.
    /// ⛔ **URL은 지울 것이 없다** — 파일을 만들지 않는다(값이 자료 자신이다).
    private func discardTemps() {
        speech.cancelAndDiscard()
        for p in draftPhotos { PhotoStore.deleteTemp(p) }
        draftPhotos = []
        draftURLs = []
    }

    // MARK: 「보조 자료」 카드 (2026-08-30 · 옛 「사진 첨부」 줄을 대신한다)
    //
    // ⛔ **옛 조건을 뗐다:** 카메라 활성 조건이 `hasText && !speech.isRecording`이었다
    //    (*"원문 없는 기억"*을 3중으로 막고, 오디오 세션 충돌을 피하려고).
    //    ✅ **녹음 중 정지는 유지한다**(아래 `.camera` 갈래 첫 줄) — 그것이 세션 충돌을 막던 쪽이다.
    //    ⚠️ **본문 조건은 뗐다** — `+`는 늘 눌린다(상세와 같다). 「원문 없는 기억」은
    //    **[저장]의 `disabled`와 `capture`의 guard**가 막는다.

    @ViewBuilder private var captureMediaCard: some View {
        CaptureMediaCard(
            photos: draftPhotos,
            urls: draftURLs,
            onAdd: { showAddSheet = true },
            onTapPhoto: { if let f = draftPhotos.first { zooming = ZoomingPhoto(url: f) } },
            onTapURL: { u in if let url = URL(string: u) { openingURL = OpeningURL(url: url) } },
            onRemovePhoto: { i in
                guard draftPhotos.indices.contains(i) else { return }
                PhotoStore.deleteTemp(draftPhotos.remove(at: i))   // 임시 파일을 남기지 않는다(고아 방지)
            },
            onRemoveURL: { i in
                guard draftURLs.indices.contains(i) else { return }
                draftURLs.remove(at: i)                            // 지울 파일이 없다
            })
    }

    /// `+` → 종류 시트 → (사진 찍기 | 앨범에서 고르기 | URL). **상세와 같은 시트를 쓴다** —
    /// ⛔ **입구를 하나로 유지하려는 것이다**(둘로 갈리면 한쪽만 고쳐진다).
    /// ⚠️ 시트가 **닫힌 뒤** 다음 화면을 연다(`onDismiss`) — 겹쳐 띄우면 iOS가 둘째를 무시한다.
    @ViewBuilder private func mediaAddPlumbing<V: View>(_ content: V) -> some View {
        content
            .sheet(isPresented: $showAddSheet, onDismiss: {
                switch pendingAdd {
                case .camera:
                    if speech.isRecording { speech.stop() }   // 오디오 세션 충돌·발화 끊김 방지
                    location.begin()                          // 프레이밍하는 동안 촬영 위치 취득(EXIF용)
                    // ⛔⛔ **present보다 먼저 올린다** — 카메라가 뜨는 순간 이 시트의 `onDisappear`가
                    //    불리고, 그때 이 표시가 아직 false면 **받아쓰기·녹음이 지워진다**(머리주석 표).
                    cameraOpen = true
                    // ⛔ **커버로 감싸지 않는다 — 모달로 띄운다**(2026-08-24 · `SystemCamera` 머리주석).
                    SystemCamera.present { img in
                        // 촬영마다 **고유** 임시 경로 → 목록에 그대로 쌓인다(같은 경로에 덮으면 옛 썸네일이 남는다).
                        if let temp = PhotoStore.saveCaptured(img, location: location.last,
                                                              sessionId: UUID().uuidString) {
                            draftPhotos.append(temp)
                        }
                    } onFinish: {
                        cameraOpen = false
                    }
                case .album:  showAlbum = true
                case .url:    showURLSheet = true
                case nil:     break
                }
                pendingAdd = nil
            }) {
                MediaAddSheet(onCamera: { pendingAdd = .camera; showAddSheet = false },
                              onAlbum:  { pendingAdd = .album;  showAddSheet = false },
                              onURL:    { pendingAdd = .url;    showAddSheet = false })
            }
            // 앨범에서 온 파일은 **원본 EXIF를 품고 온다** — 위치가 있으면 그대로 살아 있다.
            .sheet(isPresented: $showAlbum) {
                AlbumPicker { temp in draftPhotos.append(temp) }
            }
            .sheet(isPresented: $showURLSheet) {
                URLAddSheet { raw in
                    // ⚠️ **여기서 정규화한다** — 저장 때 `addURL`이 또 한 번 하지만,
                    //    카드에 그리는 값도 정규화된 것이어야 짧은 이름·미리보기가 맞는다.
                    if let v = URLAsset.normalized(raw) { draftURLs.append(v) }
                }
            }
            // **앱 안 보기** — 닫으면 바로 수집 화면으로 돌아온다(사파리로 나가지 않는다).
            .sheet(item: $openingURL) { o in SafariSheet(url: o.url).ignoresSafeArea() }
            // **크게 보기** — ⛔ `MediaViewer`를 못 쓴다(저장된 항목의 포인터를 읽는다).
            //   ⚠️ **닫기는 아이콘이다** — 뷰어와 같은 꼴(`MediaViewer.closeButton`). 화면에 새 말이 없다.
            .fullScreenCover(item: $zooming) { z in
                ZStack(alignment: .topLeading) {
                    Color.black.ignoresSafeArea()
                    if let img = UIImage(contentsOfFile: z.url.path) {
                        ZoomableImage(image: img).ignoresSafeArea()
                    }
                    Button { zooming = nil } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(12)
                            .background(Circle().fill(.black.opacity(0.45)))
                    }
                    .buttonStyle(.plain)
                    .padding(16)
                }
            }
    }

    /// **잡혔다는 진동** — 끌 수 있게 된 순간 한 번(2026-08-31 사용자 결정).
    /// ⚠️ **`.light`다** — *"약간의 진동"*이라고 했다. ⛔ 세기를 올리지 말 것.
    private static func grabHaptic() {
        let gen = UIImpactFeedbackGenerator(style: .light)
        gen.prepare()
        gen.impactOccurred()
    }

    /// **처음 열릴 때 짧게 흔든다** — 「이 단추는 움직인다」를 몸으로 알린다.
    ///
    /// 사용자(2026-08-31): *"이 화면에 처음 진입하면 마이크 버튼이 움직일 수 있다는 느낌을 주기 위해
    /// default 위치에서 위로 두번 정도 왼쪽으로 두번정도 흔들어줘. 짧게."*
    ///
    /// **움직일 수 있는 두 방향을 그대로 보인다** — 위(우측 변) 두 번 · 왼쪽(하단 변) 두 번.
    /// ⛔ **`EdgeSlide.snap`을 통과하지 않는다.** 이것은 **이동이 아니라 신호**이고,
    /// 칸이 낮을 때(80pt) `snap`은 **위로 0**을 주므로 통과시키면 **위 흔들기가 아예 안 보인다.**
    /// ⚠️ **그래서 12pt가 칸 밖으로 조금 나간다** — 짧고 한 번뿐이라 그대로 뒀다. **화면에서 볼 값이다.**
    /// ⛔ **끝나면 반드시 기본 자리로 돌아온다** — `micBase`는 건드리지 않으므로 다음 끌기의 기준은 그대로다.
    private func micHintWiggle() async {
        let amount = 12.0
        // ★ **2배 느리게** (2026-08-31 사용자: *"흔들리는 속도는 2배로 느리게 하자"*).
        //   ⛔ 옛 값 **0.09**(≈0.72초) → **0.18**(≈1.44초). **칸 수는 그대로 여덟이다.**
        let step = 0.18          // 한 칸 0.18초 × 8칸 ≈ 1.44초
        func move(_ to: EdgeSlide.Shift) async {
            withAnimation(.easeInOut(duration: step)) { micShift = to }
            try? await Task.sleep(for: .seconds(step))
        }
        for _ in 0..<2 {                                  // 위로 두 번
            await move(EdgeSlide.Shift(dx: 0, dy: -amount))
            await move(.home)
        }
        for _ in 0..<2 {                                  // 왼쪽으로 두 번
            await move(EdgeSlide.Shift(dx: -amount, dy: 0))
            await move(.home)
        }
    }

    /// `sheet(item:)`·`fullScreenCover(item:)`이 요구하는 그릇 둘.
    private struct OpeningURL: Identifiable { let id = UUID(); let url: URL }
    private struct ZoomingPhoto: Identifiable { let id = UUID(); let url: URL }

    #endif
}
