import MapKit
import SwiftUI

/// Screen 3 — Meeting details. Cost is visible before the RSVP action:
/// free events read "RSVP for free"; paid events read "RSVP" with the fee
/// shown. No payment is collected in-app.
struct MeetingDetailView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    let ranked: RankedMeeting

    @State private var position: MapCameraPosition
    @State private var showingPaywall = false
    @State private var showingSignIn = false
    @State private var rsvpError: String?
    @State private var showingReport = false
    @State private var reportReason = MeetingStore.reportReasons[0]
    @State private var reportDone = false
    @State private var confirmingBlock = false
    @Environment(\.dismiss) private var dismiss

    init(ranked: RankedMeeting) {
        self.ranked = ranked
        let center = ranked.meeting.coordinate
        _position = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )))
    }

    private var meeting: Meeting { ranked.meeting }

    /// Live copy from the store so RSVP counts update in place.
    private var live: Meeting {
        store.meetings.first(where: { $0.id == meeting.id }) ?? meeting
    }

    private var rsvpd: Bool { store.hasRSVPd(meeting) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Text(meeting.category.rawValue.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(BizStyle.teal.opacity(0.12))
                        .foregroundStyle(BizStyle.teal)
                        .clipShape(Capsule())
                    if meeting.isVirtual {
                        Text("ONLINE")
                            .font(.caption2.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                    BizCostBadge(meeting: meeting)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.title.bold())
                        .foregroundStyle(BizStyle.ink)
                        .accessibilityAddTraits(.isHeader)
                    if !meeting.audienceLine.isEmpty {
                        Text(meeting.audienceLine)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(spacing: 12) {
                    BizMetaRow(
                        icon: "calendar",
                        title: Formatters.fullWithZone.string(from: meeting.startsAt),
                        detail: "Local time on your device"
                    )
                    if meeting.isVirtual {
                        BizMetaRow(
                            icon: "video.fill",
                            title: "Online event",
                            detail: "Check the event page for access instructions."
                        )
                    } else {
                        BizMetaRow(
                            icon: "mappin.circle.fill",
                            title: meeting.venue,
                            detail: "\(meeting.address), \(meeting.city), \(meeting.state) \(meeting.zipCode)"
                        )
                    }
                    if !meeting.isVirtual, let text = store.distanceText(for: meeting) {
                        BizMetaRow(icon: "car.fill", title: text, detail: "Straight-line distance")
                    }
                    BizMetaRow(
                        icon: "ticket.fill",
                        title: meeting.isFreeEntry ? "Free entry" : "Entry: \(meeting.costBadgeText)",
                        detail: meeting.isFreeEntry
                            ? "No attendance fee listed."
                            : "Pay the host directly — BizLinq never charges attendees."
                    )
                    BizMetaRow(
                        icon: "person.2.fill",
                        title: live.spotsLeftText ?? "\(live.attendeeCount) going",
                        detail: "RSVPs show interest, not guaranteed attendance."
                    )
                }
                .padding(14)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: BizStyle.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: BizStyle.cardRadius)
                        .stroke(BizStyle.hairline, lineWidth: 1)
                )

                if !meeting.isVirtual {
                    Map(position: $position) {
                        Marker(meeting.venue, coordinate: meeting.coordinate)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Map showing \(meeting.venue)")
                }

                BizGroupHeader(
                    groupName: meeting.groupName,
                    tagline: meeting.audienceLine,
                    hostName: meeting.hostName
                )

                NavigationLink {
                    GroupProfileView(groupName: meeting.groupName)
                } label: {
                    HStack {
                        Text("View group profile").fontWeight(.semibold)
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .foregroundStyle(BizStyle.teal)
                    .padding(14)
                    .background(BizStyle.teal.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View group profile for \(meeting.groupName)")

                Text("About this meeting")
                    .font(.headline)
                    .foregroundStyle(BizStyle.ink)
                Text(meeting.description)
                    .font(.body)

                if let source = meeting.source {
                    Label("Curated listing · sourced from \(source)", systemImage: "checkmark.seal.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let urlString = meeting.sourceURL, let url = URL(string: urlString),
                   urlString.hasPrefix("http") {
                    Link(destination: url) {
                        Label("More info on the event page", systemImage: "safari")
                            .font(.subheadline)
                            .foregroundStyle(BizStyle.teal)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(BizStyle.gutter)
            .padding(.bottom, 170)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        if auth.userID == nil {
                            showingSignIn = true
                        } else {
                            showingReport = true
                        }
                    } label: {
                        Label("Report meeting", systemImage: "flag")
                    }
                    if meeting.hostID != nil {
                        Button(role: .destructive) {
                            confirmingBlock = true
                        } label: {
                            Label("Block host", systemImage: "nosign")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Meeting options")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                BizPrimaryButton(
                    title: rsvpd ? "RSVP confirmed — tap to undo"
                        : (meeting.isFreeEntry ? "RSVP for free" : "RSVP"),
                    isBusy: false
                ) {
                    if auth.userID == nil {
                        showingSignIn = true
                    } else {
                        Task {
                            do {
                                try await store.toggleRSVP(for: meeting)
                            } catch {
                                rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            }
                        }
                    }
                }
                ShareLink(item: shareText) {
                    Label("Share this meeting", systemImage: "square.and.arrow.up")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
                .tint(BizStyle.teal)
            }
            .padding(.horizontal, BizStyle.gutter)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .sheet(isPresented: $showingPaywall) {
            NavigationStack {
                PaywallView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showingPaywall = false }
                        }
                    }
            }
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView(prompt: "Sign in with a free account to RSVP for this meeting.")
        }
        .alert("Couldn't update RSVP", isPresented: Binding(
            get: { rsvpError != nil },
            set: { if !$0 { rsvpError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(rsvpError ?? "Try again later.")
        }
        .sheet(isPresented: $showingReport) {
            NavigationStack {
                Form {
                    Section {
                        Text("Flag this meeting for review. We remove spam, scams, and inappropriate content.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Section("Reason") {
                        Picker("Reason", selection: $reportReason) {
                            ForEach(MeetingStore.reportReasons, id: \.self) { reason in
                                Text(reason).tag(reason)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                    Section {
                        Button("Submit report") {
                            Task {
                                do {
                                    try await store.reportMeeting(meeting, reason: reportReason)
                                    showingReport = false
                                    reportDone = true
                                } catch {
                                    rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                    showingReport = false
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Report meeting")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showingReport = false }
                    }
                }
            }
        }
        .alert("Thanks - report received", isPresented: $reportDone) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("We'll review this meeting and remove it if it breaks the rules.")
        }
        .confirmationDialog("Block this host?", isPresented: $confirmingBlock, titleVisibility: .visible) {
            Button("Block host", role: .destructive) {
                store.blockHost(of: meeting)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll no longer see meetings from this host.")
        }
    }

    private var shareText: String {
        "\(meeting.title) - \(meeting.groupName) on \(Formatters.dateLine(for: meeting.startsAt)) at \(meeting.venue), \(meeting.city). Found on BizLinq."
    }
}
