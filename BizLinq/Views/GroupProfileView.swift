import SwiftUI

/// Screen 4 — Group profile. Built only from genuinely upcoming meetings
/// that share this exact group name. Nothing is manufactured: no invented
/// schedule, no activity claims, no merged identities.
struct GroupProfileView: View {
    @EnvironmentObject private var store: MeetingStore
    let groupName: String
    @State private var showingNext = false

    private var upcoming: [Meeting] {
        store.meetings
            .filter { $0.status == "live" && $0.groupName == groupName && $0.startsAt > Date() }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var venues: [Meeting] {
        var seen: Set<String> = []
        var out: [Meeting] = []
        for meeting in upcoming {
            let key = meeting.isVirtual ? "online" : "\(meeting.venue)|\(meeting.city)"
            if seen.insert(key).inserted { out.append(meeting) }
            if out.count == 3 { break }
        }
        return out
    }

    private var eventLink: URL? {
        upcoming.lazy.compactMap { meeting -> URL? in
            guard let raw = meeting.sourceURL, raw.hasPrefix("http") else { return nil }
            return URL(string: raw)
        }.first
    }

    private var category: MeetingCategory { upcoming.first?.category ?? .businessNetworking }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                banner
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(groupName)
                            .font(.title2.bold())
                            .foregroundStyle(BizStyle.ink)
                            .accessibilityAddTraits(.isHeader)
                        if let tagline = upcoming.first?.audienceLine, !tagline.isEmpty {
                            Text(tagline)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .bizAppear(index: 0)

                    if let host = upcoming.first?.hostName, !host.isEmpty {
                        BizHostRow(hostName: host, showsChevron: false)
                            .bizAppear(index: 1)
                    }

                    if let next = upcoming.first {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("About this group")
                                .font(.headline)
                                .foregroundStyle(BizStyle.ink)
                            Text(next.description)
                                .font(.subheadline)
                                .foregroundStyle(BizStyle.ink.opacity(0.8))
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .bizAppear(index: 2)
                    }

                    if !venues.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(venues) { meeting in
                                if meeting.isVirtual {
                                    BizMetaRow(icon: "video", title: "Online", detail: "Join from anywhere")
                                } else {
                                    BizMetaRow(
                                        icon: "mappin.and.ellipse",
                                        title: meeting.venue,
                                        detail: "\(meeting.address), \(meeting.city), \(meeting.state) \(meeting.zipCode)"
                                    )
                                }
                            }
                            if let eventLink {
                                Link(destination: eventLink) {
                                    HStack(spacing: 12) {
                                        Image(systemName: "globe")
                                            .frame(width: 22)
                                        Text(eventLink.host() ?? eventLink.absoluteString)
                                            .lineLimit(1)
                                        Image(systemName: "arrow.up.right.square")
                                            .font(.footnote)
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(BizStyle.teal)
                                }
                            }
                            Text("Venues as listed on upcoming meetings.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .bizAppear(index: 3)
                    }

                    if let eventLink {
                        Link(destination: eventLink) {
                            BizSecondaryLabel(title: "Visit website", systemImage: "safari")
                        }
                        .buttonStyle(BizPressStyle())
                    }

                    if upcoming.isEmpty {
                        BizStateView(
                            kind: .empty,
                            title: "No upcoming meetings",
                            message: "This group has nothing scheduled right now. Check back soon.",
                            systemImage: "calendar"
                        )
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            BizSectionHeader(title: "Upcoming meetings")
                            VStack(spacing: 0) {
                                ForEach(Array(upcoming.prefix(5).enumerated()), id: \.element.id) { index, meeting in
                                    if index > 0 { Divider().padding(.leading, 52) }
                                    NavigationLink {
                                        MeetingDetailView(
                                            ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting))
                                        )
                                    } label: {
                                        BizDateRow(meeting: meeting)
                                    }
                                    .buttonStyle(BizPressStyle())
                                }
                            }
                        }
                        .bizAppear(index: 4)

                        BizPrimaryButton(title: "View next meeting") {
                            showingNext = true
                        }
                    }
                }
                .padding(.horizontal, BizStyle.gutter)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
        }
        .ignoresSafeArea(edges: .top)
        .background(BizStyle.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let eventLink {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: eventLink) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share group")
                }
            }
        }
        .tint(BizStyle.teal)
        .navigationDestination(isPresented: $showingNext) {
            if let next = upcoming.first {
                MeetingDetailView(ranked: RankedMeeting(meeting: next, distanceMiles: store.distance(for: next)))
            }
        }
    }

    private var banner: some View {
        BizCover(seed: groupName, category: category)
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .clipped()
            .overlay(alignment: .top) {
                LinearGradient(colors: [.black.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 100)
            }
            .overlay(alignment: .bottomLeading) {
                BizCover(seed: groupName + "-avatar", category: category)
                    .frame(width: 84, height: 84)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(BizStyle.canvas, lineWidth: 4))
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
                    .offset(x: BizStyle.gutter, y: 34)
            }
            .padding(.bottom, 34)
    }
}
