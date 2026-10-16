import SwiftUI

/// Screen 1 — Discover. Brand row, headline, compact location, search +
/// Filters, horizontal category chips, then meeting cards.
struct BrowseView: View {
    @EnvironmentObject private var store: MeetingStore
    @State private var showingSearch = false
    @State private var showingFilters = false
    @State private var path = NavigationPath()
    @FocusState private var searchFocused: Bool
    @Namespace private var zoom
    var autoOpenDetail: Bool = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    searchRow
                    chipsRow
                    resultsSection
                }
                .padding(.horizontal, BizStyle.gutter)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
            .background(BizStyle.canvas)
            .refreshable {
                await store.resolveZip()
                await store.refreshFromBackend()
            }
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting)))
                    .bizZoomTransition(id: meeting.id, in: zoom)
            }
            .sheet(isPresented: $showingSearch) {
                ZipSearchSheet()
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showingFilters) {
                FiltersSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(28)
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

    private var locationText: String {
        if store.radius == .nationwide || store.searchZip.isEmpty { return "Nationwide" }
        let place = store.resolvedPlace ?? store.searchZip
        return "\(place) · \(store.radius.label.replacingOccurrences(of: " mi", with: " miles"))"
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image("Logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .accessibilityHidden(true)
                Text("BizLinq")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(BizStyle.ink)
                Spacer()
            }
            .padding(.top, 8)

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
                    .tint(BizStyle.teal)
                }
                .padding(10)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            Text("Find your next\nbusiness connection")
                .font(.system(.largeTitle, weight: .bold))
                .foregroundStyle(BizStyle.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .accessibilityAddTraits(.isHeader)

            Button {
                showingSearch = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .foregroundStyle(BizStyle.teal)
                    Text(locationText)
                        .foregroundStyle(BizStyle.ink)
                        .contentTransition(.interpolate)
                    if store.isResolving {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline.weight(.medium))
                .contentShape(Rectangle())
            }
            .buttonStyle(BizPressStyle(scale: 0.96))
            .accessibilityLabel("Location: \(locationText). Change location.")
        }
        .animation(BizStyle.spring, value: store.backendError)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search meetings", text: $store.query)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .accessibilityLabel("Search meetings")
                if !store.query.isEmpty {
                    Button {
                        withAnimation(BizStyle.snappy) { store.query = "" }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .accessibilityLabel("Clear search")
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(BizStyle.field, in: RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                    .stroke(searchFocused ? BizStyle.teal : .clear, lineWidth: 1.5)
            )
            .animation(BizStyle.snappy, value: searchFocused)
            .animation(BizStyle.snappy, value: store.query.isEmpty)

            Button {
                showingFilters = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "slider.horizontal.3")
                    Text("Filters")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BizStyle.ink)
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                        .stroke(BizStyle.hairline, lineWidth: 1)
                )
                .overlay(alignment: .topTrailing) {
                    if store.activeFilterCount > 0 {
                        Text("\(store.activeFilterCount)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(minWidth: 18, minHeight: 18)
                            .background(BizStyle.teal, in: Circle())
                            .offset(x: 6, y: -6)
                            .contentTransition(.numericText())
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .buttonStyle(BizPressStyle(scale: 0.95))
            .animation(BizStyle.spring, value: store.activeFilterCount)
            .accessibilityLabel("Filters\(store.activeFilterCount > 0 ? ", \(store.activeFilterCount) active" : "")")
        }
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BizChip(title: "All", selected: store.selectedCategory == nil) {
                    store.selectedCategory = nil
                }
                ForEach(MeetingCategory.allCases) { category in
                    BizChip(
                        title: category.shortName,
                        selected: store.selectedCategory == category
                    ) {
                        store.selectedCategory = store.selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, BizStyle.gutter)
            .padding(.vertical, 2)
        }
        .padding(.horizontal, -BizStyle.gutter)
    }

    @ViewBuilder
    private var resultsSection: some View {
        let results = store.filteredMeetings()
        Group {
            if store.locationUnresolved {
                BizStateView(
                    kind: .error,
                    title: "Can't find that ZIP",
                    message: "We couldn't locate \(store.searchZip). Check the ZIP code and try again — results may be outside your radius until then.",
                    systemImage: "mappin.slash",
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
                    action: { withAnimation(BizStyle.spring) { store.clearFilters() } },
                    secondaryAction: {
                        store.radius = .nationwide
                        store.saveLocation()
                    }
                )
                .transition(.opacity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Upcoming meetings")
                            .font(.headline)
                            .foregroundStyle(BizStyle.ink)
                        Spacer()
                        Text(results.count == 1 ? "1 result" : "\(results.count) results")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.numericText())
                    }
                    LazyVStack(spacing: 14) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { index, ranked in
                            NavigationLink(value: ranked.meeting) {
                                BizMeetingCard(ranked: ranked)
                                    .bizZoomSource(id: ranked.meeting.id, in: zoom)
                            }
                            .buttonStyle(BizPressStyle())
                            .bizAppear(index: index)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.96)),
                                removal: .opacity
                            ))
                        }
                    }
                }
            }
        }
        .animation(BizStyle.spring, value: results.map(\.id))
    }
}

/// Screen 2 — Filters sheet. Draft state commits only on "Show meetings";
/// swipe-to-dismiss leaves the Discover list untouched.
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

    /// Result count for the draft. Only knowable while the ZIP is unchanged
    /// (a new ZIP must be geocoded first).
    private var previewCount: Int? {
        guard zip == store.searchZip else { return nil }
        return store.filteredMeetings(category: category, visibility: visibility, cost: cost, radius: radius).count
    }

    private var radiusOptions: [SearchRadius] { [.five, .ten, .twentyFive, .fifty, .hundred] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Find your fit")
                    .font(.title2.bold())
                    .foregroundStyle(BizStyle.ink)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Clear all") {
                    withAnimation(BizStyle.spring) { resetDrafts() }
                }
                .font(.subheadline.weight(.semibold))
                .tint(BizStyle.teal)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Location") {
                        HStack {
                            TextField("ZIP code", text: $zip)
                                .keyboardType(.numberPad)
                                .textContentType(.postalCode)
                                .accessibilityLabel("Location ZIP code")
                                .onChange(of: zip) { _, newValue in
                                    let digits = String(newValue.filter(\.isNumber).prefix(5))
                                    if digits != newValue { zip = digits }
                                }
                            if !zip.isEmpty {
                                Button {
                                    zip = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                                }
                                .accessibilityLabel("Clear ZIP code")
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 46)
                        .background(BizStyle.canvas, in: RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: BizStyle.controlRadius, style: .continuous)
                                .stroke(BizStyle.hairline, lineWidth: 1)
                        )
                    }

                    section("Radius") {
                        BizFlowLayout {
                            ForEach(radiusOptions) { option in
                                BizChip(
                                    title: option == .hundred ? "100 miles" : option.label.replacingOccurrences(of: " mi", with: ""),
                                    selected: radius == option
                                ) { radius = option }
                            }
                            BizChip(title: "Nationwide", selected: radius == .nationwide, systemImage: "globe.americas") {
                                radius = .nationwide
                            }
                        }
                    }

                    section("Categories") {
                        BizFlowLayout {
                            ForEach(MeetingCategory.allCases) { option in
                                BizChip(
                                    title: option.rawValue.replacingOccurrences(of: " Meetings", with: ""),
                                    selected: category == option,
                                    showsCheck: true
                                ) {
                                    category = category == option ? nil : option
                                }
                            }
                        }
                    }

                    section("Format") {
                        HStack(spacing: 8) {
                            BizChip(title: "Any", selected: visibility == .all) { visibility = .all }
                            BizChip(title: "In person", selected: visibility == .inPerson) { visibility = .inPerson }
                            BizChip(title: "Online", selected: visibility == .virtual) { visibility = .virtual }
                        }
                    }

                    section("Cost", footnote: "Listings without a stated fee count as Paid, never Free.") {
                        HStack(spacing: 8) {
                            BizChip(title: "Any", selected: cost == .any) { cost = .any }
                            BizChip(title: "Free", selected: cost == .free) { cost = .free }
                            BizChip(title: "Paid", selected: cost == .paid) { cost = .paid }
                        }
                    }

                    section("Sort by") {
                        HStack(spacing: 8) {
                            BizChip(title: "Nearest", selected: nearestFirst) { nearestFirst = true }
                            BizChip(title: "Soonest", selected: !nearestFirst) { nearestFirst = false }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.immediately)

            BizPrimaryButton(title: showTitle, isBusy: isApplying, action: apply)
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 12)
                .animation(BizStyle.snappy, value: previewCount)
        }
        .background(BizStyle.canvas)
        .onAppear(perform: loadDrafts)
    }

    private var showTitle: String {
        if let previewCount { return "Show meetings (\(previewCount))" }
        return "Show meetings"
    }

    private func section<Content: View>(
        _ title: String,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BizStyle.ink)
            content()
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
            withAnimation(BizStyle.spring) {
                store.selectedCategory = category
                store.visibility = visibility
                store.costFilter = cost
                store.sortByDistance = nearestFirst
            }
            isApplying = false
            dismiss()
        }
    }
}
