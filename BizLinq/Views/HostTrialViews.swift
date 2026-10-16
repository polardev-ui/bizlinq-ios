import SwiftUI

// MARK: - Host rules (once per account, before the first post)

/// Full-screen agreement shown before a host's first post. It cannot be
/// swiped away; "Not now" leaves posting locked until the rules are accepted.
struct HostRulesView: View {
    let onAccept: () -> Void
    let onNotNow: () -> Void
    @State private var agreed = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 10) {
                        BizIconBadge(systemImage: "person.badge.shield.checkmark", size: 64)
                            .bizAppear(index: 0)
                        Text("Before you post")
                            .font(.largeTitle.bold())
                            .foregroundStyle(BizStyle.ink)
                            .accessibilityAddTraits(.isHeader)
                            .bizAppear(index: 1)
                        Text("BizLinq works because every listing is real. Please review the host rules — you only need to do this once.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .bizAppear(index: 2)
                    }
                    .padding(.top, 24)

                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(HostRules.rules.enumerated()), id: \.element.id) { index, rule in
                            HStack(alignment: .top, spacing: 14) {
                                BizIconBadge(systemImage: rule.icon, size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(rule.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(BizStyle.ink)
                                    Text(rule.detail)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .bizAppear(index: index + 3)
                        }
                    }
                    .padding(18)
                    .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))

                    HStack(spacing: 16) {
                        if let terms = URL(string: "https://bizlinq.app/terms") {
                            Link("Terms of Use", destination: terms)
                        }
                        if let privacy = URL(string: "https://bizlinq.app/privacy") {
                            Link("Privacy Policy", destination: privacy)
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .tint(BizStyle.teal)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }

            VStack(spacing: 12) {
                Button {
                    withAnimation(BizStyle.snappy) { agreed.toggle() }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: agreed ? "checkmark.square.fill" : "square")
                            .font(.title3)
                            .foregroundStyle(agreed ? BizStyle.teal : .secondary)
                            .symbolEffect(.bounce, value: agreed)
                        Text("I've read and agree to the BizLinq host rules.")
                            .font(.subheadline)
                            .foregroundStyle(BizStyle.ink)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: agreed)
                .accessibilityAddTraits(agreed ? .isSelected : [])

                BizPrimaryButton(title: "Agree and continue", enabled: agreed, action: onAccept)
                Button("Not now", action: onNotNow)
                    .font(.subheadline.weight(.semibold))
                    .tint(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .background(BizStyle.canvas)
        .interactiveDismissDisabled()
    }
}

/// Shown in the post flow until the host accepts the rules.
struct HostRulesRequiredView: View {
    let onReview: () -> Void

    var body: some View {
        BizIntroView(
            systemImage: "person.badge.shield.checkmark",
            title: "Agree to the host rules",
            message: "Before your first post, take a minute to review how hosting on BizLinq works.",
            actionTitle: "Review host rules",
            action: onReview
        )
    }
}

// MARK: - Trial ended

/// "Your trial is up" — offered once when the trial expires (full screen)
/// and whenever an expired host tries to post (inline).
struct TrialEndedView: View {
    enum Style { case fullScreen, inline }
    var style: Style = .fullScreen
    let onPlans: () -> Void
    let onBrowse: () -> Void
    let onRemind: () -> Void
    @State private var confirmingBrowse = false

    private var reminderTime: String {
        TrialNotifications.sameTimeTomorrow().formatted(date: .omitted, time: .shortened)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                TrialHeroBadge(systemImage: "sparkles")
                    .padding(.top, style == .fullScreen ? 40 : 16)

                VStack(spacing: 10) {
                    Text("Enjoying BizLinq?")
                        .font(.largeTitle.bold())
                        .foregroundStyle(BizStyle.ink)
                        .multilineTextAlignment(.center)
                        .accessibilityAddTraits(.isHeader)
                        .bizAppear(index: 1)
                    Text("Your 14-day free trial has wrapped up.")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(BizStyle.teal)
                        .multilineTextAlignment(.center)
                        .bizAppear(index: 2)
                    Text("To keep sharing your meetings with local professionals, choose a plan below. Just here to browse? That's completely fine — finding and joining meetings is always free.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .bizAppear(index: 3)
                }

                VStack(alignment: .leading, spacing: 14) {
                    TrialFactRow(icon: "checkmark.circle", text: "Meetings you already published stay live.")
                    TrialFactRow(icon: "magnifyingglass", text: "Browsing, saving, and RSVPs remain free.")
                    TrialFactRow(icon: "lock", text: "Posting new meetings needs an active plan.")
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
                .bizAppear(index: 4)

                VStack(spacing: 12) {
                    BizPrimaryButton(title: "View plans", systemImage: "arrow.right.circle.fill", action: onPlans)
                    BizSecondaryButton(title: "I'll just browse") { confirmingBrowse = true }
                    Button(action: onRemind) {
                        VStack(spacing: 2) {
                            Label("Remind me tomorrow", systemImage: "bell")
                                .font(.subheadline.weight(.semibold))
                            Text("Need time to think? We'll check in at \(reminderTime) tomorrow.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .tint(BizStyle.teal)
                }
                .bizAppear(index: 5)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(BizStyle.canvas)
        .confirmationDialog("Stop hosting for now?", isPresented: $confirmingBrowse, titleVisibility: .visible) {
            Button("Just browse") { onBrowse() }
            Button("Keep my options open", role: .cancel) {}
        } message: {
            Text("You won't be able to post new meetings, and we'll stop reminding you. You can pick a plan from the Host tab anytime.")
        }
    }
}

// MARK: - Ready to move forward? (opened from the reminder)

struct ReadyToMoveForwardView: View {
    let onPlans: () -> Void
    let onKeepBrowsing: () -> Void
    let onStopReminders: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            TrialHeroBadge(systemImage: "arrow.forward")
            VStack(spacing: 10) {
                Text("Ready to move forward?")
                    .font(.largeTitle.bold())
                    .foregroundStyle(BizStyle.ink)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                    .bizAppear(index: 1)
                Text("Pick a plan and post your next meeting today. Not quite yet? Keep browsing — we'll check back tomorrow.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .bizAppear(index: 2)
            }
            Spacer()
            VStack(spacing: 12) {
                BizPrimaryButton(title: "View plans", systemImage: "arrow.right.circle.fill", action: onPlans)
                BizSecondaryButton(title: "Keep browsing", action: onKeepBrowsing)
                Button("I'm only browsing — stop reminders", action: onStopReminders)
                    .font(.footnote.weight(.medium))
                    .tint(.secondary)
                    .padding(.top, 4)
            }
            .bizAppear(index: 3)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .background(BizStyle.canvas)
    }
}

private struct TrialHeroBadge: View {
    let systemImage: String
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .fill(BizStyle.tealSoft)
                .frame(width: 132, height: 132)
                .scaleEffect(pulse ? 1.08 : 0.94)
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 96, height: 96)
                .background(
                    LinearGradient(colors: [BizStyle.teal, BizStyle.teal.opacity(0.75)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    in: Circle()
                )
                .shadow(color: BizStyle.teal.opacity(0.35), radius: 14, y: 8)
                .symbolEffect(.bounce, value: pulse)
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}

private struct TrialFactRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BizStyle.teal)
                .frame(width: 22)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BizStyle.ink)
        }
    }
}

// MARK: - Presentation

enum TrialPrompt: String, Identifiable {
    case ended
    case ready
    var id: String { rawValue }
}

/// Root-level presenter: shows "trial ended" once when the trial expires,
/// "Ready to move forward?" when a reminder is tapped (or comes due while
/// notifications are off), and the plans sheet on top of either.
struct TrialPromptPresenter: ViewModifier {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    @ObservedObject private var router = AppRouter.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var prompt: TrialPrompt?

    func body(content: Content) -> some View {
        content
            .fullScreenCover(item: $prompt) { kind in
                TrialPromptScreen(kind: kind) { prompt = nil }
                    .environmentObject(store)
                    .environmentObject(subscriptions)
            }
            .onAppear(perform: evaluate)
            .onChange(of: router.pendingRoute) { _, _ in evaluate() }
            .onChange(of: scenePhase) { _, phase in if phase == .active { evaluate() } }
            .onChange(of: store.trialStartDate) { _, _ in evaluate() }
            .onChange(of: auth.userID) { _, _ in evaluate() }
            .onChange(of: subscriptions.isPosterActive) { _, active in
                if active {
                    store.trialResolvedBySubscription()
                    prompt = nil
                }
            }
    }

    private func evaluate() {
        let subscribed = subscriptions.isPosterActive
        if router.pendingRoute == .trialDecision {
            router.pendingRoute = nil
            if store.trialAwaitingDecision(subscribed: subscribed) {
                prompt = .ready
            }
            return
        }
        guard prompt == nil else { return }
        if store.shouldShowTrialEnded(subscribed: subscribed) {
            prompt = .ended
        } else if store.isTrialReminderDue(subscribed: subscribed) {
            prompt = .ready
        }
    }
}

private struct TrialPromptScreen: View {
    let kind: TrialPrompt
    let close: () -> Void
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var showingPlans = false

    var body: some View {
        Group {
            switch kind {
            case .ended:
                TrialEndedView(
                    onPlans: { showingPlans = true },
                    onBrowse: {
                        store.stopHostingAfterTrial()
                        close()
                    },
                    onRemind: {
                        store.remindAboutTrialTomorrow()
                        close()
                    }
                )
            case .ready:
                ReadyToMoveForwardView(
                    onPlans: { showingPlans = true },
                    onKeepBrowsing: {
                        store.remindAboutTrialTomorrow()
                        close()
                    },
                    onStopReminders: {
                        store.stopHostingAfterTrial()
                        close()
                    }
                )
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $showingPlans) {
            NavigationStack {
                PaywallView(context: .trialEnded) {
                    store.trialResolvedBySubscription()
                    showingPlans = false
                    close()
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingPlans = false }
                    }
                }
            }
        }
    }
}

extension View {
    func trialPrompts() -> some View {
        modifier(TrialPromptPresenter())
    }
}
