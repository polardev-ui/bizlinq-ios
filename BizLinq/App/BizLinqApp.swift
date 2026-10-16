import SwiftUI
import UserNotifications

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
        // Must be set before launch finishes so cold-start notification taps route.
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if let plan = ScreenshotPlan.current {
                    ScreenshotHost(plan: plan, store: store)
                } else if hasCompletedOnboarding {
                    ContentView()
                        .trialPrompts()
                } else {
                    OnboardingView()
                }
                #else
                if hasCompletedOnboarding {
                    ContentView()
                        .trialPrompts()
                } else {
                    OnboardingView()
                }
                #endif
            }
            .environmentObject(store)
            .environmentObject(subscriptions)
            .environmentObject(auth)
            .onChange(of: auth.userID) { _, userID in
                guard userID != nil, store.backend != nil else { return }
                Task {
                    await store.refreshTrialFromServer()
                    await store.refreshHostRules()
                    await subscriptions.resyncWithServer()
                }
            }
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
        subscriptions.accountToken = { [weak auth] in auth?.userID }
        subscriptions.syncToServer = { [weak auth, backend] jws in
            guard auth?.userID != nil else { return }
            _ = try? await backend.verifySubscription(jws: jws)
        }
        Task {
            await store.refreshMyMeetings()
            await store.refreshTrialFromServer()
            await store.refreshHostRules()
            await subscriptions.resyncWithServer()
            if subscriptions.isPosterActive {
                store.trialResolvedBySubscription()
            }
        }
    }
}
