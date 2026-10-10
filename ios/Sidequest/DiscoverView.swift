import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Group {
                switch model.eventState {
                case .idle, .loading where model.events.isEmpty:
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
                                    NavigationLink(value: event) { EventCard(event: event) }.buttonStyle(.plain)
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
            .navigationDestination(for: EventFeedItem.self) { EventDetailView(event: $0) }
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

private struct EventCard: View {
    let event: EventFeedItem
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text(event.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary); Spacer(); Text(event.priceLabel).font(.subheadline.bold()) }
            Text(event.title).font(.title2.bold()).foregroundStyle(Color.sidequestInk)
            Text(event.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Divider()
            HStack { Label(event.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar"); Spacer(); Text(event.organizationName) }.font(.caption).foregroundStyle(.secondary)
        }
        .padding(18).background(.white, in: RoundedRectangle(cornerRadius: 20)).overlay(alignment: .topTrailing) { Circle().fill(Color.sidequestLime).frame(width: 13).padding(14) }
    }
}

private struct EventDetailView: View {
    let event: EventFeedItem
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text(event.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            Text(event.title).font(.largeTitle.bold())
            Label(event.startsAt.formatted(date: .complete, time: .shortened), systemImage: "calendar")
            Label(event.organizationName, systemImage: "person.3")
            Label(event.collegeName, systemImage: "building.columns")
            Text(event.description).font(.body).lineSpacing(5)
            if let eligibility = event.eligibility { GroupBox("Eligibility") { Text(eligibility).frame(maxWidth: .infinity, alignment: .leading) } }
            Button("Registration is the next connected workflow") {}.buttonStyle(.borderedProminent).disabled(true)
        }.padding() }.navigationBarTitleDisplayMode(.inline)
    }
}
