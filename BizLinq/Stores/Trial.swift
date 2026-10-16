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
            if daysLeft == 0 {
                content.userInfo = [AppRouter.routeKey: AppRouter.Route.trialDecision.rawValue]
            }
            let request = UNNotificationRequest(
                identifier: "bizlinq.trial-day\(daysLeft)", content: content, trigger: trigger
            )
            center.add(request)
        }
    }

    static func cancelTrialReminders() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids())
        cancelDecisionReminder()
    }

    // MARK: Post-trial "remind me tomorrow"

    static let decisionID = "bizlinq.trial-decision"

    /// Same wall-clock time tomorrow, in the user's current calendar.
    static func sameTimeTomorrow(from now: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
    }

    /// One reminder at `date`; tapping it opens "Ready to move forward?".
    static func scheduleDecisionReminder(at date: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [decisionID])
        let content = UNMutableNotificationContent()
        content.title = "Ready to keep hosting?"
        content.body = "Your BizLinq trial has ended. Pick a plan to post your next meeting — or keep browsing for free."
        content.sound = .default
        content.userInfo = [AppRouter.routeKey: AppRouter.Route.trialDecision.rawValue]
        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        center.add(UNNotificationRequest(identifier: decisionID, content: content, trigger: trigger))
    }

    static func cancelDecisionReminder() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [decisionID])
        center.removeDeliveredNotifications(withIdentifiers: [decisionID])
    }
}

/// Routes notification taps into the UI.
@MainActor
final class AppRouter: ObservableObject {
    static let shared = AppRouter()
    nonisolated static let routeKey = "route"

    enum Route: String {
        case trialDecision
    }

    /// Set when the user taps a trial reminder; the root view presents
    /// "Ready to move forward?" and clears it.
    @Published var pendingRoute: Route?
}

/// Receives notification taps (including cold launches) and banners while
/// the app is open.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let raw = response.notification.request.content.userInfo[AppRouter.routeKey] as? String
        guard let raw, let route = AppRouter.Route(rawValue: raw) else { return }
        await MainActor.run { AppRouter.shared.pendingRoute = route }
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// The rules every host agrees to before their first post.
enum HostRules {
    /// Bump when the rules change materially to ask everyone again.
    static let version = 1

    struct Rule: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    static let rules: [Rule] = [
        Rule(icon: "checkmark.seal", title: "Real meetings only",
             detail: "List genuine business networking events that you host or are authorized to promote."),
        Rule(icon: "calendar.badge.clock", title: "Keep details accurate",
             detail: "Date, time, place, and format must be correct. Edit or cancel the listing if plans change."),
        Rule(icon: "tag", title: "Be upfront about cost",
             detail: "Show any attendance fee. Attendees pay you directly; BizLinq never collects event fees."),
        Rule(icon: "hand.raised", title: "Keep it professional",
             detail: "No spam, misleading claims, harassment, discrimination, or illegal activity."),
        Rule(icon: "lock.shield", title: "Respect attendees' privacy",
             detail: "Use contact details only for your event. Never sell or share them."),
        Rule(icon: "clock.badge.checkmark", title: "14-day free trial, then a plan",
             detail: "Your first post starts a 14-day free posting trial. After that, a paid plan is required to post. Browsing and RSVPs stay free."),
        Rule(icon: "flag", title: "We review reports",
             detail: "Listings that break these rules may be removed, and repeat issues can end posting access."),
    ]

    static func defaultsKey(for user: UUID?) -> String {
        "bizlinq.hostRulesAccepted.v\(version).\(user?.uuidString ?? "guest")"
    }
}
