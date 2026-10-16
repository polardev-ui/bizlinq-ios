import SwiftUI

/// Shown when subscribing: from the trial-expired screen, My Posts, or Profile.
struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var selectedID: String = SubscriptionPlan.monthly.id
    enum Context { case standard, trialEnded }
    /// `.trialEnded` drops the free-trial pitch: the app trial is used up.
    var context: Context = .standard
    var onPurchased: (() -> Void)? = nil

    private var selected: SubscriptionPlan {
        SubscriptionPlan.all.first { $0.id == selectedID } ?? SubscriptionPlan.monthly
    }

    private var trialEligible: Bool {
        context == .standard && subscriptions.isTrialEligible(selected)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                Text(context == .trialEnded ? "Keep hosting\non BizLinq" : "Help local professionals\nfind your group")
                    .font(.title2.bold())
                    .foregroundStyle(BizStyle.ink)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .bizAppear(index: 0)

                if context == .trialEnded {
                    Text("Your free trial is over. Choose a plan to post your next meeting — cancel anytime in your App Store settings.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .bizAppear(index: 1)
                }

                PaywallIllustration()
                    .frame(height: 150)
                    .bizAppear(index: 1)

                VStack(alignment: .leading, spacing: 16) {
                    PaywallBullet(
                        icon: "magnifyingglass",
                        title: "Discovery by location and category",
                        text: "Your group can be found by professionals in your area."
                    )
                    PaywallBullet(
                        icon: "person.2.fill",
                        title: "Meeting details and free RSVPs",
                        text: "Share key details and let people RSVP directly in the app."
                    )
                    PaywallBullet(
                        icon: "calendar",
                        title: "Unlimited meeting posts",
                        text: "Keep your group visible, and edit any listing anytime."
                    )
                }
                .bizAppear(index: 2)

                Divider()

                VStack(spacing: 4) {
                    if trialEligible {
                        Text("14 days free")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundStyle(BizStyle.ink)
                    }
                    Text(trialEligible
                         ? "\(selected.price)/\(selected.id == SubscriptionPlan.annual.id ? "year" : "month") afterward"
                         : "\(selected.price) \(selected.cadence)")
                        .font(trialEligible ? .title3.weight(.semibold) : .system(size: 34, weight: .bold))
                        .foregroundStyle(BizStyle.teal)
                        .contentTransition(.numericText())
                }
                .animation(BizStyle.spring, value: selectedID)

                HStack(spacing: 10) {
                    ForEach(SubscriptionPlan.all) { plan in
                        PlanCard(plan: plan, isSelected: plan.id == selectedID) {
                            withAnimation(BizStyle.snappy) { selectedID = plan.id }
                        }
                    }
                }

                VStack(spacing: 10) {
                    BizPrimaryButton(
                        title: trialEligible ? "Start your free trial" : "Subscribe — \(selected.price) \(selected.cadence)",
                        isBusy: subscriptions.isPurchasing
                    ) {
                        Task {
                            await subscriptions.purchase(selected)
                            if subscriptions.isPosterActive {
                                onPurchased?()
                            }
                        }
                    }

                    if let error = subscriptions.storeError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Text("Subscription renews automatically.\nCancel in App Store settings. Attending events is always free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Restore purchases") {
                        Task {
                            await subscriptions.restore()
                            if subscriptions.isPosterActive {
                                onPurchased?()
                            }
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .tint(BizStyle.teal)

                    HStack(spacing: 16) {
                        if let terms = URL(string: "https://bizlinq.app/terms") {
                            Link("Terms", destination: terms)
                        }
                        if let privacy = URL(string: "https://bizlinq.app/privacy") {
                            Link("Privacy", destination: privacy)
                        }
                    }
                    .font(.footnote)
                    .tint(.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(BizStyle.canvas)
    }
}

/// Map card with a pin and two floating listing cards.
private struct PaywallIllustration: View {
    @State private var bob = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(BizStyle.tealSoft)
            Canvas { ctx, size in
                var roads = Path()
                roads.move(to: CGPoint(x: 0, y: size.height * 0.30))
                roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.55))
                roads.move(to: CGPoint(x: size.width * 0.25, y: 0))
                roads.addLine(to: CGPoint(x: size.width * 0.45, y: size.height))
                roads.move(to: CGPoint(x: size.width * 0.70, y: 0))
                roads.addLine(to: CGPoint(x: size.width * 0.60, y: size.height))
                roads.move(to: CGPoint(x: 0, y: size.height * 0.80))
                roads.addLine(to: CGPoint(x: size.width, y: size.height * 0.75))
                ctx.stroke(roads, with: .color(.white.opacity(0.9)), lineWidth: 6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            HStack(spacing: 18) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 54))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, BizStyle.teal)
                    .shadow(color: BizStyle.teal.opacity(0.35), radius: 8, y: 6)
                    .offset(y: bob ? -4 : 2)
                VStack(alignment: .leading, spacing: 8) {
                    miniCard(icon: "magnifyingglass", widths: [70, 40])
                    miniCard(icon: "person.2.fill", widths: [60, 34])
                }
            }
        }
        .accessibilityHidden(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { bob = true }
        }
    }

    private func miniCard(icon: String, widths: [CGFloat]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(BizStyle.teal)
            VStack(alignment: .leading, spacing: 4) {
                ForEach(widths, id: \.self) { width in
                    Capsule().fill(BizStyle.hairline).frame(width: width, height: 5)
                }
            }
        }
        .padding(10)
        .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

struct PaywallBullet: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BizIconBadge(systemImage: icon, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Compact plan option; tapping selects it.
struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(plan.id == SubscriptionPlan.annual.id ? "Annual" : "Monthly")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                Text("\(plan.price) \(plan.cadence)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? BizStyle.tealSoft : BizStyle.canvas)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? BizStyle.teal : BizStyle.hairline, lineWidth: isSelected ? 1.5 : 1)
            )
            .overlay(alignment: .top) {
                if let badge = plan.badge, plan.id == SubscriptionPlan.annual.id {
                    Text(badge.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(BizStyle.teal, in: Capsule())
                        .offset(y: -8)
                }
            }
        }
        .buttonStyle(BizPressStyle(scale: 0.97))
        .sensoryFeedback(.selection, trigger: isSelected)
        .accessibilityLabel("\(plan.name), \(plan.price) \(plan.cadence)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
