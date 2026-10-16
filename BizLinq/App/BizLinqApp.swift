import SwiftUI

@main
struct BizLinqApp: App {
    @StateObject private var store = MeetingStore()
    @StateObject private var subscriptions = SubscriptionManager()
    @StateObject private var auth: AuthManager

    private let backend: SupabaseBackendService

    @AppStorage("bizlinq.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    init() {
        let client = SupabaseRESTClient()
        let backend = SupabaseBackendService(client: client)
        self.backend = backend
        _auth = StateObject(wrappedValue: AuthManager(client: client))
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let plan = ScreenshotPlan.current {
                    ScreenshotHost(plan: plan, store: store)
                } else if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
                #else
                if hasCompletedOnboarding {
                    ContentView()
                } else {
                    OnboardingView()
                }
                #endif
            }
            .environmentObject(store)
            .environmentObject(subscriptions)
            .environmentObject(auth)
            .task {
                #if DEBUG
                if ScreenshotPlan.current == nil {
                    wireBackend()
                }
                #else
                wireBackend()
                #endif
            }
        }
    }

    private func wireBackend() {
        store.backend = backend
        store.auth = auth
        Task {
            await store.refreshMyMeetings()
            await store.refreshTrialFromServer()
            if subscriptions.isPosterActive {
                TrialNotifications.cancelTrialReminders()
            }
        }
    }
}
