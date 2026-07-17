import Foundation
import UserNotifications
import SecondBrainCore

/// 로컬 알림 실배선(Phase 3 "배달"): 순수 계획(`NotificationPlanner`)을 실제 시스템 알림으로 등록.
/// 로컬 알림은 iOS·macOS 모두 **entitlement 불필요 = 무료 서명 유지**(iCloud 배선과 동일 원칙).
/// 결정 로직은 전부 Core의 순수 planner에 있고(테스트로 검증됨), 여기는 얇은 실행 글루뿐이다.
enum NotificationScheduler {
    /// 알림 식별자 접두어(우리 앱 소유 알림 구분용).
    private static let idPrefix = "sb:"

    /// 계획을 시스템에 반영. 우리 앱이 모든 로컬 알림을 소유하므로 **전부 지우고 다시 등록(멱등)**.
    /// 삭제·완료·재분류로 계획에서 빠진 항목은 자동으로 알림도 사라진다.
    /// 매 `load()`(=매 행동)마다 호출돼 파일 진실원과 알림이 항상 일치.
    static func reschedule(_ plans: [PlannedNotification], calendar: Calendar = .current) async {
        let center = UNUserNotificationCenter.current()

        // 권한: notDetermined면 최초 1회만 시스템 프롬프트. 미허용이면 등록하지 않고 정리만.
        let settings = await center.notificationSettings()
        var status = settings.authorizationStatus
        if status == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
            status = granted ? .authorized : .denied
        }
        guard status == .authorized || status == .provisional else {
            center.removeAllPendingNotificationRequests()
            return
        }

        center.removeAllPendingNotificationRequests()
        for p in plans {
            let content = UNMutableNotificationContent()
            content.title = p.title
            content.body = p.body
            content.sound = .default
            let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: p.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            let req = UNNotificationRequest(identifier: idPrefix + p.id, content: content, trigger: trigger)
            try? await center.add(req)
        }
    }
}
