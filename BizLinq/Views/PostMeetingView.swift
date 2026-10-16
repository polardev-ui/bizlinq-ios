import SwiftUI

struct PostMeetingView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager

    // Listing form fields.
    @State private var groupName = ""
    @State private var contactName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var website = ""
    @State private var date = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var time = Calendar.current.date(bySettingHour: 18, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var location = ""
    @State private var category: MeetingCategory = .businessNetworking
    @State private var located: LocatedAddress?
    @State private var isLocating = false

    @State private var isSubmitting = false
    @State private var showGeoError = false
    @State private var didPost = false
    @State private var postedTitle = ""
    @State private var showingSignIn = false
    @State private var showingSubscribe = false
    @State private var confirmingCancelTrial = false
    @State private var publishError: String?

    private var trialStatus: TrialStatus {
        TrialStatus.current(start: store.trialStartDate, now: Date(), subscribed: subscriptions.isPosterActive)
    }

    var body: some View {
        NavigationStack {
            Group {
                if auth.userID == nil {
                    SignInPrompt(showingSignIn: $showingSignIn)
                } else if didPost {
                    PostSuccessView(title: postedTitle) {
                        didPost = false
                    }
                } else if trialStatus == .expired && !subscriptions.isPosterActive {
                    if store.trialDeclined {
                        TrialPausedView(showingSubscribe: $showingSubscribe)
                    } else {
                        TrialExpiredView(
                            showingSubscribe: $showingSubscribe,
                            confirmingCancelTrial: $confirmingCancelTrial
                        )
                    }
                } else {
                    listingForm
                }
            }
            .navigationTitle("Post a meeting")
            .task {
                await store.refreshTrialFromServer()
            }
        }
        .sheet(isPresented: $showingSubscribe) {
            NavigationStack {
                PaywallView {
                    store.setTrialDeclined(false)
                    TrialNotifications.cancelTrialReminders()
                    showingSubscribe = false
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showingSubscribe = false }
                    }
                }
            }
        }
        .confirmationDialog("Cancel your trial?", isPresented: $confirmingCancelTrial, titleVisibility: .visible) {
            Button("Cancel trial", role: .destructive) {
                store.setTrialDeclined(true)
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("You won't be able to post new meetings. You can resubscribe anytime.")
        }
    }

    // MARK: - Validation

    private var contactValid: Bool {
        !groupName.trimmingCharacters(in: .whitespaces).isEmpty
            && !contactName.trimmingCharacters(in: .whitespaces).isEmpty
            && phone.filter({ $0.isNumber }).count >= 7
            && email.contains("@") && email.contains(".")
            && !website.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var meetingDateTime: Date? {
        let calendar = Calendar.current
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        var merged = DateComponents()
        merged.year = day.year
        merged.month = day.month
        merged.day = day.day
        merged.hour = clock.hour
        merged.minute = clock.minute
        return calendar.date(from: merged)
    }

    private var isValid: Bool {
        contactValid
            && (meetingDateTime ?? Date.distantPast) > Date()
            && located != nil
    }

    // MARK: - Form

    private var listingForm: some View {
        Form {
            Section {
                switch trialStatus {
                case .notStarted:
                    Text("List your group free. Your first post starts a 14-day trial — then subscribe to keep posting.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .active(let days):
                    Label(days == 1 ? "1 day left in your free trial" : "\(days) days left in your free trial", systemImage: "calendar.badge.clock")
                        .font(.footnote)
                        .foregroundStyle(days <= TrialStatus.reminderDays ? .orange : .secondary)
                case .expired:
                    EmptyView()
                }
            }

            Section("Group") {
                TextField("Name of group", text: $groupName)
                Picker("Category", selection: $category) {
                    ForEach(MeetingCategory.allCases) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
            }

            Section("Contact") {
                TextField("Name of contact", text: $contactName)
                TextField("Phone number", text: $phone)
                    .keyboardType(.phonePad)
                TextField("Email", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                TextField("Website", text: $website)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
            }

            Section("Meeting") {
                DatePicker("Date of meeting", selection: $date, in: Date()..., displayedComponents: [.date])
                DatePicker("Time of meeting", selection: $time, displayedComponents: [.hourAndMinute])
                TextField("Location (venue, city, state, ZIP)", text: $location)
                if let located {
                    Label("Found: \(located.label)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(.green)
                } else {
                    Button {
                        locate()
                    } label: {
                        if isLocating {
                            ProgressView()
                        } else {
                            Text("Find location")
                        }
                    }
                    .disabled(location.trimmingCharacters(in: .whitespaces).isEmpty || isLocating)
                }
            }

            Section {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Text("Publish listing")
                    }
                }
                .disabled(!isValid || isSubmitting)
                if !isValid {
                    Text("Fill in every field, pick a future date and time, and find the location to publish.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .alert("Couldn't locate that address", isPresented: $showGeoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Include the venue, city, state, and ZIP — e.g. Grand Hall, Orlando, FL 32801.")
        }
        .alert("Couldn't publish", isPresented: Binding(
            get: { publishError != nil },
            set: { if !$0 { publishError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(publishError ?? "Try again later.")
        }
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
        .onChange(of: location) { _, _ in
            located = nil
        }
    }

    private func locate() {
        guard !location.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isLocating = true
        Task { @MainActor in
            if let found = await store.locate(location) {
                located = found
            } else {
                showGeoError = true
            }
            isLocating = false
        }
    }

    private func submit() {
        guard isValid, let startsAt = meetingDateTime, let place = located else { return }
        isSubmitting = true
        Task { @MainActor in
            let contact = "Contact: \(contactName.trimmingCharacters(in: .whitespaces)) · \(phone.trimmingCharacters(in: .whitespaces)) · \(email.trimmingCharacters(in: .whitespaces)) · \(website.trimmingCharacters(in: .whitespaces))"
            let meeting = Meeting(
                title: groupName.trimmingCharacters(in: .whitespaces),
                groupName: groupName.trimmingCharacters(in: .whitespaces),
                category: category,
                tagline: "\(groupName.trimmingCharacters(in: .whitespaces)) — \(place.city)",
                description: contact,
                startsAt: startsAt,
                venue: location.trimmingCharacters(in: .whitespaces),
                address: location.trimmingCharacters(in: .whitespaces),
                city: place.city,
                state: place.state,
                zipCode: place.zip,
                latitude: place.coordinate.latitude,
                longitude: place.coordinate.longitude,
                hostName: contactName.trimmingCharacters(in: .whitespaces),
                attendeeCount: 1,
                attendeeLimit: nil,
                isVirtual: false,
                costDescription: "Free"
            )
            do {
                try await store.publish(meeting)
                postedTitle = meeting.title
                reset()
                didPost = true
            } catch let error as BackendError {
                switch error {
                case .notSignedIn:
                    showingSignIn = true
                case .server(let message):
                    publishError = message
                }
            } catch {
                publishError = error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func reset() {
        groupName = ""
        contactName = ""
        phone = ""
        email = ""
        website = ""
        location = ""
        located = nil
    }
}

struct SignInPrompt: View {
    @Binding var showingSignIn: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.badge.key.fill")
                .font(.system(size: 56))
                .foregroundStyle(.teal)
            Text("Sign in to post")
                .font(.title2.bold())
            Text("Posting requires a free BizLinq account. Your first 14 days are free.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Sign in with Apple") {
                showingSignIn = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
        .sheet(isPresented: $showingSignIn) {
            SignInView()
        }
    }
}

struct TrialExpiredView: View {
    @Binding var showingSubscribe: Bool
    @Binding var confirmingCancelTrial: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 56))
                .foregroundStyle(.orange)
            Text("Your 14-day trial ended")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Subscribe to keep posting your meetings, or cancel and browse free like everyone else.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Subscribe — $10/month") {
                showingSubscribe = true
            }
            .buttonStyle(.borderedProminent)
            Button("Cancel", role: .destructive) {
                confirmingCancelTrial = true
            }
            Spacer()
        }
        .padding()
    }
}

struct TrialPausedView: View {
    @Binding var showingSubscribe: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "pause.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Posting is paused")
                .font(.title2.bold())
            Text("You cancelled your trial. Resubscribe anytime to post new meetings.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Subscribe — $10/month") {
                showingSubscribe = true
            }
            .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}

struct PostSuccessView: View {
    let title: String
    let onDone: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Meeting published")
                .font(.title2.bold())
            Text("\"\(title)\" is now live for people across the US to discover. Find it under My Posts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
            Spacer()
        }
        .padding()
    }
}
