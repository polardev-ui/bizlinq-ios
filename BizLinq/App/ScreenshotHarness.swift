#if DEBUG
import SwiftUI

/// Screenshot automation for redesign verification. Driven by launch
/// arguments, e.g. `-shotScreen detail -shotZip 32832`.
/// Never compiled into Release builds. All data is fictional SampleData
/// with future dates; production fixtures are never used here.
enum ScreenshotPlan {
    case browse
    case filters
    case detail
    case meetings
    case host
    case post
    case review
    case group
    case paywall

    static var current: ScreenshotPlan? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-shotScreen"), args.indices.contains(index + 1) else {
            // Legacy flags keep working.
            if args.contains("-shotPaywall") { return .paywall }
            if args.contains("-shotDetail") { return .detail }
            if args.contains("-shotBrowse") { return .browse }
            return nil
        }
        switch args[index + 1] {
        case "browse": return .browse
        case "filters": return .filters
        case "detail": return .detail
        case "meetings": return .meetings
        case "host": return .host
        case "post": return .post
        case "review": return .review
        case "group": return .group
        case "paywall": return .paywall
        default: return nil
        }
    }

    static var zip: String {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-shotZip"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return "32832"
    }

    var initialTab: Int {
        switch self {
        case .browse, .filters, .detail: return 0
        case .meetings: return 1
        case .host, .post: return 2
        case .review, .group, .paywall: return 0
        }
    }
}

struct ScreenshotHost: View {
    let plan: ScreenshotPlan
    @ObservedObject var store: MeetingStore
    @EnvironmentObject private var auth: AuthManager
    @EnvironmentObject private var subscriptions: SubscriptionManager

    var body: some View {
        shotContent
            .onAppear(perform: seed)
    }

    @ViewBuilder
    private var shotContent: some View {
        switch plan {
        case .browse:
            ContentView(initialTab: 0)
        case .filters:
            NavigationStack {
                FiltersSheet()
                    .environmentObject(store)
            }
        case .detail:
            ContentView(initialTab: 0, autoOpenDetail: true)
        case .meetings:
            ContentView(initialTab: 1)
        case .host:
            ContentView(initialTab: 2)
        case .post:
            NavigationStack {
                PostMeetingView()
                    .environmentObject(store)
            }
        case .review:
            NavigationStack {
                if let sample = SampleData.meetings.first {
                    ReviewMeetingView(
                        draft: MeetingDraft(from: sample),
                        place: LocatedAddress(
                            coordinate: sample.coordinate, city: sample.city,
                            state: sample.state, zip: sample.zipCode, label: sample.city
                        ),
                        confirmTitle: "Publish meeting",
                        onConfirm: {}, onEdit: {}
                    )
                    .environmentObject(store)
                }
            }
        case .group:
            NavigationStack {
                GroupProfileView(groupName: SampleData.meetings.first?.groupName ?? "Sample Group")
                    .environmentObject(store)
            }
        case .paywall:
            NavigationStack {
                PaywallView()
                    .environmentObject(subscriptions)
            }
        }
    }

    private func seed() {
        store.backend = nil
        let samples = SampleData.meetings
        store.meetings = samples
        store.auth = nil
        switch plan {
        case .browse, .filters, .detail:
            store.searchZip = ScreenshotPlan.zip
            store.radius = .twentyFive
            Task { await store.resolveZip() }
        case .meetings:
            auth.userID = UUID()
            store.auth = auth
            store.rsvpIDs = Set(samples.prefix(2).map { $0.id })
        case .host, .post:
            auth.userID = UUID()
            store.auth = auth
            store.myMeetingIDs = Set(samples.prefix(3).map { $0.id })
        case .review, .group:
            break
        case .paywall:
            auth.userID = UUID()
            store.auth = auth
        }
    }
}
#endif
