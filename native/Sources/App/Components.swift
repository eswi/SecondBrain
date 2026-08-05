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

/// 되풀이 상태 칩(목록, §4) — 놓침이면 "N일 놓침"(coral=overdue, 진짜 경고) / 이번 회차 완료면 "완료"(accent). 아니면 nil.
/// "이번 회차 했나"가 목록에서 한눈에 보이게(완료 후 살아있는 기억으로 옮겨가도 티가 남).
/// 판정은 게이트와 같은 마감 앵커 기준(`doneThisCycle`) — 옛 날짜기준 `doneToday`는 게이트와 갈려 모순을 냈다(2026-08-03 #4).
func recurStatusChip(_ it: ResolvedItem, now: Date = Date()) -> (text: String, overdue: Bool)? {
    guard it.type == "recurrence" else { return nil }
    let missed = Recurrence.missed(it, now: now)
    if missed > 0 { return ("\(missed)일 놓침", true) }
    if Recurrence.doneThisCycle(it, now: now) { return ("완료", false) }
    return nil
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
            .frame(width: 300)
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
