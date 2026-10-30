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

    @State private var appeared = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 14) {
                    Image("Logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 104, height: 104)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: BizStyle.teal.opacity(0.3), radius: 16, y: 8)
                        .scaleEffect(appeared ? 1 : 0.6)
                        .opacity(appeared ? 1 : 0)
                        .padding(.top, 36)

                    Text("BizLinq")
                        .font(.largeTitle.bold())
                        .foregroundStyle(BizStyle.ink)
                        .bizAppear(index: 1)

                    Text("Find business networking meetings near you. Free to browse and RSVP. Hosts post for $10/month.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)
                        .bizAppear(index: 2)
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "dot.radiowaves.left.and.right", title: "Discover meetups", text: "Search by ZIP code and driving radius, anywhere in the US.")
                    FeatureRow(icon: "checkmark.seal", title: "Real listings", text: "Hosts pay for a poster plan, so listings stay real.")
                    FeatureRow(icon: "calendar.badge.clock", title: "Always free to attend", text: "Browse, save, and RSVP without paying a thing.")
                }
                .padding(18)
                .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.cardRadius, style: .continuous))
                .padding(.horizontal)
                .bizAppear(index: 3)

                VStack(alignment: .leading, spacing: 12) {
                    Text("Where should we look?")
                        .font(.headline)
                        .foregroundStyle(BizStyle.ink)

                    HStack(spacing: 8) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(BizStyle.teal)
                        TextField("ZIP code", text: $zip)
                            .keyboardType(.numberPad)
                            .textContentType(.postalCode)
                            .onChange(of: zip) { _, newValue in
                                let digits = String(newValue.filter { $0.isNumber }.prefix(5))
                                if digits != newValue { zip = digits }
                            }
                        if isValid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(BizStyle.teal)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                            .stroke(isValid ? BizStyle.teal : BizStyle.hairline, lineWidth: isValid ? 1.5 : 1)
                    )
                    .animation(BizStyle.snappy, value: isValid)

                    Text("How far will you drive?")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)

                    RadiusChips(selection: $radius)

                    BizPrimaryButton(title: "Find networking meetings", isBusy: isSaving, enabled: isValid) {
                        save()
                    }
                    .padding(.top, 8)

                    Button("Explore nationwide instead") {
                        store.searchZip = ""
                        store.radius = .nationwide
                        store.saveLocation()
                        completed = true
                    }
                    .frame(maxWidth: .infinity)
                    .font(.subheadline.weight(.semibold))
                    .tint(BizStyle.teal)
                    .padding(.top, 4)
                }
                .padding(.horizontal)
                .bizAppear(index: 4)

                Spacer(minLength: 24)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .background(BizStyle.canvas)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) { appeared = true }
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            isSaving = false
            withAnimation(BizStyle.spring) { completed = true }
        }
    }
}

struct FeatureRow: View {
    let icon: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            BizIconBadge(systemImage: icon, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.bold()).foregroundStyle(BizStyle.ink)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

struct RadiusChips: View {
    @Binding var selection: SearchRadius

    var body: some View {
        BizFlowLayout {
            ForEach(SearchRadius.allCases) { option in
                BizChip(title: option.label, selected: selection == option) {
                    selection = option
                }
            }
        }
    }
}
