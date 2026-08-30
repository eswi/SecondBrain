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
    @Environment(\.dismiss) private var dismiss
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
                #if os(iOS)
                micControl
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
            .navigationTitle("새 기억")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("취소") { cancel() }
                }
                // ⛔ **오른쪽 위의 [저장]을 뺐다** (2026-08-31 사용자: *"수집 화면에서 저장이 가장 위로
                //    올라가 있잖아? 그런데 일관성 차원에서는 [저장 하기] 버튼은 텍스트 바로 아랫줄에
                //    위치되는 것이 좋겠어."*) → 본문의 `decideRow`로 내려갔다.
                // ⚠️ **[취소]는 남겼다** — 상세 화면의 `‹`(뒤로)에 대응하는 자리다.
                //    ⏸ **[삭제하기]와 하는 일이 같다**(임시를 버리고 닫는다) — 하나로 줄일지는 사용자 결정.
            }
        }
        // ⛔ **아래로 쓸어 닫는 것을 막는다** (2026-08-30 사용자 지시: *"수집 화면 어디를 누르든
        //    터치하여 아래로 스와이프하면 화면이 취소되고 사라짐. 취소 버튼이 있으니 이 기능은 지워버리세요."*)
        //    ★ 이것이 **데이터를 잃는 길이기도 했다** — 쓸어 닫히면 받아쓰기·녹음이 그대로 버려졌다.
        //    나가는 길은 **[취소]와 [저장] 둘뿐**이다.
        .interactiveDismissDisabled(true)
        #if os(iOS)
        .onAppear {
            // ⛔ **카메라가 닫힐 때도 여기 온다**(머리주석 표) — 그때 다시 start()하면 받아쓰기가 지워진다.
            guard !didStart else { return }
            didStart = true
            speech.start()                                    // 열리면 바로 STT(+ 원본 음성 녹음)
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
            Button(role: .destructive) { cancel() } label: {
                Label("삭제하기", systemImage: "trash")
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 6)
            }
            .buttonStyle(.bordered).tint(Palette.overdue)

            Button { save() } label: {
                Label("저장 후 편집하기", systemImage: "square.and.pencil")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.today)
            // 원문이 없으면 저장할 것이 없다 — 「원문 없는 기억」을 막는 두 장치 중 하나
            // (다른 하나는 `InboxModel.capture`의 guard).
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    /// [취소] — 임시 음성·사진을 **여기서 직접** 버리고 닫는다.
    /// ⛔ `onDisappear`에만 맡기지 않는다 — 그 콜백은 카메라가 덮을 때도 오기 때문이다(머리주석 표).
    private func cancel() {
        #if os(iOS)
        discardTemps()
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

    @ViewBuilder private var micControl: some View {
        HStack {
            Spacer()
            Button {
                if speech.isRecording { speech.stop() } else { speech.resume(seed: text) }
            } label: {
                Image(systemName: speech.isRecording ? "stop.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(speech.isRecording ? Palette.overdue : Palette.accent)
            }
            .buttonStyle(.plain)
            Spacer()
        }
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

    /// `sheet(item:)`·`fullScreenCover(item:)`이 요구하는 그릇 둘.
    private struct OpeningURL: Identifiable { let id = UUID(); let url: URL }
    private struct ZoomingPhoto: Identifiable { let id = UUID(); let url: URL }

    #endif
}
