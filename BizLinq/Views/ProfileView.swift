import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var store: MeetingStore
    @EnvironmentObject private var subscriptions: SubscriptionManager
    @EnvironmentObject private var auth: AuthManager
    @AppStorage("bizlinq.hasCompletedOnboarding") private var completed = true

    @State private var zip: String = ""
    @State private var radius: SearchRadius = .twentyFive
    @State private var displayName: String = ""
    @State private var isSaving = false
    @State private var showingPaywall = false
    @State private var showingSignIn = false
    @State private var confirmingSignOut = false

    private var zipValid: Bool {
        ZipDatabase.isValidFormat(zip)
    }

    private var signInCapabilityText: String {
        switch AppDiagnostics.signInCapabilityInProfile {
        case .some(true): return "In this build"
        case .some(false): return "MISSING — update needed"
        case .none: return "Simulator (N/A)"
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if auth.userID != nil {
                        HStack {
                            Image(systemName: "person.crop.circle.fill")
                                .foregroundStyle(.teal)
                            VStack(alignment: .leading) {
                                Text(auth.displayName.isEmpty ? "BizLinq member" : auth.displayName)
                                    .font(.headline)
                                Text("Signed in with Apple")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        TextField("Display name", text: $displayName)
                        Button("Save display name") {
                            Task { await auth.saveDisplayName(displayName) }
                        }
                        .disabled(displayName.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Sign out", role: .destructive) {
                            confirmingSignOut = true
                        }
                    } else {
                        Text("Posting and RSVPing require a free account. Browsing does not.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Sign in with Apple") {
                            showingSignIn = true
                        }
                    }
                }

                Section("Search area") {
                    TextField("ZIP code", text: $zip)
                        .keyboardType(.numberPad)
                        .onChange(of: zip) { _, newValue in
                            zip = String(newValue.filter { $0.isNumber }.prefix(5))
                        }
                    Picker("Radius", selection: $radius) {
                        ForEach(SearchRadius.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    Button {
                        saveLocation()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Save search area")
                        }
                    }
                    .disabled(!zipValid || isSaving)
                }

                Section("Poster plan") {
                    if subscriptions.isPosterActive {
                        HStack {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(.green)
                            VStack(alignment: .leading) {
                                Text(subscriptions.activePlan?.name ?? "Poster plan")
                                    .font(.headline)
                                Text("1 live post every 7 days")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let expiry = subscriptions.subscriptionExpiry {
                                    Text("Renews \(Formatters.dateLine(for: expiry))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        Button("Manage subscription") {
                            subscriptions.openManageSubscriptions()
                        }
                    } else {
                        Text("Browsing is free. Posting requires a poster plan.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("See poster plans") {
                            showingPaywall = true
                        }
                    }
                }

                Section("How BizLinq works") {
                    Label("Free to view and join meetings", systemImage: "eye.fill")
                    Label("Costs money to post a meeting", systemImage: "ticket.fill")
                    Label("1 post per poster every 7 days", systemImage: "calendar.badge.clock")
                }

                Section {
                    Button("Replay intro") {
                        completed = false
                    }
                }

                Section("Diagnostics") {
                    HStack {
                        Text("Bundle ID")
                        Spacer()
                        Text(AppDiagnostics.bundleID)
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(AppDiagnostics.versionBuild)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Apple sign-in capability")
                        Spacer()
                        Text(signInCapabilityText)
                            .foregroundStyle(.secondary)
                    }
                    if let team = AppDiagnostics.teamPrefix {
                        HStack {
                            Text("Team")
                            Spacer()
                            Text(team)
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        }
                    }
                }

                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0 (Prototype)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Profile")
            .onAppear {
                zip = store.searchZip
                radius = store.radius
                displayName = auth.displayName
            }
            .sheet(isPresented: $showingSignIn) {
                SignInView()
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
            .confirmationDialog("Sign out of BizLinq?", isPresented: $confirmingSignOut, titleVisibility: .visible) {
                Button("Sign out", role: .destructive) {
                    Task { await auth.signOut() }
                }
                Button("Stay signed in", role: .cancel) {}
            }
        }
    }

    private func saveLocation() {
        guard zipValid else { return }
        isSaving = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            isSaving = false
        }
    }
}
