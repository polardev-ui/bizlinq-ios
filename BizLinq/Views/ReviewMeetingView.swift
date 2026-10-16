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

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Here's how it will appear. You can edit if needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    BizCover(seed: preview.groupName, category: preview.category)
                        .frame(height: 140)
                        .frame(maxWidth: .infinity)
                        .clipped()
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preview.title)
                                .font(.title3.bold())
                                .foregroundStyle(BizStyle.ink)
                            if !preview.audienceLine.isEmpty {
                                Text(preview.audienceLine)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        VStack(alignment: .leading, spacing: 12) {
                            BizMetaRow(icon: "calendar", title: Formatters.fullWithZone.string(from: preview.startsAt))
                            if preview.isVirtual {
                                BizMetaRow(
                                    icon: "video", title: "Online event",
                                    detail: preview.address.isEmpty ? "Access info to be added." : preview.address
                                )
                            } else {
                                BizMetaRow(
                                    icon: "mappin.and.ellipse", title: preview.venue,
                                    detail: "\(preview.address), \(preview.city), \(preview.state) \(preview.zipCode)"
                                )
                            }
                            BizMetaRow(
                                icon: "tag",
                                title: preview.isFreeEntry ? "Free to attend" : "\(preview.costBadgeText) to attend",
                                detail: preview.isFreeEntry ? nil : "Attendees pay the host directly."
                            )
                            BizMetaRow(
                                icon: "person.2",
                                title: trimmed(draft.contactName).isEmpty ? "Hosted by \(preview.groupName)" : "Hosted by \(trimmed(draft.contactName))",
                                detail: trimmed(draft.contactName).isEmpty ? nil : preview.groupName
                            )
                            BizMetaRow(icon: "square.grid.2x2", title: preview.category.rawValue)
                        }

                        let email = trimmed(draft.email)
                        let phone = trimmed(draft.phone)
                        let website = trimmed(draft.website)
                        if !email.isEmpty || !phone.isEmpty || !website.isEmpty {
                            Divider()
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Contact & website")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(BizStyle.ink)
                                if !email.isEmpty { contactLine(icon: "envelope", text: email) }
                                if !phone.isEmpty { contactLine(icon: "phone", text: phone) }
                                if !website.isEmpty { contactLine(icon: "arrow.up.right.square", text: website) }
                            }
                        }
                    }
                    .padding(16)
                }
                .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
                .bizCard()
                .bizAppear(index: 0)

                Label("Posting is unlimited — publish as often as you like.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BizStyle.field, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

                VStack(spacing: 10) {
                    BizPrimaryButton(title: confirmTitle, isBusy: isBusy, action: onConfirm)
                    BizSecondaryButton(title: "Edit details", action: onEdit)
                }
            }
            .padding(BizStyle.gutter)
        }
        .background(BizStyle.canvas)
        .navigationTitle("Review your meeting")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contactLine(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(BizStyle.ink.opacity(0.7))
            Text(text)
                .font(.subheadline)
                .foregroundStyle(BizStyle.teal)
                .lineLimit(1)
        }
    }
}
