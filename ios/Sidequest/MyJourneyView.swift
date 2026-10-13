import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

struct MyJourneyView: View {
    @Environment(AppModel.self) private var model
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if !model.isAuthenticated {
                    ContentUnavailableView("Sign in to see your journey", systemImage: "person.crop.circle.badge.questionmark", description: Text("Use Profile to sign in. Confirmed registrations, waitlists and passes will persist here."))
                } else {
                    switch model.journeyState {
                    case .idle where model.journey.isEmpty,
                         .loading where model.journey.isEmpty:
                        ProgressView("Loading your journey…")
                    case .failed(let message) where model.journey.isEmpty:
                        ContentUnavailableView {
                            Label("Couldn’t load your journey", systemImage: "wifi.exclamationmark")
                        } description: { Text(message) } actions: {
                            Button("Try again") { Task { await model.reloadJourney() } }
                        }
                    default:
                        if model.journey.isEmpty {
                            ContentUnavailableView("No registrations yet", systemImage: "ticket", description: Text("Register for a published event and it will appear here."))
                        } else {
                            List(model.journey) { item in
                                JourneyCard(item: item, conflicts: conflicts(for:item), cancel: { await cancel(item) })
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                            }
                            .listStyle(.plain)
                            .refreshable { await model.reloadJourney() }
                        }
                    }
                }
            }
            .background(Color.sidequestMist)
            .navigationTitle("My Journey")
            .task { if model.isAuthenticated && model.journeyState == .idle { await model.reloadJourney() } }
            .alert("Couldn’t update registration", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "Please try again.") }
        }
    }

    private func cancel(_ item: JourneyItem) async {
        do { try await model.cancel(item) }
        catch { errorMessage = error.localizedDescription }
    }
    private func conflicts(for item:JourneyItem)->[JourneyItem]{model.journey.filter{$0.id != item.id && $0.status=="registered" && item.startsAt < $0.endsAt && $0.startsAt < item.endsAt}}
}

private struct JourneyCard: View {
    @Environment(AppModel.self) private var model
    let item: JourneyItem
    let conflicts:[JourneyItem]
    let cancel: () async -> Void
    @State private var isCancelling = false
    @State private var reviewing = false
    @State private var reporting = false
    @State private var showingEventChat = false
    @State private var showingEventMedia = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(item.category.uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                Spacer()
                Text(item.status.replacingOccurrences(of: "_", with: " ").uppercased())
                    .font(.caption2.bold())
                    .foregroundStyle(item.status == "registered" ? .green : item.status == "waitlisted" ? .orange : .secondary)
            }
            Text(item.title).font(.title3.bold())
            Label(item.startsAt.formatted(date: .abbreviated, time: .shortened), systemImage: "calendar")
            Text(item.organizationName).font(.subheadline).foregroundStyle(.secondary)
            if let venue=item.venueName { Label(venue,systemImage:"mappin.and.ellipse") }
            if let destination=item.destinationLandmarkId { Button("Navigate me there",systemImage:"location.north.fill"){model.prepareNavigation(to:destination,from:item.designatedGateLandmarkId)}.buttonStyle(.borderedProminent) }
            if !conflicts.isEmpty { Label("Schedule conflict with \(conflicts.map(\.title).joined(separator: ", "))",systemImage:"exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.orange) }
            if item.registrationClosesAt > .now { Label("Registration closes \(item.registrationClosesAt.formatted(.relative(presentation:.named)))",systemImage:"bell").font(.footnote).foregroundStyle(.secondary) }

            if let token = item.passToken, item.status == "registered" {
                Divider()
                HStack(spacing: 16) {
                    PassQRCode(token: token)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Event pass").font(.headline)
                        Text("This opaque code contains no personal information.").font(.caption).foregroundStyle(.secondary)
                        Text(token.uuidString).font(.caption2.monospaced()).textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Event chat",systemImage:"bubble.left.and.bubble.right"){showingEventChat=true}
                        .buttonStyle(.bordered)
                    Button("Event photos",systemImage:"photo.on.rectangle"){showingEventMedia=true}
                        .buttonStyle(.bordered)
                    Button("Report issue",systemImage:"flag"){reporting=true}
                        .buttonStyle(.bordered)
                }
            } else if item.status == "waitlisted" {
                Label("Waitlist position \(item.waitlistPosition ?? 0)", systemImage: "clock.badge")
            }

            if item.status != "cancelled" {
                Button("Cancel registration", role: .destructive) {
                    isCancelling = true
                    Task { await cancel(); isCancelling = false }
                }
                .disabled(isCancelling)
            }
            if item.status == "registered" && item.endsAt < .now {
                Button("Leave verified-attendee review") { reviewing = true }
            }
        }
        .padding(18)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
        .sheet(isPresented: $reviewing) { ReviewForm(item: item) }
        .sheet(isPresented:$reporting) { ReportForm(item:item) }
        .sheet(isPresented:$showingEventChat) { EventChatSheet(eventId:item.eventId) }
        .sheet(isPresented:$showingEventMedia) { EventMediaView(item:item) }
    }
}

private struct EventMediaView:View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item:JourneyItem
    @State private var photo:PhotosPickerItem?
    @State private var caption=""
    @State private var error:String?
    @State private var loading=false
    private let columns=[GridItem(.flexible()),GridItem(.flexible())]
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("Photos shared by people registered for \(item.title). Keep uploads relevant to the event and respect others’ privacy.").font(.subheadline).foregroundStyle(.secondary)
                    TextField("Optional caption",text:$caption).textFieldStyle(.roundedBorder)
                    PhotosPicker(selection:$photo,matching:.images) { Label("Share an event photo",systemImage:"plus.rectangle.on.rectangle") }.buttonStyle(.borderedProminent).disabled(loading)
                    if loading { ProgressView("Uploading your photo…") }
                    if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                    LazyVGrid(columns:columns,spacing:12) {
                        ForEach(model.eventMedia[item.editionId] ?? []) { image in
                            VStack(alignment:.leading,spacing:6) {
                                AsyncImage(url:image.url) { phase in
                                    if let content=phase.image { content.resizable().scaledToFill() }
                                    else if phase.error != nil { ContentUnavailableView("Photo unavailable",systemImage:"photo.badge.exclamationmark") }
                                    else { ProgressView().frame(maxWidth:.infinity,minHeight:130) }
                                }.frame(height:150).frame(maxWidth:.infinity).clipped().clipShape(RoundedRectangle(cornerRadius:12))
                                if let caption=image.caption,!caption.isEmpty { Text(caption).font(.caption).lineLimit(2) }
                                Text(image.createdAt.formatted(date:.abbreviated,time:.shortened)).font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !loading && (model.eventMedia[item.editionId] ?? []).isEmpty { ContentUnavailableView("No event photos yet",systemImage:"photo.on.rectangle",description:Text("Be the first attendee to share a moment.")) }
                }.padding()
            }
            .navigationTitle("Event photos")
            .toolbar { ToolbarItem(placement:.cancellationAction){Button("Done"){dismiss()}} }
            .task { do{try await model.reloadEventMedia(editionId:item.editionId)}catch{self.error=error.localizedDescription} }
            .onChange(of:photo){_,item in guard let item else{return};loading=true;Task{defer{loading=false;photo=nil};do{guard let source=try await item.loadTransferable(type:Data.self),let image=UIImage(data:source),let jpeg=image.jpegData(compressionQuality:0.82) else{throw CocoaError(.fileReadCorruptFile)};try await model.uploadEventPhoto(editionId:self.item.editionId,data:jpeg,caption:caption);caption="";error=nil}catch{self.error=error.localizedDescription}}}
        }
    }
}

private struct ReviewForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem
    @State private var rating = 5
    @State private var reviewText = ""
    @State private var error: String?
    @State private var busy = false
    var content: some View {
        Form {
            Stepper("Rating: \(rating) / 5", value: $rating, in: 1...5)
            TextField("Share useful feedback", text: $reviewText, axis: .vertical).lineLimit(3...8)
            if let error { Text(error).foregroundStyle(.red) }
            Button(busy ? "Saving…" : "Save review") {
                busy = true
                Task { do { try await model.submitReview(editionId: item.editionId, rating: rating, body: reviewText); dismiss() } catch { self.error = error.localizedDescription; busy = false } }
            }.disabled(busy)
        }
    }
    var body: some View { NavigationStack { content.navigationTitle("Review \(item.title)").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } } } }
}

private struct PassQRCode: View {
    let token: UUID
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image).interpolation(.none).resizable()
            } else {
                Image(systemName: "qrcode").resizable()
            }
        }
        .frame(width: 104, height: 104)
        .accessibilityLabel("Event pass QR code")
    }

    private var image: UIImage? {
        filter.message = Data(token.uuidString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
