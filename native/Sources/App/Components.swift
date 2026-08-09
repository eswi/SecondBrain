import SwiftUI
import SecondBrainCore

// MARK: - D-day 배지

struct DDayBadge: View {
    let dday: DDay

    private var text: String {
        switch dday.bucket {
        case .overdue: return "D+\(-dday.days)"   // 지남
        case .today:   return "D-DAY"
        case .future:  return "D-\(dday.days)"
        }
    }
    private var color: Color {
        switch dday.bucket {
        case .overdue: return Palette.overdue
        case .today:   return Palette.today
        case .future:  return Palette.neutral
        }
    }

    var body: some View {
        Text(text)
            .font(.caption2.weight(.bold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}

// MARK: - source 아이콘 배지

struct SourceBadge: View {
    let source: String?
    var body: some View {
        Image(systemName: SourceIcon.symbol(source))
            .font(.caption2)
            .foregroundStyle(Palette.textTertiary)
    }
}

// MARK: - 종류 아이콘 (버튼 → 분류 변경 메뉴)

/// 항목의 종류를 나타내는 아이콘. 탭하면 종류 선택 메뉴가 떠서 분류를 바꾼다(엔진 재사용).
struct TypeMenuButton: View {
    let item: ResolvedItem
    let onChange: (String) -> Void

    var body: some View {
        Menu {
            ForEach(ClassRegistry.assignable) { m in    // 기본층 6 + 유연층(주차 위치) — 상세화면과 동일 집합
                Button {
                    if let k = m.key { onChange(k) }
                } label: {
                    Label(m.label, systemImage: m.symbol)
                }
                .disabled(m.key == item.type)
            }
        } label: {
            let m = ClassRegistry.meta(item.type)       // 유연층-인지 조회(주차=car). 기본층-전용이면 미분류로 폴백됨
            Image(systemName: m.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(m.color)
                .frame(width: 30, height: 30)
                .background(m.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
    }
}

/// 비대화형 종류 글리프(보관함 등에서).
struct TypeGlyph: View {
    let type: String?
    var body: some View {
        let m = ClassRegistry.meta(type)                // 유연층-인지 조회(주차 포함) — TypeMenuButton과 통일
        Image(systemName: m.symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(m.color)
            .frame(width: 28, height: 28)
            .background(m.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - 항목 캡션(출처 · 시각 · 시점)

/// 항목 캡션. `showCaptureTime`=false면 **수집 시각을 뺀다**(지금 챙길 것 목록 — 스케줄이 핵심이고 폭이 좁다;
/// 수집 시각은 상세 "최초 수집 · 성역"에 그대로 남는다). 보관함·검색은 기본값(true)으로 수집 시각 유지.
func itemCaption(_ it: ResolvedItem, showCaptureTime: Bool = true, now: Date = Date()) -> String {
    var parts: [String] = []
    if showCaptureTime {
        let dt = "\(it.date ?? "") \(it.time ?? "")".trimmingCharacters(in: .whitespaces)
        if !dt.isEmpty { parts.append(dt) }
    }
    // §7 분류 게이트: 그 분류가 쓰는 칸의 날짜만 노출한다(안 쓰는 칸의 옛 날짜는 안 보임).
    // 상세 "시간 설정"·"지금 챙길 것"과 같은 게이트를 타 — 보이는 곳마다 어긋나지 않게.
    if let due = ItemSchedule.deadlineDay(it) { parts.append("~\(displaySchedule(due, now: now))") }
    if let rs = ItemSchedule.gatedResurface(it) { parts.append("↻\(displaySchedule(rs, now: now))") }
    return parts.joined(separator: " · ")
}

/// 스케줄 날짜(마감/미리 알림) 표시 — **올해면 연도 생략**("08-05"), **다른 해면 연도 표시**("2027-08-05").
/// 내년 마감을 올해로 오해하지 않게 한다(사용자 요청). 시각이 있으면 뒤에 붙인다("08-05 19:00").
func displaySchedule(_ v: String, now: Date = Date(), calendar: Calendar = .current) -> String {
    guard let d = ItemSchedule.parseDay(v, calendar: calendar) else { return displayDateTime(v) }   // 폴백
    let c = calendar.dateComponents([.year, .month, .day], from: d)
    let datePart = (c.year == calendar.component(.year, from: now))
        ? String(format: "%02d-%02d", c.month ?? 0, c.day ?? 0)
        : String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    if let t = ItemSchedule.timeOfDay(v) { return String(format: "%@ %02d:%02d", datePart, t.hour, t.minute) }
    return datePart
}

/// 저장 문자열의 시각 구분자 `T`를 사람이 읽게 공백으로("2026-08-05T19:00" → "2026-08-05 19:00"). date-only는 그대로.
func displayDateTime(_ v: String) -> String { v.replacingOccurrences(of: "T", with: " ") }

/// 목록 상태 칩 — **칩 자리는 한 줄에 하나뿐**이라 세 신호가 여기서 우선순위를 다툰다.
///
/// | 순위 | 칩 | 색 | 언제 |
/// |---|---|---|---|
/// | 1 | "N일 놓침" | **coral**(경고) | 되풀이가 회차를 건너뛰어 쌓였다 |
/// | 2 | "8/14에 다시 · 7일 늦음" | **amber**(주의) | **늦었는데 숨겨진 것**(D, 2026-08-07) |
/// | 3 | "완료" | accent | 이번 회차를 실제로 했다 |
///
/// **1이 2를 이긴다** — coral(경고) > amber(주의)의 한 단계 위계를 지킨다(D-4). 놓침이 있으면 그것부터 봐야 한다.
/// **2와 3은 서로 배타적이라 순서가 뜻이 없다** — `doneThisCycle`은 `마감 > now`(1절)를,
/// `overdueHidden`은 `마감 ≤ now`(3절)를 요구하므로 **둘이 동시에 참일 수 없다.**
///
/// 판정은 게이트와 같은 마감 앵커 기준(`doneThisCycle`) — 옛 날짜기준 `doneToday`는 게이트와 갈려 모순을 냈다(2026-08-03 #4).
func statusChip(_ it: ResolvedItem, now: Date = Date()) -> (text: String, tint: Color)? {
    if it.type == "recurrence" {
        let missed = Recurrence.missed(it, now: now)
        if missed > 0 { return ("\(missed)일 놓침", Palette.overdue) }
    }
    if let oh = ItemSchedule.overdueHidden(it, now: now) {
        return (overdueHiddenChipText(oh), Palette.today)
    }
    if it.type == "recurrence", Recurrence.doneThisCycle(it, now: now) { return ("완료", Palette.accent) }
    return nil
}

/// **늦었는데 숨겨진 것**의 칩 문구 — 「8/14에 다시 · 7일 늦음」(2026-08-07, 문구는 사용자가 정했다).
///
/// **★ "숨겨짐"이라고 말하지 않는다.** 그 상태를 만든 것은 **사람 자신**이고(미루기를 눌렀거나 날짜를 옮겼거나),
/// 앱이 "숨겨졌습니다"라고 알리는 것은 **자기가 치운 것을 앱에게 듣는 꼴**이다.
/// 알릴 것은 **"언제 돌아오나"** 와 **"그것이 마감보다 뒤다"** 둘뿐이다.
///
/// **늦은 날 수가 0이면 그 부분을 뺀다** — 「0일 늦음」이라는 말은 안 쓴다(오늘 마감이 지난 경우).
/// 늦었다는 것 자체는 **색(amber)** 이 말한다.
///
/// 폭 실측(iPhone 16 Pro 393pt · `MemoryRow`): 칩+원문 예산 274pt 중 **긴 형태 103pt**(최악 114pt).
/// 들어가지만 그 줄의 원문이 약 34자 → 24자로 준다. **칩이 붙은 줄은 "왜 안 보이나"를 알려주는 자리**라
/// 원문 10자보다 값이 크다고 보고 긴 형태를 택했다(2026-08-07 사용자 결정).
/// 폰에서 답답하면 「8/14에 다시」로 줄이고 늦음은 색으로만 말한다.
func overdueHiddenChipText(_ oh: ItemSchedule.OverdueHidden) -> String {
    // `returnsOn`은 nil이 될 수 없다 — 숨긴 장본인이 미리 알림이므로(`overdueHidden` 4절의 귀결).
    // 그래도 문자열을 만드는 자리라 방어한다: 없으면 늦음만.
    guard let on = oh.returnsOn.map(slashDate) else {
        return oh.lateDays > 0 ? "\(oh.lateDays)일 늦음" : "마감 지남"
    }
    return oh.lateDays > 0 ? "\(on)에 다시 · \(oh.lateDays)일 늦음" : "\(on)에 다시"
}

/// **늦었는데 숨겨진 것** 배너의 둘째 줄 — 「마감은 7월 31일이었어요 · 7일 지남」.
/// 늦음 0일이면 일수를 뺀다(칩과 같은 규약 — 「0일」이라는 말은 안 쓴다).
@MainActor func overdueHiddenSubtitle(_ due: String?, lateDays: Int, now: Date = Date()) -> String {
    guard let due else { return lateDays > 0 ? "\(lateDays)일 지남" : "" }
    let d = korDateTime(due, now: now)
    return lateDays > 0 ? "마감은 \(d)이었어요 · \(lateDays)일 지남" : "마감은 \(d)이었어요"
}

/// 배너용 사람말 날짜 — "8월 14일" · "8월 8일 12:00" · **오늘이면 "오늘 13:00"**.
/// 배너는 넓어서 `korShort`를 그대로 쓸 수 있다(칩은 `slashDate`).
/// `@MainActor`인 이유는 `InboxModel.korShort`를 **그대로 쓰기 위해서**다 —
/// 같은 모양의 날짜 문구를 하나 더 만들지 않는다(복사 금지). 부르는 곳이 전부 뷰라 제약이 안 된다.
/// **`withTime: false`면 시각을 뺀다** — **판정이 날짜 단위인 문장에서 쓴다**(2026-08-07).
/// 규칙 1의 date-only 갈래가 그 자리다: 판정은 날짜로 하는데 문장이 「마감은 8월 10일 **08:00**이에요」라고
/// 시각을 말하면 *"그럼 07:00은 왜 안 되지"* 를 부른다. **문장이 판정보다 더 말하지 않게 한다.**
@MainActor func korDateTime(_ v: String, now: Date = Date(), calendar: Calendar = .current,
                            withTime: Bool = true) -> String {
    let head: String
    if let d = ItemSchedule.parseDay(v, calendar: calendar), calendar.isDate(d, inSameDayAs: now) {
        head = "오늘"
    } else {
        head = InboxModel.korShort(v)
    }
    if withTime, let t = ItemSchedule.timeOfDay(v) { return String(format: "%@ %02d:%02d", head, t.hour, t.minute) }
    return head
}

/// "2026-08-14" · "2026-08-08T12:00" → **"8/14"**. 칩은 좁아서 `korShort`("8월 14일")를 못 쓴다.
func slashDate(_ v: String) -> String {
    let day = v.split(whereSeparator: { $0 == "T" || $0 == " " }).first.map(String.init) ?? v
    let p = day.split(separator: "-")
    guard p.count == 3, let m = Int(p[1]), let d = Int(p[2]) else { return day }
    return "\(m)/\(d)"
}

/// 목록의 **"했어요" 액션을 그릴지** — 칩과 **같은 판정**(`doneThisCycle`)을 본다.
/// 안 물리면 칩이 "완료"인데 스와이프엔 "했어요"가 남아 **눌러도 아무 일이 없다**
/// (§5-A가 지목한 dead button 둘 중 목록 쪽. 상세 버튼은 `completionRow`가 같은 판정으로 이미 갈린다).
/// 되풀이가 아니면 항상 false — 일반 항목의 완료는 그대로다.
/// 취소는 여기 안 넣는다(상세에서) — 목록 스와이프에 되돌리기를 두면 오조작이 쉽다.
func cycleAlreadyDone(_ it: ResolvedItem, now: Date = Date()) -> Bool {
    it.type == "recurrence" && Recurrence.doneThisCycle(it, now: now)
}

/// 목록 **오른쪽 시각 칩**(§6-B 보조 시각) — D-day 배지의 **시각 세분**. **마감(기한) 기준만**이다.
/// "며칠/몇시간 남음"은 마감 기준이라는 날짜 역할 분리 원칙을 그대로 따른다(D-day 배지 = `deadlineDay`).
/// 마감에 시각이 있을 때만: 오늘이면 "N시간 남음"/"지남", 다른 날이면 마감 "HH:mm".
/// 마감 없거나(미리 알림만 있는 항목) 마감에 시각 없으면 nil — 칩 안 뜬다(카운트다운은 기한이 있어야 성립).
func scheduleTimeChip(_ it: ResolvedItem, now: Date = Date()) -> String? {
    guard let due = ItemSchedule.deadlineDay(it), let t = ItemSchedule.timeOfDay(due) else { return nil }
    if let within = ItemSchedule.withinDayCaption(due, now: now) { return within }      // 오늘: 남은 시간
    return String(format: "%02d:%02d", t.hour, t.minute)                                // 다른 날: 마감 시각
}

// MARK: - 표준 확인·안내 대화상자 (앱 공용 형식 — confirm-dialog-style)
// 배경 딤 + 가운데 카드 + 큰 제목(표준 alert보다 2단계) + 하단 버튼 행.
// 사용처: 기억하기 재확인 · 원칙 자동결정 안내 · 삭제 확인(상세·리스트 공통).

struct StandardDialog<Buttons: View>: View {
    let title: String
    /// 카드 폭. 기본 300 — **기존 대화상자는 전부 이 값 그대로**다(부르는 쪽을 안 건드린다).
    /// 넓히는 것은 **안에 넓은 것을 담을 때만**이다(시점 고치는 자리의 달력 — 칸 너비가 행 높이를 정한다).
    var width: CGFloat = 300
    @ViewBuilder var buttons: () -> Buttons

    var body: some View {
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
            .frame(width: width)
            .background(Palette.surface2, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.border))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
        }
    }
}

/// 대화상자 하단 버튼. prominent = 굵게(주 액션). tint로 색을 덮어씀(삭제=overdue 등).
struct DialogButton: View {
    let title: String
    var prominent: Bool = false
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(prominent ? .title3.weight(.semibold) : .title3)
                .frame(maxWidth: .infinity, minHeight: 52)
        }
        .foregroundStyle(tint ?? (prominent ? Palette.accent : Palette.textSecondary))
    }
}

/// 두 버튼(취소/확정) 표준 확인 대화상자 — 가장 흔한 형태.
struct ConfirmDialog: View {
    let title: String
    var cancelTitle: String = "취소"
    var confirmTitle: String
    var confirmTint: Color? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        StandardDialog(title: title) {
            HStack(spacing: 0) {
                DialogButton(title: cancelTitle, action: onCancel)
                Divider().overlay(Palette.border)
                DialogButton(title: confirmTitle, prominent: true, tint: confirmTint, action: onConfirm)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
