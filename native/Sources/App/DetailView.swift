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
    /// 판정 = `Recurrence.doneThisCycle`(마감 앵커 기준, 게이트와 동일 — 2026-08-03 #4).
    @State private var cycleDoneLocal: Bool

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
    }

    private var changes: [String: String] {
        var c = EditDiff.changes(type: type, due: due, resurface: resurface, raw: raw, from: item)
        foldRecurChanges(into: &c)   // 되풀이 설정도 같은 [저장] 이벤트에 묶는다(새 필드).
        return c
    }

    /// 되풀이 설정 draft를 원본과 비교해 바뀐 새 필드만 changes에 넣는다(값 안 지움 — 미설정은 빈 문자열).
    private func foldRecurChanges(into c: inout [String: String]) {
        let oldUnit = item.fields[Recurrence.unitKey] ?? ""
        if (recurUnit ?? "") != oldUnit { c[Recurrence.unitKey] = recurUnit ?? "" }
        let oldAuto = item.fields[Recurrence.autoKey] ?? Recurrence.AutoComplete.none.rawValue
        if recurAuto != oldAuto { c[Recurrence.autoKey] = recurAuto }
        let oldPaused = item.fields[Recurrence.pausedKey] == "true"
        if recurPaused != oldPaused { c[Recurrence.pausedKey] = recurPaused ? "true" : "false" }
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
                    anchorBanner   // 되풀이인데 회차 기준(미리 알림) 없으면 안내(조용히 안 도는 것 방지)
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

    private var normalizedType: String? { (type?.isEmpty ?? true) ? nil : type }

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
                        // 규칙 1: 미리 알림은 마감 하루 전까지만. DatePicker 범위를 상한으로 제한(가능한 만큼).
                        let bound = ItemSchedule.resurfaceUpperBound(due: due, now: Date(), resurfaceHasTime: ItemSchedule.timeOfDay(resurface ?? "") != nil)
                        timeRow(ClassRegistry.title(normalizedType, .resurface), value: $resurface,
                                showDefer: true, upperBound: bound)
                    }
                }
                .padding(14).card()
            }
        }
    }

    @ViewBuilder
    private func timeRow(_ title: String, value: Binding<String?>, showDefer: Bool,
                        upperBound: Date? = nil) -> some View {
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
                // 규칙 1: 상한이 있으면 그 날까지만 고를 수 있게 범위 제한(미리 알림 ≤ 마감 − 1일).
                // 상한이 지금 값보다 과거여도(마감을 앞으로 당긴 경우) 저장 시 검증이 최종 방어선이다.
                if let ub = upperBound {
                    DatePicker("", selection: dateBinding(value), in: ...ub, displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
                } else {
                    DatePicker("", selection: dateBinding(value), displayedComponents: .date)
                        .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
                }
                // 시각(선택) — OFF면 날짜만, ON이면 시·분 지정(§6-B: 시각 안 넣을 자유). 규칙1은 날짜 단위라 여기 상한 없음.
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
                noticeDialog = "마감이 가까워 미리 알림을 마감 하루 전(\(InboxModel.korShort(day)))으로 맞췄어요"
            }
        case .blocked(let cap):
            noticeDialog = "마감이 임박해(하루 전 \(InboxModel.korShort(cap))) 더 미룰 수 없어요"
        }
    }

    // MARK: 반복 설정 (되풀이 분류 전용, Stage 2) — '시간 설정' 아래 카드.
    // 주기·자동완성 = "어떻게 도느냐" / 꺼두기 = "지금 도느냐". 회차·완료는 Stage 3·4.

    /// 되풀이 꺼둠이면 상세 상단에 바로 보이는 배너(스크롤 없이). 꺼둔 걸 잊지 않게.
    @ViewBuilder
    private var pausedBanner: some View {
        if normalizedType == "recurrence", recurPaused {
            HStack(spacing: 8) {
                Image(systemName: "pause.circle.fill").foregroundStyle(Palette.overdue)
                Text("되풀이 꺼둠 — 알림·되살아나기 멈춤").font(.callout.weight(.semibold)).foregroundStyle(Palette.overdue)
                Spacer()
            }
            .padding(12)
            .background(Palette.overdue.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// 회차 기준(미리 알림) 없음 안내 — 되풀이는 미리 알림이 앵커라, 없으면 회차가 안 돈다.
    /// 조용히 안 도는 대신 화면으로 알린다(#3). "시간 설정"의 회차 시각(미리 알림)을 채우게 유도.
    @ViewBuilder
    private var anchorBanner: some View {
        if normalizedType == "recurrence", !Self.isRealDate(due) {
            HStack(spacing: 8) {
                Image(systemName: "info.circle.fill").foregroundStyle(Palette.accent)
                Text("회차 시각이 없어요 — 위 '시간 설정'에서 **회차 시각(마감)**을 정해야 반복이 돕니다")
                    .font(.caption).foregroundStyle(Palette.textSecondary)
                Spacer()
            }
            .padding(12).background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    /// N일 놓침 주의(§4) — 상단에 바로. 되풀이·놓침>0일 때만.
    @ViewBuilder
    private var missedBanner: some View {
        let n = Recurrence.missed(item, now: Date())
        if normalizedType == "recurrence", n > 0 {
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
                Button("취소") { model.undoRecurComplete(item); cycleDoneLocal = false }
                    .font(.caption).tint(Palette.overdue)
            }
        } else {
            Button { model.markDone(item); cycleDoneLocal = true } label: {
                Label("이번 것 했어요", systemImage: "checkmark.circle")
                    .font(.callout.weight(.semibold)).frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent).tint(Palette.accent)
        }
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
        let isRecur = normalizedType == "recurrence"
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
        // 규칙 1 최종 방어선: 미리 알림이 마감 하루 전보다 늦으면(마감 미래 기준) 저장을 막고 알린다.
        // DatePicker 범위 제한을 우회했거나 마감을 나중에 앞으로 당겨 역전된 경우를 여기서 잡는다.
        if ItemSchedule.violatesRule1(resurface: resurface, due: due, now: Date()) {
            let ub = ItemSchedule.resurfaceUpperBound(due: due, now: Date(), resurfaceHasTime: ItemSchedule.timeOfDay(resurface ?? "") != nil)
            let cap = ub.map { InboxModel.korShort(ItemSchedule.dayString($0)) } ?? ""
            noticeDialog = "미리 알림은 마감 하루 전(\(cap))까지만 설정할 수 있어요"
            return
        }
        // 미기억 항목을 원칙으로 지정한 채 저장하면 → 기억하기로 자동 결정(원칙은 살아있는 기억).
        // 먼저 안내 팝업을 띄우고, 확인 시 저장 + 자동 기억하기.
        if !isRemembered && normalizedType == "principle" {
            showPrincipleAutoRemember = true
            return
        }
        model.commitEdits(item, changes: changes)   // 빈 변경이면 내부에서 무시
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
