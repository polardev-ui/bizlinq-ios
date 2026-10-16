import Foundation
import UserNotifications

/// 14-day poster trial: first listing starts the clock (server-stamped, so
/// reinstalls don't reset it). After day 14, posting requires a subscription.
enum TrialStatus: Equatable {
    case notStarted
    case active(daysLeft: Int)
    case expired

    static let lengthDays = 14
    static let reminderDays = 7
    /// Trials that started before the 14-day cutover keep their original
    /// 30-day terms; only newer trials use 14 days.
    static let cutoverDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 17
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar.current.date(from: c) ?? Date()
    }()
    static let legacyLengthDays = 30

    static func lengthDays(for start: Date?) -> Int {
        guard let start else { return lengthDays }
        return start < cutoverDate ? legacyLengthDays : lengthDays
    }

    static func current(start: Date?, now: Date, subscribed: Bool) -> TrialStatus {
        let total = lengthDays(for: start)
        if subscribed { return .active(daysLeft: total) }
        guard let start else { return .notStarted }
        let elapsed = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0
        let left = total - elapsed
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
/// the last 7 days, plus one on day 14 itself.
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
        let total = TrialStatus.lengthDays(for: start)
        for back in 0...TrialStatus.reminderDays {
            let daysLeft = TrialStatus.reminderDays - back
            let fire = Calendar.current.date(byAdding: .day, value: total - daysLeft, to: start) ?? start
            guard fire > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = "BizLinq trial"
            if daysLeft == 0 {
                content.body = "Your posting trial ends today. Open BizLinq to subscribe or cancel."
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
