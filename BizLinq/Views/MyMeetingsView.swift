import SwiftUI

struct MyMeetingsView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if subscriptions.isPosterActive {
                        HStack(spacing: 12) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(subscriptions.activePlan?.name ?? "Poster plan active")
                                    .font(.headline)
                                Text("Post as often as you like")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("You don't have a poster plan yet")
                                .font(.headline)
                            Text("Browsing is free. A plan lets you publish unlimited meetings.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Button("See poster plans") {
                                showingPaywall = true
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("My posts (\(store.myMeetings.count))") {
                    if store.myMeetings.isEmpty {
                        Text("Nothing here yet. Publish your first meeting from the Post tab.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(store.myMeetings) { meeting in
                            MyMeetingRow(meeting: meeting)
                        }
                    }
                }
            }
            .navigationTitle("My Posts")
            .task {
                await store.refreshMyMeetings()
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
        }
    }
}

struct MyMeetingRow: View {
    @EnvironmentObject private var store: MeetingStore
    let meeting: Meeting
    @State private var confirmingCancel = false
    @State private var editing: Meeting?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(meeting.title)
                .font(.headline)
            Text("\(meeting.groupName) - \(Formatters.dateLine(for: meeting.startsAt))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(meeting.locationLine)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Label("\(meeting.attendeeCount) going", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Edit") {
                    editing = meeting
                }
                .font(.subheadline)
                Button("Cancel", role: .destructive) {
                    confirmingCancel = true
                }
                .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
        .sheet(item: $editing) { meeting in
            NavigationStack {
                EditMeetingView(meeting: meeting)
            }
        }
        .confirmationDialog("Cancel this meeting?", isPresented: $confirmingCancel, titleVisibility: .visible) {
            Button("Cancel meeting", role: .destructive) {
                Task { await store.cancelMeeting(meeting) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This removes the listing.")
        }
    }
}
