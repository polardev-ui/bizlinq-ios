#if DEBUG
import SwiftUI

/// Screenshot automation for App Store artwork. Driven by launch arguments
/// (Scheme > Run > Arguments), e.g. `-shotBrowse -shotZip 10001`.
/// Never compiled into Release builds.
enum ScreenshotPlan {
    case browse
    case paywall
    case detail

    static var current: ScreenshotPlan? {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-shotPaywall") { return .paywall }
        if args.contains("-shotDetail") { return .detail }
        if args.contains("-shotBrowse") { return .browse }
        return nil
    }

    static var zip: String {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-shotZip"), args.indices.contains(index + 1) {
            return args[index + 1]
        }
        return "10001"
    }

    var initialTab: Int {
        switch self {
        case .paywall: return 1
        case .browse, .detail: return 0
        }
    }
}

struct ScreenshotHost: View {
    let plan: ScreenshotPlan
    @ObservedObject var store: MeetingStore
    @EnvironmentObject private var auth: AuthManager

    var body: some View {
        ContentView(initialTab: plan.initialTab, autoOpenDetail: plan == .detail)
            .onAppear {
                store.backend = nil
                store.meetings = SampleData.meetings
                if plan == .paywall {
                    // Fake a signed-in user so the shot shows pricing, not the gate.
                    // (Views read the environment auth object, not store.auth.)
                    auth.userID = UUID()
                    store.auth = auth
                } else {
                    store.auth = nil
                    store.searchZip = ScreenshotPlan.zip
                    store.radius = .twentyFive
                    Task { await store.resolveZip() }
                }
            }
    }
}
#endif
