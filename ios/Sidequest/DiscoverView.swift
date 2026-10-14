import MapKit
import SwiftUI

// Laid out after screenshots 02 (Home / date-grouped feed) and 03 (Discover / category chips,
// campus rail). The feed is flat on a white background — no cards — and every row is an
// `SQEventRow`. See DESIGN_NOTES.md.

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilters = false
    @State private var compareIds: Set<UUID> = []
    @State private var showComparison = false
    @State private var showMap = false
    @State private var showSearch = false

    /// Events bucketed by calendar day, in chronological order — the "17 October / Saturday"
    /// grouping from screenshot 02.
    private var grouped: [(day: Date, events: [EventFeedItem])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: model.events) { calendar.startOfDay(for: $0.startsAt) }
        return buckets.keys.sorted().map { (day: $0, events: buckets[$0]!.sorted { $0.startsAt < $1.startsAt }) }
    }

    /// Distinct categories present in the feed, used to build the chip rail in screenshot 03.
    private var categories: [String] {
        var seen = Set<String>()
        return model.events.compactMap { event in
            let name = event.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, seen.insert(name.lowercased()).inserted else { return nil }
            return name
        }
    }

    private var activeFilterCount: Int {
        var count = 0
        if !model.categoryFilter.isEmpty { count += 1 }
        if !model.collegeFilter.isEmpty { count += 1 }
        if model.freeOnly { count += 1 }
        if !model.maxPrice.isEmpty { count += 1 }
        if !model.eligibilityFilter.isEmpty { count += 1 }
        if model.upcomingDays != 0 { count += 1 }
        return count
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                SQScreenHeader(title: "Discover", avatarSeed: "Sidequest", showsSparkle: true) {
                    SQActionCapsule {
                        SQCapsuleGlyph(
                            systemImage: showSearch ? "xmark" : "magnifyingglass",
                            accessibilityTitle: showSearch ? "Close search" : "Search events"
                        ) {
                            showSearch.toggle()
                            if !showSearch && !model.searchText.isEmpty {
                                model.searchText = ""
                            }
                        }
                        SQCapsuleGlyph(systemImage: "map", accessibilityTitle: "Discover colleges on map") {
                            showMap = true
                        }
                        SQCapsuleGlyph(
                            systemImage: activeFilterCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle",
                            showsBadge: activeFilterCount > 0,
                            accessibilityTitle: "Event filters"
                        ) {
                            showFilters = true
                        }
                    }
                }
                .padding(.bottom, SQSpace.lg)

                if showSearch {
                    SQField(placeholder: "Search published events", text: $model.searchText, systemImage: "magnifyingglass")
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, SQSpace.margin)
                        .padding(.bottom, SQSpace.lg)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                content
            }
            .background(SQColor.plainBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(for: EventFeedItem.self) { selectedEvent in
                EventDetailView(event: selectedEvent, comparing: compareIds.contains(selectedEvent.id)) { comparing in
                    if comparing { compareIds.insert(selectedEvent.id) } else { compareIds.remove(selectedEvent.id) }
                }
            }
            .sheet(isPresented: $showFilters) { EventFiltersView() }
            .sheet(isPresented: $showComparison) {
                CompareEventsView(events: model.events.filter { compareIds.contains($0.id) })
            }
            .sheet(isPresented: $showMap) { CampusDiscoveryMap(campuses: model.campuses) }
            .animation(.easeInOut(duration: 0.2), value: showSearch)
            .onChange(of: model.searchText) {
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    guard !Task.isCancelled else { return }
                    await model.reloadEvents()
                }
            }
            .task { if model.eventState == .idle { await model.reloadEvents() } }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.eventState {
        case .idle where model.events.isEmpty, .loading where model.events.isEmpty:
            loadingState
        case .failed(let message) where model.events.isEmpty:
            scrollWrapper {
                SQEmptyState(
                    message: "Couldn’t load events. \(message)",
                    systemImage: "wifi.exclamationmark",
                    actionTitle: "Try again"
                ) {
                    Task { await model.reloadEvents() }
                }
                .padding(.horizontal, SQSpace.margin)
            }
        default:
            if model.events.isEmpty {
                scrollWrapper {
                    VStack(alignment: .leading, spacing: SQSpace.xxl) {
                        SQSectionHeader(title: "Picked for You", subtitle: "Nothing yet", subtitleGlyph: nil)
                        SQEmptyState(
                            message: "When organizers publish events, they’ll appear here automatically.",
                            systemImage: "calendar.badge.plus",
                            actionTitle: activeFilterCount > 0 ? "Clear filters" : nil,
                            action: activeFilterCount > 0 ? { clearFilters() } : nil
                        )
                        .padding(.horizontal, SQSpace.margin)
                    }
                }
            } else {
                feed
            }
        }
    }

    private var loadingState: some View {
        scrollWrapper {
            VStack(alignment: .leading, spacing: SQSpace.groupGap) {
                SQSectionHeader(title: "Picked for You", subtitle: "Finding what’s next…")
                ForEach(0..<3, id: \.self) { _ in
                    SQEventRowPlaceholder().padding(.horizontal, SQSpace.margin)
                }
            }
        }
    }

    private var feed: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SQSpace.groupGap, pinnedViews: []) {
                if !compareIds.isEmpty {
                    compareBanner
                }

                SQSectionHeader(
                    title: "Picked for You",
                    subtitle: model.searchText.isEmpty ? "Nearby" : "Matching “\(model.searchText)”",
                    subtitleGlyph: model.searchText.isEmpty ? "chevron.up.chevron.down" : nil
                )

                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: SQSpace.rowGap) {
                        SQDateHeader(date: group.day)
                        ForEach(group.events) { event in
                            NavigationLink(value: event) {
                                SQEventRow(
                                    title: event.title,
                                    hostName: event.organizationName,
                                    imageURL: model.eventImageURLs[event.id],
                                    seed: event.title,
                                    timeText: event.startsAt.formatted(date: .omitted, time: .shortened),
                                    venueText: event.venueName,
                                    badgeText: badgeText(for: event),
                                    badgeForeground: badgeForeground(for: event),
                                    badgeBackground: badgeBackground(for: event)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, SQSpace.margin)
                            .contextMenu { compareMenu(for: event) }
                        }
                    }
                }

                if model.canLoadMore {
                    SQSecondaryButton(title: "Show more", systemImage: "arrow.down") {
                        Task { await model.loadNextPage() }
                    }
                    .padding(.horizontal, SQSpace.margin)
                }

                if !categories.isEmpty {
                    categorySection
                }

                if !model.campuses.isEmpty {
                    campusSection
                }
            }
            .padding(.bottom, SQSpace.tabBarClearance)
        }
        .refreshable { await model.reloadEvents() }
    }

    private var compareBanner: some View {
        HStack(spacing: SQSpace.md) {
            Text("\(compareIds.count) selected to compare")
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
            Spacer()
            Button("Compare") { showComparison = true }
                .font(SQFont.bodyEmphasis)
                .foregroundStyle(SQColor.textPrimary)
            Button("Clear") { compareIds.removeAll() }
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
        }
        .padding(.horizontal, SQSpace.cardInset)
        .frame(height: SQSize.listRow)
        .background(SQColor.lime.opacity(0.35), in: RoundedRectangle(cornerRadius: SQRadius.chip, style: .continuous))
        .padding(.horizontal, SQSpace.margin)
    }

    @ViewBuilder private func compareMenu(for event: EventFeedItem) -> some View {
        if compareIds.contains(event.id) {
            Button("Remove from comparison", systemImage: "minus.square") { compareIds.remove(event.id) }
        } else {
            Button("Add to comparison", systemImage: "square.on.square") { compareIds.insert(event.id) }
        }
    }

    /// "Browse by Category" — screenshot 03. Chips drive the existing `categoryFilter`.
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: SQSpace.lg) {
            SQSectionHeader(title: "Browse by Category")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: [GridItem(.fixed(SQSize.listRow), spacing: SQSpace.md),
                                 GridItem(.fixed(SQSize.listRow), spacing: SQSpace.md)],
                          spacing: SQSpace.md) {
                    ForEach(categories, id: \.self) { category in
                        SQChip(
                            title: category,
                            systemImage: Self.glyph(for: category),
                            color: SQColor.categorical(for: category),
                            isSelected: model.categoryFilter.caseInsensitiveCompare(category) == .orderedSame
                        ) {
                            toggleCategory(category)
                        }
                    }
                }
                .padding(.horizontal, SQSpace.margin)
            }
            .frame(height: SQSize.listRow * 2 + SQSpace.md)
        }
    }

    /// "Cities" in screenshot 03 becomes Sidequest's campus rail.
    private var campusSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.lg) {
            SQSectionHeader(title: "Campuses", showsChevron: true) { showMap = true }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: SQSpace.md) {
                    ForEach(model.campuses) { campus in
                        CampusCard(campus: campus) { showMap = true }
                    }
                }
                .padding(.horizontal, SQSpace.margin)
            }
        }
    }

    private func scrollWrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) { content() }
                .padding(.top, SQSpace.sm)
                .padding(.bottom, SQSpace.tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await model.reloadEvents() }
    }

    private func toggleCategory(_ category: String) {
        if model.categoryFilter.caseInsensitiveCompare(category) == .orderedSame {
            model.categoryFilter = ""
        } else {
            model.categoryFilter = category
        }
        Task { await model.reloadEvents() }
    }

    private func clearFilters() {
        model.categoryFilter = ""
        model.collegeFilter = ""
        model.freeOnly = false
        model.maxPrice = ""
        model.eligibilityFilter = ""
        model.upcomingDays = 0
        Task { await model.reloadEvents() }
    }

    private func badgeText(for event: EventFeedItem) -> String? {
        if let registration = model.registration(for: event.editionId) {
            return registration.status == "registered" ? "Going" : registration.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
        if compareIds.contains(event.id) { return "Comparing" }
        if model.savedEventIds.contains(event.id) { return "Saved" }
        if event.priceMinor == 0 { return nil }
        return event.priceLabel
    }

    private func badgeForeground(for event: EventFeedItem) -> Color {
        guard let registration = model.registration(for: event.editionId) else { return SQColor.textPrimary }
        return registration.status == "registered" ? SQColor.positive : SQColor.warning
    }

    private func badgeBackground(for event: EventFeedItem) -> Color {
        guard let registration = model.registration(for: event.editionId) else { return SQColor.lime.opacity(0.4) }
        return registration.status == "registered"
            ? SQColor.positive.opacity(0.15)
            : SQColor.warning.opacity(0.15)
    }

    /// Maps a free-text category onto an SF Symbol, mirroring how Luma gives every category
    /// its own glyph in screenshot 03. Falls back to a neutral tag.
    static func glyph(for category: String) -> String {
        switch category.lowercased() {
        case let value where value.contains("tech") || value.contains("code") || value.contains("hack"): "chevron.left.forwardslash.chevron.right"
        case let value where value.contains("music") || value.contains("concert"): "music.note"
        case let value where value.contains("sport") || value.contains("run") || value.contains("fitness"): "figure.run"
        case let value where value.contains("food") || value.contains("drink"): "fork.knife"
        case let value where value.contains("art") || value.contains("design"): "paintpalette"
        case let value where value.contains("book") || value.contains("literature"): "book"
        case let value where value.contains("game") || value.contains("gaming"): "dice"
        case let value where value.contains("ai") || value.contains("ml") || value.contains("data"): "brain"
        case let value where value.contains("workshop") || value.contains("talk") || value.contains("seminar"): "person.bust"
        case let value where value.contains("film") || value.contains("movie") || value.contains("drama"): "theatermasks"
        case let value where value.contains("volunteer") || value.contains("social"): "hands.sparkles"
        default: "tag"
        }
    }
}

/// Skeleton row shown while the first page loads, so the feed keeps its shape.
private struct SQEventRowPlaceholder: View {
    var body: some View {
        HStack(alignment: .top, spacing: SQSpace.lg) {
            RoundedRectangle(cornerRadius: SQRadius.thumb, style: .continuous)
                .fill(SQColor.surfaceAlt)
                .frame(width: SQSize.eventThumb, height: SQSize.eventThumb)
            VStack(alignment: .leading, spacing: SQSpace.sm) {
                Capsule().fill(SQColor.surfaceAlt).frame(width: 120, height: 14)
                Capsule().fill(SQColor.surfaceAlt).frame(height: 18)
                Capsule().fill(SQColor.surfaceAlt).frame(width: 180, height: 14)
            }
            .padding(.top, 4)
        }
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

/// The photo card from screenshot 03's "Cities" rail, reused for campuses.
private struct CampusCard: View {
    let campus: CampusPoint
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [SQColor.categorical(for: campus.name).opacity(0.85), SQColor.ink],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                VStack(alignment: .leading) {
                    ZStack {
                        Circle().fill(.ultraThinMaterial)
                        Image(systemName: "building.columns")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .frame(width: SQSize.sheetCircle, height: SQSize.sheetCircle)
                    Spacer()
                    Text(campus.name)
                        .font(SQFont.rowTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(14)
            }
            .frame(width: 200, height: 230)
            .clipShape(RoundedRectangle(cornerRadius: SQRadius.cover, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

/// Full-bleed map with floating circular chrome — screenshot 06.
private struct CampusDiscoveryMap: View {
    @Environment(\.dismiss) private var dismiss
    let campuses: [CampusPoint]

    var body: some View {
        ZStack(alignment: .top) {
            if campuses.isEmpty {
                SQColor.background.ignoresSafeArea()
                VStack {
                    Spacer()
                    SQEmptyState(
                        message: "Published campus coordinates will appear here.",
                        systemImage: "map"
                    )
                    .padding(.horizontal, SQSpace.margin)
                    Spacer()
                }
            } else {
                Map {
                    ForEach(campuses) { campus in
                        Annotation(campus.name, coordinate: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude)) {
                            MapThumbnailPin(title: campus.name)
                        }
                    }
                }
                .ignoresSafeArea()
            }

            HStack {
                SQCircleButton(systemImage: "chevron.left") { dismiss() }
                Spacer()
            }
            .padding(.horizontal, SQSpace.margin)
            .padding(.top, SQSpace.sm)
        }
    }
}

/// Luma's map annotation (screenshot 06): a small thumbnail tile with a white border and a
/// shadow, with the title centered underneath.
struct MapThumbnailPin: View {
    let title: String
    var imageURL: URL?
    var overflow: Int = 0

    var body: some View {
        VStack(spacing: 6) {
            SQThumbnail(url: imageURL, seed: title, size: 56, radius: SQRadius.tile)
                .overlay(
                    RoundedRectangle(cornerRadius: SQRadius.tile, style: .continuous)
                        .stroke(.white, lineWidth: 2)
                )
                .sqShadow(SQShadow.floating)
            Text(title)
                .font(SQFont.bodyEmphasis)
                .foregroundStyle(SQColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if overflow > 0 {
                Text("+\(overflow) more")
                    .font(SQFont.body)
                    .foregroundStyle(SQColor.textSecondary)
            }
        }
        .frame(width: 130)
    }
}

/// Filters, restyled as the grouped sheet from screenshot 07.
private struct EventFiltersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        SQSheet(title: "Filters", onClose: { dismiss() }) {
            SQCard(padding: SQSpace.cardInset) {
                VStack(spacing: SQSpace.md) {
                    SQField(placeholder: "Category (exact)", text: $model.categoryFilter)
                        .textInputAutocapitalization(.never)
                    SQField(placeholder: "College (exact)", text: $model.collegeFilter)
                    SQField(placeholder: "Eligibility contains", text: $model.eligibilityFilter)
                }
            }

            SQGroupHeader(title: "Price")
                .padding(.horizontal, -SQSpace.margin)
            SQCard {
                SQListRow(title: "Free events only", accessory: .none) {
                    Toggle("", isOn: $model.freeOnly).labelsHidden()
                }
                SQInsetDivider(leading: SQSpace.cardInset)
                VStack(alignment: .leading, spacing: SQSpace.sm) {
                    SQField(placeholder: "Maximum price (₹)", text: $model.maxPrice)
                        .keyboardType(.decimalPad)
                        .disabled(model.freeOnly)
                        .opacity(model.freeOnly ? 0.4 : 1)
                }
                .padding(SQSpace.cardInset)
            }

            SQGroupHeader(title: "Date")
                .padding(.horizontal, -SQSpace.margin)
            SQCard {
                Picker("Date", selection: $model.upcomingDays) {
                    Text("Any date").tag(0)
                    Text("Next 7 days").tag(7)
                    Text("Next 30 days").tag(30)
                }
                .pickerStyle(.segmented)
                .padding(SQSpace.cardInset)
            }

            VStack(spacing: SQSpace.md) {
                SQPrimaryButton(title: "Apply filters", systemImage: "line.3.horizontal.decrease") {
                    Task {
                        await model.reloadEvents()
                        dismiss()
                    }
                }
                SQSecondaryButton(title: "Clear filters", systemImage: "arrow.counterclockwise", destructive: true) {
                    model.categoryFilter = ""
                    model.collegeFilter = ""
                    model.freeOnly = false
                    model.maxPrice = ""
                    model.eligibilityFilter = ""
                    model.upcomingDays = 0
                    Task {
                        await model.reloadEvents()
                        dismiss()
                    }
                }
            }
        }
    }
}

/// Side-by-side comparison, restyled as grouped cards.
private struct CompareEventsView: View {
    @Environment(\.dismiss) private var dismiss
    let events: [EventFeedItem]

    var body: some View {
        SQSheet(title: "Compare", onClose: { dismiss() }) {
            if events.isEmpty {
                SQEmptyState(
                    message: "Press and hold an event in Discover to add it to a comparison.",
                    systemImage: "square.on.square"
                )
            }
            ForEach(events) { event in
                VStack(alignment: .leading, spacing: SQSpace.headerToCard) {
                    SQGroupHeader(title: event.title)
                        .padding(.horizontal, -SQSpace.margin)
                    SQCard {
                        CompareRow(label: "Organizer", value: event.organizationName)
                        SQInsetDivider(leading: SQSpace.cardInset)
                        CompareRow(label: "College", value: event.collegeName)
                        SQInsetDivider(leading: SQSpace.cardInset)
                        CompareRow(label: "When", value: event.startsAt.formatted(date: .abbreviated, time: .shortened))
                        SQInsetDivider(leading: SQSpace.cardInset)
                        CompareRow(label: "Price", value: event.priceLabel)
                        SQInsetDivider(leading: SQSpace.cardInset)
                        CompareRow(label: "Eligibility", value: event.eligibility ?? "Open")
                    }
                }
            }
        }
    }
}

private struct CompareRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: SQSpace.lg) {
            Text(label)
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
            Spacer(minLength: SQSpace.sm)
            Text(value)
                .font(SQFont.bodyEmphasis)
                .foregroundStyle(SQColor.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, SQSpace.cardInset)
        .frame(minHeight: 48)
    }
}
