import MapKit
import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchTask: Task<Void, Never>?
    @State private var showFilters = false
    @State private var compareIds: Set<UUID> = []
    @State private var showComparison = false
    @State private var showMap = false

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
                    if model.events.isEmpty {
                        ContentUnavailableView("Nothing published yet", systemImage: "calendar.badge.plus", description: Text("When organizers publish events, they’ll appear here automatically."))
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 14) {
                                ForEach(model.events) { event in
                                    NavigationLink(value: event) { EventCard(event: event, imageURL: model.eventImageURLs[event.id], isSaved: model.savedEventIds.contains(event.id)) }.buttonStyle(.plain)
                                }
                                if model.canLoadMore {
                                    Button("Show more") { Task { await model.loadNextPage() } }
                                        .buttonStyle(.borderedProminent).padding(.vertical)
                                }
                            }.padding()
                        }.refreshable { await model.reloadEvents() }
                    }
                }
            }
            .background(Color.sidequestMist)
            .navigationTitle("Discover")
            .navigationDestination(for: EventFeedItem.self) { selectedEvent in
                EventDetailView(event: selectedEvent, comparing: compareIds.contains(selectedEvent.id)) { comparing in
                    if comparing { compareIds.insert(selectedEvent.id) } else { compareIds.remove(selectedEvent.id) }
                }
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showFilters=true } label: { Image(systemName:"line.3.horizontal.decrease.circle") }.accessibilityLabel("Event filters")
                    Button { showMap=true } label: { Image(systemName:"map") }.accessibilityLabel("Discover colleges on map")
                    if !compareIds.isEmpty { Button("Compare \(compareIds.count)") { showComparison=true } }
                }
            }
            .sheet(isPresented:$showFilters) { EventFiltersView() }
            .sheet(isPresented:$showComparison) { CompareEventsView(events:model.events.filter{compareIds.contains($0.id)}) }
            .sheet(isPresented:$showMap) { CampusDiscoveryMap(campuses:model.campuses) }
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

private struct CampusDiscoveryMap:View{
    @Environment(\.dismiss) private var dismiss;let campuses:[CampusPoint]
    var body:some View{NavigationStack{Group{if campuses.isEmpty{ContentUnavailableView("No mapped campuses",systemImage:"map",description:Text("Published campus coordinates will appear here."))}else{Map{ForEach(campuses){campus in Marker(campus.name,coordinate:.init(latitude:campus.latitude,longitude:campus.longitude))}}}}.navigationTitle("Campus discovery").toolbar{ToolbarItem(placement:.confirmationAction){Button("Done"){dismiss()}}}}}
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
        }.padding() }.navigationBarTitleDisplayMode(.inline)
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
            Picker("Date",selection:$model.upcomingDays){Text("Any date").tag(0);Text("Next 7 days").tag(7);Text("Next 30 days").tag(30)}
            Button("Apply filters") { Task { await model.reloadEvents(); dismiss() } }
            Button("Clear filters",role:.destructive) { model.categoryFilter="";model.collegeFilter="";model.freeOnly=false;model.upcomingDays=0;Task{await model.reloadEvents();dismiss()} }
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
