import SwiftUI

struct BrowseView: View {
    @EnvironmentObject private var store: MeetingStore
    @State private var showingSearch = false
    @State private var path = NavigationPath()
    var autoOpenDetail: Bool = false

    var body: some View {
        NavigationStack(path: $path) {
            List {
                if let error = store.backendError {
                    Section {
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
                    }
                }
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(store.locationSummary)
                                .font(.headline)
                            if store.radius != .nationwide, !store.searchZip.isEmpty {
                                Text("Within \(store.radius.label)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("All upcoming meetings in the US")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if store.isResolving {
                            ProgressView()
                        } else {
                            Button("Change") { showingSearch = true }
                        }
                    }

                    TextField("Search title, group, or city", text: $store.query)
                        .textFieldStyle(.roundedBorder)

                    Text("Browse by category")
                        .font(.headline)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(MeetingCategory.allCases) { category in
                            CategoryTile(
                                category: category,
                                count: store.count(for: category),
                                isSelected: store.selectedCategory == category
                            ) {
                                if store.selectedCategory == category {
                                    store.selectedCategory = nil
                                } else {
                                    store.selectedCategory = category
                                }
                            }
                        }
                    }

                    Picker("Showing", selection: $store.visibility) {
                        ForEach(VisibilityFilter.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)

                    Picker("Sort", selection: $store.sortByDistance) {
                        Text("Nearest").tag(true)
                        Text("Soonest").tag(false)
                    }
                    .pickerStyle(.segmented)
                }

                Section {
                    let results = store.filteredMeetings()
                    if store.locationUnresolved {
                        ContentUnavailableView(
                            "Can't find that ZIP",
                            systemImage: "mappin.slash",
                            description: Text("We couldn't locate \(store.searchZip). Check the ZIP code and try again — results below may be outside your radius until then.")
                        )
                        Button("Retry locating ZIP") {
                            Task {
                                await store.resolveZip()
                                await store.refreshFromBackend()
                            }
                        }
                        Button("Browse nationwide instead") {
                            store.radius = .nationwide
                            store.saveLocation()
                        }
                    } else if results.isEmpty {
                        ContentUnavailableView(
                            "No meetings found",
                            systemImage: "radar",
                            description: Text("Try a wider radius or browse nationwide.")
                        )
                        Button("Expand to 100 mi") {
                            store.radius = .hundred
                            store.saveLocation()
                        }
                        Button("Go nationwide") {
                            store.radius = .nationwide
                            store.saveLocation()
                        }
                    } else {
                        ForEach(results) { ranked in
                            NavigationLink(value: ranked.meeting) {
                                MeetingRow(ranked: ranked)
                            }
                        }
                    }
                } header: {
                    Text("Upcoming meetings (\(store.filteredMeetings().count))")
                }
            }
            .listStyle(.plain)
            .navigationTitle("BizLinq")
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
                }
            }
            .navigationDestination(for: Meeting.self) { meeting in
                MeetingDetailView(ranked: RankedMeeting(meeting: meeting, distanceMiles: store.distance(for: meeting)))
            }
            .sheet(isPresented: $showingSearch) {
                ZipSearchSheet()
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
}

struct CategoryTile: View {
    let category: MeetingCategory
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(category.tint.opacity(isSelected ? 0.3 : 0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: category.systemImage)
                        .foregroundStyle(category.tint)
                }
                Text(category.rawValue)
                    .font(.caption2.bold())
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
                Text("\(count)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(isSelected ? category.tint.opacity(0.12) : Color(.secondarySystemBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? category.tint : Color.clear, lineWidth: 2)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

struct MeetingRow: View {
    @EnvironmentObject private var store: MeetingStore
    let ranked: RankedMeeting

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(ranked.meeting.category.tint.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: ranked.meeting.category.systemImage)
                    .foregroundStyle(ranked.meeting.category.tint)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(ranked.meeting.title)
                        .font(.headline)
                        .lineLimit(1)
                    if ranked.meeting.isVirtual {
                        Text("VIRTUAL")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text(ranked.meeting.groupName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(Formatters.dateLine(for: ranked.meeting.startsAt))
                    Spacer()
                    if ranked.meeting.attendeeCount > 0 {
                        Image(systemName: "person.2.fill")
                        Text("\(ranked.meeting.attendeeCount)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                HStack(spacing: 4) {
                    Image(systemName: "mappin.circle.fill")
                    Text(ranked.meeting.locationLine)
                        .lineLimit(1)
                    if let text = store.distanceText(for: ranked.meeting) {
                        Text("- \(text)")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
