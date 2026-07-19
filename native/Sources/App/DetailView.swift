import SwiftUI
import SecondBrainCore

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

    // draft — 편집 대상 필드만. raw(원문)는 없음(§8 잠금).
    @State private var type: String?
    @State private var due: String?
    @State private var resurface: String?

    /// 화면을 닫지 않고 기억하기 처리하므로(stale한 item 대신) 로컬로 상태를 든다.
    /// (엔진의 `confirmed`에 대응 — 개념·이름만 "기억하기"로 바뀜.)
    @State private var isRemembered: Bool
    @State private var showRememberConfirm = false
    /// 미기억 항목을 원칙으로 지정하고 저장할 때 "기억하기 자동 결정" 안내(원칙=살아있는 기억).
    @State private var showPrincipleAutoRemember = false

    init(item: ResolvedItem, model: InboxModel) {
        self.item = item
        self.model = model
        _type = State(initialValue: item.type)
        _due = State(initialValue: item.due)
        _resurface = State(initialValue: item.resurface)
        _isRemembered = State(initialValue: item.confirmed)
    }

    private var changes: [String: String] {
        EditDiff.changes(type: type, due: due, resurface: resurface, from: item)
    }
    private var dirty: Bool { !changes.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                rawSection
                metaSection
                if !isRemembered { rememberButton }   // 기본정보 아래 — 아직 안 한 기억에만
                typeSection
                timeSection
                historyRow
            }
            .padding(16)
            .padding(.bottom, 8)
        }
        .background(Palette.bg.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) { bottomBar }
        .navigationTitle("기억")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .overlay { if showRememberConfirm { rememberDialog } }
        .overlay { if showPrincipleAutoRemember { principleAutoRememberDialog } }
        .animation(.easeInOut(duration: 0.15), value: showRememberConfirm)
        .animation(.easeInOut(duration: 0.15), value: showPrincipleAutoRemember)
    }

    // MARK: 원문 (§8 잠금)

    private var rawSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionLabel("원문")
                Spacer()
                Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Palette.textTertiary)
            }
            Text(item.raw ?? "(내용 없음)")
                .font(.body).foregroundStyle(Palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            Text("원문 수정은 준비 중이에요").font(.caption2).foregroundStyle(Palette.textTertiary)
        }
        .padding(14).card()
    }

    // MARK: 메타 — 최초 수집 정보(불변 성역, §4-1·§7). 언제·기기·방식.

    private var metaSection: some View {
        let when = "\(item.date ?? "") \(item.time ?? "")".trimmingCharacters(in: .whitespaces)
        let device = CaptureDevice.label(source: item.source, createdDeviceId: item.createdHLC.deviceId)
        return VStack(alignment: .leading, spacing: 7) {
            sectionLabel("최초 수집 · 성역")
            metaRow("clock", when.isEmpty ? "(시각 없음)" : when)                    // 언제
            metaRow("iphone", device)                                               // 기기
            metaRow(SourceIcon.symbol(item.source), Self.sourceLabel(item.source))   // 방식
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
                ForEach(TypeCatalog.assignable) { m in
                    Button { type = m.key } label: { Label(m.label, systemImage: m.symbol) }
                        .disabled(m.key == normalizedType)
                }
                Divider()
                Button { type = "" } label: { Label("미분류", systemImage: "questionmark.circle") }
                    .disabled(normalizedType == nil)
            } label: {
                let m = TypeCatalog.meta(normalizedType)
                HStack(spacing: 9) {
                    Image(systemName: m.symbol).foregroundStyle(m.color)
                    Text(m.label).foregroundStyle(Palette.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(Palette.textTertiary)
                }
            }
            .menuStyle(.button).buttonStyle(.plain)
        }
        .padding(14).card()
    }

    // MARK: 시간 설정 (Due · Resurface — 임의 날짜 + 지우기/none, §4-2·§4-3)

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionLabel("시간 설정")
            timeRow("마감 (Due)", value: $due, showDefer: false)
            Divider().overlay(Palette.border)
            timeRow("다시 보기 (Resurface)", value: $resurface, showDefer: true)
        }
        .padding(14).card()
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
                DatePicker("", selection: dateBinding(value), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact).tint(Palette.accent)
            } else {
                Text(value.wrappedValue == "weekly" ? "매주" : "없음")
                    .font(.caption).foregroundStyle(Palette.textTertiary)
            }
            if showDefer {
                Button { value.wrappedValue = Self.daysFromNow(7) } label: {
                    Label("+7일 미루기", systemImage: "clock")
                }
                .font(.caption).buttonStyle(.plain).foregroundStyle(Palette.accent)
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
        HStack(spacing: 10) {
            // 왼편: 삭제하기(tombstone, 보관함서 복구 가능)
            Button(role: .destructive) { model.delete(item); dismiss() } label: {
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
            .disabled(!dirty)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    /// 기억하기 재확인 — 표준 대화상자. [취소하기] / [기억하기].
    private var rememberDialog: some View {
        standardDialog("정말로 기억하시겠습니까?") {
            HStack(spacing: 0) {
                dialogButton("취소하기") { showRememberConfirm = false }
                Divider().overlay(Palette.border)
                dialogButton("기억하기", prominent: true) { showRememberConfirm = false; remember() }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 원칙 지정 시 기억하기 자동 결정 안내 — 표준 대화상자, 안내형 단일 버튼.
    private var principleAutoRememberDialog: some View {
        standardDialog("'기억하기'로 자동 결정됩니다") {
            dialogButton("확인", prominent: true) { commitAsPrinciple() }
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 표준 확인·안내 대화상자 (메모리 confirm-dialog-style — 앱 공용 형식)
    // 배경 딤 + 가운데 카드 + 큰 제목(표준 alert보다 2단계) + 하단 버튼 행.

    private func standardDialog<Buttons: View>(_ title: String,
                                               @ViewBuilder buttons: () -> Buttons) -> some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 0) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20).padding(.vertical, 24)
                Divider().overlay(Palette.border)
                buttons()
            }
            .frame(width: 300)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
    }

    private func dialogButton(_ title: String, prominent: Bool = false,
                              _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(prominent ? .title3.weight(.semibold) : .title3)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(prominent ? Palette.accent : Palette.textSecondary)
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

    /// String?("YYYY-MM-DD") ↔ Date 브릿지(DatePicker용).
    private func dateBinding(_ b: Binding<String?>) -> Binding<Date> {
        Binding(
            get: { ItemSchedule.parseDay(b.wrappedValue ?? "") ?? Date() },
            set: { b.wrappedValue = Self.fmt.string(from: $0) }
        )
    }

    static func isRealDate(_ s: String?) -> Bool {
        guard let s = s, !s.isEmpty, s != "none", s != "weekly" else { return false }
        return true
    }

    private static func daysFromNow(_ d: Int) -> String {
        let dt = Calendar.current.date(byAdding: .day, value: d, to: Date()) ?? Date()
        return fmt.string(from: dt)
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
