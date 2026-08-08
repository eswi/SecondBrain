import SwiftUI
import SecondBrainCore
import MapKit
import CoreLocation
#if os(iOS)
import UIKit
#endif

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
    /// 규칙 1 안내(단일 버튼 정보 팝업) — +7일 미루기 상한/차단, 저장 시 위반 차단에 공용으로 쓴다.
    @State private var noticeDialog: String?

    /// 원문 편집 포커스. 원문 밖을 누르면 내리고(키보드 숨김), 원문을 다시 누르면 그 위치에 커서·키보드 복귀.
    @FocusState private var rawFocused: Bool

    /// 원본 음성 "다시 듣기" 재생기(성역 카드).
    @StateObject private var audio = AudioPlayer()

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                rawSection
                // 원문 밖 전체 — 빈 여백이든 버튼·메뉴·날짜·다시듣기든 누르면 키보드를 내린다(원문 편집 종료).
                // simultaneousGesture라 컨트롤 동작과 **함께** 발화하고(버튼은 정상 동작), rawSection은
                // 이 그룹 밖이라 원문 탭은 방해받지 않는다(탭하면 그 위치에 커서·키보드 복귀 — .focused 바인딩).
                VStack(alignment: .leading, spacing: 14) {
                    pausedBanner   // 되풀이 꺼둠이면 상단에 바로(잊으면 약을 안 챙긴다 — "지금 도느냐")
                    missedBanner   // N일 놓침 주의(§4)
                    overdueHiddenBanner   // 늦었는데 숨겨진 것(D) — 언제 돌아오는지
                    anchorBanner   // 되풀이인데 회차 시각(마감) 없으면 안내(조용히 안 도는 것 방지)
                    leadClampedBanner   // 회차 전진이 미리 알림을 당겼으면 말한다((c)) — 할 일 없는 통지라 맨 아래
                    metaSection
                    if !isRemembered { rememberButton }   // 기본정보 아래 — 아직 안 한 기억에만
                    typeSection
                    if let q = item.fields["question"], !q.isEmpty { questionSection(q) }
                    timeSection          // '시간 설정'(기준 날짜) — 위 (첫 카드 위치 통일)
                    recurrenceSection    // '반복 설정'(주기·자동완성·꺼두기) — 아래
                    historyRow
                }
                .contentShape(Rectangle())
                .simultaneousGesture(TapGesture().onEnded { rawFocused = false })
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
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
        .overlay { if let msg = noticeDialog { noticeDialogView(msg) } }
        .animation(.easeInOut(duration: 0.15), value: showRememberConfirm)
        .animation(.easeInOut(duration: 0.15), value: showPrincipleAutoRemember)
        .animation(.easeInOut(duration: 0.15), value: showDeleteConfirm)
        .animation(.easeInOut(duration: 0.15), value: showDiscardConfirm)
        .animation(.easeInOut(duration: 0.15), value: noticeDialog)
    }

    /// 커스텀 뒤로가기: 저장 안 한 수정이 있으면 확인, 없으면 즉시 닫기.
    private func backTapped() {
        if dirty { showDiscardConfirm = true } else { dismiss() }
    }

    // MARK: 원문 — 상세 진입 시 바로 편집 가능(별도 진입 없음, edit-policy.md §2-A).
    // 텍스트 층 가변(§6). 고치면 하단 [저장]이 활성(수정 감지). [저장]=전체 수정 커밋(≠ 기억하기, §2).
    // (명시적 [수정하기]/[수정 완료] 진입 방식을 시도했다가 되돌림 — 바로 편집이 낫다는 판단, 2026-07-30.)

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("원문")
            // TextEditor 대신 axis:.vertical TextField — 내용 따라 높이가 늘고 **자체 스크롤이 없어**
            // 바깥 ScrollView가 그대로 스크롤된다(긴 원문 위를 드래그해도 페이지가 넘어감). 여러 줄·줄바꿈 지원.
            TextField("원문", text: $raw, axis: .vertical)
                .font(.body)
                .foregroundStyle(Palette.textPrimary)
                .textFieldStyle(.plain)
                .focused($rawFocused)   // 탭하면 포커스·키보드(커서는 탭 위치) / 밖을 누르면 아래에서 해제
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

    // MARK: 메타 — 최초 수집 정보(불변 성역, §4-1·§7). 언제·기기·방식.

    /// **⚠️ 2026-08-08 전수 점검에서 「안 고침」** — 스냅숏 `item`을 읽지만 여기 나오는 것은
    /// 캡처 시각·방식·기기·음성·사진처럼 **어떤 편집으로도 안 바뀌는 필드**다(화면이 그렇게 말하고도 있다).
    /// 낡을 여지가 없으므로 `saved`로 옮길 이유가 없다.
    private var metaSection: some View {
        let when = "\(item.date ?? "") \(item.time ?? "")".trimmingCharacters(in: .whitespaces)
        let device = CaptureDevice.label(source: item.source, createdDeviceId: item.createdHLC.deviceId,
                                         stored: item.fields["device"])
        return VStack(alignment: .leading, spacing: 7) {
            sectionLabel("최초 수집 · 성역")
            metaRow("clock", when.isEmpty ? "(시각 없음)" : when)                    // 언제
            metaRow("iphone", device)                                               // 기기
            metaRow(SourceIcon.symbol(item.source), Self.sourceLabel(item.source))   // 방식
            if item.fields["audio"] != nil { audioRow }                              // 원본 음성(있으면)
            if item.fields["photo"] != nil { photoRow }                              // 원본 사진(있으면)
            Text("이 값은 어떤 편집으로도 바뀌지 않아요").font(.caption2).foregroundStyle(Palette.textTertiary)
        }
        .padding(14).card()
    }

    private func metaRow(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.caption).foregroundStyle(Palette.textTertiary).frame(width: 16)
            Text(text).font(.callout).foregroundStyle(Palette.textPrimary)
        }
    }

    /// 원본 음성 "다시 듣기" — 이 기기에 파일이 있으면 재생 버튼, 없으면(다른 기기 녹음) 안내.
    @ViewBuilder private var audioRow: some View {
        if let url = AudioStore.url(forId: item.id) {
            Button { audio.toggle(url: url) } label: {
                HStack(spacing: 8) {
                    Image(systemName: audio.isPlaying ? "stop.circle.fill" : "play.circle.fill")
                        .font(.callout).foregroundStyle(Palette.accent).frame(width: 16)
                    Text(audio.isPlaying ? "정지" : "원본 음성 다시 듣기")
                        .font(.callout).foregroundStyle(Palette.accent)
                }
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 8) {
                Image(systemName: "mic.slash").font(.caption).foregroundStyle(Palette.textTertiary).frame(width: 16)
                Text("원본 음성 있음 · 이 기기엔 없음").font(.callout).foregroundStyle(Palette.textTertiary)
            }
        }
    }

    /// 원본 사진 — 이 기기에 파일이 있으면 이미지(+ EXIF 위치 지도), 없으면 안내. audioRow 미러.
    @ViewBuilder private var photoRow: some View {
        #if os(iOS)
        if let url = PhotoStore.url(forId: item.id), let img = UIImage(contentsOfFile: url.path) {
            VStack(alignment: .leading, spacing: 8) {
                Image(uiImage: img)
                    .resizable().scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
                if let coord = PhotoStore.coordinate(forId: item.id) { photoMap(coord) }  // 사진 EXIF의 촬영 위치
            }
        } else {
            photoMissingRow
        }
        #else
        photoMissingRow
        #endif
    }

    #if os(iOS)
    /// 사진 EXIF 좌표를 작은 지도로(비상호작용) + 지도 앱 열기. 좌표는 사진 안에만 있음(그릇 X).
    @ViewBuilder private func photoMap(_ coord: CLLocationCoordinate2D) -> some View {
        let region = MKCoordinateRegion(center: coord,
                                        span: MKCoordinateSpan(latitudeDelta: 0.003, longitudeDelta: 0.003))
        VStack(alignment: .leading, spacing: 6) {
            Map(initialPosition: .region(region), interactionModes: []) {
                Marker("촬영 위치", coordinate: coord)
            }
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.border))
            Button {
                if let u = URL(string: "http://maps.apple.com/?ll=\(coord.latitude),\(coord.longitude)") {
                    UIApplication.shared.open(u)
                }
            } label: {
                Label("지도 앱에서 열기", systemImage: "map").font(.caption)
            }
            .buttonStyle(.plain).foregroundStyle(Palette.accent)
        }
    }
    #endif

    private var photoMissingRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "photo").font(.caption).foregroundStyle(Palette.textTertiary).frame(width: 16)
            Text("원본 사진 있음 · 이 기기엔 없음").font(.callout).foregroundStyle(Palette.textTertiary)
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

    // MARK: 기억하기 버튼 (기본정보 아래 — 최소 필터링 관문, 단방향)

    private var rememberButton: some View {
        Button { showRememberConfirm = true } label: {
            Label("기억하기", systemImage: "checkmark.seal.fill")
                .font(.body.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.borderedProminent).tint(Palette.today)
        // 재확인 대화상자는 화면 전체 오버레이(rememberDialog)로 띄운다 — 제목을 크게 하려고 커스텀.
    }

    // MARK: 분류 (미기억이면 "임시" 배지 + override)

    /// **편집 중인 분류**(draft). 편집기(분류 메뉴·시간 설정 노출·반복 설정)가 쓴다.
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
            HStack {
                sectionLabel("분류")
                Spacer()
                if !isRemembered { ProvisionalBadge() }   // 기억하면 표시 없음(임시 배지 제거)
            }
            Menu {
                ForEach(ClassRegistry.assignable) { m in    // 기본층 6 + 유연층(주차 위치)
                    Button { type = m.key } label: { Label(m.label, systemImage: m.symbol) }
                        .disabled(m.key == normalizedType)
                }
                Divider()
                Button { type = "" } label: { Label("미분류", systemImage: "questionmark.circle") }
                    .disabled(normalizedType == nil)
            } label: {
                let m = ClassRegistry.meta(normalizedType)
                HStack(spacing: 9) {
                    Image(systemName: m.symbol).foregroundStyle(m.color)
                    Text(m.label).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .menuStyle(.button).buttonStyle(.plain)
            // Menu는 탭을 자기가 삼켜(메뉴 표시) 바깥 TapGesture가 안 걸린다 → touch-down에 걸리는
            // DragGesture(0)로 메뉴 여는 순간 키보드를 내린다. simultaneous라 메뉴 동작은 그대로.
            .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in
                if rawFocused { rawFocused = false }
            })
        }
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
                    if usesDue { timeRow(ClassRegistry.title(normalizedType, .due), value: $due, showDefer: false) }
                    if usesDue && usesResurface { Divider().overlay(Palette.border) }
                    if usesResurface {
                        // 규칙 1은 **여기서 안 막는다** — [저장]에서 저장될 최종 짝으로 검사한다(B, 2026-08-08).
                        // 두 칸이 같은 `timeRow`를 같은 인자로 쓴다 = 날짜와 시각이 같은 방식으로 다뤄진다.
                        timeRow(ClassRegistry.title(normalizedType, .resurface), value: $resurface, showDefer: true)
                    }
                }
                .padding(14).card()
            }
        }
    }

    @ViewBuilder
    private func timeRow(_ title: String, value: Binding<String?>, showDefer: Bool) -> some View {
        let hasDate = Self.isRealDate(value.wrappedValue)
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.callout).foregroundStyle(Palette.textPrimary)
                Spacer()
                if hasDate {
                    Button("지우기") { value.wrappedValue = "none" }
                        .font(.caption).tint(Palette.overdue)
                } else {
                    Button("날짜 설정") { value.wrappedValue = Self.fmt.string(from: Date()) }
                        .font(.caption).tint(Palette.accent)
                }
            }
            if hasDate {
                // ★ **범위 제한(`in: ...ub`)을 두지 않는다** — B, 2026-08-08. 규칙 1은 [저장]에서만 막는다.
                //
                // **왜 뺐나:** 범위를 주면 피커가 **값의 원천이 된다.** `dateBinding`의 setter는 피커가 뱉은 값을
                // 그대로 draft에 쓰는데, 그것이 **사람이 고른 것인지 피커가 스스로 재조정한 것인지 구분할 수 없다.**
                // 실측(2026-08-08, 실기기): 선택값이 상한에 **딱 붙어 있으면 상한을 따라 움직인다** —
                // 마감을 08-09로 고친 draft에서 미리 알림 08-08에 **시각 토글만 켜자**(상한이 08-08→08-09로 넓어짐)
                // 날짜가 저절로 08-09가 됐다. 끄면 08-08로 돌아온다(왕복). **대조군:** 상한에 안 붙은 08-07은
                // 양쪽에서 안 움직였다 → 원인이 토글이나 시·분 피커가 아니라 **범위**임이 갈렸다.
                // → **앱이 사람이 안 건드린 값을 조용히 바꾼다.** 그 값은 규칙 1 위반도 아니라 저장 검사도 못 잡는다.
                //
                // **막음이 약해지지 않는다 — 오히려 넓어진다.** 피커 상한은 날짜만 봐서 마감과 **같은 날 늦은 시각**을
                // 통과시켰다(시각 칸엔 애초에 상한이 없었다 = 반쪽 방어). `violatesRule1`은 시각 인지라 그것도 잡는다.
                // 달라지는 것은 **언제 아느냐** 하나다: 고를 때 → [저장] 누를 때(`rule1Block`이 값과 할 일을 말한다).
                DatePicker("", selection: dateBinding(value), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
                // 시각(선택) — OFF면 날짜만, ON이면 시·분 지정(§6-B: 시각 안 넣을 자유). 여기도 상한 없음(위와 같은 이유·같은 방식).
                HStack(spacing: 8) {
                    Text("시각").font(.caption).foregroundStyle(Palette.textSecondary)
                    Toggle("", isOn: timeEnabledBinding(value)).labelsHidden().tint(Palette.accent)
                    Spacer()
                    if ItemSchedule.timeOfDay(value.wrappedValue ?? "") != nil {
                        DatePicker("", selection: timeBinding(value), displayedComponents: .hourAndMinute)
                            .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
                    }
                }
            } else {
                Text("없음")   // 시점 없음. (레거시 "weekly" 값도 여기로 — 반복 기능은 없었다: 날짜 없음의 동의어)
                    .font(.caption).foregroundStyle(Palette.textTertiary)
            }
            if showDefer {
                Button { deferResurface(value) } label: {
                    Label("+7일 미루기", systemImage: "clock")
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
        }
    }

    /// +7일 미루기(상세 draft) — 규칙 1을 지켜 미리 알림 draft를 정한다. 위반 상태로 세팅하지 않는다.
    /// 상한에 걸려 당겨졌거나 마감 임박이라 못 미루면 안내 팝업으로 알린다("알린다").
    private func deferResurface(_ value: Binding<String?>) {
        switch ItemSchedule.deferSevenDays(due: due, now: Date(), resurfaceHasTime: ItemSchedule.timeOfDay(value.wrappedValue ?? "") != nil) {
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
                menuRow("반복 주기", value: Recurrence.Unit(rawValue: recurUnit ?? "")?.korean ?? "없음") {
                    ForEach(Recurrence.Unit.allCases, id: \.self) { u in
                        Button(u.korean) { recurUnit = u.rawValue }
                    }
                    Button("없음") { recurUnit = nil }
                }
                Divider().overlay(Palette.border)
                menuRow("자동 완성", value: Recurrence.AutoComplete(rawValue: recurAuto)?.korean ?? "없음") {
                    ForEach(Recurrence.AutoComplete.allCases, id: \.self) { a in
                        Button(a.korean) { recurAuto = a.rawValue }
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
    private func menuRow<Content: View>(_ title: String, value: String, @ViewBuilder menu: () -> Content) -> some View {
        HStack {
            Text(title).font(.callout).foregroundStyle(Palette.textPrimary)
            Spacer()
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
                      onConfirm: { showRememberConfirm = false; remember() })
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
    private var discardDialog: some View {
        ConfirmDialog(title: "수정 중이에요. 저장하지 않고 나가면 고친 내용이 사라져요",
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
        if !isRemembered && normalizedType == "principle" {
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

    /// [기억하기] — 기억하기 처리만(§3 단방향). 화면은 닫지 않는다. 로컬 상태로 버튼/배지를 비운다.
    /// 미저장 편집은 draft에 그대로 남아 [저장]으로 반영할 수 있다(수정 ≠ 기억하기, §2 — 서로 독립).
    /// 엔진은 그대로 `model.confirm` 재사용(개념·이름만 "기억하기").
    private func remember() {
        model.confirm(item)
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

    /// "시각" 토글 — OFF면 날짜만(시각 안 넣을 자유, §6-B), ON이면 기본 09:00을 붙여 시·분 지정을 연다.
    private func timeEnabledBinding(_ b: Binding<String?>) -> Binding<Bool> {
        Binding(
            get: { ItemSchedule.timeOfDay(b.wrappedValue ?? "") != nil },
            set: { on in
                let base = Self.fmt.string(from: ItemSchedule.parseDay(b.wrappedValue ?? "") ?? Date())
                b.wrappedValue = on ? "\(base)T09:00" : base
            }
        )
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
    static let shortFmt: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

private extension View {
    /// 상세 화면 카드 배경(surface + hairline).
    func card() -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Palette.border))
    }
}
