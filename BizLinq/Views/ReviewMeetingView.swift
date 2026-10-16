import SwiftUI

/// Screen 7 — Review & publish. Previews the exact submitted data with the
/// same components visitors see. Publishing happens once, here, after the
/// backend confirms success — never before.
struct ReviewMeetingView: View {
    @EnvironmentObject private var store: MeetingStore
    let draft: MeetingDraft
    let place: LocatedAddress
    let confirmTitle: String
    var isBusy: Bool = false
    let onConfirm: () -> Void
    let onEdit: () -> Void

    private var preview: Meeting {
        draft.buildMeeting(place: place, hostName: draft.contactName)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Review your meeting")
                    .font(.title2.bold())
                    .foregroundStyle(BizStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Text("This is exactly what visitors will see.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                BizMeetingCard(
                    ranked: RankedMeeting(
                        meeting: preview,
                        distanceMiles: store.distance(for: preview)
                    )
                )

                VStack(spacing: 12) {
                    BizMetaRow(icon: "calendar", title: Formatters.fullWithZone.string(from: preview.startsAt))
                    if preview.isVirtual {
                        BizMetaRow(
                            icon: "video.fill", title: "Online event",
                            detail: preview.address.isEmpty ? "Access info to be added." : preview.address
                        )
                    } else {
                        BizMetaRow(
                            icon: "mappin.circle.fill", title: preview.venue,
                            detail: "\(preview.address), \(preview.city), \(preview.state) \(preview.zipCode)"
                        )
                    }
                    BizMetaRow(
                        icon: "ticket.fill",
                        title: preview.isFreeEntry ? "Free entry" : "Entry: \(preview.costBadgeText)",
                        detail: preview.isFreeEntry ? nil : "Attendees pay the host directly."
                    )
                    BizMetaRow(icon: "tag.fill", title: preview.category.rawValue)
                    if !preview.audienceLine.isEmpty {
                        BizMetaRow(icon: "person.2.fill", title: preview.audienceLine)
                    }
                    BizMetaRow(
                        icon: "person.fill", title: "Host: \(draft.contactName)",
                        detail: "\(draft.phone) · \(draft.email)"
                    )
                    BizMetaRow(icon: "globe", title: draft.website)
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: BizStyle.cardRadius)
                        .stroke(BizStyle.hairline, lineWidth: 1)
                )

                Text("Posting is unlimited — publish as often as you like.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                BizPrimaryButton(title: confirmTitle, isBusy: isBusy, action: onConfirm)
                BizSecondaryButton(title: "Edit details", action: onEdit)
            }
            .padding(BizStyle.gutter)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Review")
        .navigationBarTitleDisplayMode(.inline)
    }
}
