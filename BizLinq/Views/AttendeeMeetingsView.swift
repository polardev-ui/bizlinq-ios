import SwiftUI

/// "My Meetings" tab — the attendee's upcoming RSVP'd meetings (with
/// undo/cancel) plus meetings saved on this device. Owned posts live under Host.
struct AttendeeMeetingsView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var auth: AuthManager
    @AppStorage(SavedMeetings.key) private var savedRaw = ""
    @State private var showingSignIn = false
    @State private var rsvpError: String?
    @State private var segment: Segment = .going
    @Namespace private var zoom

    private enum Segment: String, CaseIterable, Identifiable {
        case going = "Going"
        case saved = "Saved"
        var id: String { rawValue }
    }

    private var saved: [Meeting] {
        let ids = SavedMeetings.ids(savedRaw)
        return store.meetings
            .filter { ids.contains($0.id.uuidString) && $0.status == "live" && $0.startsAt > Date() }
            .sorted { $0.startsAt < $1.startsAt }
    }

    private var rsvpAlertShown: Binding<Bool> {
        Binding(
            get: { rsvpError != nil },
            set: { newValue in if !newValue { rsvpError = nil } }
        )
    }

    private func cancelRSVP(_ meeting: Meeting) {
        Task {
            do {
                try await store.toggleRSVP(for: meeting)
            } catch {
                rsvpError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    HStack(spacing: 8) {
                        ForEach(Segment.allCases) { option in
                            BizChip(
                                title: option.rawValue,
                                count: option == .going ? store.myRSVPs.count : saved.count,
                                selected: segment == option
                            ) { segment = option }
                        }
                        Spacer()
                    }

                    Group {
                        switch segment {
                        case .going: goingList
                        case .saved: savedList
                        }
                    }
                    .transition(.opacity)
                }
                .padding(BizStyle.gutter)
                .animation(BizStyle.spring, value: segment)
            }
            .background(BizStyle.canvas)
            .navigationTitle("My Meetings")
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting)))
                    .bizZoomTransition(id: meeting.id, in: zoom)
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView(prompt: "Sign in to track your RSVPs.")
            }
            .alert("Couldn't update RSVP", isPresented: rsvpAlertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(rsvpError ?? "Try again later.")
            }
        }
    }

    @ViewBuilder
    private var goingList: some View {
        if auth.userID == nil {
            BizStateView(
                kind: .empty,
                title: "Your RSVPs live here",
                message: "Sign in with a free account to RSVP, then find your upcoming meetings in this list.",
                systemImage: "calendar",
                actionTitle: "Sign in with Apple",
                action: { showingSignIn = true }
            )
        } else if store.myRSVPs.isEmpty {
            BizStateView(
                kind: .empty,
                title: "No upcoming RSVPs",
                message: "Find a meeting on Discover and tap RSVP — it will show up here.",
                systemImage: "calendar.badge.plus"
            )
        } else {
            cards(store.myRSVPs, cancellable: true)
        }
    }

    @ViewBuilder
    private var savedList: some View {
        if saved.isEmpty {
            BizStateView(
                kind: .empty,
                title: "Nothing saved yet",
                message: "Tap the heart on any meeting to keep it here for later.",
                systemImage: "heart"
            )
        } else {
            cards(saved, cancellable: false)
        }
    }

    private func cards(_ meetings: [Meeting], cancellable: Bool) -> some View {
        LazyVStack(spacing: 14) {
            ForEach(Array(meetings.enumerated()), id: \.element.id) { index, meeting in
                NavigationLink(value: meeting) {
                    BizMeetingCard(ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting)))
                        .bizZoomSource(id: meeting.id, in: zoom)
                }
                .buttonStyle(BizPressStyle())
                .bizAppear(index: index)
                .contextMenu {
                    if cancellable {
                        Button("Cancel RSVP", systemImage: "xmark.circle", role: .destructive) {
                            cancelRSVP(meeting)
                        }
                    }
                }
            }
        }
    }
}
