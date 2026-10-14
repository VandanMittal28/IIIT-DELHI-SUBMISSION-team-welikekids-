import MapKit
import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilters = false
    @State private var compareIds: Set<UUID> = []
    @State private var showComparison = false
    @State private var showMap = false
    @State private var showChat = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.eventState {
                case .idle where model.events.isEmpty,
                     .loading where model.events.isEmpty:
                    ProgressView("Finding what’s next…")
                case .failed(let message) where model.events.isEmpty:
                    ContentUnavailableView {
                        Label("Couldn’t load events", systemImage: "wifi.exclamationmark")
                    } description: { Text(message) } actions: {
                        Button("Try again") { Task { await model.reloadEvents() } }
                    }
                default:
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            OpenMeetupsSection().padding(.bottom, 6)
                            if model.events.isEmpty {
                                ContentUnavailableView("Nothing published yet", systemImage: "calendar.badge.plus", description: Text("When organizers publish events, they’ll appear here automatically."))
                            } else {
                                ForEach(model.events) { event in
                                    NavigationLink(value: event) { EventCard(event: event, imageURL: model.eventImageURLs[event.id], isSaved: model.savedEventIds.contains(event.id)) }.buttonStyle(.plain)
                                }
                                if model.canLoadMore {
                                    Button("Show more") { Task { await model.loadNextPage() } }
                                        .buttonStyle(.borderedProminent).padding(.vertical)
                                }
                            }
                        }.padding()
                    }.refreshable { await model.reloadEvents(); await model.reloadMeetups() }
                }
            }
            .background(Color.sidequestMist)
            .navigationTitle("Discover")
            .navigationDestination(for: EventFeedItem.self) { selectedEvent in
                EventDetailView(event: selectedEvent, comparing: compareIds.contains(selectedEvent.id)) { comparing in
                    if comparing { compareIds.insert(selectedEvent.id) } else { compareIds.remove(selectedEvent.id) }
                }
            }
            .navigationDestination(for: OpenMeetup.self) { meetup in OpenMeetupDetailView(initial: meetup) }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFilters=true } label: { Image(systemName:"line.3.horizontal.decrease.circle") }.accessibilityLabel("Event filters")
                    Button { showMap=true } label: { Image(systemName:"map") }.accessibilityLabel("Discover colleges on map")
                    Button { showChat=true } label: { ChatHeaderIcon(unread: model.chat.totalUnread) }
                        .accessibilityLabel(model.chat.totalUnread > 0 ? "Chat rooms, \(model.chat.totalUnread) unread" : "Chat rooms")
                    if !compareIds.isEmpty { Button("Compare \(compareIds.count)") { showComparison=true } }
                }
            }
            .sheet(isPresented:$showFilters) { EventFiltersView() }
            .sheet(isPresented:$showComparison) { CompareEventsView(events:model.events.filter{compareIds.contains($0.id)}) }
            .sheet(isPresented:$showMap) { CampusDiscoveryMap() }
            .sheet(isPresented:$showChat, onDismiss: { Task { await model.chat.reloadRooms() } }) { ChatHomeView() }
            .task { if model.isAuthenticated { await model.chat.reloadRooms() } }
            .searchable(text: $model.searchText, prompt: "Search published events")
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
}

/// Header chat icon with a small unread badge that stays inside the toolbar button's bounds.
private struct ChatHeaderIcon: View {
    let unread: Int
    var body: some View {
        Image(systemName: "bubble.left.and.bubble.right")
            .overlay(alignment: .topTrailing) {
                if unread > 0 {
                    Text(unread > 9 ? "9+" : "\(unread)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.sidequestInk)
                        .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                        .background(Color.sidequestLime, in: Capsule())
                        .overlay(Capsule().stroke(Color.sidequestInk, lineWidth: 1))
                        .offset(x: 9, y: -8)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct CampusDiscoveryMap: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var eventPins: [DiscoveryMapPin] {
        model.mapEvents.filter { $0.endsAt > .now }.compactMap { event in
            coordinate(for: event.venueId).map {
                DiscoveryMapPin(id: event.id, title: event.title, coordinate: $0)
            }
        }
    }

    private var meetupPins: [DiscoveryMapPin] {
        model.meetups.filter { $0.status == "published" && $0.endsAt > .now }.compactMap { meetup in
            coordinate(for: meetup.venueId).map {
                DiscoveryMapPin(id: meetup.id, title: meetup.title, coordinate: $0)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Map(initialPosition: .automatic) {
                ForEach(model.campuses) { campus in
                    Marker(campus.name, systemImage: "building.columns.fill", coordinate: .init(latitude: campus.latitude, longitude: campus.longitude))
                        .tint(.gray)
                }
                ForEach(eventPins) { pin in
                    Marker(pin.title, systemImage: "calendar", coordinate: pin.coordinate)
                        .tint(.blue)
                }
                ForEach(meetupPins) { pin in
                    Marker(pin.title, systemImage: "cup.and.saucer.fill", coordinate: pin.coordinate)
                        .tint(.orange)
                }
            }
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 7) {
                    Label("Events · ongoing and upcoming", systemImage: "calendar").foregroundStyle(.blue)
                    Label("Open meetups", systemImage: "cup.and.saucer.fill").foregroundStyle(.orange)
                    Label("Campuses", systemImage: "building.columns.fill").foregroundStyle(.secondary)
                }
                .font(.caption.bold())
                .padding(12)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .padding()
            }
            .navigationTitle("Discover map")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task {
                await model.reloadMapEvents()
                await model.reloadMeetups()
                await model.reloadMapVenueLocations()
            }
        }
    }

    private func coordinate(for venueId: UUID?) -> CLLocationCoordinate2D? {
        guard let venueId, let location = model.mapVenueLocations[venueId] else { return nil }
        if let latitude = location.latitude, let longitude = location.longitude {
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard let campus = model.campuses.first(where: { $0.id == location.campusId }) else { return nil }
        return CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude)
    }
}

private struct DiscoveryMapPin: Identifiable {
    let id: UUID
    let title: String
    let coordinate: CLLocationCoordinate2D
}

private struct EventCard: View {
    let event: EventFeedItem
    let imageURL: URL?
    let isSaved: Bool
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let imageURL {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 150)
                }
                .frame(height: 170).frame(maxWidth: .infinity).clipped()
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            HStack { Text(event.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Text(event.priceLabel).font(.subheadline.bold()) }
            Text(event.title).font(.title2.bold()).foregroundStyle(Color.sidequestInk)
            Text(event.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack { Label(event.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar"); Spacer(); Text(event.organizationName) }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20)).overlay(alignment: .topTrailing) { Image(systemName:isSaved ? "bookmark.fill":"circle.fill").foregroundStyle(Color.sidequestLime).padding(14) }
    }
}

private struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    let event: EventFeedItem
    let comparing: Bool
    let setComparing: (Bool)->Void
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isLoadingDetails=false

    private var sessions:[EventSessionScheduleItem]{model.sessionsByEdition[event.editionId] ?? []}
    private var currentReview:EditionReviewSummary?{model.reviewSummariesByEvent[event.id]?.first{$0.editionId==event.editionId}}
    private var previousReview:(average:Double,sampleSize:Int)?{
        let prior=(model.reviewSummariesByEvent[event.id] ?? []).filter{$0.editionId != event.editionId}
        let count=prior.reduce(0){$0+$1.sampleSize};guard count>0 else{return nil}
        let total=prior.reduce(0.0){$0+$1.averageRating*Double($1.sampleSize)}
        return(total/Double(count),count)
    }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            if let imageURL=model.eventImageURLs[event.id] {
                AsyncImage(url:imageURL) { image in image.resizable().scaledToFill() } placeholder: { ProgressView().frame(maxWidth:.infinity,minHeight:180) }
                    .frame(height:220).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:18))
            }
            Text(event.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            Text(event.title).font(.largeTitle.bold())
            Label(event.startsAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
            Label(event.organizationName, systemImage: "person.3")
            Label(event.collegeName, systemImage: "building.columns")
            if let venue=event.venueName { Label(venue,systemImage:"mappin.and.ellipse") }
            Text(event.description).font(.body).lineSpacing(5)
            GroupBox("Session schedule") {
                VStack(alignment:.leading,spacing:10) {
                    if isLoadingDetails { ProgressView("Loading published sessions…") }
                    else if sessions.isEmpty { Text("No detailed sessions have been published.").foregroundStyle(.secondary) }
                    else { ForEach(sessions){session in VStack(alignment:.leading,spacing:3){Text(session.title).font(.headline);Text("\(session.startsAt.formatted(date:.abbreviated,time:.shortened))–\(session.endsAt.formatted(date:.omitted,time:.shortened))").font(.subheadline);if let venue=session.venueName{Label([venue,session.campusName].compactMap{$0}.joined(separator:", "),systemImage:"mappin")}}} }
                }.frame(maxWidth:.infinity,alignment:.leading)
            }
            GroupBox("Verified attendee feedback") {
                VStack(alignment:.leading,spacing:8) {
                    if let currentReview { LabeledContent("Current edition",value:"\(String(format:"%.1f",currentReview.averageRating)) / 5 · \(currentReview.sampleSize) \(currentReview.sampleSize==1 ? "review":"reviews")") }
                    else { LabeledContent("Current edition",value:"No reviews yet") }
                    if let previousReview { LabeledContent("Previous editions",value:"\(String(format:"%.1f",previousReview.average)) / 5 · \(previousReview.sampleSize) \(previousReview.sampleSize==1 ? "review":"reviews")") }
                    else { LabeledContent("Previous editions",value:"No reviews yet") }
                }
            }
            HStack {
                Button(model.savedEventIds.contains(event.id) ? "Saved" : "Save event", systemImage:model.savedEventIds.contains(event.id) ? "bookmark.fill":"bookmark") { Task { do { try await model.toggleSaved(eventId:event.id) } catch { errorMessage=error.localizedDescription } } }.buttonStyle(.bordered)
                Button(comparing ? "Comparing" : "Compare", systemImage: comparing ? "checkmark.square.fill" : "square.on.square") { setComparing(!comparing) }
                    .buttonStyle(.bordered)
            }
            if let eligibility = event.eligibility { GroupBox("Eligibility") { Text(eligibility).frame(maxWidth: .infinity, alignment: .leading) } }
            if let destination=event.destinationLandmarkId { Button("Navigate to venue",systemImage:"location.north.fill"){model.prepareNavigation(to:destination)}.buttonStyle(.borderedProminent) }
            if let registration = model.registration(for: event.editionId) {
                Label(registration.status == "registered" ? "Registered — pass is in My Journey" : "Waitlisted — position \(registration.waitlistPosition ?? 0)", systemImage: registration.status == "registered" ? "checkmark.seal.fill" : "clock.badge")
                    .foregroundStyle(registration.status == "registered" ? .green : .orange)
            } else {
                Button(model.registrationStates[event.editionId] == .loading ? "Confirming…" : "Register") {
                    Task { await register() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.registrationStates[event.editionId] == .loading)
            }
            if let message { Text(message).foregroundStyle(.green).font(.footnote) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
        }.padding() }.navigationBarTitleDisplayMode(.inline).task{isLoadingDetails=true;defer{isLoadingDetails=false};do{try await model.loadEventDetails(for:event)}catch{errorMessage=error.localizedDescription}}
    }

    private func register() async {
        message = nil; errorMessage = nil
        do {
            let result = try await model.register(for: event)
            message = result.status == "registered"
                ? "Registration confirmed. Your opaque pass is ready."
                : "You’re on the waitlist at position \(result.waitlistPosition ?? 0)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct EventFiltersView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        @Bindable var model=model
        NavigationStack { Form {
            TextField("Category (exact)",text:$model.categoryFilter)
            TextField("College (exact)",text:$model.collegeFilter)
            Toggle("Free events only",isOn:$model.freeOnly)
            TextField("Maximum price (₹)",text:$model.maxPrice).keyboardType(.decimalPad).disabled(model.freeOnly)
            TextField("Eligibility contains",text:$model.eligibilityFilter)
            Picker("Date",selection:$model.upcomingDays){Text("Any date").tag(0);Text("Next 7 days").tag(7);Text("Next 30 days").tag(30)}
            Button("Apply filters") { Task { await model.reloadEvents(); dismiss() } }
            Button("Clear filters",role:.destructive) { model.categoryFilter="";model.collegeFilter="";model.freeOnly=false;model.maxPrice="";model.eligibilityFilter="";model.upcomingDays=0;Task{await model.reloadEvents();dismiss()} }
        }.navigationTitle("Filters").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}} }
    }
}

private struct CompareEventsView: View {
    @Environment(\.dismiss) private var dismiss
    let events:[EventFeedItem]
    var body: some View {
        NavigationStack {
            List(events) { event in
                Section(event.title) {
                    LabeledContent("Organizer", value: event.organizationName)
                    LabeledContent("College", value: event.collegeName)
                    LabeledContent("When", value: event.startsAt.formatted(date: .abbreviated, time: .shortened))
                    LabeledContent("Price", value: event.priceLabel)
                    LabeledContent("Eligibility", value: event.eligibility ?? "Open")
                }
            }
            .navigationTitle("Compare events")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
