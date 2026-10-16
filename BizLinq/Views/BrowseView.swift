import SwiftUI

/// Screen 1 — Discover. Headline, compact location, search + Filters,
/// horizontal category chips, then meeting cards.
struct BrowseView: View {
    @EnvironmentObject private var store: MeetingStore
    @State private var showingSearch = false
    @State private var showingFilters = false
    @State private var path = NavigationPath()
    var autoOpenDetail: Bool = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    searchRow
                    chipsRow
                    resultsSection
                }
                .padding(.horizontal, BizStyle.gutter)
                .padding(.bottom, 16)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("BizLinq")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await store.resolveZip()
                            await store.refreshFromBackend()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh meetings")
                }
            }
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting)))
            }
            .sheet(isPresented: $showingSearch) {
                ZipSearchSheet()
            }
            .sheet(isPresented: $showingFilters) {
                FiltersSheet()
            }
            .task {
                await store.resolveZip()
                await store.refreshFromBackend()
            }
            .onAppear {
                if autoOpenDetail, path.isEmpty, let first = store.filteredMeetings().first {
                    path.append(first.meeting)
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let error = store.backendError {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Retry") {
                        Task { await store.refreshFromBackend() }
                    }
                    .font(.footnote.bold())
                }
                .padding(10)
                .background(Color.orange.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            Text("Find your next business connection")
                .font(.title.bold())
                .foregroundStyle(BizStyle.ink)
                .accessibilityAddTraits(.isHeader)
            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundStyle(BizStyle.teal)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(store.locationSummary)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BizStyle.ink)
                        if store.radius != .nationwide, !store.searchZip.isEmpty {
                            Text("Within \(store.radius.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("All upcoming meetings in the US")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    if store.isResolving {
                        ProgressView()
                    } else {
                        Text("Change")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(BizStyle.teal)
                    }
                }
                .padding(12)
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(BizStyle.hairline, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Location: \(store.locationSummary). Change location.")
        }
        .padding(.top, 8)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search title, group, or city", text: $store.query)
                    .accessibilityLabel("Search meetings")
            }
            .padding(10)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(BizStyle.hairline, lineWidth: 1)
            )
            Button {
                showingFilters = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                    Text("Filters")
                    if store.activeFilterCount > 0 {
                        Text("\(store.activeFilterCount)")
                            .font(.caption2.bold())
                            .padding(6)
                            .background(Color.white.opacity(0.25))
                            .clipShape(Circle())
                    }
                }
                .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(BizStyle.teal)
            .accessibilityLabel("Filters\(store.activeFilterCount > 0 ? ", \(store.activeFilterCount) active" : "")")
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BizChip(
                    title: "All", count: nil,
                    selected: store.selectedCategory == nil
                ) { store.selectedCategory = nil }
                ForEach(MeetingCategory.allCases) { category in
                    BizChip(
                        title: category.shortName,
                        count: store.count(for: category),
                        selected: store.selectedCategory == category
                    ) {
                        if store.selectedCategory == category {
                            store.selectedCategory = nil
                        } else {
                            store.selectedCategory = category
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = store.filteredMeetings()
        if store.locationUnresolved {
            BizStateView(
                kind: .error,
                title: "Can't find that ZIP",
                message: "We couldn't locate \(store.searchZip). Check the ZIP code and try again — results below may be outside your radius until then.",
                actionTitle: "Retry locating ZIP",
                secondaryTitle: "Browse nationwide instead",
                action: {
                    Task {
                        await store.resolveZip()
                        await store.refreshFromBackend()
                    }
                },
                secondaryAction: {
                    store.radius = .nationwide
                    store.saveLocation()
                }
            )
        } else if results.isEmpty {
            BizStateView(
                kind: .empty,
                title: "No meetings found",
                message: "Try clearing filters, widening the radius, or browsing nationwide.",
                actionTitle: "Clear filters",
                secondaryTitle: "Go nationwide",
                action: { store.clearFilters() },
                secondaryAction: {
                    store.radius = .nationwide
                    store.saveLocation()
                }
            )
        } else {
            Text("Upcoming meetings (\(results.count))")
                .font(.headline)
                .foregroundStyle(BizStyle.ink)
                .padding(.top, 4)
            LazyVStack(spacing: 10) {
                ForEach(results) { ranked in
                    NavigationLink(value: ranked.meeting) {
                        BizMeetingCard(ranked: ranked)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// Screen 2 — Filters sheet. Draft state commits only on "Show meetings";
/// Cancel/swipe leaves the Discover list untouched.
struct FiltersSheet: View {
    @EnvironmentObject private var store: MeetingStore
    @Environment(\.dismiss) private var dismiss

    @State private var zip: String = ""
    @State private var radius: SearchRadius = .twentyFive
    @State private var category: MeetingCategory? = nil
    @State private var visibility: VisibilityFilter = .all
    @State private var cost: CostFilter = .any
    @State private var nearestFirst = true
    @State private var isApplying = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Location") {
                    TextField("ZIP code", text: $zip)
                        .keyboardType(.numberPad)
                        .textContentType(.postalCode)
                        .accessibilityLabel("Location ZIP code")
                    Picker("Radius", selection: $radius) {
                        ForEach(SearchRadius.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        Text("All categories").tag(nil as MeetingCategory?)
                        ForEach(MeetingCategory.allCases) { option in
                            Text(option.rawValue).tag(option as MeetingCategory?)
                        }
                    }
                }

                Section("Format") {
                    Picker("Format", selection: $visibility) {
                        ForEach(VisibilityFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    Picker("Attendance cost", selection: $cost) {
                        ForEach(CostFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("Listings without a stated fee count as Paid, never Free.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Cost")
                }

                Section("Sort") {
                    Picker("Sort", selection: $nearestFirst) {
                        Text("Nearest").tag(true)
                        Text("Soonest").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("Find your fit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear all") { resetDrafts() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: loadDrafts)
            .safeAreaInset(edge: .bottom) {
                Button {
                    apply()
                } label: {
                    if isApplying {
                        ProgressView().tint(.white)
                    } else {
                        Text("Show meetings").fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .buttonStyle(.borderedProminent)
                .tint(BizStyle.teal)
                .padding(.horizontal, BizStyle.gutter)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityLabel("Show meetings")
            }
        }
    }

    private func loadDrafts() {
        zip = store.searchZip
        radius = store.radius
        category = store.selectedCategory
        visibility = store.visibility
        cost = store.costFilter
        nearestFirst = store.sortByDistance
    }

    private func resetDrafts() {
        zip = ""
        radius = .nationwide
        category = nil
        visibility = .all
        cost = .any
        nearestFirst = true
    }

    private func apply() {
        isApplying = true
        Task { @MainActor in
            await store.updateLocation(zip: zip, radius: radius)
            store.selectedCategory = category
            store.visibility = visibility
            store.costFilter = cost
            store.sortByDistance = nearestFirst
            isApplying = false
            dismiss()
        }
    }
}
