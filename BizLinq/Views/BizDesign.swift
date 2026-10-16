import SwiftUI
import UIKit

/// Shared BizLinq style tokens. Teal carries primary action/selection;
/// category color is used sparingly (selected filters, badges).
enum BizStyle {
    static let teal = Color(red: 0.0, green: 0.56, blue: 0.58) // ~#008F95
    /// Near-black in light mode, near-white in dark mode.
    static let ink = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.96, alpha: 1.0)
            : UIColor(red: 0.09, green: 0.15, blue: 0.20, alpha: 1.0) // ~#182632
    })
    static let canvas = Color(.systemGroupedBackground)
    static let hairline = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 1.0, alpha: 0.14)
            : UIColor(red: 0.878, green: 0.902, blue: 0.918, alpha: 1.0) // ~#E0E6EA
    })
    static let cardRadius: CGFloat = 16
    static let gutter: CGFloat = 16
}

/// Primary teal action button, 50pt tall, full width.
struct BizPrimaryButton: View {
    let title: String
    var systemImage: String? = nil
    var isBusy: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy { ProgressView().tint(.white) }
                if let systemImage { Image(systemName: systemImage) }
                Text(title).fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(BizStyle.teal)
        .disabled(!enabled || isBusy)
        .accessibilityLabel(title)
    }
}

/// Secondary outlined button.
struct BizSecondaryButton: View {
    let title: String
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            Text(title)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .buttonStyle(.bordered)
        .tint(role == .destructive ? .red : BizStyle.teal)
        .accessibilityLabel(title)
    }
}

/// Small selectable filter chip.
struct BizChip: View {
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(selected ? .semibold : .regular))
                if let count {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(selected ? BizStyle.teal : .secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? BizStyle.teal.opacity(0.12) : Color(.secondarySystemBackground))
            .overlay(
                Capsule().stroke(selected ? BizStyle.teal : Color.clear, lineWidth: 1.5)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)\(selected ? ", selected" : "")")
    }
}

/// Cost badge. Unknown/unspecified costs read as "Fee varies" — never "Free".
struct BizCostBadge: View {
    let meeting: Meeting

    var body: some View {
        Text(meeting.costBadgeText)
            .font(.caption2.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((meeting.isFreeEntry ? Color.green : BizStyle.teal).opacity(0.14))
            .foregroundStyle(meeting.isFreeEntry ? .green : BizStyle.teal)
            .clipShape(Capsule())
            .accessibilityLabel(meeting.isFreeEntry ? "Free entry" : "Cost: \(meeting.costBadgeText)")
    }
}

/// One tappable meeting card for Discover lists.
struct BizMeetingCard: View {
    let ranked: RankedMeeting
    @EnvironmentObject private var store: MeetingStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.secondarySystemBackground))
                        .frame(width: 52, height: 52)
                    Image(systemName: ranked.meeting.category.systemImage)
                        .font(.title3)
                        .foregroundStyle(BizStyle.teal)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(ranked.meeting.title)
                        .font(.headline)
                        .foregroundStyle(BizStyle.ink)
                        .lineLimit(2)
                    Text("Hosted by \(ranked.meeting.groupName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                BizCostBadge(meeting: ranked.meeting)
            }
            if !ranked.meeting.audienceLine.isEmpty {
                Text(ranked.meeting.audienceLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Label(Formatters.dateLine(for: ranked.meeting.startsAt), systemImage: "calendar")
                Spacer()
                if ranked.meeting.attendeeCount > 0 {
                    Label("\(ranked.meeting.attendeeCount)", systemImage: "person.2.fill")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack(spacing: 4) {
                Image(systemName: ranked.meeting.isVirtual ? "video.fill" : "mappin.circle.fill")
                Text(ranked.meeting.locationLine).lineLimit(1)
                if !ranked.meeting.isVirtual, let text = store.distanceText(for: ranked.meeting) {
                    Text("· \(text)")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: BizStyle.cardRadius)
                .stroke(BizStyle.hairline, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(ranked.meeting.title), \(Formatters.dateLine(for: ranked.meeting.startsAt))")
    }
}

/// Icon + two-line metadata row.
struct BizMetaRow: View {
    let icon: String
    let title: String
    var detail: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(BizStyle.teal)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                if let detail {
                    Text(detail).font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Group/host header used on detail, group, and host screens.
struct BizGroupHeader: View {
    let groupName: String
    let tagline: String
    let hostName: String?

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(BizStyle.teal.opacity(0.12))
                    .frame(width: 52, height: 52)
                Text(String(groupName.prefix(1)).uppercased())
                    .font(.title2.bold())
                    .foregroundStyle(BizStyle.teal)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(groupName).font(.headline)
                if !tagline.isEmpty {
                    Text(tagline).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                if let hostName, !hostName.isEmpty {
                    Text("Hosted by \(hostName)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Group \(groupName)")
    }
}

/// Small summary tile for host metrics.
struct BizMetricTile: View {
    let value: String
    let label: String
    var footnote: String? = nil

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold()).foregroundStyle(BizStyle.ink)
            Text(label).font(.caption).foregroundStyle(.secondary)
            if let footnote {
                Text(footnote).font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BizStyle.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// Honest placeholder when a metric has no backing data yet.
struct BizMetricUnavailable: View {
    let label: String
    let reason: String

    var body: some View {
        VStack(spacing: 4) {
            Text("—").font(.title2.bold()).foregroundStyle(.secondary)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(reason).font(.caption2).foregroundStyle(.tertiary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(BizStyle.hairline, lineWidth: 1))
    }
}

/// Shared empty / error / loading states.
struct BizStateView: View {
    enum Kind { case empty, error, loading }
    let kind: Kind
    let title: String
    let message: String
    var actionTitle: String? = nil
    var secondaryTitle: String? = nil
    var action: (() -> Void)? = nil
    var secondaryAction: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            if kind == .loading {
                ProgressView()
            } else {
                Image(systemName: kind == .error ? "wifi.exclamationmark" : "radar")
                    .font(.system(size: 44))
                    .foregroundStyle(BizStyle.teal)
                    .accessibilityHidden(true)
            }
            Text(title).font(.headline).multilineTextAlignment(.center)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let actionTitle, let action {
                BizPrimaryButton(title: actionTitle, action: action)
                    .padding(.top, 4)
            }
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.subheadline.weight(.semibold))
                    .tint(BizStyle.teal)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
    }
}

/// Form section wrapper with consistent spacing.
struct BizFormSection<Content: View>: View {
    let title: String
    var footnote: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        Section(title) {
            content
            if let footnote {
                Text(footnote).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
