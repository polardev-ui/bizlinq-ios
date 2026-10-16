import SwiftUI

/// Shown when subscribing: from the trial-expired screen, My Posts, or Profile.
struct PaywallView: View {
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var selectedID: String = SubscriptionPlan.monthly.id
    var onPurchased: (() -> Void)? = nil

    private var selected: SubscriptionPlan {
        SubscriptionPlan.all.first { $0.id == selectedID } ?? SubscriptionPlan.monthly
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 88, height: 88)
                    .padding(.top, 16)

                VStack(spacing: 6) {
                    Text("Help local professionals find your group")
                        .font(.title.bold())
                        .multilineTextAlignment(.center)
                    Text("They don't need to know your group's name. They just need to be looking for their next connection.")
                        .font(.subheadline.italic())
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 10) {
                    PaywallBullet(icon: "mappin.circle.fill", text: "Discovery by location and category")
                    PaywallBullet(icon: "person.2.fill", text: "Meeting details and free RSVPs")
                    PaywallBullet(icon: "calendar.badge.clock", text: "Unlimited meeting posts, editable anytime")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))

                VStack(spacing: 10) {
                    ForEach(SubscriptionPlan.all) { plan in
                        PlanCard(plan: plan, isSelected: plan.id == selectedID, trialEligible: subscriptions.isTrialEligible(plan))
                            .onTapGesture { selectedID = plan.id }
                    }
                }

                VStack(spacing: 4) {
                    Text("14 days free")
                        .font(.headline)
                    Text(selected.id == SubscriptionPlan.annual.id
                         ? "$99/year afterward"
                         : "$10/month afterward")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("This is for hosting. Attending events is always free.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task {
                        await subscriptions.purchase(selected)
                        if subscriptions.isPosterActive {
                            onPurchased?()
                        }
                    }
                } label: {
                    if subscriptions.isPurchasing {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else if subscriptions.isTrialEligible(selected) {
                        Text("Start your free trial")
                            .frame(maxWidth: .infinity)
                            .padding()
                    } else {
                        Text("Continue - \(selected.price) \(selected.cadence)")
                            .frame(maxWidth: .infinity)
                            .padding()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(subscriptions.isPurchasing)

                if let error = subscriptions.storeError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                Button("Restore purchase") {
                    Task { await subscriptions.restore() }
                }
                .font(.subheadline)

                HStack(spacing: 16) {
                    if let terms = URL(string: "https://bizlinq.app/terms") {
                        Link("Terms", destination: terms)
                    }
                    if let privacy = URL(string: "https://bizlinq.app/privacy") {
                        Link("Privacy", destination: privacy)
                    }
                }
                .font(.footnote)

                Text("Post unlimited meetings on every plan. Subscriptions renew automatically until cancelled in your App Store settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal)
        }
    }
}

struct PaywallBullet: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}

struct PlanCard: View {
    let plan: SubscriptionPlan
    let isSelected: Bool
    let trialEligible: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.systemImage)
                .foregroundStyle(.teal)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(plan.name)
                        .font(.headline)
                    if let badge = plan.badge {
                        Text(badge.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.teal.opacity(0.15))
                            .foregroundStyle(.teal)
                            .clipShape(Capsule())
                    }
                }
                Text(plan.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if trialEligible {
                    Text("14 days free, then \(plan.price) \(plan.cadence)")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                }
            }
            Spacer()
            VStack(alignment: .trailing) {
                Text(plan.price)
                    .font(.headline)
                Text(plan.cadence)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? .teal : .gray)
        }
        .padding()
        .background(isSelected ? Color.teal.opacity(0.08) : Color(.secondarySystemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.teal : Color.clear, lineWidth: 2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
