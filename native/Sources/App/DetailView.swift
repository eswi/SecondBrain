import SwiftUI
import SecondBrainCore
import MapKit
import CoreLocation

/// 상세 화면 — "편집의 무대" (memory-philosophy.md §6, 정책 정본 = edit-policy.md).
///
/// **draft 편집 방식**: 화면 위에서 분류·Due·Resurface를 고쳐도 로컬 상태에만 담기고,
/// [저장] 전까지 이벤트로 커밋되지 않는다. 병합 엔진·이벤트 소싱 구조는 그대로 —
/// 커밋 시점만 [저장]으로 미룬다.
///
/// 액션은 두 층: ① 기본 정보 아래 **[기억하기]**(아직 안 한 기억에만 노출, 살아있는 기억으로
/// 살릴지의 최소 관문) ② 맨 아래 필수 바(삭제하기·취소·저장).
///
/// - **[기억하기]** = "이 기억을 (단기/장기적으로) 기억하기로 한다"는 결정. 최종 승격(§3 단방향,
///   되돌리려면 삭제). "되돌릴 수 없다" 재확인 팝오버를 거쳐 처리만 하고 **화면은 닫지 않는다**.
///   기억하면 버튼도 표시도 없이 그 자리를 비운다.
///   (엔진 unconfirm 없음 + `model.confirm` 멱등 + UI 미렌더 = 삼중 보장으로 미기억 복귀 원천 차단.)
/// - **[저장]** = 이 화면 수정(분류·시점)을 그 시점 기준으로 반영(EditDiff → 이벤트 1개 = 이력 한 묶음).
///   저장해도 항목은 여전히 미기억일 수 있다 — **수정 ≠ 기억하기** (§2).
/// - **[취소]** = 수정 전부 버리고 닫기(아무것도 반영 안 됨).
/// - **[삭제하기]** = 기억 자체 삭제(tombstone, 보관함서 복구 가능).
struct DetailView: View {
    /// 자료 받아오기(§6) — 상세를 열 때 그 항목 것 **하나만** 받는다. 음성·사진 각각.
    @StateObject private var audioFetch = MediaFetch()
    @StateObject private var photoFetch = MediaFetch()
    let item: ResolvedItem
    @ObservedObject var model: InboxModel
    @Environment(\.dismiss) private var dismiss

    // draft — 편집 대상 필드. raw(원문)도 편집 대상(edit-policy.md §6 텍스트 층 가변).
    @State private var type: String?
    @State private var due: String?
    @State private var resurface: String?
    @State private var raw: String
    // 되풀이(반복) 설정 draft — 새 필드. 되풀이 분류일 때만 카드로 노출(Stage 2).
    @State private var recurUnit: String?
    @State private var recurAuto: String
    @State private var recurPaused: Bool
    /// 이번 회차 완료 상태(로컬 — 즉시 반영, isRemembered와 같은 이유로 stale item 대신 로컬로 든다).
    /// **⚠️ 2026-08-08 전수 점검에서 「안 고침」으로 판단한 자리다** — 다음에 같은 점검을 하는 사람이
    /// 조사를 되풀이하지 않게 남긴다. 초기값만 스냅숏이고 그 뒤로는 **낙관적 로컬 상태**다.
    /// 저장값으로 바꾸면 누른 즉시 반영이 사라져 **의도한 동작이 죽는다**(그래서 일부러 이렇게 뒀다).
    /// 판정 = `Recurrence.doneThisCycle`(마감 앵커 기준, 게이트와 동일 — 2026-08-03 #4).
    @State private var cycleDoneLocal: Bool

    /// **성역·분류 접힘 상태 (2차 압축 1단계).** 성역 카드가 접혔나 — **분류 카드의 아이콘 크기도 이걸 본다**
    /// (둘이 나란히 서므로 한 상태가 둘을 정한다). 기본 **접힘** — 압축이 목적이고 성역은 자주 보는 값이 아니다.
    ///
    /// **★ 이건 draft도 저장값도 아니다 — 화면 안에서만 뜻이 있는 표시 상태다.**
    /// 저장 없이 닫으면 사라져야 맞다(사양서 §0-A-2 닫힘 시험: 닫아서 사라져도 거짓이 되는 말이 없다).
    /// 그래서 `changes`에 안 들어가고 amber도 안 만든다. **저장 대상이 아니다.**
    @State private var metaCollapsed = true

    /// `metaTypeRow`의 실제 폭 — 분류 칸을 1/3로 묶는 데만 쓴다(위 `classColumnWidth`).
    /// **표시 상태이지 데이터가 아니다** — `changes`와 무관하고 amber도 안 만든다.
    @State private var metaTypeRowWidth: CGFloat = 0
    /// **draft의 기준선 = "화면이 아는 저장값".** `EditDiff`가 이것과 draft를 비교해 바뀐 칸을 낸다.
    /// `item`(스냅숏)을 직접 쓰지 않는 이유: **완료·취소가 이 화면 안에서 저장값을 옮기기 때문**이다.
    /// 그때 draft만 옮기고 기준선을 안 옮기면 **누른 것만으로 "저장하지 않은 수정이 있어요"** 가 뜬다.
    /// 둘을 같이 옮기면 화면은 낡지 않고 dirty도 거짓으로 켜지지 않는다 (2026-08-06 `가`).
    @State private var baseline: ResolvedItem

    /// 화면을 닫지 않고 기억하기 처리하므로(stale한 item 대신) 로컬로 상태를 든다.
    /// (엔진의 `confirmed`에 대응 — 개념·이름만 "기억하기"로 바뀜.)
    @State private var isRemembered: Bool
    @State private var showRememberConfirm = false
    /// 미기억 항목을 원칙으로 지정하고 저장할 때 "기억하기 자동 결정" 안내(원칙=살아있는 기억).
    @State private var showPrincipleAutoRemember = false
    /// [삭제하기] 재확인(공용 대화상자). 확인 시 삭제 + 화면 닫기.
    @State private var showDeleteConfirm = false
    /// 저장하지 않은 수정이 있는데 뒤로가기로 이탈하려 할 때 재확인(조용히 버리지 않음, 결정 1).
    @State private var showDiscardConfirm = false
    /// 규칙 1 안내(단일 버튼 정보 팝업) — N일 미루기 상한/차단, 저장 시 위반 차단에 공용으로 쓴다.
    @State private var noticeDialog: String?

    /// 원문 편집 포커스. 원문 밖을 누르면 내리고(키보드 숨김), 원문을 다시 누르면 그 위치에 커서·키보드 복귀.
    /// ⚠️ **`@FocusState`가 아니다** — `UIViewRepresentable`(`JustifiedTextEditor`)에는 `.focused`가
    /// 안 걸린다. Bool로 주고받고, 텍스트 뷰가 `becomeFirstResponder`/`resign`으로 따라온다.
    /// 밖을 눌러 내리는 세 자리(`rawFocused = false`)는 그대로 산다.
    @State private var rawFocused: Bool = false

    /// 지금 고치는 중인 시점 칸(없으면 nil). **기억하지 않는다** — `@State`라 화면과 함께 태어나고 죽는다.
    /// 화면을 다시 열면 언제나 닫힌 채다.
    @State private var editingTime: TimeField?
    /// **고치는 자리를 열 때의 값.** [취소]가 이것으로 되돌린다.
    /// 임시층이 아니다 — 편집은 그대로 draft에 담기고, 이건 "열 때 무엇이었나" 한 칸짜리 되돌리기 버퍼다.
    /// (임시층을 두면 값의 층이 셋이 되어 draft/저장값 하나로 정리해 둔 판정이 흐려진다.)
    @State private var editingBackup: String?
    /// **시각 토글을 껐을 때 그 시각을 기억해 둔다**(2026-08-09). 끄면 값에서 시각이 빠지지만
    /// 화면은 그것을 **흐리게 계속 보여주고**, 다시 켜면 **그 시각이 되살아난다.**
    /// 안 기억하면 껐다 켜는 것만으로 사람이 정한 시각이 사라져 기본값 09:00으로 덮인다 — 조용한 유실이다.
    /// 화면 안에서만 산다(`@State`) — 저장 형식은 안 바뀐다.
    @State private var rememberedTime: [TimeField: String] = [:]

    /// 시점 두 칸. `ClassSpec`의 칸과 1:1이고 **화면에 안 나오는 이름**이다(제목은 분류가 정한다).
    enum TimeField { case due, resurface }

    /// 원본 음성 "다시 듣기" 재생기(성역 카드).
    @StateObject private var audio = AudioPlayer()
    /// 뷰어에 무엇을 띄웠나 — nil이면 안 떠 있다(§0 22~26번 · `MediaViewer.swift`).
    @State private var viewerKind: MediaCardKind?
    // 자료 추가(3단계 · 2026-08-23) — `+` → 종류 시트 → 카메라/앨범.
    // ⚠️ **시트 위에 시트를 겹치지 않는다** — 종류 시트가 닫힌 **뒤** 여는 것이 `pendingAdd`의 몫이다.
    @State private var showAddSheet = false
    @State private var pendingAdd: MediaAddRoute?
    @State private var showAlbum = false
    // URL 자료(2026-08-24 · 설계 §3-Z) — 담는 시트 하나, 여는 자리 하나.
    @State private var showURLSheet = false
    /// 앱 안 보기로 열고 있는 URL. ⚠️ **`URL`은 `Identifiable`이 아니라** 감싸서 쓴다.
    @State private var openingURL: OpeningURL?
    /// **떼려고 확인을 묻고 있는 URL 자료의 id.** nil이면 안 묻고 있다(§3-Z-10).
    /// ⚠️ **팝오버가 아니라 여기서 묻는다** — 이 앱의 확인 대화상자는 다 상세가 갖는다.
    @State private var deletingURLAsset: String??

    /// ★★ **이 앱에서 「동작 줄이기」를 보는 첫 자리다** (2026-08-23 · 설계 §0 32번 · §3-I-6).
    ///
    /// ⚠️ **앞으로 애니메이션을 넣을 때마다 이 자리를 함께 본다** — 빠지면 **앱 안에서 동작 정책이 갈린다**
    /// (「어디는 되고 어디는 안 되는」이 된다). **첫 자리가 규칙이 되는 꼴이다.**
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(item: ResolvedItem, model: InboxModel) {
        self.item = item
        self.model = model
        _type = State(initialValue: item.type)
        _due = State(initialValue: item.due)
        _resurface = State(initialValue: item.resurface)
        _raw = State(initialValue: item.raw ?? "")
        _isRemembered = State(initialValue: item.confirmed)
        _recurUnit = State(initialValue: Recurrence.unit(item)?.rawValue)
        _recurAuto = State(initialValue: Recurrence.autoComplete(item).rawValue)
        _recurPaused = State(initialValue: Recurrence.isPaused(item))
        _cycleDoneLocal = State(initialValue: Recurrence.doneThisCycle(item, now: Date()))
        _baseline = State(initialValue: item)
    }

    private var changes: [String: String] {
        var c = EditDiff.changes(type: type, due: due, resurface: resurface, raw: raw, from: baseline)
        foldRecurChanges(into: &c)   // 되풀이 설정도 같은 [저장] 이벤트에 묶는다(새 필드).
        // **⛔ 임시(미확정)면 원문·분류만 커밋 대상이다** (edit-policy.md §1-A, 2026-08-14).
        // 둘 다 **식별** 층이라 열려 있고, 활용(시점·반복)은 화면에 아예 안 그려진다.
        // 카드를 안 그리므로 다른 칸이 담길 일은 없지만, **`dirty` 판정도 이걸 본다** —
        // 안 걸러내면 "화면에 없는 칸 때문에 나갈 때 경고가 뜬다"가 날 수 있다(예: 자동 분류가
        // 붙인 값이 draft 초기값과 어긋나는 경우).
        if !isRemembered { c = c.filter { $0.key == "raw" || $0.key == "type" } }
        return c
    }

    /// 되풀이 설정 draft를 원본과 비교해 바뀐 새 필드만 changes에 넣는다(값 안 지움 — 미설정은 빈 문자열).
    private func foldRecurChanges(into c: inout [String: String]) {
        let oldUnit = baseline.fields[Recurrence.unitKey] ?? ""
        if (recurUnit ?? "") != oldUnit { c[Recurrence.unitKey] = recurUnit ?? "" }
        let oldAuto = baseline.fields[Recurrence.autoKey] ?? Recurrence.AutoComplete.none.rawValue
        if recurAuto != oldAuto { c[Recurrence.autoKey] = recurAuto }
        let oldPaused = baseline.fields[Recurrence.pausedKey] == "true"
        if recurPaused != oldPaused {
            c[Recurrence.pausedKey] = recurPaused ? "true" : "false"
            // **끌 때 그 시점을 남긴다** — 놓침을 여기까지만 세고(꺼둔 기간은 안 셈), 켤 때 이만큼만
            // 회차를 전진시켜 이전 놓침을 보존한다(`Recurrence.resumeChanges`). 켤 때는 안 지운다 —
            // 지우는 건 전진을 실행한 쪽(로드 시 `resumeRecurrence`)의 몫이라야 기록이 유실되지 않는다.
            if recurPaused { c[Recurrence.pausedAtKey] = ItemSchedule.dayTimeString(Date()) }
        }
    }
    private var dirty: Bool { !changes.isEmpty }
    /// 본문을 전부 지운 상태(공백만 남은 것 포함). 내용 없는 기억은 만들지 않는다
    /// (사진 촬영이 본문 선행을 요구하는 규칙·capture의 원문 선행과 정합). → 저장 차단.
    private var rawEmpty: Bool { raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: 본문 순서 (2026-08-23 신설 — 자료 확장 ② 커밋 ①)

    /// 본문 안쪽 카드들의 **자리**. ⛔ **`id`가 고정이라 SwiftUI가 「같은 것이 옮겨간 것」으로 본다** —
    /// 그것이 이 배열의 존재 이유다(설계 §3-G-4 · §0의 29번).
    /// ⚠️ **원문(`rawSection`)은 이 배열 밖이다** — 바깥 `VStack`에 그대로 있다(제스처 그룹이 다르다).
    private enum BodySection: String, Identifiable, CaseIterable {
        case pausedBanner, missedBanner, overdueHiddenBanner, anchorBanner, leadClampedBanner
        case metaType, media, question, time, recurrence, history, decide
        var id: String { rawValue }
    }

    /// 지금 상태에서 **무엇이 어느 순서로 그려지나.**
    /// ⛔ **옛 코드와 같은 순서·같은 조건이다** — 커밋 ①은 화면을 바꾸지 않는다.
    /// **대조표(옛 → 새):**
    /// `if isRemembered { 배너 다섯 }` → 앞의 다섯 · `metaTypeRow` → `.metaType` ·
    /// `if let q = …question` → `.question` · `if isRemembered { time·recurrence·history }` → 셋 ·
    /// `else { decideRow }` → `.decide`.
    private var bodyOrder: [BodySection] {
        var out: [BodySection] = []
        if isRemembered {
            out += [.pausedBanner, .missedBanner, .overdueHiddenBanner, .anchorBanner, .leadClampedBanner]
        }
        out.append(.metaType)
        // ★ **보조 자료 카드의 자리**(설계 §0 3번 · §3-F-2 · §3-K-1) — 사용자: *"카드의 위치는 항상 성역
        //   아래이며, 「기억하기」 전까지는 「기억하기」 버튼보다 아래에 두기로 하자."*
        //
        //   ⚠️ **「성역 바로 다음」이 아니라 「성역보다 아래」다**(2026-08-23 사용자 정정).
        //   **재확인 질문은 성역·분류와 같은 일을 한다** — *"이 기억이 무엇인가"*(식별 층).
        //   그 셋을 붙여 두고 **자료는 그 아래**다. 자료는 「보는 것」이라 성격이 다르다(설계 §3-2의 구분).
        //
        //   **확정: 성역+분류 → 재확인 질문 → 보조 자료 → 시간 설정…**
        //   **미확정: … → 재확인 질문 → [삭제하기]·[기억하기] → 보조 자료(맨 끝).**
        //   ⚠️ 그래서 **확정되는 순간 카드가 위로 올라간다** — 그 움직임에 애니메이션을 거는 것이 커밋 ②-2다.
        if let q = item.fields["question"], !q.isEmpty { out.append(.question) }
        if isRemembered {
            out.append(.media)
            out += [.time, .recurrence, .history]
        } else {
            out.append(.decide)
            out.append(.media)
        }
        return out
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                rawSection
                // 원문 밖 전체 — 빈 여백이든 버튼·메뉴·날짜·다시듣기든 누르면 키보드를 내린다(원문 편집 종료).
                // simultaneousGesture라 컨트롤 동작과 **함께** 발화하고(버튼은 정상 동작), rawSection은
                // 이 그룹 밖이라 원문 탭은 방해받지 않는다(탭하면 그 위치에 커서·키보드 복귀 — .focused 바인딩).
                VStack(alignment: .leading, spacing: 14) {
                    // **★ 배너 다섯은 2차 압축이 건드릴 자리가 아니다 (2026-08-11).**
                    // 압축은 **성역·분류 두 카드의 배치**만 바꾼다. 이 다섯은 그 두 카드 **안에 없고**
                    // 전부 `saved`/`savedType`을 본다(아래 MARK의 규약). 계측 단계에서 다섯을 하나씩 확인했다 —
                    // 옮기지도, 입력을 바꾸지도 말 것. **G-7이 검사하는 것이 정확히 이 다섯의 입력이다.**
                    // **★ 임시(미확정)면 「판단에 필요한 것」만 그린다** (edit-policy.md §1-A, 2026-08-14).
                    //
                    // 회색으로 다운시키지 않고 **아예 안 그린다** — 사용자 결정. 그래서
                    // 「어느 제목을 회색으로 할까」·「분류가 정하는 제목을 임시엔 무엇으로 할까」가
                    // **원천적으로 사라진다**(분류마다 제목이 다르다: 마감/언제/일시 — `ClassRegistry.title`).
                    //
                    // **보이는 것:** 원문(위) · 성역(음성·사진·지도·수집 시각·기기·방식) · 분류 · 재확인 질문.
                    // **안 보이는 것:** 배너 다섯 · 시간 설정 · 반복 설정(→ **이번 회차 완료도 함께 사라진다**) ·
                    //   수정 이력 · 하단 필수 바(`bottomBar`는 `safeAreaInset`에서 갈린다).
                    //
                    // ⚠️ **배너 다섯은 G-7이 검사하는 자리다**(아래 MARK 규약) — 입력을 바꾸지 않고
                    // **그릴지 말지만** 갈랐다. 확정 항목에서는 다섯이 그대로 같은 입력(`saved`)을 본다.
                    // ★★ **순서를 배열로 든다** (2026-08-23 · 자료 확장 ② 커밋 ①).
                    //
                    // ⛔ **이 커밋에서 화면 결과는 바뀌지 않는다.** 아래 `bodyOrder`가 내는 순서·조건은
                    //    옛 코드(`if isRemembered { 배너 다섯 } · metaTypeRow · question · if/else`)와 **같다.**
                    //
                    // **왜 바꾸나:** 다음 커밋에서 **보조 자료 카드**가 들어오는데, 그 카드는
                    // **자리가 상태에 따라 다르다** — **확정이면 성역 바로 아래**, **미확정이면 본문 맨 끝**
                    // ([기억하기] 아래 · `media-expansion-design.md` §3-F-2).
                    // 두 자리에 **각각 두면**(`if`/`else`) SwiftUI가 **다른 뷰로 보고 사라졌다 나타난다** —
                    // 랩 실측에서 **빈 프레임 셋**이 찍혔다(설계 §3-G-4의 A안).
                    // **고정 `id`를 가진 배열이라야 「같은 것이 옮겨간다」로 보고 미끄러진다**(B안 · 연속 사다리).
                    ForEach(bodyOrder) { s in
                        switch s {
                        case .pausedBanner:       pausedBanner   // 되풀이 꺼둠이면 상단에 바로(잊으면 약을 안 챙긴다 — "지금 도느냐")
                        case .missedBanner:       missedBanner   // N일 놓침 주의(§4)
                        case .overdueHiddenBanner: overdueHiddenBanner   // 늦었는데 숨겨진 것(D) — 언제 돌아오는지
                        case .anchorBanner:       anchorBanner   // 되풀이인데 회차 시각(마감) 없으면 안내(조용히 안 도는 것 방지)
                        case .leadClampedBanner:  leadClampedBanner   // 회차 전진이 미리 알림을 당겼으면 말한다((c)) — 할 일 없는 통지라 맨 아래
                        case .metaType:           metaTypeRow    // 성역 2/3 + 분류 1/3 나란히(2차 압축 1-C) — 임시에도 보인다(식별)
                        case .media:              mediaSection
                        // 재확인 질문은 임시에도 보인다 — 자동 분류가 "이게 무엇인가"를 되물은 것이라 **식별 층**이다.
                        case .question:
                            if let q = item.fields["question"], !q.isEmpty { questionSection(q) }
                        case .time:               timeSection          // '시간 설정'(기준 날짜) — 위 (첫 카드 위치 통일)
                        case .recurrence:         recurrenceSection    // '반복 설정'(주기·자동완성·꺼두기) — 아래
                        case .history:            historyRow
                        case .decide:             decideRow            // [삭제하기] · [기억하기] — 살릴지 버릴지 결정을 내민다
                        }
                    }
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { rawFocused = false })
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Palette.bg.ignoresSafeArea())
        // **임시(미확정)면 하단 필수 바를 아예 안 그린다** (edit-policy §1-A) — 그 자리 대신
        // 본문 안에 `decideRow`([삭제하기]·[기억하기])가 들어간다. [저장]이 없으므로 「저장하지 않은
        // 수정이 있어요」 줄도 함께 사라진다(그 뜻은 `backTapped()`의 확인 대화상자가 맡는다).
        .safeAreaInset(edge: .bottom) { if isRemembered { bottomBar } }
        .navigationTitle("기억")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // 저장 없이 뒤로가기로 이탈하는 조용한 경로를 막는다(결정 1). 기본 back(스와이프 포함)을 숨기고
        // 커스텀 back이 dirty면 확인 대화상자, 아니면 즉시 닫기. [취소]는 명시적 버림이라 그대로 둔다.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button { backTapped() } label: { Label("기억", systemImage: "chevron.backward") }
                    .tint(Palette.accent)
            }
        }
        #endif
        .overlay { if showRememberConfirm { rememberDialog } }
        .overlay { if showPrincipleAutoRemember { principleAutoRememberDialog } }
        .overlay { if showDeleteConfirm { deleteDialog } }
        .overlay { if showDiscardConfirm { discardDialog } }
        // **URL을 뗄까요** — 정본이 「되돌리기 없음」이라 **한 번 묻는다**(§3-Z-10 · 사용자 결정).
        .overlay { if deletingURLAsset != nil { deleteURLDialog } }
        // ★ **`ignoresSafeArea()`가 핵심이다**(2026-08-10 — 크기 변함의 진짜 원인).
        //
        // **원인은 달력이 아니라 하단 바였다.** 날짜를 처음 누르면 `dirty`가 켜지고 하단 바에
        // 「저장하지 않은 수정이 있어요」 **줄이 하나 생긴다** → `safeAreaInset(edge:.bottom)`이 커진다 →
        // **ScrollView가 쓸 수 있는 높이가 줄어든다** → 그 위에 얹힌 이 대화상자에게 주어지는 높이도 줄어
        // **달력이 「채우기」를 포기하고 제 크기로 떨어진다.**
        //
        // **증거(스크린샷 두 장 실측):** 큰 달력 쪽엔 amber 띠가 **없고**, 작은 달력 쪽엔 **y 725~740pt에 있다.**
        // 이 하나로 셋이 다 설명된다 — ⓐ 날짜를 누를 때만 생김(그때 `dirty`가 처음 켜짐)
        // ⓑ 한 번 작아지면 그대로(`dirty`는 계속 켜져 있음) ⓒ 폭을 넓힐수록 변동이 작아짐
        // (폭이 넓으면 «제 크기»가 «채운 크기»에 가까워 낙차가 작다).
        //
        // → **대화상자를 안전 영역 밖으로 빼서 하단 바와 무관하게 만든다.** 그러면 주어지는 높이가 안 변한다.
        // (다른 대화상자들은 글자만 담아 높이가 안 흔들리므로 굳이 안 건드린다.)
        .overlay { if let f = editingTime { timeDialog(f).ignoresSafeArea() } }
        .overlay { if let msg = noticeDialog { noticeDialogView(msg) } }
        // ★ **「내려받는 중」** — 「미리보기 다시 받기」를 누른 동안 (2026-08-26).
        //   ⚠️ **뷰어와 **같은** 표시다**(`DownloadToast` 한 자리) — 꼴이 갈리지 않게.
        //   ⚠️ **위 여백은 짐작이다** — 상세에는 뷰어의 「n / n」이 없으므로 더 위로 올렸다.
        //   **화면에서 판정받을 값이다**(계측 규칙 7).
        .overlay { if !model.refetchingURLs.isEmpty { DownloadToast(topPadding: 24) } }
        // **자료 추가** — 카드의 `+` → 종류 시트 → (사진 찍기 | 앨범에서 고르기).
        // ⚠️ 시트가 **닫힌 뒤** 다음 화면을 연다(`onDismiss`) — 겹쳐 띄우면 iOS가 둘째를 무시한다.
        #if os(iOS)
        .sheet(isPresented: $showAddSheet, onDismiss: {
            switch pendingAdd {
            case .camera:
                // ⛔ **커버로 감싸지 않는다 — 모달로 띄운다**(2026-08-24 · `SystemCamera` 머리주석).
                // ⚠️ **위치를 안 넘긴다** — 수집 화면은 위치를 함께 박지만(§5 Stage 3) 상세에는
                //    그 장치가 없다. **추가로 찍은 사진에는 EXIF 위치가 없다**(⏸ 후속 · §3-Y-9).
                SystemCamera.present { img in
                    if let temp = PhotoStore.saveCaptured(img, location: nil,
                                                          sessionId: UUID().uuidString) {
                        model.addPhoto(to: item.id, temp: temp)
                    }
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
        // **URL 담기** — 파일이 없으므로 확정할 것도 없다. 값이 그대로 op으로 붙는다.
        .sheet(isPresented: $showURLSheet) {
            URLAddSheet { model.addURL(to: item.id, url: $0) }
        }
        // **앱 안 보기** — 닫으면 바로 이 화면으로 돌아온다(사파리로 나가지 않는다).
        .sheet(item: $openingURL) { o in
            SafariSheet(url: o.url).ignoresSafeArea()
        }
        .sheet(isPresented: $showAlbum) {
            // 앨범에서 온 파일은 **원본 EXIF를 품고 온다** — 위치가 있으면 그대로 살아 있다.
            AlbumPicker { temp in model.addPhoto(to: item.id, temp: temp) }
        }
        #endif
        // **뷰어** — 네모를 누르면 전체 화면으로 연다(§0 22~26번).
        // ⚠️ `fullScreenCover`는 iOS 전용이라 맥은 시트로 연다 — **판정·내용은 같은 코드**다
        //    (`photoRow`가 `#if`를 걷어낸 것과 같은 결: 갈라 두면 한쪽만 고쳐진다).
        #if os(iOS)
        .fullScreenCover(item: $viewerKind) { k in
            // ⛔ **`item`이 아니라 최신 항목이다**(2026-08-24 결함 수정) — 카드만 최신을 받고
            //    뷰어는 낡은 값을 받고 있었다. 그래서 **뷰어를 한 번 열었다가 상세로 나와 사진을 더 붙이면
            //    카드의 개수는 늘는데 뷰어에는 새 사진이 없었다**(사용자가 잡았다).
            //    ★ **C에서 카드는 고치고 뷰어는 빠뜨린 자리다** — 같은 값을 두 곳에서 넘기면 한쪽만 고쳐진다.
            MediaViewer(item: model.current(item.id) ?? item, kind: k, audio: audio) { viewerKind = nil }
        }
        #else
        .sheet(item: $viewerKind) { k in
            MediaViewer(item: model.current(item.id) ?? item, kind: k, audio: audio) { viewerKind = nil }
                // ⛔ **`min`만 주면 창이 사진을 따라 커진다** — 맥 시트는 **내용 크기로 열린다.**
                //    그래서 **가로 사진과 세로 사진에서 창 높이가 달랐고**, 아래에 붙은 썸네일 줄이
                //    그만큼 **오르락내리락했다**(2026-08-26 사용자가 잡았다).
                //    ✅ **`ideal`을 줘서 창을 못 박는다** — 사진이 무엇이든 같은 창이다.
                //    ⚠️ **iOS에는 없던 일이다** — 거기는 `fullScreenCover`라 화면에 고정돼 있다.
                //    ⚠️ **980×760은 재서 정한 값이 아니다** — 「적당한 크기」로 고른 값이다(사용자 판정 대기).
                .frame(minWidth: 520, idealWidth: 980, minHeight: 420, idealHeight: 760)
        }
        #endif
        .animation(.easeInOut(duration: 0.15), value: showRememberConfirm)
        .animation(.easeInOut(duration: 0.15), value: showPrincipleAutoRemember)
        .animation(.easeInOut(duration: 0.15), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.15), value: showDiscardConfirm)
        .animation(.easeInOut(duration: 0.15), value: noticeDialog)
        .animation(.easeInOut(duration: 0.15), value: editingTime)
    }

    /// 커스텀 뒤로가기: 저장 안 한 수정이 있으면 확인, 없으면 즉시 닫기.
    /// **보조 자료 카드** — 자료를 성역에서 뗀 카드(§0 0-1·0-2 · `MediaCard.swift`).
    ///
    /// ⚠️ **`item`이 아니라 최신 항목을 넘긴다** — 자료를 붙인 직후에 카드가 다시 그려져야 한다
    /// (값으로 받은 `item`은 그때 낡아 있다).
    ///
    /// ⚠️ **본문 `switch` 안에 인라인으로 두면 안 된다** — 2026-08-25에 인자가 하나 늘자
    /// **타입 검사가 시간을 넘겼다**(`unable to type-check this expression in reasonable time`).
    /// 이 파일의 다른 조각들(`metaTypeRow`·`timeSection`)처럼 **계산 속성으로 뺀다.**
    ///
    /// ⛔ **URL만 뷰어가 아니다** — **앱 안 보기**로 연다(§3-Z-2 G). 그래서 URL에는 뷰어의 `‹` `›`가 없다.
    /// ⚠️ **URL이 둘 이상일 때 고르는 목록은 카드가 띄운다**(§3-Z-9) — 팝오버가 **누른 네모에 붙어야**
    /// 해서 자리가 거기다. 상세는 「열기」만 받는다.
    @ViewBuilder private var mediaSection: some View {
        MediaCard(item: model.current(item.id) ?? item,
                  audioFetch: audioFetch,
                  photoFetch: photoFetch,
                  onTap: { viewerKind = $0 },
                  onAdd: { openAddSheet() },
                  onOpenURL: openURL(_:),
                  onDeleteURL: { deletingURLAsset = $0 },
                  onRefetchURL: { model.refetchURLPreview($0) })
    }

    /// `+` 시트를 연다 — iOS만.
    private func openAddSheet() {
        #if os(iOS)
        showAddSheet = true
        #endif
    }

    /// **URL을 지우기 전 확인** — 문구는 사용자가 골랐다(2026-08-25 · 항시 규칙 6):
    /// **「이 URL을 기억에서 지웁니다. 되돌릴 수 없어요.」** · 버튼 **「지우기」**.
    ///
    /// ## ⛔ 옛 꼴이 뒤집혔다 — **「뗍니다 / 떼기」였다** (2026-08-25 사용자)
    /// **내가 고른 이유(그대로 남긴다):** `edit-policy.md` ③이 자료 삭제를 *"기억에서 떼는 것"*으로
    /// 정의하고, **앱의 「삭제」는 항목을 버리는 것**이라 **같은 말을 쓰면 항목 삭제로 읽힌다**(기록 규칙 5).
    /// **사용자가 뒤집은 이유:** *"아무도 웹 페이지가 지워질 것이라고 생각하지 않을 거야."*
    ///
    /// ★★ **그리고 사용자 쪽이 맞았다 — 「지우기」는 이미 이 앱의 말이다.**
    /// `timeRow`의 **「지우기」가 「한 칸의 값을 없앤다」**는 뜻으로 쓰이고 있고(**색도 이 코랄이다**),
    /// **이 구현이 정확히 그것이다**(`set url.<자료id>=` — 칸을 비운다).
    /// **「삭제」(항목을 버린다)와 뜻이 안 겹친다** — 걱정했던 혼동이 애초에 없었다.
    /// ⚠️ **항시 규칙 6을 거꾸로 쓴 자리다** — 새 말을 짓는 대신 **이미 있는 말을 찾아야 했다.**
    private var deleteURLDialog: some View {
        ConfirmDialog(
            title: "이 URL을 기억에서 지웁니다. 되돌릴 수 없어요.",
            confirmTitle: "지우기", confirmTint: Palette.overdue,
            onCancel: { deletingURLAsset = nil },
            onConfirm: {
                if let a = deletingURLAsset { model.removeURL(from: item.id, assetId: a) }
                deletingURLAsset = nil
            })
    }

    /// URL 하나를 **앱 안 보기**로 연다(§3-Z-2 G).
    /// ⚠️ **함수로 뺐다** — `MediaCard(...)` 안에 인라인으로 두니 **타입 검사가 시간을 넘겼다**
    /// (2026-08-25 · `error: the compiler is unable to type-check this expression in reasonable time`).
    private func openURL(_ raw: String) {
        #if os(iOS)
        guard let v = URLAsset.normalized(raw), let u = URL(string: v) else { return }
        openingURL = OpeningURL(url: u)
        #endif
    }

    private func backTapped() {
        if dirty { showDiscardConfirm = true } else { dismiss() }
    }

    // MARK: 원문 — 상세 진입 시 바로 편집 가능(별도 진입 없음, edit-policy.md §2-A).
    // 텍스트 층 가변(§6). 고치면 하단 [저장]이 활성(수정 감지). [저장]=전체 수정 커밋(≠ 기억하기, §2).
    // (명시적 [수정하기]/[수정 완료] 진입 방식을 시도했다가 되돌림 — 바로 편집이 낫다는 판단, 2026-07-30.)

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("원문")
            // ⛔ **옛 서술(부분적으로 뒤집혔다 · 2026-08-21):** *"TextEditor 대신 axis:.vertical TextField —
            // 내용 따라 높이가 늘고 **자체 스크롤이 없어** 바깥 ScrollView가 그대로 스크롤된다"*.
            // **6줄까지는 그대로다**(안 넘치면 스크롤을 켜지 않는다). **넘으면 칸 안에서 스크롤한다** —
            // 긴 원문에서 칸이 화면을 다 먹어 성역·분류가 안 보이는 것을 사용자가 잡았다.
            // ✅ **유지되는 것:** 6줄 이내에서는 바깥이 스크롤하고, 높이는 내용만큼 늘어난다.
            // **편집 중에도 좌우 맞춤**(2026-08-21 사용자 요구) → `JustifiedTextEditor`(UITextView).
            // 옛 `TextField(axis:.vertical)`의 성질은 지킨다 — 자체 스크롤 없음·내용만큼 높이 늘어남.
            // ⚠️ 맥은 좌우 맞춤이 없으므로 옛 방식 그대로 둔다.
            // ⚠️ `Group`으로 감싼 이유: `#if`가 수식어 사슬을 끊는다(아래 여백·테두리가 둘 다에 걸려야 한다).
            Group {
                #if os(iOS)
                JustifiedTextEditor(text: $raw, isFocused: $rawFocused,
                                    style: .body, color: Palette.textPrimary)
                #else
                TextField("원문", text: $raw, axis: .vertical)
                    .font(.body)
                    .foregroundStyle(Palette.textPrimary)
                    .textFieldStyle(.plain)
                #endif
            }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Palette.bg, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Palette.border))
            if rawEmpty {
                // 내용 없는 기억 방지 — 비었으면 알린다(하단 [저장]도 비활성).
                Text("본문은 비울 수 없어요").font(.caption2).foregroundStyle(Palette.overdue)
            }
        }
        .padding(14).card()
    }

    // MARK: 성역 + 분류 나란히 (2차 압축 1-C)

    /// **성역 2/3 · 분류 1/3을 한 줄에.** 위 정렬로 붙이고 **각자 자연 높이**를 갖는다.
    ///
    /// **왜 `HStack(alignment: .top)`이고 빈칸을 안 채우나 (계측):** 두 카드의 크기 관계가 **상태에 따라 뒤집힌다.**
    /// 성역 접힘 ~92pt vs 분류 접힘 ~95pt → **분류가 크다.** 성역 펼침은 사진·지도가 있으면 **최대 ~617pt**
    /// vs 분류 펼침 ~122pt → **성역이 495pt 크다.** 어느 쪽에 맞춰 늘리든 **반대 상태에서 깨진다.**
    /// → 빈칸은 "채워야 할 것"이 아니다. (2단계로 사진·지도가 「수집 원본 자료」로 빠지면 빈칸이 499 → 48pt로 줄어든다.)
    ///
    /// > **★ 정정 (2026-08-12 맥북, 시뮬레이터 9단계 실측).** 위의 **「성역 접힘 ~92 vs 분류 접힘 ~95 →
    /// > 분류가 크다」는 지금 사실이 아니다.** **접힘에서 두 카드는 높이·밑변이 정확히 같다(어긋남 0pt).**
    /// > Large 95.0 / XL 102.3 / XXL 109.3 / XXXL 116.3pt — **네 단계 모두 위·아래가 픽셀 단위로 동일**하다
    /// > (성역 안 3열·분류 안 3열이 서로 일치했고, 두 카드 사이 빈틈이 배경으로 확인돼 별개 카드임도 확인).
    /// > **`e01b041`(1-A 분류 카드를 세로 배치로)이 그 3.3pt를 없앤 것으로 보인다.**
    /// > 옛 값을 지우지 않고 남기는 이유: 그때의 판단 근거였고, 「무엇이 언제 바뀌었나」가 그 대비로만 보인다.
    /// >
    /// > **결론(빈칸을 안 채운다)은 그대로 유효하다** — 근거가 접힘이 아니라 **펼침**으로 옮겼을 뿐이다.
    /// > 펼침 실측: 성역 141.7 → 393pt 이상 / 분류 124.7 → 204.7pt. **밑변 차이 Large 17.0 → AX4 149.3pt.**
    /// > 성역이 **2.8배** 자라는 동안 분류는 **1.6배**만 자란다. 늘려 맞추면 그만큼이 통째로 빈칸이 된다.
    /// > (가장 큰 한 방은 **XXL에서 「이 값은 어떤 편집으로도 바뀌지 않아요」가 두 줄로 넘어가는 것** —
    /// >  그 구간만 +31.6pt로 다른 구간 +12~14pt의 두 배가 넘는다. 사용자가 화면에서 판정.)
    /// >
    /// > ⚠️ **AX5 성역은 못 쟀다** — 하단 바에 가려 밑변이 화면에 없다. **최소 381pt 이상**까지만 말할 수 있다.
    ///
    /// **왜 카드 둘(A 틀)이고 한 카드 좌우 분할(B 틀)이 아닌가:** B가 폭을 18.7pt 더 주지만 **살 것이 없다** —
    /// 세로 배치 분류는 최악 「주차 위치」가 77.2pt(화면 실측 ~80.3)이고 A가 이미 **91.3pt**를 준다.
    /// 그리고 **탭 표적이 카드 경계로 갈린다** — 성역 카드 = 접힘 토글, 분류 카드 = 메뉴. B는 한 카드가
    /// 좌·우에서 다르게 반응한다. 탭 튐 버그(2026-07-21)가 인접 표적 오조작이었다. 게다가 2단계의
    /// 「수집 원본 자료」는 A면 **카드 하나 추가**로 끝난다.
    ///
    /// **비율은 폭을 재서 나눈다** — `.padding(16)`이 `ScrollView` 안쪽에 있어 `containerRelativeFrame`은
    /// 컨테이너를 402pt로 잡아 어긋난다. 그래서 이 줄의 실제 폭을 읽어 `(폭 − 12) / 3`을 분류 칸에 준다.
    /// `card()`가 이미 `maxWidth: .infinity`라 성역은 남은 폭을 저절로 채운다(안 묶으면 1:1로 갈린다).
    private var metaTypeRow: some View {
        HStack(alignment: .top, spacing: 12) {
            metaSection
            typeSection.frame(width: classColumnWidth)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { metaTypeRowWidth = $0 }
    }

    /// 분류 칸 폭 = (줄 폭 − 간격 12) / 3. **재기 전(0)에는 안 묶는다** — `nil`이면 `frame(width:)`가
    /// 제약을 안 걸어 첫 프레임에 카드가 찌그러지지 않는다(그 한 프레임만 1:1로 보이고 곧 자리를 잡는다).
    private var classColumnWidth: CGFloat? {
        guard metaTypeRowWidth > 0 else { return nil }
        return (metaTypeRowWidth - 12) / 3
    }

    // MARK: 메타 — 최초 수집 정보(불변 성역, §4-1·§7). 언제·기기·방식.

    /// **⚠️ 2026-08-08 전수 점검에서 「안 고침」** — 스냅숏 `item`을 읽지만 여기 나오는 것은
    /// 캡처 시각·방식·기기·음성·사진처럼 **어떤 편집으로도 안 바뀌는 필드**다(화면이 그렇게 말하고도 있다).
    /// 낡을 여지가 없으므로 `saved`로 옮길 이유가 없다.
    ///
    /// **★ 2차 압축(2026-08-11)에서 지켜야 할 것 — `saved`로 바꾸지 말 것. 접힘 줄도 `item`을 읽는다.**
    /// 이 카드를 접고 나중에 사진·지도를 「수집 원본 자료」로 떼어내면, 옆에 선 분류 카드가 draft를 보는 것과
    /// 대비돼 "여기도 최신값을 봐야 하지 않나"는 생각이 들기 쉽다. **바꾸면 「성역」이라는 말이 거짓이 된다** —
    /// 불변인 값을 **가변 출처**로 읽는 것이고, 화면은 바로 아래에서 *"이 값은 어떤 편집으로도 바뀌지 않아요"*
    /// 라고 말하고 있다. 위 2026-08-08 판단이 그대로 유효하다. **접힘 머리 줄의 종류 아이콘도 같은 이유로 `item`.**
    private var metaSection: some View {
        let when = "\(item.date ?? "") \(item.time ?? "")".trimmingCharacters(in: .whitespaces)
        let device = CaptureDevice.label(source: item.source, createdDeviceId: item.createdHLC.deviceId,
                                         stored: item.fields["device"])
        let card = VStack(alignment: .leading, spacing: 7) {
            metaHeaderRow(asButton: !metaCollapsed)                                 // 제목 + (접힘) 종류 아이콘 + 펼침 표시
            metaRow("clock", when.isEmpty ? "(시각 없음)" : when)                    // 언제 — 접혀도 보인다
            metaRow("iphone", device)                                               // 기기 — 접혀도 보인다
            if !metaCollapsed {
                metaRow(SourceIcon.symbol(item.source), Self.sourceLabel(item.source))   // 방식
                // ⛔ **원본 음성·사진 줄은 2026-08-23에 여기서 뺐다** — 자료는 이제 **보조 자료 카드**에 있다
                //    (설계 §0 1번). 성역에 남는 것은 **수집 사실**(시각·기기·방식)뿐이다.
                Text("이 값은 어떤 편집으로도 바뀌지 않아요").font(.caption2).foregroundStyle(Palette.textTertiary)
            }
        }
        .padding(14).card()

        // **접힘이면 카드 전체가 표적, 펼침이면 머리 줄만** — 아래 `metaHeaderRow` 주석의 경위 참조.
        return Group {
            if metaCollapsed {
                Button { toggleMeta() } label: { card }.buttonStyle(.plain)
            } else {
                card
            }
        }
    }

    private func toggleMeta() {
        withAnimation(.easeInOut(duration: 0.18)) { metaCollapsed.toggle() }
    }

    /// **접힘/펼침 머리 줄 (2차 압축 1단계).** 제목 · (접힘일 때) 종류 아이콘 요약 · 펼침 표시.
    ///
    /// **접힘은 세 줄이다** — 이 머리 줄 + 시각 + 기기. **시각·기기의 폰트를 안 줄인다**(둘 다 `.callout` 16).
    /// 두 줄로 줄이려면 시각·기기를 @12로 내려야 하는데(계측 194.1pt), 그러면 ⓐ 수집 시각이 읽기 어려워지고
    /// ⓑ **같은 값이 접으면 12pt·펴면 16pt로 크기가 변한다.** G-11에서 지킨 원칙(화면이 보여준 값과 붙는 값이
    /// 같아야 한다)과 인접한 불일치다. 그리고 ⓒ **줄여서 아낀 30.6pt 중 6.1pt는 애초에 못 쓴다** —
    /// 나란히 서면 행 높이가 `max(성역, 분류)`이고 두 줄안에서는 **분류(72.3)가 높이를 정해버린다.**
    /// 접기의 실익은 사진 있는 항목(616.8 → 96.8 = **520pt**)에서 나오고, 24.5pt는 그 옆에서 5%다.
    ///
    /// **표적은 상태에 따라 다르다 — 접힘: 카드 전체 · 펼침: 이 줄만.** 그래서 접힘에서는 이 줄이
    /// **버튼이 아니라 그림**이다(안에 버튼을 또 두면 바깥 표적과 겹친다).
    ///
    /// **★ 처음 판단을 계측이 뒤집었다 (2026-08-11, 지우지 말 것).**
    /// 처음엔 *"두 상태에서 표적이 같아야 예측 가능하다"* 는 **일관성**을 이유로 **머리 줄만** 표적으로 잡았다.
    /// 그런데 접근성 좌표로 재 보니 이 줄이 **342 × 14pt**였다 — 애플 권장 최소 44pt에 한참 못 미치고,
    /// 바로 아래 시각 줄과 붙어 있어 **스치면 옆이 눌린다**(탭 튐 버그 2026-07-21이 정확히 그 문제였다).
    /// 여백으로 44pt를 만들면 카드가 **30pt 커져 압축을 되돌린다.**
    ///
    /// **계측이 공짜 답을 알려줬다:** **접힘 상태의 카드 안에는 누를 것이 하나도 없다** —
    /// 원본 음성 재생·지도 열기 버튼은 **펼침에서만** 나타난다. 그래서 접힘에서는 카드 전체(**~92pt**)를
    /// 표적으로 줘도 **겹칠 대상이 없고 높이 대가가 0이다.** 펼침에서는 안에 버튼이 있으니 이 줄만 쓴다.
    ///
    /// **비대칭이 방향에도 맞다** — 펼치기는 자주 하고 표적이 크며, 접기는 드물게 하고 신중해진다.
    /// → **교훈: 표적 크기는 「일관성」보다 「그 상태에 무엇이 들어 있나」가 정한다.** 재 보기 전엔 안 보였다.
    ///
    /// 애니메이션은 **의도한 탭**에만 붙는다(탭 튐 버그의 「우발적 선택 무애니메이션」과 구분되는 자리다).
    /// **펼침 표적도 재서 고쳤다 (2026-08-11).** 이 줄의 실제 높이는 **14pt**다(접근성 좌표 `342 × 14`) —
    /// 접힘을 카드 전체로 바꿔도 **펼침에서 접는 표적은 그대로 14pt**로 남는다. 44pt에 한참 못 미친다.
    ///
    /// **여백으로 키우면 카드가 30pt 커진다**(압축을 되돌린다). 그래서 **레이아웃은 그대로 두고 표적만** 키웠다 —
    /// 위아래 여백 15를 주고 그 크기로 표적을 잡은 뒤 **같은 만큼 음수 여백으로 되돌린다.**
    /// → 표적 **342 × 44**, 카드 높이 증가 **0pt**.
    ///
    /// **왜 안전한가 — 접힘에서와 같은 근거다.** 늘어난 표적이 덮는 위쪽 15pt는 **카드 자신의 여백**(14)이고,
    /// 아래쪽 15pt는 **시각·기기 줄**인데 그 둘은 `metaRow` = **그냥 글자**다(누를 것이 아니다).
    /// 펼침에서 실제로 누를 수 있는 것(원본 음성 재생·지도 열기)은 **한참 아래**에 있어 겹치지 않는다.
    /// → **표적 크기는 「그 자리에 무엇이 들어 있나」가 정한다**는 같은 규칙이 두 번째로 답을 줬다.
    @ViewBuilder private func metaHeaderRow(asButton: Bool) -> some View {
        if asButton {
            Button { toggleMeta() } label: {
                metaHeaderLabel
                    .padding(.vertical, 15)
                    .contentShape(Rectangle())
                    .padding(.vertical, -15)
            }
            .buttonStyle(.plain)
        } else {
            metaHeaderLabel
        }
    }

    private var metaHeaderLabel: some View {
        HStack(spacing: 8) {
            sectionLabel("최초 수집 · 성역")
            if metaCollapsed { metaKindIcons }
            Spacer(minLength: 4)
            Image(systemName: metaCollapsed ? "chevron.down" : "chevron.up")
                .font(.caption).foregroundStyle(Palette.textTertiary)
        }
        .contentShape(Rectangle())   // Spacer 빈칸까지 표적에 넣는다(줄 전체가 눌린다)
    }

    /// 접힘일 때만 보이는 **종류 요약** — 접어서 감춘 줄이 "무엇이 있었나"를 아이콘으로 남긴다. **이제 하나다.**
    ///
    /// ⛔ **2026-08-23에 자료 둘(`mic.fill`·`photo.fill`)을 뺐다** — 자료가 **보조 자료 카드**로 나갔으므로
    /// **성역은 자료를 안 갖는다. 아이콘이 남으면 거짓말이다**(사용자 결정 · 설계 §3-J-4).
    /// 그리고 자료 카드는 **접힘 없이 항상 보이므로** 그 정보는 카드가 이미 말한다.
    ///
    /// ✅ **방식은 남는다 — 이 파일이 옛날부터 그 구분을 적어 두고 있었다:**
    /// *"**뜻이 겹치지 않게 골랐다:** 방식은 `SourceIcon`(음성 수집이면 `waveform`)이고
    /// **원본 음성 보관은 `mic.fill`**이다. 둘은 다른 사실이다 — *「음성으로 들어왔다」*와
    /// *「녹음 파일이 남아 있다」*."* **앞엣것은 성역(`source`)이고 뒤엣것이 자료다.**
    ///
    /// ⚠️ **옛 서술(낡았다):** *"**최대 3개.** (조건부인 것은 `audio`·`photo` 둘이고 방식은 항상 1개다 —
    /// 계측에서 최대 3개로 확정.)"* — **이제 조건부가 없고 항상 하나다.**
    /// ✅ **요약의 뜻은 그대로다** — 방식 줄은 **펼침에만 있어서**(`if !metaCollapsed`) 접힘에서 감춰진다.
    private var metaKindIcons: some View {
        Image(systemName: SourceIcon.symbol(item.source))
            .font(.caption).foregroundStyle(Palette.textTertiary)
    }

    private func metaRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Palette.textTertiary).frame(width: 16)
            Text(text).font(.callout).foregroundStyle(Palette.textPrimary)
        }
    }

    /// ⏸ **지금은 아무도 안 부른다 (2026-08-23)** — 자료가 보조 자료 카드로 나가면서
    /// `photoRow`가 사라졌다. **뷰어의 「위치 보기」가 이것을 쓴다**(설계 §0 26번 · 뷰어 상세 문서).
    /// ⛔ **지우지 않는다** — 지도 핀 결함(27일 묵었던 것)을 고친 코드가 여기 있고,
    /// 다시 만들면 그 값을 잃는다(`MapsLink` · `photoPinName`).
    ///
    /// 사진 EXIF 좌표를 작은 지도로(비상호작용) + 지도 앱 열기. 좌표는 사진 안에만 있음(그릇 X).
    /// **여는 일만** `PlatformMedia`가 갈라 한다 — URL 꼴은 두 플랫폼이 같다.
    @ViewBuilder private func photoMap(_ coord: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker(MediaMigrationText.photoPinName, coordinate: coord)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
            Button {
                PlatformMedia.openInMaps(coord)
            } label: {
                Label("지도 앱에서 열기", systemImage: "map").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
    }

    /// 수집 방식(source) 한글 라벨. 알 수 없으면 원문 그대로.
    private static func sourceLabel(_ s: String?) -> String {
        switch s {
        case "voice":   return "음성"
        case "web":     return "웹·링크"
        case "image":   return "이미지"
        case "mail":    return "메일"
        case "doc":     return "문서"
        case "chat":    return "대화"
        case "meeting": return "회의"
        default:        return s?.isEmpty == false ? s! : "알 수 없음"
        }
    }

    // MARK: 결정 줄 — 임시 항목에서 하단 필수 바를 대신한다 (edit-policy §1-A, 2026-08-14)

    /// **[삭제하기] · [기억하기] 둘만.** 임시 항목에서 사람이 할 일은 **살릴지 버릴지 정하는 것** 하나이므로
    /// 화면이 그 둘만 내민다. `bottomBar`([삭제하기]·[취소]·[저장])는 임시일 때 아예 안 그린다.
    ///
    /// **[취소]가 없는 이유:** 임시에는 커밋할 [저장]이 없어 「수정을 버린다」가 독립 행동으로 성립하지 않는다.
    /// 나가려면 `<`를 누르고, 고친 것이 있으면 `backTapped()`의 확인 대화상자가 재확인한다.
    ///
    /// 삭제·기억하기 **둘 다 공용 재확인 대화상자를 거친다** — 둘 다 무게가 큰 결정이라 그대로 둔다.
    private var decideRow: some View {
        HStack(spacing: 10) {
            Button(role: .destructive) { showDeleteConfirm = true } label: {
                barLabel("삭제하기", "trash")
            }
            .buttonStyle(.bordered).tint(Palette.overdue)

            Button { showRememberConfirm = true } label: {
                Label("기억하기", systemImage: "checkmark.seal.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent).tint(Palette.today)
            .disabled(rawEmpty)   // 본문 전부 지운 상태면 기억할 것이 없다(내용 없는 기억 방지 — bottomBar와 같은 규약)
        }
        // 재확인 대화상자는 화면 전체 오버레이(rememberDialog·deleteDialog)로 띄운다.
    }

    // MARK: 분류 (override) — 「임시」 배지는 2026-08-18에 뺐다([기억하기] 버튼이 같은 말을 한다)

    /// **편집 중인 분류**(draft). 편집기(분류 메뉴·시간 설정 노출·반복 설정)가 쓴다.
    ///
    /// **★ 2차 압축(2026-08-11)에서 지켜야 할 것 — `savedType`으로 바꾸지 말 것.**
    /// 분류 카드를 성역과 나란히 옮기면서 입력을 `savedType`으로 바꾸고 싶어질 수 있다(옆에 선 성역이
    /// 저장값 성격이라 딸려가기 쉽다). 바꾸면 **08-08의 닫힘 시험이 뒤집힌다** — 이 카드는 **편집기**라서
    /// 분류를 골랐을 때 화면이 **고른 값**을 보여줘야 하고, 저장 없이 닫으면 되돌아가야 맞다.
    /// `savedType`을 보면 고른 즉시 화면이 안 바뀌어 **"안 골라졌다"로 보인다.**
    /// (사실을 말하는 배너는 반대다 — 아래 MARK 참조. **이 줄은 배너가 아니라 편집기다.**)
    private var normalizedType: String? { (type?.isEmpty ?? true) ? nil : type }

    // MARK: ★ 사실을 말하는 자리의 입력 — `saved` / `savedType` (2026-08-08 전수 점검)
    //
    // **기준(사양서 §0-A-2):** *저장 없이 화면을 닫았을 때 그 말이 거짓이 되면 저장값을,
    // 화면 안에서만 뜻이 있으면 화면 값을, 둘의 차이가 곧 그 말이면 둘 다 본다.*
    //
    // **왜 기준이 필요했나:** 같은 파일 20줄 사이에서 `overdueHiddenBanner`는 이 함정을 피하고
    // `anchorBanner`는 밟았다. 함정을 주석으로 적어 놓고도 **옆을 안 봤다.** 알고도 놓쳤으므로
    // 자리마다 고치는 것으로는 안 된다 — 자리를 세지 말고 **입력을 한 곳으로 모은다.**
    //
    // 사실을 말하는 배너·확인 문구는 **전부 이 둘만** 본다. draft(`due`/`recurPaused`/`normalizedType`)나
    // 스냅숏(`item`)을 직접 보면 안 된다 — 전자는 저장 전에 거짓이 되고, 후자는 낡는다(2026-08-06 `가`).

    /// **지금 저장돼 있는 상태.** 스냅숏(`item`)은 이 화면 안에서 완료·취소가 저장값을 옮겨도 안 따라간다.
    private var saved: ResolvedItem { model.current(item.id) ?? item }
    /// 저장된 분류(정규화) — `normalizedType`의 저장값 짝.
    private var savedType: String? { (saved.type?.isEmpty ?? true) ? nil : saved.type }

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // **제목 줄 전체가 접기 표적** — 성역 카드의 머리 줄과 같은 규약(제목 줄 = 접기).
            // **표시는 두 군데, 동작은 하나** — 여기를 눌러도 `toggleMeta()`라 성역과 **함께** 움직인다.
            // 분류만 따로 접히지 않는다(두 카드가 나란히 서므로 상태가 갈리면 줄이 어긋난다).
            //
            // **표적: 90 × 33.2**(위 14 = 카드 여백 + 줄 14.2 + 아래 5). 1-B와 같은 기법 — 여백을 주고
            // 표적을 잡은 뒤 같은 만큼 음수로 되돌려 **레이아웃은 안 움직인다.**
            // ⚠️ **아래로 5만 쓴다** — `spacing 10`을 다 쓰면 아래 메뉴 표적(아이콘, 90 × 40)과 **맞닿는다.**
            // 탭 튐 버그(2026-07-21)가 정확히 **인접 표적 오조작**이라 0pt는 피한다. → **사이 5pt.**
            // 44pt엔 못 닿는데(위 14·아래 10밖에 없다) **접기는 대체 경로가 크다** —
            // 접힘이면 **성역 카드 전체(92pt)** 가 같은 동작을 한다. 못 눌러도 잃는 게 없고,
            // 잘못 눌러도 메뉴가 열릴 뿐이다.
            //
            // **★ 「임시」 배지를 이 줄에서 뺐다 (2026-08-18 사용자 결정).**
            //
            // **왜:** *"바로 아래에 [기억하기] 버튼이 있어서 확정되지 않았다는 사실이 이미 명확하다."*
            // 배지와 `decideRow`의 [기억하기]는 **완전히 같은 조건**(`!isRemembered`)으로 뜨므로
            // 배지가 **정보를 0비트 추가한다** — 버튼의 존재가 이미 「임시다」를 말하고, 게다가 무엇을 해야
            // 하는지까지 말한다(전수 조사: `2026-08-14-macbook.md` §14-2).
            //
            // **★ 이 한 줄이 별개 과제 ⑥을 없앤다.** 확인 목록 **17번이 깨진 자리가 바로 여기였다** —
            // Large 실측 **88.3 / 91.0(여유 2.7pt)**이고 **XL에서 배지가 「임」/「시」 두 줄, XXL에서 「⋯」로
            // 뭉개져 뜻이 사라졌다**(`2026-08-12-macbook.md` §17번). **배지가 없으면 깨질 것이 없다.**
            // 남는 것은 「분류」 20.8 + 접기 14 + 간격뿐이라 XXXL에서도 넉넉하다.
            //
            // **`spacing`을 4 → 8로 되돌렸다.** 4였던 이유가 *"배지까지 넣으면 8에서 93.9로 넘친다"* 였는데
            // **그 제약이 사라졌다.** (`Spacer`가 남는 폭을 먹으므로 **화면 모양은 안 바뀐다** — 최소폭만 달라진다.)
            //
            // ⚠️ **「임시」 표시가 없어지는 것이 아니다** — 목록에는 남는다: 「새 기억들」(`MemoryRow`) ·
            //    **「검색」 결과 캡션 줄**(2026-08-18 신설, `SearchView`).
            Button { toggleMeta() } label: {
                HStack(spacing: 8) {
                    sectionLabel("분류")
                    Spacer(minLength: 4)
                    Image(systemName: metaCollapsed ? "chevron.down" : "chevron.up")
                        .font(.caption).foregroundStyle(Palette.textTertiary)
                }
                .padding(.top, 14).padding(.bottom, 5)
                .contentShape(Rectangle())
                .padding(.top, -14).padding(.bottom, -5)
            }
            .buttonStyle(.plain)
            Menu {
                ForEach(ClassRegistry.assignable) { m in    // 기본층 6 + 유연층(주차 위치)
                    Button { type = m.key } label: { Label(m.label, systemImage: m.symbol) }
                        .disabled(m.key == normalizedType)
                }
                Divider()
                Button { type = "" } label: { Label("미분류", systemImage: "questionmark.circle") }
                    .disabled(normalizedType == nil)
            } label: {
                // **세로 배치 — 아이콘 위 · 이름 아래 (2차 압축 1단계, 2026-08-11).**
                //
                // **왜 세로인가 (계측):** 이 카드가 성역과 2:1로 나란히 서면 안쪽 폭이 **91.3pt**다
                // (342가 아니다 — 402 − 바깥 16×2 − gap 12를 2:1로 나눈 뒤 카드 패딩 14×2를 또 뺀 값).
                // 옛 가로 배치는 최소폭이 `심볼 + 이름 + chevron 11 + 간격 27`이라 **최악 「주차 위치」가 120.2pt** —
                // 아홉 분류 중 **일곱이 안 들어갔다.** 세로로 세우면 폭 = `max(심볼, 이름+chevron)`이 되어
                // **최악 77.2pt**(주차 위치 63.2 + 3 + 11)로 떨어진다 → 여유 14.1pt.
                // ⚠️ **여유가 XXXL에서 1pt까지 좁아진다.**
                // > **★ 정정 (2026-08-18).** 이 줄이 **「XXXL(20pt)」**로 적혀 있었다 — **XXXL은 23pt다.**
                // > 계측 규칙 6이 이름 붙여 경고하는 그 실수(Dynamic Type 크기를 기억으로 쓴 것)가 여기 남아 있었다.
                // > 23pt 실측은 **이름 84.8 + 3 + chevron = 98.8 / 90**이다(`ae0421d`가 뗀 이유 ⓑ).
                // > 이어 적혀 있던 **「더 필요하면 chevron을 떼는 것이 다음 지렛대다」는 뺐다** — 이미 뗐고,
                // > **2026-08-18에 「되살리지 않는다」로 최종 확정됐다**(아래 ⓐ·ⓑ 블록).
                //
                // 아이콘 크기는 접힘 **17** / 펼침 **44**(상한 50). 펼침 44는 최악 심볼 `person.2.fill`이
                // 69.9pt로 91.3 안에 든다. **가로↔세로로 모양을 바꾸지 않는다** — 크기만 바뀌므로 접었다 펴도
                // 배치가 안 흔들린다(같은 이유로 성역도 접힘에서 폰트를 안 바꾼다 — G-11에서 지킨 원칙).
                // **접힘: 아이콘만 크게(30pt) · 펼침: 아이콘(44pt) + 이름.**
                //
                // **왜 30이고 40 이상이 아닌가 — 키우려던 것을 줄이는 게 답이었다.**
                // 이름이 빠져 폭은 넉넉하다(최악 `person.2.fill`이 50pt에서도 79/90). **높이가 먼저 걸린다:**
                // 접힘 카드 = 28(여백) + 14.2(제목 줄) + 10(spacing) + 아이콘 프레임.
                // 프레임 40이면 **92.2pt** = 성역 접힘 **92pt**와 맞고, 행 높이가 **97 → 92로 5pt 더 줄어든다.**
                // 프레임 52(=아이콘 40pt)면 104.2로 **지금보다 7pt 커져** 압축을 되돌린다.
                //
                // ⚠️ **프레임 높이를 고정하는 이유 — 심볼마다 높이가 다르다.** @40pt에서
                // `mappin.and.ellipse` 52 · `lightbulb.fill` 51 · `person.2.fill` 43 —
                // 안 고정하면 **분류 카드 높이가 항목마다 9pt씩 달라진다.**
                // (펼침은 고정하지 않았다 — 거기선 성역이 훨씬 커서 행 높이를 정하므로 영향이 없다.)
                //
                // **메뉴 chevron(`chevron.up.chevron.down`)을 뗐다.** 이유 둘:
                // ⓐ 제목 줄에 **접기 chevron이 생겨** 90pt 카드 안에 chevron이 둘이면 헷갈린다.
                // ⓑ **Dynamic Type 여유를 산다** — 「주차 위치」+chevron은 **XXL(21pt)에서 이미 91.6/90으로 넘쳤다.**
                //    떼면 XXXL(23pt)에서 84.8/90으로 **여유 5.2pt.**
                // ⚠️ **대가: 메뉴임을 알리는 표시가 없어진다**(자리로만 안다).
                //
                // ─────────────────────────────────────────────────────────────────────────────
                // **★ 최종 확정 (2026-08-18 사용자) — 메뉴 표시는 넣지 않는다. 되살리지 않는다.**
                //
                // 사용자 판정: *"그냥 아이콘 누르면 변경 가능한 것으로 알게 될 것이라고 확신해."*
                // **확인 목록 14번(chevron 없이도 메뉴인 줄 알겠나)이 이 판정으로 닫혔다** —
                // 2026-08-14에 「판정이 흐리다」로 미결로 되돌렸던 것을 **취소하고 08-13 통과를 유지한다.**
                //
                // **되살리는 안을 만들어 보고 거부됐다** (같은 날, 시뮬에서 펼쳐 확인한 뒤):
                // chevron을 **아이콘 줄로 옮기고**(이름은 `.body`라 커지지만 아이콘은 `.system(size:)`라 고정이므로
                // 폭 병목을 벗어난다 — 아이콘 판 70 + 3 + chevron 11~13 = **84~86 / 90**, 모든 단계 통과)
                // **아이콘에 색 판**(목록 `TypeMenuButton`과 같은 `color.opacity(0.14)` + `RoundedRectangle`)까지
                // 함께 넣었다. **폭 지렛대는 하나도 안 건드렸다.** 그래도 **화면이 마음에 안 든다는 판정**이었다.
                // → **되돌렸다. 이 자리는 지금 모양이 최종이다.**
                //
                // ⚠️ **다시 손대려면 폭 비용부터 풀어야 한다** — 이름 줄에 되살리면 **XXL(21pt)에서 92.6 / 90**이다
                //    (`ae0421d`는 chevron을 **11.0 고정**으로 계산해 91.6이라고 적었는데, `.caption2`라 함께 커진다:
                //    11pt→11.0 · 13pt→12.0 · 14pt→13.0. 실측 2026-08-18).
                // ⚠️ **`chevron.down` 하나로 줄이는 것은 폭을 못 번다** — 세로로 겹친 `⌃⌄`가 더 좁다
                //    (11pt에서 13.0 vs 11.0. 실측 2026-08-18).
                // ─────────────────────────────────────────────────────────────────────────────
                let m = ClassRegistry.meta(normalizedType)
                VStack(spacing: 6) {
                    Image(systemName: m.symbol)
                        .font(.system(size: metaCollapsed ? 30 : 44))
                        .foregroundStyle(m.color)
                        .frame(height: metaCollapsed ? 40 : nil)
                        // 접힘에서 카드가 성역 높이로 늘어나므로(아래 `typeSection` 주석) 남는 공간 **가운데**에 둔다.
                        // 메뉴 표적도 이만큼 커진다 — 접기 표적과의 5pt 간격이 그만큼 안전해진다.
                        .frame(maxHeight: metaCollapsed ? .infinity : nil)
                    if !metaCollapsed {
                        // `.body`(17pt)를 **명시**한다 — 옛 코드는 환경 폰트 상속에 기대고 있어서
                        // 계측할 때 "이 줄이 몇 pt인가"를 코드에서 읽을 수 없었다.
                        Text(m.label).font(.body).lineLimit(1).foregroundStyle(Palette.textPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .menuStyle(.button).buttonStyle(.plain)
            // **임시(미확정)에서도 분류는 고칠 수 있다** (edit-policy.md §1-A, 2026-08-14).
            // 분류는 **활용이 아니라 식별**이다 — 사람이 밟는 순서가 원문 고치기 → 분류 고르기 → 기억하기다
            // (`memory-philosophy.md` §2-1-A). 임시에는 [저장]이 없으므로 **[기억하기]가 함께 커밋한다.**
            // (⚠️ **목록의 종류 글리프는 막혀 있다** — 거기선 누르면 즉시 커밋이라 뜻이 갈린다. `TypeMenuButton`.)
            // (아래 `.frame(maxHeight:)`가 접힘에서 이 카드를 성역 높이에 맞춘다 — `typeSection` 끝 주석 참조)
            // Menu는 탭을 자기가 삼켜(메뉴 표시) 바깥 TapGesture가 안 걸린다 → touch-down에 걸리는
            // DragGesture(0)로 메뉴 여는 순간 키보드를 내린다. simultaneous라 메뉴 동작은 그대로.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if rawFocused { rawFocused = false }
            })
        }
        // **접힘에서만 성역 카드 높이에 맞춘다 (2026-08-12).**
        //
        // **왜 필요한가:** 픽셀 실측으로 접힘이 **성역 95.0 / 분류 91.7 = 3.3pt 차이**였다.
        // 나란히 선 두 카드의 밑변이 어긋나 눈에 바로 걸린다.
        //
        // **왜 숫자로 안 맞추나 — 한 크기에서만 맞는다.** 성역 접힘 높이는 **시각·기기 = `.callout`** 이 정하므로
        // **Dynamic Type에 따라 커지고**(XXXL에서 ~108pt), 분류는 **아이콘 `.system(size: 30)`** 이라 **고정**이다.
        // 프레임을 43으로 바꾸면 Large에서만 맞고 XXXL에서 16pt 이상 벌어진다.
        //
        // **왜 접힘에만 늘리나 — 「그 상태에 무엇이 들어 있나」 (세 번째로 같은 규칙):**
        // 접힘은 두 카드 차이가 **3.3pt**라 늘려도 빈칸이 사실상 없다. 펼침은 **17.7pt**(사진 없음)에서
        // 사진·지도가 있으면 **최대 ~495pt**까지 벌어진다 — 거기서 늘리면 거대한 빈칸이 생긴다.
        // → **`metaTypeRow`의 「빈칸을 안 채운다」 결정은 그대로다.** 그 판단은 펼침의 495pt를 두고 한 것이었다.
        .frame(maxHeight: metaCollapsed ? .infinity : nil)
        .padding(14).card()
    }

    // MARK: 재확인 질문 (info-action, §3 자동분류가 남긴 "구체적으로 뭘·언제")
    //
    // **⚠️ 2026-08-08 전수 점검에서 「안 고침」** — 스냅숏 `item`을 읽지만 이 화면이 **못 고치는 필드**라
    // draft와 갈릴 일이 없다. (자동분류 스윕이 나중에 채울 수는 있는데, 그건 상세를 연 채로는 안 돈다.)
    // 읽기 전용 표시. fields.v1 편집 블록으로 파일에 저장되므로 재실행에도 유지된다(그릇 Stage 1 검증 지점).
    private func questionSection(_ q: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("확인이 필요해요")
            Text(q).font(.callout).foregroundStyle(Palette.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).card()
    }

    // MARK: 시간 설정 (Due · Resurface — 임의 날짜 + 지우기/none, §4-2·§4-3)

    private var timeSection: some View {
        // §7 (a): 분류가 마감·다시보기를 쓰는지 ClassDef가 정한다. 정의 없으면(미분류·미등록) 기본=씀.
        // → 주차=마감만 숨김 / 정보·아이디어·원칙=둘 다 안 써 "시간 설정" 섹션 통째 숨김 / 6종·미분류=회귀 없음.
        // 표시 전용(비파괴적): 숨겨도 저장된 due/resurface 값은 안 지운다(무효화·알림 정리는 §7 (c)/D3).
        let usesDue       = ClassSpecCatalog.uses(normalizedType, .due)
        let usesResurface = ClassSpecCatalog.uses(normalizedType, .resurface)
        return Group {
            if usesDue || usesResurface {
                VStack(alignment: .leading, spacing: 12) {
                    sectionLabel("시간 설정")
                    // **접힘 판정은 draft를 본다** — 편집기이므로(§0-A-2 닫힘 시험: 저장 없이 닫으면 뜻이 사라진다).
                    // 배너 넷은 그대로 `saved`를 본다. 이번 압축은 **배치만** 바꾸고 판정 입력은 안 건드린다.
                    let edited = changes                       // 한 번만 계산해 두 줄이 나눠 쓴다
                    if usesDue {
                        timeRow(ClassRegistry.title(normalizedType, .due), value: $due,
                                field: .due, edited: edited["due"] != nil)
                    }
                    if usesDue && usesResurface { Divider().overlay(Palette.border) }
                    if usesResurface {
                        // 규칙 1은 **여기서 안 막는다** — [저장]에서 저장될 최종 짝으로 검사한다(B, 2026-08-08).
                        // 두 칸이 같은 `timeRow`를 같은 인자로 쓴다 = 날짜와 시각이 같은 방식으로 다뤄진다.
                        timeRow(ClassRegistry.title(normalizedType, .resurface), value: $resurface,
                                field: .resurface, edited: edited["resurface"] != nil)
                    }
                }
                .padding(14).card()
            }
        }
    }

    /// **시점 한 칸 = 한 줄.** 값을 누르면 **가운데 대화상자**에서 고친다(2026-08-09).
    ///
    /// **왜 이 모양인가 — 접이식을 접었다.** 처음엔 눌러서 아래로 펼치는 방식이었는데 셋이 어긋났다:
    /// ① 접힌 줄이 「8월 14일 06:00」을 말하는데 펼치면 같은 날짜가 피커로 **한 번 더** 나왔다.
    /// ② 날짜는 [지우기]·[날짜 설정] **버튼**인데 시각만 **토글**이라 짝이 안 맞았다.
    /// ③ 값이 있는 줄을 누르는 것은 *"고치겠다"* 는 뜻인데, 펼치기는 그 뜻에 한 단계를 더 얹었다.
    /// → **누르면 바로 고치는 자리가 열린다.** 날짜와 시각이 **한 대화상자 안에서 같은 방식**으로 다뤄진다.
    ///
    /// **[지우기]·[날짜 설정]은 제목 옆에 둔다**(사용자 결정). 폭은 남는다 — 실측으로
    /// 제목 59.5 + 버튼 31 + 값 ~103 + 간격 20 = **약 214pt**이고 카드 안쪽은 **342pt**다.
    /// 덤으로 **파괴적 버튼(지우기)과 값 표적이 줄의 양끝으로 갈라져** 오폭이 줄어든다.
    ///
    /// **`edited` = 그 칸에 저장 안 된 변경이 있나.** 부르는 쪽이 `changes`에서 뽑아 준다 —
    /// **하단 「저장하지 않은 수정이 있어요」·[저장] 버튼과 같은 값**이라 셋이 어긋날 수 없다(새 판정 없음).
    @ViewBuilder
    private func timeRow(_ title: String, value: Binding<String?>, field: TimeField,
                         edited: Bool) -> some View {
        let hasDate = Self.isRealDate(value.wrappedValue)
        HStack(spacing: 10) {
            Text(title).font(.callout).foregroundStyle(Palette.textPrimary)
            if hasDate {
                Button("지우기") { value.wrappedValue = "none" }
                    .font(.caption).tint(Palette.overdue)
            } else {
                Button("날짜 설정") { startEditing(value, field) }
                    .font(.caption).tint(Palette.accent)
            }
            Spacer(minLength: 8)
            // 값 자체가 표적 — 누르면 고치는 자리가 열린다. 값이 없을 때 「없음」을 눌러도 같다
            // (죽은 표적을 안 만든다 — [날짜 설정]과 같은 동작).
            Button { startEditing(value, field) } label: {
                Text(hasDate ? korDateTime(value.wrappedValue ?? "") : "없음")
                    .font(.callout).foregroundStyle(valueTint(edited: edited, hasDate: hasDate))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
        }
    }

    /// 고치는 자리를 연다. 값이 없었으면 **오늘**을 넣고 연다(옛 [날짜 설정]과 같은 동작 — 빈 피커를 안 만든다).
    private func startEditing(_ value: Binding<String?>, _ field: TimeField) {
        editingBackup = value.wrappedValue                 // ← 반드시 오늘을 넣기 **전에**
        if !Self.isRealDate(value.wrappedValue) { value.wrappedValue = Self.fmt.string(from: Date()) }
        editingTime = field
    }

    /// 시점 고치는 대화상자 — **날짜와 시각을 한자리에서, 같은 방식으로.**
    /// 위에서 아래로: 달력(날짜) → **시각 토글** → 시·분. 토글을 시·분 **바로 위**에 둬서
    /// 무엇을 켜고 끄는지가 자리로 드러난다(사용자 결정).
    ///
    /// **임시값을 두지 않는다.** 여기서 고친 것은 **곧바로 draft**에 담기고, 화면 전체와 마찬가지로
    /// **[저장] 전까지 커밋되지 않는다.** 대화상자 전용 임시층을 만들면 화면에 값의 층이 셋(임시·draft·저장값)이
    /// 되어, 지금까지 draft/저장값 하나로 정리해 둔 판정이 다시 흐려진다.
    ///
    /// ★ **피커에 범위(`in:`)를 주지 않는다** — B(2026-08-08). 범위를 주면 피커가 **값의 원천**이 되어
    /// 사람이 안 건드린 값을 조용히 바꾼다(상한에 붙은 값이 상한을 따라 움직였다). 규칙 1은 [저장]에서만 막는다.
    @ViewBuilder
    private func timeDialog(_ field: TimeField) -> some View {
        let value = field == .due ? $due : $resurface
        let title = ClassRegistry.title(normalizedType, field == .due ? .due : .resurface)
        // **amber = 「지금 값이 저장값과 다르다」.** 줄의 값 색·하단 문장·[저장] 버튼이 보는 그 `changes`를
        // 그대로 본다 — 대화상자 안팎이 같은 판정을 쓰므로 어긋날 수 없다(새 판정 없음).
        let edited = changes[field == .due ? "due" : "resurface"] != nil
        // 「없음」으로 열렸는데 지금은 날짜가 있다 = 날짜 자체가 새로 생긴 것.
        let cameFromEmpty = !Self.isRealDate(editingBackup) && Self.isRealDate(value.wrappedValue)
        // **폭 400pt** — 2026-08-10 확정.
        // `.graphical` 달력의 **행 높이는 칸 너비를 따른다**: 폭 300 → 칸 41pt·행 34pt / 폭 400 → 칸 ≈56pt·행 ≈46pt.
        // **늘리기 없이** 크기를 얻는 손잡이는 **폭**이다. 화면이 402pt라 좌우 1pt씩만 남는다.
        // **글자 크기 줄이기(`dynamicTypeSize`)도 시험했다가 되돌렸다** — 이 달력만 기기의 글자 크기 설정을
        // 안 따르게 되는데(접근성 손해), 그만한 값이 없었다.
        // **다른 대화상자는 그대로 300pt다**(`StandardDialog`의 기본값 — 부르는 쪽을 안 건드렸다).
        StandardDialog(title: title, width: 400) {
            VStack(spacing: 12) {
                // **달력은 평소 accent다.** `.tint`는 선택 표시뿐 아니라 **월 이동 < > 까지** 물들여서,
                // 날짜를 고칠 때마다 화살표 색이 따라 바뀌면 시끄럽다(2026-08-09 정정).
                // **딱 한 경우만 amber**: 「없음」이었다가 날짜가 생겼을 때 — 그때는 **어느 날이든 다 바뀐 것**이라
                // 비교할 «전»이 화면에 없다. 날짜를 옮긴 경우는 옮긴 자리가 스스로 보이므로 색이 필요 없다.
                // ★ **늘리기를 없앤다 — 제 크기로만 그린다**(2026-08-10 결정 「나」).
                //
                // **네 번 시도했고 완전히는 못 닫았다** — 과정은 확인표 G-12에 표로 남겼다:
                // ① `frame(height:330)` ② `+ maxHeight:.infinity` ③ `fixedSize(vertical:)` ④ ③ + 폭 360.
                // **④가 변함이 가장 작았다.** 틀을 주면 「남는 높이를 쓸지 말지」라는 자유가 남고,
                // 그 자유가 곧 흔들림이다. 틀을 걷고 **폭으로 크기를 키우는 쪽**이 남는 흔들림이 제일 작다.
                //
                // **실측이 바로잡은 것:** 같은 2026년 8월·같은 6줄인데 **행 간격이 34.0 ↔ 46.3pt**로 갈렸고
                // 대화상자 구분선은 **248·604·664pt로 동일**했다. → **주 수 문제가 아니다**(그렇게 설명했던 것은
                // 틀렸다). 같은 달에서 **날짜만 눌러도** 변한다.
                //
                // ⚠️ **완전히 안 닫혔다.** `fixedSize(vertical:)`를 줘도 조금 변한다 — 「제 이상 크기로만」이
                // 이 피커에선 끝까지 안 지켜진다. **값은 안 잃고 동작도 정상이라 급한 자리가 아니다.**
                // 다음 후보(달력 직접 그리기 · `.wheel` · 높이 못박고 잘라내기)도 G-12에 적어 뒀다.
                DatePicker("", selection: dateBinding(value), displayedComponents: .date)
                    .datePickerStyle(.graphical).labelsHidden()
                    .tint(cameFromEmpty ? Palette.today : Palette.accent)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                // **미루기 셋 — 바로 위 달력에 결과가 나타난다.** 자리를 닫지 않는다:
                // 눌러 보고 마음에 안 들면 다른 날 수를 누르거나 [취소]로 되돌릴 수 있어야 한다.
                // **지금 값을 만든 버튼이 amber**로 켜진다(아래 `deferSelected`). 미리 알림에만 있다.
                if field == .resurface {
                    // **셋이 폭을 똑같이 나눈다.** 옛 코드는 각자 제 폭 + `Spacer`라 합이 대화상자(300pt)를
                    // 넘어 **첫 버튼이 찌그러졌다**(실측: 글자 69.3 + 좌우 여백 18 = 87pt × 3 = 261pt에
                    // 좌우 여백 32를 더하면 293pt로 268pt를 넘는다).
                    // 이제 각 칸 = (300 − 24 − 간격 16) ÷ 3 ≈ **86.7pt**, 글자 69.3pt라 17pt 남는다.
                    HStack(spacing: 8) {
                        ForEach([1, 3, 7], id: \.self) { n in
                            Button("\(n)일 미루기") { deferResurface(value, days: n) }
                                .font(.callout).buttonStyle(.plain)
                                .lineLimit(1).minimumScaleFactor(0.85)
                                .foregroundStyle(deferSelected(n, value: value.wrappedValue, edited: edited)
                                                 ? Palette.today : Palette.accent)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 7)
                                .background(Palette.border, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 12)
                }
                Divider().overlay(Palette.border)
                HStack(spacing: 8) {
                    Text("시각").font(.callout).foregroundStyle(Palette.textPrimary)
                    Toggle("", isOn: timeEnabledBinding(value, field)).labelsHidden().tint(Palette.accent)
                    Spacer()
                    if ItemSchedule.timeOfDay(value.wrappedValue ?? "") != nil {
                        DatePicker("", selection: timeBinding(value), displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
                    } else {
                        // **꺼도 시각은 보인다 — 흐리게.** 안 고른 상태임이 색으로 드러나고,
                        // 그 값이 **켜면 붙을 값**이다(같은 `pendingTime`). 꺼둔 시각을 화면에서 잃지 않는다.
                        Text(pendingTimeText(field))
                            .font(.callout).foregroundStyle(Palette.textPrimary.opacity(0.35))
                    }
                }
                .frame(height: 34)               // ← 켜짐(피커)·꺼짐(글자) 높이가 달라 들썩이던 자리
                .padding(.horizontal, 16)
            }
            .padding(.vertical, 14)
            Divider().overlay(Palette.border)
            // [취소]는 **열 때의 값으로 되돌린다** — 「없음」이었으면 다시 「없음」이 된다.
            // [확인]은 닫기만 한다(편집은 이미 draft에 있다). 저장은 화면 아래 [저장]이 한다.
            HStack(spacing: 8) {
                DialogButton(title: "취소") { value.wrappedValue = editingBackup; editingTime = nil }
                    .background(Palette.border, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                DialogButton(title: "확인", prominent: true) { editingTime = nil }
                    .background(Palette.border, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .padding(.horizontal, 12).padding(.bottom, 12).padding(.top, 4)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// **이 미루기 버튼이 지금 값을 만든 것인가** — 그러면 amber로 켠다.
    ///
    /// **`edited`가 먼저다.** 값이 저장값과 같으면 어떤 버튼도 안 켠다 — *"원래 날짜로 오면 색깔은 변화 없게"*.
    /// 그래서 amber의 뜻이 대화상자 안에서 하나로 유지된다: **「지금 값이 원래와 다르다」.**
    ///
    /// 판정은 `deferBy`를 **다시 돌려** 그 날짜와 비교한다 — 버튼이 실제로 만들 값과 **같은 함수**라
    /// 갈릴 수 없다(상한에 걸려 당겨지는 경우까지 그대로 따라간다).
    /// ⚠️ 그래서 **둘 이상이 켜질 수 있다** — 3일과 7일이 같은 상한으로 당겨지면 둘 다 그 값을 만든다.
    /// 그건 거짓이 아니라 사실이다(어느 쪽을 눌러도 같은 날이 된다).
    private func deferSelected(_ n: Int, value: String?, edited: Bool) -> Bool {
        guard edited, let value, Self.isRealDate(value) else { return false }
        guard case .deferred(let day, _) = ItemSchedule.deferBy(
                days: n, due: due, now: Date(),
                resurfaceHasTime: ItemSchedule.timeOfDay(value) != nil) else { return false }
        return Self.datePart(value) == day
    }

    /// 값의 날짜부("2026-08-14T06:00" → "2026-08-14"). 시각이 있든 없든 날짜만 비교할 때 쓴다.
    static func datePart(_ s: String) -> String {
        s.split(whereSeparator: { $0 == "T" || $0 == " " }).first.map(String.init) ?? s
    }

    /// 값 글자의 색 — **저장 안 된 변경이 있으면 amber**(하단 「저장하지 않은 수정이 있어요」와 **같은 색**).
    ///
    /// **하단이 「있다」, 이 색이 「어디」다.** 하단 문장은 그대로 둔다 — 줄이 화면 밖으로 스크롤되면
    /// 안 보이므로, 전체를 말하는 자리는 여전히 하단 하나뿐이다.
    ///
    /// ⚠️ **후보 「나」(값 글자를 물들임)를 시험 중이다** — amber가 「늦음·지남」으로 읽히면
    /// 후보 「가」(제목 왼쪽 amber 점)로 바꾼다. **바꿀 자리는 이 함수 하나다**(확인표 G-3).
    private func valueTint(edited: Bool, hasDate: Bool) -> Color {
        if edited { return Palette.today }
        return hasDate ? Palette.textPrimary : Palette.textTertiary
    }

    /// **N일 미루기**(상세 draft) — 규칙 1을 지켜 미리 알림 draft를 정한다. 위반 상태로 세팅하지 않는다.
    /// 상한에 걸려 당겨졌거나 마감 임박이라 못 미루면 안내 팝업으로 알린다("알린다").
    ///
    /// **1·3·7일이 같은 길을 탄다** — `ItemSchedule.deferBy`가 날 수만 받고 판정은 하나다(2026-08-09).
    /// **자리를 닫지 않는다** — 눌러 보고 다른 날 수를 누르거나 [취소]로 되돌릴 수 있어야 한다.
    /// 상한/차단 안내는 이 대화상자 **위에** 겹쳐 뜬다(오버레이 순서로 보장).
    private func deferResurface(_ value: Binding<String?>, days: Int) {
        switch ItemSchedule.deferBy(days: days, due: due, now: Date(),
                                    resurfaceHasTime: ItemSchedule.timeOfDay(value.wrappedValue ?? "") != nil) {
        case .deferred(let day, let capped):
            value.wrappedValue = ItemSchedule.withTimeOfDay(day, from: value.wrappedValue)   // 원래 시각 보존(§6-B)
            if capped {
                // "하루 전"을 뺐다(미결 3번) — 시각 있는 미리 알림이면 상한이 **마감 당일**이라 거짓이었다.
                // 맞춘 **값만** 말하면 규칙이 갈려도 안 틀린다.
                noticeDialog = "마감이 가까워 미리 알림을 \(InboxModel.korShort(day))로 맞췄어요"
            }
        case .blocked:
            // cap(상한)이 아니라 **마감**을 말한다 — 사람이 아는 값이고, "하루 전"이라는 규칙 서술이 필요 없다.
            noticeDialog = "마감(\(korDateTime(due ?? "")))이 가까워 더 미룰 수 없어요"
        }
    }

    // MARK: 반복 설정 (되풀이 분류 전용, Stage 2) — '시간 설정' 아래 카드.
    // 주기·자동완성 = "어떻게 도느냐" / 꺼두기 = "지금 도느냐". 회차·완료는 Stage 3·4.

    /// 되풀이 꺼둠이면 상세 상단에 바로 보이는 배너(스크롤 없이). 꺼둔 걸 잊지 않게.
    ///
    /// **저장값을 본다**(2026-08-08). 기준을 돌려보면: 꺼두기 토글만 켜고 저장 없이 닫으면
    /// **알림은 안 멈춘다** → 지금 떠 있던 배너가 거짓이다. 배너가 약속하는 것("알림·되살아나기 멈춤")은
    /// **저장된 사실**이지 토글의 위치가 아니다. 토글 자체가 움직이므로 반응이 없지도 않다.
    @ViewBuilder
    private var pausedBanner: some View {
        if savedType == "recurrence", Recurrence.isPaused(saved) {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").foregroundStyle(Palette.overdue)
                Text("되풀이 꺼둠 — 알림·되살아나기 멈춤").font(.callout.weight(.semibold)).foregroundStyle(Palette.overdue)
                Spacer()
            }
            .padding(12)
            .background(Palette.overdue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// 회차 기준(회차 시각) 없음 안내 — 되풀이는 마감이 앵커라, 없으면 회차가 안 돈다.
    /// 조용히 안 도는 대신 화면으로 알린다(#3). "시간 설정"의 회차 시각을 채우게 유도.
    ///
    /// **★ 저장값을 본다**(E-5, 2026-08-08 — 사용자가 실기기에서 발견). 옛 코드는 draft `due`를 봐서
    /// **날짜를 입력하는 순간 배너가 사라졌는데 저장값은 아직 비어 있었다** — 화면이 "이제 반복이 돕니다"라고
    /// 말하는데 사실은 안 돌았다. 저장 없이 [이번 것 했어요]를 눌러도 아무것도 전진하지 않는 이유가 이것이다
    /// (완료는 저장값 위에서 돈다 — `runCycleAction`).
    /// **바로 아래 `overdueHiddenBanner`가 같은 함정을 피하고 있었다** — 그런데도 여기서 밟았다.
    /// 그래서 자리를 고치는 대신 입력을 `saved`/`savedType`으로 모았다(위 MARK 참조).
    @ViewBuilder
    private var anchorBanner: some View {
        if savedType == "recurrence", !Self.isRealDate(saved.due) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Palette.accent)
                Text("회차 시각이 없어요 — 위 '시간 설정'에서 **회차 시각(마감)**을 정해야 반복이 돕니다")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
            .padding(12).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// **늦었는데 숨겨진 것**(D, 2026-08-07) — 마감이 지났는데 미리 알림이 아직이라 목록에 안 나오는 항목.
    ///
    /// **★ "숨겨졌습니다"라고 말하지 않는다.** 그 상태를 만든 것은 사람 자신이다(미루기를 눌렀거나 날짜를 옮겼거나) —
    /// 자기가 치운 것을 앱에게 듣는 꼴이 된다. 알릴 것은 **"언제 돌아오나"** 와 **"그것이 마감보다 뒤다"** 둘뿐.
    ///
    /// **첫 줄이 돌아오는 날이다** — §0-A-2의 *"놀란 사람은 첫 줄만 읽는다"* 와 같은 원칙이고,
    /// 여기서 첫 줄에 와야 할 것은 **행동에 쓸 사실**이다. 마감·늦음은 그것을 해석하게 해주는 설명이라 둘째 줄.
    ///
    /// **amber다** — 숨긴 것은 사람이 시킨 결과라 경고가 아니라 주의다. coral을 늘리면
    /// D-4에서 일부러 지킨 위계(놓침=coral)가 죽는다. 바로 위 `missedBanner`가 coral이라 같은 화면에서 부딪힌다.
    ///
    /// **⚠️ 판정 입력은 화면 draft가 아니라 모델의 현재 항목이다.** draft로 재면 사용자가 날짜만 고치고
    /// **저장하기 전에 배너가 사라져** "해결됐다"고 잘못 읽게 된다 — 그게 §0-A-2 넷째 유형(**고치는 변경이 새 거짓을 만든다**)이다.
    /// 배너는 **지금 저장돼 있는 상태**를 말한다. 스냅숏(`item`) 대신 `model.current`를 집는 이유는 어젯밤 (a)와 같다(스냅숏은 낡는다).
    @ViewBuilder
    private var overdueHiddenBanner: some View {
        let fresh = model.current(item.id) ?? item
        if let oh = ItemSchedule.overdueHidden(fresh, now: Date()), let on = oh.returnsOn {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "clock.arrow.circlepath").foregroundStyle(Palette.today)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(korDateTime(on))에 다시 보여드려요")
                        .font(.callout.weight(.semibold)).foregroundStyle(Palette.today)
                    Text(overdueHiddenSubtitle(fresh.due, lateDays: oh.lateDays))
                        .font(.caption).foregroundStyle(Palette.textSecondary)
                }
                Spacer()
            }
            .padding(12).background(Palette.today.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// **회차 전진이 미리 알림을 당겼다**((c), 2026-08-08) — 앱이 사람 값을 옮겼으면 **말한다.**
    ///
    /// **왜 있어야 하나:** 완료·자동 완성·꺼두기 켜기가 회차를 전진시킬 때, lead가 뒤집혀 있으면
    /// 미리 알림을 규칙 1 안으로 당긴다(`Recurrence.clampToRule1`). 그건 **앱이 값을 정하는 일**이다.
    /// 미루기(+7일)가 상한에 걸려 당겼을 때 팝업으로 알리는 것과 **같은 종류의 빚**이다 —
    /// 다만 자동 완성·켜기는 **사람이 안 누른 경로**라 팝업이 뜰 자리가 없다. 그래서 배너다(셋 다 같은 자리).
    ///
    /// **왜 목록에는 안 넣나:** 당김은 **사건**이지 상태가 아니다(한 번 당기면 lead가 고쳐져 다음 회차부터
    /// 정상 보존). 상태 칩 자리에 넣으면 사라질 조건이 없다. 그리고 **목록 신호는 이미 있다** —
    /// 뒤집힌 lead는 `overdueHidden`(「◯/◯에 다시 · N일 늦음」)이 붙는 바로 그 상태이고, 당김은 그것을
    /// **해소**한다(= 칩이 사라지는 것으로 보인다). 하나 더 넣으면 같은 사실에 신호가 둘이 된다.
    ///
    /// **한 회차만 산다** — 다음 전진이 기록을 지운다. 당겨진 값은 이미 규칙을 지키는 정상 상태라
    /// **사람이 반드시 할 일이 없기 때문**이다. 할 일 없는 신호가 남으면 꺼둠·D 배너와 자리를 다투고
    /// 정작 할 일 있는 신호가 묻힌다(색 위계에서 배운 것과 같다).
    /// ⚠️ **회차가 잦으면(하루 3회 약) 몇 시간 만에 사라진다.** 그래도 이쪽이 맞다고 봤다 —
    /// 회차가 잦다는 것은 그만큼 자주 본다는 뜻이다. 나중에 짧다고 느껴지면 그때 다시 본다.
    ///
    /// 판정 입력은 **모델의 현재 항목**이다(스냅숏은 낡는다 — `overdueHiddenBanner`와 같은 이유).
    @ViewBuilder
    private var leadClampedBanner: some View {
        let fresh = model.current(item.id) ?? item
        if let v = fresh.fields[Recurrence.leadClampedKey], !v.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Palette.accent)
                Text("미리 알림이 마감보다 늦어 \(korDateTime(v))으로 맞췄어요")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
            .padding(12).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// N일 놓침 주의(§4) — 상단에 바로. 되풀이·놓침>0일 때만.
    ///
    /// **저장값을 본다**(2026-08-08). 옛 코드는 스냅숏 `item`을 봤다. 이 화면 안에서 완료·취소를 누르면
    /// `runCycleAction`이 `baseline`만 옮기고 **`item`은 안 건드린다** — 그건 코드에서 확실하다.
    /// ⚠️ **실기기에서 옛 숫자로 남는 것을 본 적은 없다.** 고친 근거는 관찰이 아니라
    /// **바로 위아래 두 배너가 같은 이유로 저장값을 쓴다**는 것이다(확인표 F-3에 넣어 뒀다).
    @ViewBuilder
    private var missedBanner: some View {
        let n = Recurrence.missed(saved, now: Date())
        if savedType == "recurrence", n > 0 {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.overdue)
                Text("\(n)일 놓침").font(.callout.weight(.semibold)).foregroundStyle(Palette.overdue)
                Spacer()
            }
            .padding(12).background(Palette.overdue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder
    private var recurrenceSection: some View {
        if normalizedType == "recurrence" {
            VStack(alignment: .leading, spacing: 12) {
                sectionLabel("반복 설정")
                completionRow          // "오늘 약 먹었나" — 이번 회차 완료·취소
                Divider().overlay(Palette.border)
                // **주기와 자동 완성은 한 줄에 나란히**(압축, 2026-08-09).
                // **폰트 메트릭 실측으로 정정(2026-08-11)** — 08-09의 세 숫자가 전부 낙관적이었다.
                // 최악값(「당일 지나면」)까지 넣어 **304.3pt / 342pt**, 여유 **37.7pt**(옛 기록 284/58).
                // ⚠️ **꺼두기는 못 합친다** — 셋을 한 줄에 두면 **428.9pt**로 **86.9pt 넘친다**(옛 기록 401/59).
                //    제목을 「반복」·「자동」으로 줄여도 **365.1pt로 여전히 23.1pt 넘친다** —
                //    옛 주석의 "337pt로 겨우 들어간다"는 **사실이 아니었다.**
                // 옛 오차의 원인: `menuRow`의 간격 20(8+4+8)을 **줄마다 세지 않고 한 번만 셌다**(차이 정확히 20.0pt).
                //    글자 폭 모델 자체는 맞았다 — 「반복 주기」 옛 계산 59.5 vs 실측 59.6.
                // 여유 37.7pt의 뜻: Dynamic Type **XXL(18pt)까지 332pt로 버티고 XXXL(20pt)에서 359pt로 깨진다**
                //    (옛 주석의 "글자 크기 한 단계에 깨진다"보다 한 단계 더 여유가 있다).
                // 대안으로 재 둔 것: **꺼두기를 「반복 설정」 제목 줄로 올리면 153.4pt**(여유 188.6·높이 39.2pt 절약).
                //    배치가 사양서 §5·recurrence-design에 명시돼 있어 **사양서 반영이 먼저다** — 즉흥 이동 금지.
                HStack(spacing: 16) {
                    menuRow("반복 주기", value: Recurrence.Unit(rawValue: recurUnit ?? "")?.korean ?? "없음") {
                        ForEach(Recurrence.Unit.allCases, id: \.self) { u in
                            Button(u.korean) { recurUnit = u.rawValue }
                        }
                        Button("없음") { recurUnit = nil }
                    }
                    menuRow("자동 완성", value: Recurrence.AutoComplete(rawValue: recurAuto)?.korean ?? "없음") {
                        ForEach(Recurrence.AutoComplete.allCases, id: \.self) { a in
                            Button(a.korean) { recurAuto = a.rawValue }
                        }
                    }
                }
                Divider().overlay(Palette.border)
                HStack {
                    Text("꺼두기").font(.callout).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Toggle("", isOn: $recurPaused).labelsHidden().tint(Palette.accent)
                }
            }
            .padding(14).card()
        }
    }

    /// 이번 회차 완료 — 되풀이 완료는 "이번 것 했다"(항목 안 사라짐). 이번 회차 했으면 상태 표시 + 취소.
    /// 문구가 기존 "완료"(끝났다)와 다르다: 되풀이는 "이번 것 했어요".
    @ViewBuilder
    private var completionRow: some View {
        if cycleDoneLocal {
            HStack {
                Label("이번 회차 완료됨", systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold)).foregroundStyle(Palette.accent)
                Spacer()
                Button("취소") { runCycleAction { model.undoRecurComplete($0) }; cycleDoneLocal = false }
                    .font(.caption).tint(Palette.overdue)
            }
        } else {
            Button { runCycleAction { model.markDone($0) }; cycleDoneLocal = true } label: {
                Label("이번 것 했어요", systemImage: "checkmark.circle")
                    .font(.callout.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Palette.accent)
        }
    }

    /// **완료·취소를 이 화면에서 실행하고, 화면(draft·기준선)을 저장값에 맞춘다.** (2026-08-06 `가`)
    ///
    /// 완료·취소는 **마감·미리 알림을 옮긴다.** 옛 코드는 `cycleDoneLocal`만 뒤집어서 draft가 낡았고,
    /// 그 낡은 값 위에서 손편집 + 부분 저장이 일어나 **규칙 1 위반이 저장됐다**(항목 `가`).
    /// 여기서 화면을 같이 옮겨 **낡음 자체를 없앤다.** (저장 쪽 방어선은 `commit()`이 따로 든다 — 둘 다 필요하다:
    /// 이건 화면을 지키고, 그건 낡음의 다른 경로까지 막는다.)
    ///
    /// ⚠️ **사람이 손댄 칸은 안 건드린다(회귀선 6).** 마감을 고쳐 둔 채 완료를 누르면 **그 편집은 남고
    /// 미리 알림만 따라간다.** 어느 칸이 사람 것인지는 `changes`의 키로 안다 — `EditDiff`와 같은
    /// 정규화를 그대로 쓰므로 판정이 갈릴 일이 없다. 판정은 **행동 전에** 재 둔다(행동이 값을 바꾸므로).
    ///
    /// 완료·취소에 넘기는 항목도 **모델의 현재 항목**이다 — 낡은 스냅숏에서 회차를 전진시키지 않는다.
    private func runCycleAction(_ run: (ResolvedItem) -> [String: String]) {
        let touched = Set(changes.keys)                 // ← 반드시 먼저
        let applied = run(model.current(item.id) ?? item)
        guard !applied.isEmpty else { return }          // 아무것도 안 썼으면 화면도 그대로
        for (key, value) in EditDiff.draftSync(applied: applied, touched: touched) {
            let v: String? = (value.isEmpty || value == "none") ? nil : value
            if key == "due" { due = v } else if key == "resurface" { resurface = v }
        }
        // 기준선은 **손댄 칸까지 포함해 전부** 옮긴다 = 저장값과 같아진다.
        // 손댄 칸은 draft가 사람 값 그대로이므로 그 칸만 dirty로 남아 [저장]에 실린다.
        baseline = baseline.applying(applied)
    }

    /// 라벨 + 오른쪽 Menu 한 줄(반복 설정 공용).
    @ViewBuilder
    /// 라벨 + 오른쪽 Menu. **나란히 두 개를 한 줄에 놓을 수 있게** `Spacer(minLength:)`를 쓴다
    /// (`Spacer()`만 두면 둘 중 하나가 폭을 다 먹는다).
    private func menuRow<Content: View>(_ title: String, value: String, @ViewBuilder menu: () -> Content) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.callout).foregroundStyle(Palette.textPrimary)
            Spacer(minLength: 4)
            Menu { menu() } label: {
                HStack(spacing: 3) {
                    Text(value).font(.callout)
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }.foregroundStyle(Palette.accent)
            }
        }
    }

    // MARK: 수정 이력 (경량 한 줄 — §4-4 최소형, 완전형은 나중)

    private var historyRow: some View {
        let h = model.historySummary(item.id)
        return HStack(spacing: 6) {
            Image(systemName: "clock.arrow.circlepath").font(.caption2).foregroundStyle(Palette.textTertiary)
            Text(historyText(h)).font(.caption).foregroundStyle(Palette.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 4).padding(.top, 2)
    }

    private func historyText(_ h: (edits: Int, lastMillis: Int64?)) -> String {
        guard h.edits > 0 else { return "수정 이력 없음" }
        if let ms = h.lastMillis {
            let d = Date(timeIntervalSince1970: Double(ms) / 1000)
            return "수정 \(h.edits)회 · 최근 \(Self.shortFmt.string(from: d))"
        }
        return "수정 \(h.edits)회"
    }

    // MARK: 하단 필수 바 — [삭제하기]  …간격…  [취소] [저장]  (항상 노출)
    // 왼편 = 기억 삭제, 오른편 = 편집 세션(취소·저장). 기억하기는 위쪽 관문으로 이동.

    private var bottomBar: some View {
        VStack(spacing: 8) {
            // 저장 안 된 수정이 있음을 뚜렷이 알린다 — [수정 완료] 후에도 읽기전용으로 정돈돼 보여
            // "저장됨"으로 오해되기 쉬우므로(§2-A). [저장]을 눌러야 하는 상태임을 명시.
            // (빈 본문이면 저장 자체가 막히고 "본문은 비울 수 없어요"가 대신 뜨므로 여기선 숨긴다.)
            if dirty && !rawEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill").font(.caption2)
                    Text("저장하지 않은 수정이 있어요").font(.caption2.weight(.semibold))
                    Spacer()
                }
                .foregroundStyle(Palette.today)
            }
            HStack(spacing: 10) {
                // 왼편: 삭제하기(tombstone, 보관함서 복구 가능) — 공용 확인 대화상자를 거친다.
                Button(role: .destructive) { showDeleteConfirm = true } label: {
                    barLabel("삭제하기", "trash")
                }
                .buttonStyle(.bordered).tint(Palette.overdue)

                Spacer(minLength: 8)   // 간격

                // 오른편: 취소 · 저장(=수정 커밋)
                Button { dismiss() } label: {
                    barLabel("취소", "xmark")
                }
                .buttonStyle(.bordered).tint(Palette.textSecondary)
                Button { commit() } label: {
                    barLabel("저장", "square.and.arrow.down")
                }
                .buttonStyle(.borderedProminent).tint(Palette.accent)
                .disabled(!dirty || rawEmpty)   // 본문 전부 지운 상태면 저장 불가(내용 없는 기억 방지)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
        // 하단 바 버튼(삭제·취소·저장)도 원문 밖 — 누르면 키보드 내림(삭제 확인 팝업 전에도 정리).
        .simultaneousGesture(TapGesture().onEnded { rawFocused = false })
    }

    /// 기억하기 재확인 — 공용 대화상자. [취소하기] / [기억하기].
    private var rememberDialog: some View {
        ConfirmDialog(title: "정말로 기억하시겠습니까?",
                      cancelTitle: "취소하기", confirmTitle: "기억하기",
                      onCancel: { showRememberConfirm = false },
                      onConfirm: { showRememberConfirm = false; rememberAfterDialog() })
    }

    /// 원칙 지정 시 기억하기 자동 결정 안내 — 공용 대화상자, 안내형 단일 버튼.
    private var principleAutoRememberDialog: some View {
        StandardDialog(title: "'기억하기'로 자동 결정됩니다") {
            DialogButton(title: "확인", prominent: true) { commitAsPrinciple() }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// [삭제하기] 재확인 — 공용 대화상자. [취소] / [삭제](overdue 톤). 확인 시 삭제 후 화면 닫기.
    /// 삭제 로직 자체는 무변경(tombstone → 보관된 기억, 복구 가능). 확인 단계만 앞에 둔다.
    private var deleteDialog: some View {
        // 되풀이는 "그만두기 = 삭제"임을 명확히(잠시 멈춤은 꺼두기, §5). 헷갈리지 않게 문구로 가른다.
        // **저장값을 본다**(2026-08-08) — 지우는 것은 **저장된 항목**이다. 분류를 draft에서만 바꿔 둔 채
        // 삭제하면, 옛 코드는 되풀이 항목에 「정말로 삭제하시겠습니까?」를 띄워 **"기록도 함께"를 안 말했다.**
        let isRecur = savedType == "recurrence"
        return ConfirmDialog(
            title: isRecur ? "되풀이를 그만둘까요? 기록도 함께 삭제돼요" : "정말로 삭제하시겠습니까?",
            confirmTitle: isRecur ? "그만두기" : "삭제", confirmTint: Palette.overdue,
            onCancel: { showDeleteConfirm = false },
            onConfirm: { showDeleteConfirm = false; model.delete(item); dismiss() })
    }

    /// 규칙 1 안내 — 단일 버튼 정보 팝업(+7일 상한/차단, 저장 위반 차단 공용). 확인하면 닫기만(편집 유지).
    private func noticeDialogView(_ msg: String) -> some View {
        StandardDialog(title: msg) {
            DialogButton(title: "확인", prominent: true) { noticeDialog = nil }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 저장 안 한 수정을 두고 < 뒤로가기 → 재확인. 두 개만: [나가기](버림) / [계속 수정하기](머무름).
    /// 저장은 이미 [저장] 버튼이 있으므로 팝업에 넣지 않는다. 편집 중이든 [수정 완료] 뒤든 dirty면 같은 팝업.
    /// 안전한 쪽([계속 수정하기])을 prominent로 둔다 — 팝업이 잦아도 실수로 버려지지 않게.
    ///
    /// **★ 문구를 상태별로 가른다 (2026-08-18 사용자 결정 — `edit-policy.md` §1-A 미결 ㉢ 닫힘).**
    ///
    /// **왜:** 임시 항목 화면에는 **[저장] 버튼이 없다**([삭제하기]·[기억하기] 둘뿐 — `decideRow`).
    /// 그런데 한 문구를 쓰면 **화면에 없는 버튼을 가리킨다.** 2026-08-18 실기기 확인에서
    /// **임시·확정 양쪽에 같은 문구가 뜨는 것**을 사용자가 봤다(확인 목록 ③).
    /// → **각 화면이 실제로 가진 버튼을 이름으로 부른다.**
    ///
    /// **「고친」이 아니라 「수정한」이다** (2026-08-18 사용자). 화면에 나오는 말이므로 사용자가 정한다(항시 규칙 6).
    private var discardDialog: some View {
        ConfirmDialog(title: isRemembered
                        ? "수정 중이에요. 저장하지 않고 나가면 수정한 내용이 사라져요"
                        : "기억하기를 하지 않으면 수정한 내용이 사라져요",
                      cancelTitle: "나가기", confirmTitle: "계속 수정하기",
                      onCancel: { showDiscardConfirm = false; dismiss() },   // 나가기 = 버리고 닫기
                      onConfirm: { showDiscardConfirm = false })              // 계속 수정하기 = 머무름
    }

    /// 하단 바 버튼 라벨 — 줄바꿈 금지 + 좌우 여백으로 폭 확보(확정 글자 깨짐 방지).
    private func barLabel(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
    }

    // MARK: 행동 구현

    private func commit() {
        // 규칙 1을 막는 **유일한 자리**(B, 2026-08-08): 미리 알림이 마감보다 늦으면(마감 미래 기준) 저장을 막고 알린다.
        // 고르는 단계(DatePicker)에는 범위 제한이 없다 — 범위가 값을 조용히 끌어당기기 때문이다(`timeRow` 참조).
        // 그래서 여기가 "최종" 방어선이 아니라 **그냥 방어선**이다. 사람이 위반을 고르는 것은 정상 경로다.
        //
        // **검사 대상 = 저장될 최종 쌍**(화면 draft 쌍이 아니다 — 2026-08-06 `가`).
        // 저장은 `EditDiff`가 낸 **바뀐 필드만** 내보내고 그것이 **현재 저장값** 위에 필드별 LWW로 얹힌다.
        // `item`은 스냅숏이라 낡을 수 있으므로(완료→취소·외부 동기화·배경 전진) 모델의 현재 항목을 다시 집는다.
        // ⚠️ **`changes`는 계속 스냅숏 기준으로 낸다** — 그게 "사람이 실제로 건드린 것"이고, 신선한 항목과
        // 비교하면 안 건드린 칸까지 실려 **모델의 새 값을 낡은 화면 값으로 덮어쓴다**(취소된 완료가 되살아난다).
        // 그래서 진단이 "저장 범위"가 아니라 **검사 입력**을 고치는 쪽이었다.
        //
        // **문구는 이유별로 갈린다**(미결 3번, 2026-08-07). 옛 문구는 하나뿐이라
        // 시각 위반에서 「마감 **하루 전**(**마감 당일**)까지만」이라는 **자기모순**을 냈고,
        // **원인이 시각인데 날짜만 말해** 사람이 무엇을 고칠지 알 수 없었다(이미 그 날짜로 맞춰 뒀으므로).
        // ★ **규칙을 설명하는 말("하루 전")을 빼고 값과 할 일만 말한다** — 그래야 규칙이 갈려도 안 틀린다.
        let saving = changes
        let fresh = model.current(item.id) ?? item
        if let block = ItemSchedule.rule1Block(applying: saving, to: fresh, now: Date()) {
            switch block {
            case let .dayBeforeDeadline(cap, deadline):
                // **"까지로"**(2026-08-07 정정) — cap 그 날 자체가 허용인데 "이전으로"는 그 날을 빼는 것으로 읽힌다.
                // 거짓말을 없애는 작업에서 남길 애매함이 아니다.
                // **마감도 날짜만 말한다**(`withTime: false`) — 이 갈래의 판정이 날짜 단위이기 때문이다.
                noticeDialog = "미리 알림을 \(korDateTime(cap, withTime: false))까지로 옮겨 주세요 — 마감은 \(korDateTime(deadline, withTime: false))이에요"
            case let .atOrBeforeDeadline(deadline):
                noticeDialog = "미리 알림이 마감(\(korDateTime(deadline)))보다 늦어요 — 시각을 앞으로 옮겨 주세요"
            }
            return
        }
        // 미기억 항목을 원칙으로 지정한 채 저장하면 → 기억하기로 자동 결정(원칙은 살아있는 기억).
        // 먼저 안내 팝업을 띄우고, 확인 시 저장 + 자동 기억하기.
        //
        // **★ 판정을 draft(`normalizedType`)에서 「이번 저장이 실제로 쓰는 값」(`saving`)으로 바꿨다
        // (2026-08-14).** 옛 조건은 *"지금 화면의 분류가 원칙인가"*였는데, §1-A로 임시일 때 분류를 못
        // 바꾸게 되자 **이미 `principle`인 임시 항목**(자동 분류가 붙일 수 있다)에서 **원문만 고쳐 저장해도**
        // 이 팝업이 떠서 **자동으로 확정되는** 길이 열렸다. `edit-policy.md` §1의
        // *"기억하기는 절대 자동으로 일어나지 않는다"*를 정면으로 깨는 자리다.
        //
        // `saving`은 §1-A에 따라 임시면 `raw`만 남으므로 `saving["type"]`은 절대 안 담긴다
        // → **임시 항목에서 이 경로는 도달 불가**가 된다. 분류를 원칙으로 바꾸는 것 자체가
        // 기억하기 뒤에만 가능하므로, 그때는 이미 확정이라 자동 확정할 것도 없다.
        // **즉 이 조항은 §1-A로 사실상 은퇴한다** — 지우지 않고 남기는 이유는 조건이 왜 이 모양인지가
        // 이 주석으로만 보이기 때문이다.
        if !isRemembered && saving["type"] == "principle" {
            showPrincipleAutoRemember = true
            return
        }
        model.commitEdits(item, changes: saving)   // 빈 변경이면 내부에서 무시
        dismiss()
    }

    /// 원칙 자동 기억하기 안내 확인 → 저장 + 기억하기(단방향) 함께 반영.
    private func commitAsPrinciple() {
        showPrincipleAutoRemember = false
        model.commitEdits(item, changes: changes)
        model.confirm(item)
        dismiss()
    }

    /// [기억하기] — **수정 커밋 + 기억하기를 함께** 한다 (edit-policy §1-A·§2 예외, 2026-08-14).
    /// 화면은 닫지 않는다. 로컬 상태로 버튼/배지를 비우고 **정상 상세 화면으로 바뀐다.**
    ///
    /// **왜 커밋을 겸하나:** 임시 화면에는 [저장]이 없다(하단 필수 바를 안 그린다). 그래서
    /// **원문·분류를 고쳤다면 여기서 반영된다** — 안 그러면 고친 것이 조용히 사라진다.
    /// §2의 *"[저장]과 [기억하기]를 절대 섞지 않는다"*는 **확정 뒤**의 규칙으로 좁혀졌다.
    ///
    /// **순서: 커밋 → 확정.** 두 이벤트로 나눠 붙인다(제어 필드 `confirmed`는 편집 이벤트에 섞지 않는다는
    /// 규약을 지킨다 — `EditDiff`가 그것을 보장하고 `MergeEngine`이 별도 OR-머지로 읽는다).
    /// `commitEdits`가 임시일 때 `raw`·`type`만 통과시키므로 활용 칸이 새 들어갈 여지도 없다.
    /// **[기억하기]를 누른 뒤의 움직임** (설계 §0 28~32번 · 커밋 ②-2).
    ///
    /// **무엇이 움직이나:** 확정되면 `decideRow`가 사라지고 **보조 자료 카드가 위로 올라가며**,
    /// 시간 설정·반복 설정·수정 이력(그리고 조건이 맞으면 배너)이 **새로 나타난다.**
    /// **한 단계로 둔다** — 있던 카드는 미끄러지고 **새것은 기본 페이드**다(§0 28번).
    /// ⛔ **두 단계로 나누지 말 것** — 랩에서 재보니 배너가 뜨는 경우 **「올라갔다 다시 내려온다」**로
    /// 더 나빴다(설계 §3-H-1의 세 줄).
    ///
    /// **0.15초 늦추는 이유:** 재확인 대화상자는 **`black.opacity(0.4)` 스크림**을 깔고 **0.15초**에 걷힌다
    /// (`StandardDialog` · 이 파일의 `.animation(…0.15…)`). 같은 프레임에 시작하면
    /// **움직임의 앞부분이 막 아래에서 일어나** 「어디서 왔는지」가 약해진다.
    /// ⛔ **스크림 값을 줄이지 않는다** — **대화상자 여섯이 같은 값을 쓴다**(§0 31번 · §3-I-3).
    private func rememberAfterDialog() {
        guard !reduceMotion else { remember(); return }   // 동작 줄이기 — 지연도 애니메이션도 없다
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            withAnimation(.easeInOut(duration: 0.35)) { remember() }
        }
    }

    private func remember() {
        let saving = changes
        if !saving.isEmpty { model.commitEdits(item, changes: saving) }
        model.confirm(item)
        baseline = baseline.applying(saving)   // 기준선을 옮겨 dirty를 비운다(안 옮기면 나갈 때 경고가 뜬다)
        isRemembered = true
    }

    // MARK: 도우미

    private func sectionLabel(_ s: String) -> some View {
        Text(s).font(.caption.weight(.semibold)).foregroundStyle(Palette.textSecondary)
    }

    /// String?("YYYY-MM-DD" 또는 "…THH:mm") ↔ Date 브릿지(날짜 피커용).
    /// 날짜를 바꿔도 **원래 시각은 보존**한다(§6-B — withTimeOfDay).
    private func dateBinding(_ b: Binding<String?>) -> Binding<Date> {
        Binding(
            get: { ItemSchedule.parseDay(b.wrappedValue ?? "") ?? Date() },
            set: { b.wrappedValue = ItemSchedule.withTimeOfDay(Self.fmt.string(from: $0), from: b.wrappedValue) }
        )
    }

    /// "시각" 토글 — OFF면 날짜만(시각 안 넣을 자유, §6-B), ON이면 **꺼둘 때의 시각**을 되살린다.
    ///
    /// **끌 때 시각을 기억한다**(2026-08-09) — 안 그러면 껐다 켜는 것만으로 사람이 정한 6:00이
    /// 기본값 09:00으로 덮인다. **화면이 흐리게 보여주는 그 시각과 켤 때 붙는 시각이 같은 값**이어야
    /// 하므로 둘 다 `pendingTime(_:)` 하나를 본다(갈리면 화면이 거짓말을 한다).
    private func timeEnabledBinding(_ b: Binding<String?>, _ field: TimeField) -> Binding<Bool> {
        Binding(
            get: { ItemSchedule.timeOfDay(b.wrappedValue ?? "") != nil },
            set: { on in
                let base = Self.fmt.string(from: ItemSchedule.parseDay(b.wrappedValue ?? "") ?? Date())
                if on {
                    b.wrappedValue = "\(base)T\(pendingTime(field))"
                } else {
                    if let t = ItemSchedule.timeOfDay(b.wrappedValue ?? "") {
                        rememberedTime[field] = String(format: "%02d:%02d", t.hour, t.minute)   // ← 끄기 전에 기억
                    }
                    b.wrappedValue = base
                }
            }
        )
    }

    /// **꺼져 있을 때 화면이 보여줄 시각 = 켜면 붙을 시각.** 기억해 둔 것이 없으면 09:00(옛 기본값).
    private func pendingTime(_ field: TimeField) -> String { rememberedTime[field] ?? "09:00" }

    /// 흐린 시각 표시용 — **시스템 시각 형식 그대로**(피커가 보여주는 모양과 같게. 새 표기를 만들지 않는다).
    private func pendingTimeText(_ field: TimeField) -> String {
        let hm = pendingTime(field).split(separator: ":").compactMap { Int($0) }
        var c = DateComponents(); c.hour = hm.first ?? 9; c.minute = hm.count > 1 ? hm[1] : 0
        guard let date = Calendar.current.date(from: c) else { return pendingTime(field) }
        return Self.timeFmt.string(from: date)
    }

    /// 시·분 피커 브릿지 — 날짜부는 유지하고 시각만 바꾼다. 쓰기 표준형 `T`.
    private func timeBinding(_ b: Binding<String?>) -> Binding<Date> {
        Binding(
            get: { ItemSchedule.parseDay(b.wrappedValue ?? "") ?? Date() },
            set: { picked in
                let t = Calendar.current.dateComponents([.hour, .minute], from: picked)
                let base = Self.fmt.string(from: ItemSchedule.parseDay(b.wrappedValue ?? "") ?? picked)
                b.wrappedValue = String(format: "%@T%02d:%02d", base, t.hour ?? 0, t.minute ?? 0)
            }
        )
    }

    static func isRealDate(_ s: String?) -> Bool {
        // 실제 날짜(YYYY-MM-DD)만 "시점 있음". none·빈값·깨진 값·레거시 "weekly"는 전부 false.
        ItemSchedule.parseDay(s ?? "") != nil
    }

    static let fmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    /// 시각 표시(「오전 6:00」) — 기기 형식을 따른다. 컴팩트 시각 피커와 같은 모양이 나오게.
    static let timeFmt: DateFormatter = {
        let f = DateFormatter(); f.timeStyle = .short; f.dateStyle = .none; return f
    }()
    static let shortFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

extension View {
    /// 상세 화면 카드 배경(surface + hairline).
    ///
    /// ⚠️ **2026-08-23에 `private`을 뗐다** — **보조 자료 카드**(`MediaCard.swift`)가 같은 배경을 쓴다.
    /// ⛔ **베껴 두면 갈린다** — 상세의 카드가 바뀌었는데 자료 카드만 옛 모양으로 남는 일을 막는다
    /// (랩이 앱 색을 베껴 두고 안 따라오는 것과 **반대 판단**이다: 저쪽은 실험용이라 갈려도 되고,
    /// 이쪽은 **같은 화면에 나란히 서는 카드**라 갈리면 바로 보인다).
    func card() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border))
    }
}
