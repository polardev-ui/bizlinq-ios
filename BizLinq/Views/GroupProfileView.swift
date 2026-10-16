import SwiftUI

/// Screen 4 — Group profile. Built only from genuinely upcoming meetings
/// that share this exact group name. Nothing is manufactured: no invented
/// schedule, no activity claims, no merged identities.
struct GroupProfileView: View {
    @EnvironmentObject private var store: MeetingStore
    let groupName: String

    private var upcoming: [Meeting] {
        store.meetings
            .filter { $0.status == "live" && $0.groupName == groupName && $0.startsAt > Date() }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var venues: [String] {
        var seen: [String] = []
        for meeting in upcoming {
            let label = meeting.isVirtual ? "Online" : "\(meeting.venue) — \(meeting.city), \(meeting.state)"
            if !seen.contains(label) { seen.append(label) }
            if seen.count == 3 { break }
        }
        return seen
    }

    private var eventLinks: [URL] {
        upcoming.compactMap { meeting in
            guard let raw = meeting.sourceURL, raw.hasPrefix("http"), let url = URL(string: raw) else { return nil }
            return url
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BizGroupHeader(
                    groupName: groupName,
                    tagline: upcoming.first?.audienceLine ?? "",
                    hostName: upcoming.first?.hostName
                )

                if let next = upcoming.first {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Next meeting")
                            .font(.headline)
                            .foregroundStyle(BizStyle.ink)
                        NavigationLink {
                            MeetingDetailView(
                                ranked: RankedMeeting(
                                    meeting: next,
                                    distanceMiles: store.distance(for: next)
                                )
                            )
                        } label: {
                            BizMeetingCard(
                                ranked: RankedMeeting(
                                    meeting: next,
                                    distanceMiles: store.distance(for: next)
                                )
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("View next meeting: \(next.title)")
                    }
                } else {
                    BizStateView(
                        kind: .empty,
                        title: "No upcoming meetings",
                        message: "This group has nothing scheduled right now. Check back soon."
                    )
                }

                if !venues.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where they meet")
                            .font(.headline)
                            .foregroundStyle(BizStyle.ink)
                        ForEach(venues, id: \.self) { venue in
                            BizMetaRow(icon: "mappin.circle.fill", title: venue)
                        }
                        Text("Venues as listed on upcoming meetings.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                if upcoming.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Also upcoming (\(upcoming.count - 1))")
                            .font(.headline)
                            .foregroundStyle(BizStyle.ink)
                        ForEach(upcoming.dropFirst().prefix(5)) { meeting in
                            NavigationLink {
                                MeetingDetailView(
                                    ranked: RankedMeeting(
                                        meeting: meeting,
                                        distanceMiles: store.distance(for: meeting)
                                    )
                                )
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(meeting.title)
                                            .font(.subheadline.weight(.medium))
                                            .foregroundStyle(BizStyle.ink)
                                        Text(Formatters.dateLine(for: meeting.startsAt))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(12)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(BizStyle.hairline, lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                ForEach(Array(eventLinks.prefix(2).enumerated()), id: \.offset) { _, url in
                    Link(destination: url) {
                        Label("More info on the event page", systemImage: "safari")
                            .font(.subheadline)
                            .foregroundStyle(BizStyle.teal)
                    }
                }
            }
            .padding(BizStyle.gutter)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(groupName)
        .navigationBarTitleDisplayMode(.inline)
    }
}
