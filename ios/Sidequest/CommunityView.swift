import PhotosUI
import SwiftUI
import UIKit

struct CommunityView: View {
    @Environment(AppModel.self) private var model
    @State private var section = CommunitySection.updates
    @State private var organizationSearch = ""
    @State private var creatingThread = false

    private var visibleOrganizations: [OrganizationProfile] {
        let query=organizationSearch.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else { return model.organizations }
        return model.organizations.filter { $0.name.localizedCaseInsensitiveContains(query) || ($0.description?.localizedCaseInsensitiveContains(query) ?? false) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !model.isAuthenticated {
                    ContentUnavailableView("Sign in for community", systemImage: "person.crop.circle.badge.questionmark", description: Text("Official updates and discussions are scoped to your real event registrations."))
                } else if case .loading = model.communityState, model.announcements.isEmpty {
                    ProgressView("Loading authoritative updates…")
                } else {
                    List {
                        Section {
                            Picker("Community area",selection:$section) {
                                ForEach(CommunitySection.allCases) { item in Text(item.rawValue).tag(item) }
                            }.pickerStyle(.segmented)
                        }
                        switch section {
                        case .updates:
                            Section("Official event announcements") {
                                if model.announcements.isEmpty { Text("No announcements for your events.").foregroundStyle(.secondary) }
                                ForEach(model.announcements) { item in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Label(item.title, systemImage: item.kind == "venue_change" ? "arrow.triangle.swap" : "megaphone").font(.headline)
                                        Text(item.body)
                                        Text(item.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                            Section("Your inbox") {
                                if model.notifications.isEmpty { Text("No notifications yet.").foregroundStyle(.secondary) }
                                ForEach(model.notifications) { item in
                                    VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.body); Text(item.createdAt.formatted()).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                            Section("Event rooms") {
                                if model.channels.isEmpty { Text("Register for an event to join its attendee chat room.").foregroundStyle(.secondary) }
                                ForEach(model.channels) { channel in NavigationLink(channel.title) { ChannelView(channel:channel) } }
                            }
                        case .discussions:
                            Section {
                                HStack { Text("Campus forum").font(.headline); Spacer(); Button { creatingThread=true } label:{Label("Start thread",systemImage:"square.and.pencil")} }
                                Text("Start a topic and let your college community join in.").font(.caption).foregroundStyle(.secondary)
                                if model.discussionThreads.isEmpty { ContentUnavailableView("No discussions yet",systemImage:"text.bubble",description:Text("Be the first to start a thread. Set your college in Profile if prompted.")) }
                                ForEach(model.discussionThreads) { thread in NavigationLink { DiscussionThreadView(thread:thread) } label: { VStack(alignment:.leading,spacing:5){Text(thread.title).font(.headline);Text(thread.body).lineLimit(2).foregroundStyle(.secondary);Text(thread.updatedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.tertiary)}.padding(.vertical,3) } }
                            }
                        case .organizations:
                            Section("College profiles") {
                                if model.collegeProfiles.isEmpty { Text("No colleges available.").foregroundStyle(.secondary) }
                                ForEach(model.collegeProfiles){college in NavigationLink(college.name){CollegeProfileView(college:college,organizations:model.organizations.filter{$0.collegeId==college.id})}}
                            }
                            Section("Find a society or organization") {
                                TextField("Search societies and clubs",text:$organizationSearch)
                                    .textInputAutocapitalization(.never)
                                if visibleOrganizations.isEmpty { ContentUnavailableView.search(text:organizationSearch) }
                                ForEach(visibleOrganizations) { organization in
                                    HStack { NavigationLink{OrganizationProfileView(organization:organization,collegeName:model.collegeProfiles.first{$0.id==organization.collegeId}?.name)}label:{VStack(alignment:.leading){Text(organization.name).font(.headline);if let detail=organization.description{Text(detail).font(.caption).foregroundStyle(.secondary)}}};Spacer();Button(model.followedOrganizationIds.contains(organization.id) ? "Following":"Follow") { Task { try? await model.toggleOrganizationFollow(organization.id) } }.buttonStyle(.bordered) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Community")
            .toolbar { if model.isAuthenticated && section == .discussions { ToolbarItem(placement:.topBarTrailing){Button { creatingThread=true } label:{Image(systemName:"square.and.pencil").accessibilityLabel("Start a discussion")}} } }
            .task { if model.isAuthenticated { await model.reloadCommunity() } }
            .refreshable { await model.reloadCommunity() }
            .sheet(isPresented:$creatingThread) { NewDiscussionThreadView() }
        }
    }
}

private enum CommunitySection:String,CaseIterable,Identifiable { case updates="Updates",discussions="Forum",organizations="Clubs";var id:Self{self} }

private struct NewDiscussionThreadView:View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var title="";@State private var bodyText="";@State private var error:String?;@State private var busy=false
    var body:some View { NavigationStack { Form { Section("Start a college discussion"){TextField("Thread title",text:$title);TextField("What do you want to discuss?",text:$bodyText,axis:.vertical).lineLimit(4...10)};if let error{Text(error).foregroundStyle(.red)};Button(busy ? "Posting…":"Create thread"){busy=true;Task{do{try await model.createDiscussionThread(title:title,body:bodyText);dismiss()}catch{self.error=error.localizedDescription;busy=false}}}.disabled(busy||title.trimmingCharacters(in:.whitespacesAndNewlines).count<4||bodyText.trimmingCharacters(in:.whitespacesAndNewlines).count<5) }.navigationTitle("New thread").toolbar{ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}}} } }
}

private struct DiscussionThreadView:View {
    @Environment(AppModel.self) private var model
    let thread:DiscussionThread
    @State private var reply="";@State private var error:String?;@State private var busy=false
    var body:some View { List { Section(thread.title){Text(thread.body);Text("Started \(thread.createdAt.formatted(date:.abbreviated,time:.shortened))").font(.caption).foregroundStyle(.secondary)};Section("Replies"){ForEach(model.discussionReplies[thread.id] ?? []){item in VStack(alignment:.leading,spacing:5){Text(item.body);Text(item.createdAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)}};if (model.discussionReplies[thread.id] ?? []).isEmpty{Text("No replies yet. Add the first one.").foregroundStyle(.secondary)}};Section("Join the discussion"){TextField("Write a reply",text:$reply,axis:.vertical).lineLimit(2...6);if let error{Text(error).foregroundStyle(.red)};Button(busy ? "Posting…":"Reply"){busy=true;Task{do{try await model.replyToDiscussion(threadId:thread.id,body:reply);reply="";error=nil}catch{self.error=error.localizedDescription};busy=false}}.disabled(busy||reply.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)} }.navigationTitle("Discussion").task{do{try await model.reloadDiscussionReplies(threadId:thread.id)}catch{self.error=error.localizedDescription}}.refreshable{try? await model.reloadDiscussionReplies(threadId:thread.id)} }
}

private struct CollegeProfileView:View {
    let college:CollegeProfile;let organizations:[OrganizationProfile]
    var body:some View { List { Section("College"){LabeledContent("Name",value:college.name);LabeledContent("Time zone",value:college.timezone);if let latitude=college.latitude,let longitude=college.longitude{LabeledContent("Coordinates",value:"\(latitude.formatted()), \(longitude.formatted())")}};Section("Clubs and organizations"){if organizations.isEmpty{Text("No active organizations yet.").foregroundStyle(.secondary)};ForEach(organizations){organization in VStack(alignment:.leading){Text(organization.name).font(.headline);if let description=organization.description{Text(description).foregroundStyle(.secondary)}}}} }.navigationTitle(college.name) }
}

private struct OrganizationProfileView:View {
    @Environment(AppModel.self) private var model
    let organization:OrganizationProfile;let collegeName:String?
    var body:some View { List { Section("Organization"){LabeledContent("Name",value:organization.name);if let collegeName{LabeledContent("College",value:collegeName)};if let description=organization.description{Text(description)}};Section{Button(model.followedOrganizationIds.contains(organization.id) ? "Unfollow organization":"Follow organization"){Task{try? await model.toggleOrganizationFollow(organization.id)}}} }.navigationTitle(organization.name) }
}

struct ChannelView: View {
    @Environment(AppModel.self) private var model
    let channel:CommunityChannel
    @State private var draft=""
    @State private var error:String?
    @State private var reporting:CommunityMessage?
    var body: some View { List {
        ForEach(model.communityMessages.filter{$0.channelId==channel.id}.reversed()) { message in
            HStack(alignment:.top) {
                VStack(alignment:.leading,spacing:4) { Text(message.body);Text(message.createdAt.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary) }
                Spacer()
                Menu { Button("Report message",systemImage:"flag"){reporting=message} } label:{Image(systemName:"ellipsis.circle").foregroundStyle(.secondary)}
            }
        }
        Section { TextField("Message",text:$draft,axis:.vertical);Button("Post") { Task { do { try await model.postMessage(channelId:channel.id,body:draft);draft="" } catch { self.error=error.localizedDescription } } }.disabled(draft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty);if let error{Text(error).foregroundStyle(.red)} }
    }.navigationTitle(channel.title).navigationBarTitleDisplayMode(.inline).sheet(item:$reporting){MessageReportForm(message:$0)} }
}

struct EventChatSheet:View {
    @Environment(AppModel.self) private var model
    let eventId:UUID
    var body:some View {
        NavigationStack { Group {
            if let channel=model.channels.first(where:{$0.eventId==eventId}) { ChannelView(channel:channel) }
            else if case .failed(let message)=model.communityState { ContentUnavailableView("Couldn’t load event chat",systemImage:"wifi.exclamationmark",description:Text(message)) }
            else { ProgressView("Opening your event room…") }
        }.task{await model.reloadCommunity()} }
    }
}

private struct MessageReportForm:View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let message:CommunityMessage
    @State private var reason=""
    @State private var error:String?
    @State private var busy=false
    var body:some View {
        NavigationStack {
            Form {
                Section("Reported message") { Text(message.body).foregroundStyle(.secondary) }
                Section("Reason") { TextField("Why should moderators review this?",text:$reason,axis:.vertical).lineLimit(3...8) }
                if let error { Text(error).foregroundStyle(.red) }
                Button(busy ? "Submitting…":"Submit report") { busy=true;Task{do{try await model.reportMessage(messageId:message.id,description:reason);dismiss()}catch{self.error=error.localizedDescription;busy=false}} }
                    .disabled(busy||reason.trimmingCharacters(in:.whitespacesAndNewlines).count<5)
            }
            .navigationTitle("Report message")
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Cancel"){dismiss()}} }
        }
    }
}

struct ReportForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem
    @State private var category = "Safety"
    @State private var detail = ""
    @State private var priority = "normal"
    @State private var error: String?
    @State private var busy = false
    @State private var attachment: PhotosPickerItem?
    @State private var submitted = false

    var body: some View {
        NavigationStack {
            Form {
                Section(item.title) {
                    TextField("Category", text: $category)
                    Picker("Priority", selection: $priority) { Text("Low").tag("low"); Text("Normal").tag("normal"); Text("High").tag("high"); Text("Urgent").tag("urgent") }
                    TextField("What happened?", text: $detail, axis: .vertical).lineLimit(4...10)
                    PhotosPicker(selection: $attachment, matching: .images) {
                        Label("Choose evidence photo", systemImage: "paperclip")
                    }
                    if attachment != nil { Label("Evidence photo selected", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                    Text("The photo stays in protected report storage and is visible only to you and authorized event staff.").font(.caption).foregroundStyle(.secondary)
                }
                if let error { Text(error).foregroundStyle(submitted ? .orange : .red) }
                Button(submitted ? "Done" : (busy ? "Submitting…" : "Submit report")) {
                    if submitted { dismiss() }
                    else {
                        busy = true
                        Task { await submit() }
                    }
                }.disabled(!submitted && (busy || category.trimmingCharacters(in: .whitespaces).count < 2 || detail.trimmingCharacters(in: .whitespaces).count < 5))
            }
            .navigationTitle("Report an issue")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    private func submit() async {
        defer { busy = false }
        do {
            var evidence: Data?
            if let attachment {
                guard let source = try await attachment.loadTransferable(type: Data.self),
                      let image = UIImage(data: source),
                      let jpeg = image.jpegData(compressionQuality: 0.82) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                evidence = jpeg
            }
            let warning = try await model.submitReport(
                editionId: item.editionId,
                category: category,
                description: detail,
                priority: priority,
                attachmentData: evidence
            )
            if let warning {
                submitted = true
                error = warning
            } else {
                dismiss()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
