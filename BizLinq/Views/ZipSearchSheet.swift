import SwiftUI

/// Reusable ZIP + radius editor used by Browse and Profile.
struct ZipSearchSheet: View {
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.dismiss) private var dismiss

    @State private var zip: String = ""
    @State private var radius: SearchRadius = .twentyFive
    @State private var isSaving: Bool = false

    private var isValid: Bool {
        ZipDatabase.isValidFormat(zip)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Search area")
                    .font(.title3.bold())
                    .foregroundStyle(BizStyle.ink)
                Spacer()
                Button("Cancel") { dismiss() }
                    .tint(BizStyle.teal)
            }
            .padding(.top, 20)

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
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Driving radius")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BizStyle.ink)
                RadiusChips(selection: $radius)
                Text("Virtual events always show, no matter the radius.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            BizPrimaryButton(title: "Update search", isBusy: isSaving, enabled: isValid || radius == .nationwide) {
                save()
            }
            .padding(.bottom, 8)
        }
        .padding(.horizontal, 20)
        .background(BizStyle.canvas)
        .onAppear {
            zip = store.searchZip
            radius = store.radius
        }
    }

    private func save() {
        guard isValid || radius == .nationwide else { return }
        isSaving = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            isSaving = false
            dismiss()
        }
    }
}
