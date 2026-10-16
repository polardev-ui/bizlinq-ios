import SwiftUI

/// "My Meetings" tab — the attendee's upcoming RSVP'd meetings, with
/// undo/cancel. Owned posts live under Host.
struct AttendeeMeetingsView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var auth: AuthManager
    @State private var showingSignIn = false
    @State private var rsvpError: String?

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
            Group {
                if auth.userID == nil {
                    VStack(spacing: 16) {
                        Spacer()
                        Image(systemName: "ticket.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(BizStyle.teal)
                        Text("Your RSVPs live here")
                            .font(.title2.bold())
                        Text("Sign in with a free account to RSVP, then find your upcoming meetings in this list.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal)
                        BizPrimaryButton(title: "Sign in with Apple") {
                            showingSignIn = true
                        }
                        .padding(.horizontal, BizStyle.gutter)
                        Spacer()
                    }
                    .padding()
                } else if store.myRSVPs.isEmpty {
                    BizStateView(
                        kind: .empty,
                        title: "No upcoming RSVPs",
                        message: "Find a meeting on Discover and tap RSVP — it will show up here."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.myRSVPs) { meeting in
                                NavigationLink {
                                    MeetingDetailView(
                                        ranked: RankedMeeting(
                                            meeting: meeting,
                                            distanceMiles: store.distance(for: meeting)
                                        )
                                    )
                                } label: {
                                    BizMeetingCard(
                                        ranked: RankedMeeting(
                                            meeting: meeting,
                                            distanceMiles: store.distance(for: meeting)
                                        )
                                    )
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Cancel RSVP") {
                                        cancelRSVP(meeting)
                                    }
                                }
                            }
                        }
                        .padding(BizStyle.gutter)
                    }
                    .background(Color(.systemGroupedBackground))
                }
            }
            .navigationTitle("My Meetings")
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
}
