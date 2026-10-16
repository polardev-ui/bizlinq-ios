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
        NavigationStack {
            Form {
                Section("Location") {
                    TextField("ZIP code", text: $zip)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .onChange(of: zip) { _, newValue in
                            zip = String(newValue.filter { $0.isNumber }.prefix(5))
                        }
                }

                Section("Driving radius") {
                    Picker("Radius", selection: $radius) {
                        ForEach(SearchRadius.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Virtual events always show, no matter the radius.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Update search")
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
            .navigationTitle("Search area")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                zip = store.searchZip
                radius = store.radius
            }
        }
    }

    private func save() {
        guard isValid else { return }
        isSaving = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            isSaving = false
            dismiss()
        }
    }
}
