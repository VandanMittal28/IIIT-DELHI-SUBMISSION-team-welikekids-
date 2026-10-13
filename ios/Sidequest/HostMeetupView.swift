import SwiftUI

/// Form for a student to host and publish their own Open Meetup.
struct HostMeetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = MeetupDraft()
    /// Reused for every retry of this draft so the server can drop duplicate submissions.
    @State private var requestId = UUID()
    @State private var submitting = false
    @State private var showErrors = false
    @State private var errorMessage: String?
    @State private var published: OpenMeetup?

    private var errors: [MeetupDraft.Field: String] { draft.errors() }
    private var hostColleges: [CollegeOption] { model.colleges.filter { model.hostCollegeIds.contains($0.id) } }
    private var venues: [HostVenueOption] { model.hostVenues.filter { $0.campus.collegeId == draft.collegeId } }
    private var otherColleges: [CollegeOption] { model.colleges.filter { $0.id != draft.collegeId } }

    var body: some View {
        NavigationStack {
            Group {
                if let published { PublishedMeetupView(meetup: published) { dismiss() } }
                else {
                    switch model.hostingOptionsState {
                    case .idle, .loading: ProgressView("Loading your campus venues…")
                    case .failed(let message):
                        ContentUnavailableView { Label("Couldn’t load hosting options", systemImage: "wifi.exclamationmark") }
                        description: { Text(message) }
                        actions: { Button("Try again") { Task { await model.loadHostingOptions() } } }
                    case .loaded:
                        if model.hostCollegeIds.isEmpty {
                            ContentUnavailableView("Hosting needs a college membership", systemImage: "building.columns", description: Text("Ask your college administrator to confirm your student membership, then you can host meetups."))
                        } else { form }
                    }
                }
            }
            .navigationTitle(published == nil ? "Host a Meetup" : "Published")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if published == nil {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(submitting) }
                }
            }
            .interactiveDismissDisabled(submitting)
            .task {
                if model.hostingOptionsState != .loaded { await model.loadHostingOptions() }
                applyDefaults()
            }
        }
    }

    private var form: some View {
        Form {
            Section {
                TextField("Title, e.g. Canteen Chai Meetup", text: $draft.title)
                fieldError(.title)
                TextField("What’s the plan? Keep it casual and welcoming.", text: $draft.description, axis: .vertical).lineLimit(3...6)
                fieldError(.description)
            } header: { Text("Meetup") } footer: { Text("Open Meetups are casual social hangouts for meeting new people — not club events.") }

            Section("Where") {
                if hostColleges.count > 1 {
                    Picker("Your college", selection: $draft.collegeId) {
                        ForEach(hostColleges) { Text($0.name).tag(Optional($0.id)) }
                    }
                    .onChange(of: draft.collegeId) { draft.venueId = venues.first?.id }
                }
                if venues.isEmpty {
                    Text("No venues are set up for your campus yet.").foregroundStyle(.secondary)
                } else {
                    Picker("Venue", selection: $draft.venueId) {
                        Text("Choose a venue").tag(UUID?.none)
                        ForEach(venues) { venue in Text("\(venue.name) · \(venue.campus.name)").tag(Optional(venue.id)) }
                    }
                }
                fieldError(.venue)
                fieldError(.college)
                TextField("Location tip (optional), e.g. by the chai counter", text: $draft.locationNote)
                fieldError(.locationNote)
            }

            Section("When") {
                DatePicker("Starts", selection: $draft.startsAt, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
                fieldError(.startsAt)
                Picker("Duration", selection: $draft.durationMinutes) {
                    ForEach([30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                        Text(minutes < 60 ? "\(minutes) min" : minutes % 60 == 0 ? "\(minutes / 60) hr" : "\(minutes / 60) hr \(minutes % 60) min").tag(minutes)
                    }
                }
            }

            Section {
                Stepper(value: $draft.capacity, in: MeetupDraft.capacityRange) {
                    LabeledContent("Max attendees", value: "\(draft.capacity)")
                }
                fieldError(.capacity)
                Picker("Who can join", selection: $draft.audience) {
                    ForEach(MeetupDraft.Audience.allCases) { Text($0.label).tag($0) }
                }
                if draft.audience == .selectedColleges {
                    ForEach(otherColleges) { college in
                        Toggle(college.name, isOn: Binding(
                            get: { draft.extraCollegeIds.contains(college.id) },
                            set: { isOn in if isOn { draft.extraCollegeIds.insert(college.id) } else { draft.extraCollegeIds.remove(college.id) } }
                        ))
                    }
                    if otherColleges.isEmpty { Text("No other colleges are on Sidequest yet.").foregroundStyle(.secondary) }
                    fieldError(.colleges)
                }
            } header: { Text("Who") } footer: { Text("Only students with a confirmed membership at an eligible college can join.") }

            Section {
                TextField("Your name as host", text: $draft.hostName)
                fieldError(.hostName)
                TextField("Opening icebreaker (optional)", text: $draft.icebreaker, axis: .vertical).lineLimit(1...3)
                fieldError(.icebreaker)
            } header: { Text("Host") } footer: { Text("Your host name is shown publicly. Leave the icebreaker blank and we’ll suggest one.") }

            Section {
                Button { Task { await publish() } } label: {
                    HStack { Spacer(); if submitting { ProgressView() } else { Text("Publish meetup").bold() }; Spacer() }
                }
                .disabled(submitting)
                .accessibilityHint("Publishes the meetup to eligible students")
                if let errorMessage { Text(errorMessage).foregroundStyle(.red).font(.footnote) }
            }
        }
        .disabled(submitting)
    }

    @ViewBuilder private func fieldError(_ field: MeetupDraft.Field) -> some View {
        if showErrors, let message = errors[field] {
            Label(message, systemImage: "exclamationmark.circle").font(.footnote).foregroundStyle(.red)
        }
    }

    private func applyDefaults() {
        if draft.collegeId == nil {
            draft.collegeId = model.hostCollegeIds.first { $0 == model.profile?.collegeId } ?? model.hostCollegeIds.first
        }
        if draft.venueId == nil { draft.venueId = venues.first?.id }
        if draft.hostName.isEmpty { draft.hostName = model.profile?.fullName ?? "" }
    }

    private func publish() async {
        guard !submitting else { return }
        showErrors = true
        errorMessage = nil
        guard errors.isEmpty else { errorMessage = "Fix the highlighted fields to publish."; return }
        submitting = true
        defer { submitting = false }
        do {
            let result = try await model.hostMeetup(draft, requestId: requestId)
            published = model.meetup(id: result.meetupId)
            if published == nil { errorMessage = "Your meetup was published, but the feed hasn’t refreshed yet. Pull to refresh Discover." }
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct PublishedMeetupView: View {
    let meetup: OpenMeetup
    let done: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
            Text("Your meetup is live!").font(.title2.bold())
            Text("“\(meetup.title)” now appears in Open Meetups for eligible students.").multilineTextAlignment(.center).foregroundStyle(.secondary)
            NavigationLink { OpenMeetupDetailView(initial: meetup) } label: { Text("View meetup").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent).controlSize(.large)
            Button("Done", action: done).buttonStyle(.bordered)
            Spacer()
        }
        .padding(24)
    }
}

/// Meetups the signed-in student hosts.
struct MyHostedMeetupsView: View {
    @Environment(AppModel.self) private var model
    var body: some View {
        List {
            if model.hostedMeetups.isEmpty {
                Text("You haven’t hosted a meetup yet.").foregroundStyle(.secondary)
            }
            ForEach(model.hostedMeetups) { meetup in
                NavigationLink { OpenMeetupDetailView(initial: meetup) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(meetup.title).font(.headline)
                            Spacer()
                            Text(statusLabel(meetup)).font(.caption.bold()).foregroundStyle(meetup.isCancelled ? .red : meetup.endsAt < .now ? .secondary : Color.green)
                        }
                        Text(meetup.startsAt.formatted(date: .abbreviated, time: .shortened)).font(.subheadline).foregroundStyle(.secondary)
                        Label("\(meetup.goingCount) / \(meetup.capacity) going", systemImage: "person.2").font(.caption).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("My hosted meetups")
        .refreshable { await model.reloadHostedMeetups() }
        .task { await model.reloadHostedMeetups() }
    }

    private func statusLabel(_ meetup: OpenMeetup) -> String {
        if meetup.isCancelled { return "Cancelled" }
        return meetup.endsAt < .now ? "Ended" : "Published"
    }
}
