import Foundation
import UserNotifications

/// 30-day poster trial: first listing starts the clock (server-stamped, so
/// reinstalls don't reset it). After day 30, posting requires a subscription.
enum TrialStatus: Equatable {
    case notStarted
    case active(daysLeft: Int)
    case expired

    static let lengthDays = 30
    static let reminderDays = 7

    static func current(start: Date?, now: Date, subscribed: Bool) -> TrialStatus {
        if subscribed { return .active(daysLeft: TrialStatus.lengthDays) }
        guard let start else { return .notStarted }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        let left = lengthDays - elapsed
        if left <= 0 { return .expired }
        return .active(daysLeft: left)
    }

    var isExpiring: Bool {
        if case .active(let days) = self { return days <= TrialStatus.reminderDays }
        return false
    }
}

/// Local notifications for the trial countdown. iOS UserNotifications is the
/// whole "library" here — no dependency needed. Eight reminders: daily for
/// the last 7 days, plus one on day 30 itself.
enum TrialNotifications {
    private static func ids() -> [String] {
        (0...TrialStatus.reminderDays).map { "bizlinq.trial-day\($0)" }
    }

    static func requestPermission() async -> Bool {
        do {
            return try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    static func scheduleTrialReminders(start: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ids())
        for back in 0...TrialStatus.reminderDays {
            let daysLeft = TrialStatus.reminderDays - back
            let fire = Calendar.current.date(byAdding: .day, value: TrialStatus.lengthDays - daysLeft, to: start) ?? start
            guard fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "BizLinq trial"
            if daysLeft == 0 {
                content.body = "Your 30-day posting trial ends today. Open BizLinq to subscribe or cancel."
            } else if daysLeft == 1 {
                content.body = "Your posting trial ends tomorrow. Subscribe to keep your meetings live."
            } else {
                content.body = "Your posting trial ends in \(daysLeft) days. Subscribe to keep your meetings live."
            }
            let trigger = UNTimeIntervalNotificationTrigger(
                timeInterval: max(60, fire.timeIntervalSinceNow), repeats: false
            )
            let request = UNNotificationRequest(
                identifier: "bizlinq.trial-day\(daysLeft)", content: content, trigger: trigger
            )
            center.add(request)
        }
    }

    static func cancelTrialReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids())
    }
}
