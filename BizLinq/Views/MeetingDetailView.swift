import MapKit
import SwiftUI

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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    Label(meeting.category.rawValue, systemImage: meeting.category.systemImage)
                        .font(.caption.bold())
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(meeting.category.tint.opacity(0.15))
                        .foregroundStyle(meeting.category.tint)
                        .clipShape(Capsule())
                    if meeting.isVirtual {
                        Text("VIRTUAL")
                            .font(.caption.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title)
                        .font(.title2.bold())
                    Text("Hosted by \(meeting.groupName)")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    Text(meeting.tagline)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                DetailInfoRow(icon: "calendar", text: Formatters.full.string(from: meeting.startsAt))
                DetailInfoRow(
                    icon: "mappin.circle.fill",
                    text: meeting.isVirtual
                        ? "Online event - link sent after RSVP"
                        : "\(meeting.venue)\n\(meeting.address), \(meeting.city), \(meeting.state) \(meeting.zipCode)"
                )
                if let text = store.distanceText(for: meeting) {
                    DetailInfoRow(icon: "car.fill", text: text)
                }
                DetailInfoRow(icon: "person.fill", text: "Hosted by \(meeting.hostName)")
                DetailInfoRow(
                    icon: "person.2.fill",
                    text: live.spotsLeftText ?? "\(live.attendeeCount) going"
                )
                DetailInfoRow(icon: "ticket", text: "Cost: \(meeting.costDescription)")
                if let source = meeting.source {
                    DetailInfoRow(icon: "checkmark.seal.fill", text: "Curated listing · sourced from \(source)")
                }
                if let urlString = meeting.sourceURL, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("More info & RSVP on the event page", systemImage: "safari")
                            .font(.subheadline)
                    }
                    .padding(.vertical, 2)
                }

                if !meeting.isVirtual {
                    Map(position: $position) {
                        Marker(meeting.venue, coordinate: meeting.coordinate)
                    }
                    .frame(height: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Text("About this meeting")
                    .font(.headline)
                Text(meeting.description)
                    .font(.body)

                Button {
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
                } label: {
                    Text(store.hasRSVPd(meeting) ? "RSVP confirmed - tap to undo" : "RSVP for free")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .tint(store.hasRSVPd(meeting) ? .green : .teal)

                ShareLink(item: shareText) {
                    Label("Share this meeting", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.bordered)

                if !subscriptions.isPosterActive {
                    Button("Post your own meeting") {
                        showingPaywall = true
                    }
                    .frame(maxWidth: .infinity)
                    .font(.subheadline)
                }
            }
            .padding()
        }
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
            }
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

struct DetailInfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
        }
    }
}
