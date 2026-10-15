import SwiftUI

/// Discover section for casual meetups where students meet new people.
struct OpenMeetupsSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showHostForm = false

    private var visibleMeetups: [OpenMeetup] {
        let query = model.searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.meetups }
        return model.meetups.filter { $0.title.localizedCaseInsensitiveContains(query) || $0.description.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        let searching = !model.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if !(searching && visibleMeetups.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Meetups").font(.title3.bold()).foregroundStyle(Color.sidequestInk).accessibilityAddTraits(.isHeader)
                    Text("Casual hangouts to meet new people — no club or friend group needed.").font(.footnote).foregroundStyle(.secondary)
                }
                hostActions
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .task {
                if model.meetupState == .idle { await model.reloadMeetups() }
                await model.reloadHostedMeetups()
            }
            .sheet(isPresented: $showHostForm) { HostMeetupView() }
        }
    }

    private var hostActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { hostButton; myMeetupsLink }
            VStack(alignment: .leading, spacing: 8) { hostButton; myMeetupsLink }
        }
    }

    private var hostButton: some View {
        Button { showHostForm = true } label: {
            Label("Host a Meetup", systemImage: "plus.bubble.fill")
                .font(.subheadline.bold())
                .padding(.horizontal, 16).padding(.vertical, 10)
                .foregroundStyle(Color.sidequestInk)
                .background(Color.sidequestLime, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens a form to publish your own meetup")
    }

    @ViewBuilder private var myMeetupsLink: some View {
        if !model.hostedMeetups.isEmpty {
            NavigationLink { MyHostedMeetupsView() } label: {
                Label("My meetups (\(model.hostedMeetups.count))", systemImage: "person.crop.circle.badge.checkmark")
                    .font(.subheadline.bold())
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .foregroundStyle(Color.sidequestInk)
                    .background(.white, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder private var content: some View {
        switch model.meetupState {
        case .idle where model.meetups.isEmpty, .loading where model.meetups.isEmpty:
            ProgressView("Finding open meetups…").frame(maxWidth: .infinity, minHeight: 90)
        case .failed(let message) where model.meetups.isEmpty:
            VStack(alignment: .leading, spacing: 8) {
                Label("Couldn’t load meetups", systemImage: "wifi.exclamationmark").font(.subheadline.bold())
                Text(message).font(.caption).foregroundStyle(.secondary)
                Button("Try again") { Task { await model.reloadMeetups() } }.buttonStyle(.bordered)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        default:
            if visibleMeetups.isEmpty {
                Label("No open meetups yet. Be the first — tap Host a Meetup.", systemImage: "cup.and.saucer")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
            } else if typeSize.isAccessibilitySize {
                // Large text: stack full-width cards so nothing is truncated.
                VStack(spacing: 12) {
                    ForEach(visibleMeetups) { meetup in
                        NavigationLink(value: meetup) { OpenMeetupCard(meetup: meetup, fullWidth: true) }.buttonStyle(.plain)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(visibleMeetups) { meetup in
                            NavigationLink(value: meetup) { OpenMeetupCard(meetup: meetup) }.buttonStyle(.plain)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
            }
        }
    }
}

private struct OpenMeetupCard: View {
    let meetup: OpenMeetup
    var fullWidth = false
    private var singleLine: Int? { fullWidth ? nil : 1 }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("OPEN MEETUP").font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                if meetup.isGoing { Label("Going", systemImage: "checkmark.circle.fill").font(.caption.bold()).foregroundStyle(.green) }
                else if meetup.isFull { Text("Full").font(.caption.bold()).foregroundStyle(.orange) }
            }
            Text(meetup.title).font(.headline).foregroundStyle(Color.sidequestInk).lineLimit(fullWidth ? nil : 2)
            Text(meetup.description).font(.subheadline).foregroundStyle(.secondary).lineLimit(fullWidth ? 4 : 2)
            Divider()
            VStack(alignment: .leading, spacing: 5) {
                Label(meetup.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
                Label("\(meetup.venueName), \(meetup.campusName)", systemImage: "mappin.and.ellipse").lineLimit(singleLine)
                HostLine(meetup: meetup, lineLimit: singleLine)
                Label("\(meetup.goingCount) / \(meetup.capacity) going", systemImage: "person.2")
                Label(meetup.audienceLabel, systemImage: "building.columns").lineLimit(singleLine)
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Text("View details").font(.caption.bold()); Image(systemName: "chevron.right").font(.caption.bold()) }
                .foregroundStyle(Color.sidequestInk)
        }
        .padding(18)
        .frame(width: fullWidth ? nil : 290, alignment: .leading)
        .frame(maxWidth: fullWidth ? .infinity : nil, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens meetup details")
    }
}

private struct HostLine: View {
    let meetup: OpenMeetup
    var lineLimit: Int? = 1
    var body: some View {
        HStack(spacing: 4) {
            Label("Hosted by \(meetup.hostName)", systemImage: "person.crop.circle").lineLimit(lineLimit)
            if meetup.hostVerified {
                Image(systemName: "checkmark.seal.fill").foregroundStyle(.blue).accessibilityLabel("Recognised host")
            }
        }
    }
}

struct OpenMeetupDetailView: View {
    @Environment(AppModel.self) private var model
    let initial: OpenMeetup
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var confirmLeave = false
    @State private var confirmCancelMeetup = false

    private var meetup: OpenMeetup { model.meetup(id: initial.id) ?? initial }
    /// After a successful refresh, a meetup missing from the feed was cancelled, ended, or is no longer visible.
    private var isUnavailable: Bool { model.meetupState == .loaded && model.meetup(id: initial.id) == nil && !initial.amHost }
    private var isWorking: Bool { model.meetupActionStates[meetup.id] == .loading }

    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) {
            Text("OPEN MEETUP").font(.caption.bold()).foregroundStyle(.secondary)
            Text(meetup.title).font(.largeTitle.bold())
            Label("\(meetup.startsAt.formatted(date: .complete, time: .shortened)) – \(meetup.endsAt.formatted(date: .omitted, time: .shortened))", systemImage: "calendar")
            Label("\(meetup.venueName), \(meetup.campusName)", systemImage: "mappin.and.ellipse")
            if let note = meetup.locationNote { Label(note, systemImage: "info.circle").foregroundStyle(.secondary) }
            Text(meetup.description).font(.body).lineSpacing(5)

            VStack(alignment: .leading, spacing: 8) {
                Label("Icebreaker", systemImage: "bubble.left.and.bubble.right.fill").font(.headline)
                Text("“\(meetup.icebreaker)”").font(.title3.weight(.semibold)).foregroundStyle(Color.sidequestInk)
                Text("Not sure how to start? Ask someone this when you arrive.").font(.caption).foregroundStyle(Color.sidequestInk.opacity(0.7))
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.sidequestLime, in: RoundedRectangle(cornerRadius: 20))
            .accessibilityElement(children: .combine)

            GroupBox("Your host") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(meetup.hostName).font(.headline)
                        if meetup.hostVerified { Label("Recognised host", systemImage: "checkmark.seal.fill").font(.caption.bold()).foregroundStyle(.blue) }
                    }
                    if let headline = meetup.hostHeadline { Text(headline).font(.subheadline).foregroundStyle(.secondary) }
                    Text(meetup.collegeName).font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Who can join") {
                VStack(alignment: .leading, spacing: 6) {
                    Text(meetup.audienceLabel)
                    if meetup.audience != "all_colleges" && meetup.participatingColleges.count > 1 {
                        ForEach(meetup.participatingColleges, id: \.self) { Label($0, systemImage: "building.columns").font(.subheadline) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Attendees") {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: Double(min(meetup.goingCount, meetup.capacity)), total: Double(meetup.capacity)).tint(Color.sidequestInk)
                    Text("\(meetup.goingCount) of \(meetup.capacity) going · \(meetup.isFull ? "No spots left" : "\(meetup.spotsLeft) \(meetup.spotsLeft == 1 ? "spot" : "spots") left")").font(.subheadline)
                }
            }

            if let destination = meetup.destinationLandmarkId {
                Button("Navigate to venue", systemImage: "location.north.fill") { model.prepareNavigation(to: destination) }.buttonStyle(.bordered)
            } else {
                Label("In-app directions aren’t set up for this venue yet.", systemImage: "location.slash").font(.footnote).foregroundStyle(.secondary)
            }

            registrationControls
            if let message { Text(message).foregroundStyle(.green).font(.footnote) }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
        }.padding() }
        .background(Color.sidequestMist)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.reloadMeetups() }
        .task { await model.reloadMeetups() }
        .task { if initial.amHost { await model.reloadHostedMeetups() } }
        .confirmationDialog("Cancel this meetup?", isPresented: $confirmCancelMeetup, titleVisibility: .visible) {
            Button("Cancel meetup", role: .destructive) { Task { await cancelMeetup() } }
            Button("Keep meetup", role: .cancel) {}
        } message: { Text("Everyone who’s going will lose their spot. This can’t be undone.") }
        .confirmationDialog("Give up your spot?", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("Cancel my spot", role: .destructive) { Task { await leave() } }
            Button("Keep my spot", role: .cancel) {}
        } message: { Text("Someone else will be able to take it.") }
    }

    @ViewBuilder private var registrationControls: some View {
        if meetup.isCancelled {
            Label(meetup.amHost ? "You cancelled this meetup." : "This meetup was cancelled.", systemImage: "xmark.octagon").foregroundStyle(.red)
        } else if meetup.amHost {
            VStack(alignment: .leading, spacing: 10) {
                Label("You’re hosting this meetup", systemImage: "person.crop.circle.badge.checkmark").font(.headline)
                Text("\(meetup.goingCount) \(meetup.goingCount == 1 ? "person is" : "people are") going. Attendee names stay private.").font(.subheadline).foregroundStyle(.secondary)
                if meetup.endsAt > .now {
                    Button(isWorking ? "Cancelling…" : "Cancel meetup", role: .destructive) { confirmCancelMeetup = true }
                        .buttonStyle(.bordered).disabled(isWorking)
                }
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        } else if isUnavailable {
            Label("This meetup is no longer available. It may have been cancelled or already ended.", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.secondary)
        } else if meetup.isGoing {
            Label("You’re going! See you at \(meetup.venueName).", systemImage: "checkmark.seal.fill").foregroundStyle(.green).font(.headline)
            Button(isWorking ? "Cancelling…" : "Cancel my spot", role: .destructive) { confirmLeave = true }
                .buttonStyle(.bordered).disabled(isWorking)
        } else if !meetup.isEligible {
            Label("This meetup isn’t open to students from your college.", systemImage: "lock").foregroundStyle(.secondary)
        } else if meetup.isFull {
            Label("This meetup is full. Check back later in case someone cancels.", systemImage: "person.2.slash").foregroundStyle(.orange)
        } else {
            Button { Task { await join() } } label: {
                Text(isWorking ? "Saving your spot…" : "I’m Going").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent).controlSize(.large).disabled(isWorking)
        }
    }

    private func join() async {
        message = nil; errorMessage = nil
        do {
            try await model.joinMeetup(meetup)
            message = "You’re in! Your spot is saved."
        } catch { errorMessage = error.localizedDescription }
    }

    private func cancelMeetup() async {
        message = nil; errorMessage = nil
        do {
            try await model.cancelHostedMeetup(meetup)
            message = "Your meetup has been cancelled and everyone’s spot was released."
        } catch { errorMessage = error.localizedDescription }
    }

    private func leave() async {
        message = nil; errorMessage = nil
        do {
            try await model.leaveMeetup(meetup)
            message = "Your spot has been cancelled."
        } catch { errorMessage = error.localizedDescription }
    }
}
