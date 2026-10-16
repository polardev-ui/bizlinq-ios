import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject private var store: MeetingStore
    @AppStorage("bizlinq.hasCompletedOnboarding") private var completed = false

    @State private var zip: String = ""
    @State private var radius: SearchRadius = .twentyFive
    @State private var isSaving: Bool = false

    private var isValid: Bool {
        ZipDatabase.isValidFormat(zip)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 12) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 120, height: 120)
                        .padding(.top, 32)

                    Text("BizLinq")
                        .font(.largeTitle.bold())

                    Text("Find business networking meetings near you. Free to browse, free to join.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "radar", title: "Discover meetups", text: "Search by ZIP code and driving radius, anywhere in the US.")
                    FeatureRow(icon: "ticket", title: "Posting costs money", text: "Hosts pay for a poster plan, so listings stay real.")
                    FeatureRow(icon: "calendar.badge.clock", title: "One post per week", text: "Posters can publish 1 meeting every 7 days.")
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Where should we look?")
                        .font(.headline)

                    TextField("ZIP code", text: $zip)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: zip) { _, newValue in
                            zip = String(newValue.filter { $0.isNumber }.prefix(5))
                        }

                    Text("How far will you drive?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    RadiusChips(selection: $radius)

                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding()
                        } else {
                            Text("Find networking meetings")
                                .frame(maxWidth: .infinity)
                                .padding()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid || isSaving)

                    Button("Explore nationwide instead") {
                        store.searchZip = ""
                        store.radius = .nationwide
                        store.saveLocation()
                        completed = true
                    }
                    .frame(maxWidth: .infinity)
                    .font(.subheadline)
                }
                .padding(.horizontal)

                Spacer(minLength: 24)
            }
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            isSaving = false
            completed = true
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.teal)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold())
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct RadiusChips: View {
    @Binding var selection: SearchRadius

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(SearchRadius.allCases) { option in
                    Button(option.label) {
                        selection = option
                    }
                    .buttonStyle(.bordered)
                    .tint(selection == option ? .teal : .gray)
                    .fontWeight(selection == option ? .semibold : .regular)
                }
            }
        }
    }
}
