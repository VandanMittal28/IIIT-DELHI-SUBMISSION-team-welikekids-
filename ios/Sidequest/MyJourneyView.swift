import CoreImage.CIFilterBuiltins
import PhotosUI
import SwiftUI
import UIKit

// "Your Events" from screenshot 02: date-grouped flat rows, with the empty state as a
// left-aligned tile beside grey copy. The pass, chat, photos, report, cancel and review
// actions that used to be crammed into every list card now live on a pushed detail screen,
// which is what lets the list itself stay as sparse as Luma's.

struct MyJourneyView: View {
    @Environment(AppModel.self) private var model
    @State private var errorMessage: String?
    @State private var showingPast = false

    private var upcoming: [JourneyItem] {
        model.journey.filter { $0.endsAt >= .now && $0.status != "cancelled" }.sorted { $0.startsAt < $1.startsAt }
    }

    private var past: [JourneyItem] {
        model.journey.filter { $0.endsAt < .now || $0.status == "cancelled" }.sorted { $0.startsAt > $1.startsAt }
    }

    private var visible: [JourneyItem] { showingPast ? past : upcoming }

    private var grouped: [(day: Date, items: [JourneyItem])] {
        let calendar = Calendar.current
        let buckets = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.startsAt) }
        let keys = buckets.keys.sorted(by: showingPast ? (>) : (<))
        return keys.map { (day: $0, items: buckets[$0]!) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SQScreenHeader(title: "Journey", avatarSeed: "Sidequest") {
                    SQActionCapsule {
                        SQCapsuleGlyph(
                            systemImage: showingPast ? "clock.arrow.circlepath" : "calendar",
                            accessibilityTitle: showingPast ? "Show upcoming events" : "Show past events"
                        ) {
                            showingPast.toggle()
                        }
                    }
                }
                .padding(.bottom, SQSpace.lg)

                content
            }
            .background(SQColor.plainBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .navigationDestination(for: JourneyItem.self) { item in
                JourneyDetailView(item: item)
            }
            .task {
                if model.isAuthenticated && model.journeyState == .idle { await model.reloadJourney() }
            }
            .alert(
                "Couldn’t update registration",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    @ViewBuilder private var content: some View {
        if !model.isAuthenticated {
            wrapper {
                SQEmptyState(
                    message: "Use Profile to sign in. Confirmed registrations, waitlists and passes will persist here.",
                    systemImage: "person.crop.circle.badge.questionmark"
                )
                .padding(.horizontal, SQSpace.margin)
            }
        } else {
            switch model.journeyState {
            case .idle where model.journey.isEmpty, .loading where model.journey.isEmpty:
                wrapper {
                    VStack(alignment: .leading, spacing: SQSpace.rowGap) {
                        SQSectionHeader(title: "Your Events", subtitle: "Loading your journey…")
                    }
                }
            case .failed(let message) where model.journey.isEmpty:
                wrapper {
                    SQEmptyState(
                        message: "Couldn’t load your journey. \(message)",
                        systemImage: "wifi.exclamationmark",
                        actionTitle: "Try again"
                    ) {
                        Task { await model.reloadJourney() }
                    }
                    .padding(.horizontal, SQSpace.margin)
                }
            default:
                list
            }
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SQSpace.groupGap) {
                SQSectionHeader(
                    title: showingPast ? "Past Events" : "Your Events",
                    subtitle: showingPast ? "Finished and cancelled" : "Upcoming and waitlisted"
                )

                if visible.isEmpty {
                    SQEmptyState(
                        message: showingPast
                            ? "Nothing here yet. Events you’ve attended or cancelled will be listed here."
                            : "You have a clear schedule ahead. Explore events in Discover to register for one.",
                        systemImage: "ticket"
                    )
                    .padding(.horizontal, SQSpace.margin)
                }

                ForEach(grouped, id: \.day) { group in
                    VStack(alignment: .leading, spacing: SQSpace.rowGap) {
                        SQDateHeader(date: group.day)
                        ForEach(group.items) { item in
                            NavigationLink(value: item) {
                                SQEventRow(
                                    title: item.title,
                                    hostName: item.organizationName,
                                    seed: item.title,
                                    timeText: item.startsAt.formatted(date: .omitted, time: .shortened),
                                    venueText: item.venueName,
                                    badgeText: Self.statusTitle(item),
                                    badgeForeground: Self.statusColor(item),
                                    badgeBackground: Self.statusColor(item).opacity(0.15)
                                )
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, SQSpace.margin)

                            if !conflicts(for: item).isEmpty {
                                SQNotice(
                                    text: "Schedule conflict with \(conflicts(for: item).map(\.title).joined(separator: ", "))",
                                    kind: .warning
                                )
                                .padding(.horizontal, SQSpace.margin)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, SQSpace.tabBarClearance)
        }
        .refreshable { await model.reloadJourney() }
    }

    private func wrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) { content() }
                .padding(.top, SQSpace.sm)
                .padding(.bottom, SQSpace.tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { if model.isAuthenticated { await model.reloadJourney() } }
    }

    private func conflicts(for item: JourneyItem) -> [JourneyItem] {
        model.journey.filter {
            $0.id != item.id && $0.status == "registered" && item.startsAt < $0.endsAt && $0.startsAt < item.endsAt
        }
    }

    static func statusTitle(_ item: JourneyItem) -> String {
        switch item.status {
        case "registered": "Going"
        case "waitlisted": "Waitlist \(item.waitlistPosition ?? 0)"
        default: item.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func statusColor(_ item: JourneyItem) -> Color {
        switch item.status {
        case "registered": SQColor.positive
        case "waitlisted": SQColor.warning
        case "cancelled": SQColor.destructive
        default: SQColor.textSecondary
        }
    }
}

// MARK: - Detail

/// Everything that used to be stacked inside the list card, given room to breathe. Uses the
/// grouped-card language of screenshot 01 with a ticket-styled pass at the top.
private struct JourneyDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem

    @State private var isCancelling = false
    @State private var errorMessage: String?
    @State private var reviewing = false
    @State private var reporting = false
    @State private var showingEventChat = false
    @State private var showingEventMedia = false
    @State private var confirmCancel = false

    private var conflicts: [JourneyItem] {
        model.journey.filter {
            $0.id != item.id && $0.status == "registered" && item.startsAt < $0.endsAt && $0.startsAt < item.endsAt
        }
    }

    var body: some View {
        SQDetailScreen(title: MyJourneyView.statusTitle(item)) {
            VStack(alignment: .leading, spacing: SQSpace.sm) {
                Text(item.title)
                    .font(SQFont.display)
                    .foregroundStyle(SQColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(item.startsAt.formatted(date: .complete, time: .shortened))
                    .font(SQFont.rowLabel)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let token = item.passToken, item.status == "registered" {
                passCard(token: token)
            }

            SQCard {
                SQListRow(title: "Organizer", subtitle: item.organizationName, accessory: .none)
                if let venue = item.venueName {
                    SQInsetDivider(leading: SQSpace.cardInset)
                    SQListRow(title: "Venue", subtitle: venue, accessory: .none)
                }
                SQInsetDivider(leading: SQSpace.cardInset)
                SQListRow(title: "Category", subtitle: item.category, accessory: .none)
                if item.status == "waitlisted" {
                    SQInsetDivider(leading: SQSpace.cardInset)
                    SQListRow(title: "Waitlist position", subtitle: "\(item.waitlistPosition ?? 0)", accessory: .none)
                }
            }

            if !conflicts.isEmpty {
                SQNotice(
                    text: "Schedule conflict with \(conflicts.map(\.title).joined(separator: ", "))",
                    kind: .warning
                )
            }
            if item.registrationClosesAt > .now {
                SQNotice(
                    text: "Registration closes \(item.registrationClosesAt.formatted(.relative(presentation: .named)))",
                    kind: .info
                )
            }

            if let destination = item.destinationLandmarkId {
                SQPrimaryButton(title: "Navigate me there", systemImage: "location.north.fill") {
                    model.prepareNavigation(to: destination, from: item.designatedGateLandmarkId)
                    dismiss()
                }
            }

            if item.status == "registered" {
                SQGroupHeader(title: "During the event")
                    .padding(.horizontal, -SQSpace.margin)
                SQCard {
                    SQListRow(title: "Event chat", systemImage: "bubble.left.and.bubble.right.fill", iconColor: SQColor.hueBlue) {
                        showingEventChat = true
                    }
                    SQInsetDivider()
                    SQListRow(title: "Event photos", systemImage: "photo.on.rectangle", iconColor: SQColor.huePink) {
                        showingEventMedia = true
                    }
                    SQInsetDivider()
                    SQListRow(title: "Report an issue", systemImage: "flag.fill", iconColor: SQColor.hueOrange) {
                        reporting = true
                    }
                }
            }

            if item.status == "registered" && item.endsAt < .now {
                SQPrimaryButton(title: "Leave verified-attendee review", systemImage: "star.fill") {
                    reviewing = true
                }
            }

            if let errorMessage { SQNotice(text: errorMessage, kind: .error) }

            if item.status != "cancelled" {
                SQSecondaryButton(
                    title: isCancelling ? "Cancelling…" : "Cancel registration",
                    systemImage: "xmark.circle",
                    destructive: true,
                    isEnabled: !isCancelling
                ) {
                    confirmCancel = true
                }
            }
        }
        .sheet(isPresented: $reviewing) { ReviewForm(item: item) }
        .sheet(isPresented: $reporting) { ReportForm(item: item) }
        .sheet(isPresented: $showingEventChat) { EventChatSheet(eventId: item.eventId) }
        .sheet(isPresented: $showingEventMedia) { EventMediaView(item: item) }
        .alert("Cancel this registration?", isPresented: $confirmCancel) {
            Button("Keep registration", role: .cancel) {}
            Button("Cancel registration", role: .destructive) {
                isCancelling = true
                Task {
                    do {
                        try await model.cancel(item)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                    isCancelling = false
                }
            }
        } message: {
            Text("Your place is released immediately and may be taken by someone on the waitlist.")
        }
    }

    private func passCard(token: UUID) -> some View {
        SQCard(padding: SQSpace.xl) {
            VStack(spacing: SQSpace.lg) {
                HStack {
                    Text("Event pass")
                        .font(SQFont.rowTitle)
                        .foregroundStyle(SQColor.textPrimary)
                    Spacer()
                    SQBadge(text: "Active", foreground: SQColor.positive, background: SQColor.positive.opacity(0.15))
                }

                PassQRCode(token: token)
                    .padding(SQSpace.md)
                    .background(.white, in: RoundedRectangle(cornerRadius: SQRadius.map, style: .continuous))

                Text("This opaque code contains no personal information.")
                    .font(SQFont.meta)
                    .foregroundStyle(SQColor.textSecondary)
                    .multilineTextAlignment(.center)

                Text(token.uuidString)
                    .font(SQFont.mono)
                    .foregroundStyle(SQColor.textTertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Pass QR

private struct PassQRCode: View {
    let token: UUID
    private let context = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).interpolation(.none).resizable()
            } else {
                Image(systemName: "qrcode").resizable()
            }
        }
        .frame(width: 180, height: 180)
        .accessibilityLabel("Event pass QR code")
    }

    private var image: UIImage? {
        filter.message = Data(token.uuidString.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Event media

private struct EventMediaView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem

    @State private var photo: PhotosPickerItem?
    @State private var caption = ""
    @State private var error: String?
    @State private var loading = false

    private let columns = [GridItem(.flexible(), spacing: SQSpace.md), GridItem(.flexible(), spacing: SQSpace.md)]
    private var photos: [EventMediaPhoto] { model.eventMedia[item.editionId] ?? [] }

    var body: some View {
        SQSheet(title: "Event Photos", onClose: { dismiss() }) {
            Text("Photos shared by people registered for \(item.title). Keep uploads relevant to the event and respect others’ privacy.")
                .font(SQFont.body)
                .foregroundStyle(SQColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.md) {
                    SQField(placeholder: "Optional caption", text: $caption, systemImage: "text.quote")
                    let isUploading = loading
                    PhotosPicker(selection: $photo, matching: .images) {
                        HStack(spacing: SQSpace.sm) {
                            Image(systemName: "plus.rectangle.on.rectangle")
                            Text("Share an event photo").font(SQFont.bodyEmphasis)
                        }
                        .foregroundStyle(SQColor.onPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: SQSize.listRow)
                        .background(SQColor.primaryFill.opacity(isUploading ? 0.4 : 1), in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous))
                    }
                    .disabled(loading)
                }
            }

            if loading { SQNotice(text: "Uploading your photo…", kind: .info) }
            if let error { SQNotice(text: error, kind: .error) }

            if photos.isEmpty && !loading {
                SQEmptyState(
                    message: "No event photos yet. Be the first attendee to share a moment.",
                    systemImage: "photo.on.rectangle"
                )
            } else {
                LazyVGrid(columns: columns, spacing: SQSpace.md) {
                    ForEach(photos) { image in
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: image.url) { phase in
                                if let content = phase.image {
                                    content.resizable().scaledToFill()
                                } else if phase.error != nil {
                                    ZStack {
                                        SQColor.surfaceAlt
                                        Image(systemName: "photo.badge.exclamationmark")
                                            .foregroundStyle(SQColor.textTertiary)
                                    }
                                } else {
                                    ZStack {
                                        SQColor.surfaceAlt
                                        ProgressView().controlSize(.small)
                                    }
                                }
                            }
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: SQRadius.thumb, style: .continuous))

                            if let caption = image.caption, !caption.isEmpty {
                                Text(caption)
                                    .font(SQFont.meta)
                                    .foregroundStyle(SQColor.textPrimary)
                                    .lineLimit(2)
                            }
                            Text(image.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(SQFont.badge)
                                .foregroundStyle(SQColor.textTertiary)
                        }
                    }
                }
            }
        }
        .task {
            do { try await model.reloadEventMedia(editionId: item.editionId) }
            catch { self.error = error.localizedDescription }
        }
        .onChange(of: photo) { _, selected in
            guard let selected else { return }
            loading = true
            Task { @MainActor in
                defer { loading = false; photo = nil }
                do {
                    guard let source = try await selected.loadTransferable(type: Data.self),
                          let image = UIImage(data: source),
                          let jpeg = image.jpegData(compressionQuality: 0.82) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try await model.uploadEventPhoto(editionId: item.editionId, data: jpeg, caption: caption)
                    caption = ""
                    error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Review

private struct ReviewForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: JourneyItem

    @State private var rating = 5
    @State private var reviewText = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        SQSheet(title: "Leave a Review", onClose: { dismiss() }) {
            SQGroupHeader(title: item.title)
                .padding(.horizontal, -SQSpace.margin)

            SQCard(padding: SQSpace.cardInset) {
                VStack(alignment: .leading, spacing: SQSpace.lg) {
                    HStack {
                        Text("Rating").font(SQFont.rowLabel).foregroundStyle(SQColor.textPrimary)
                        Spacer()
                        Text("\(rating) / 5").font(SQFont.rowLabel).foregroundStyle(SQColor.textSecondary)
                    }
                    HStack(spacing: SQSpace.sm) {
                        ForEach(1...5, id: \.self) { value in
                            Button {
                                rating = value
                            } label: {
                                Image(systemName: value <= rating ? "star.fill" : "star")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(value <= rating ? SQColor.hueYellow : SQColor.textTertiary)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(value) star\(value == 1 ? "" : "s")")
                        }
                    }
                    SQField(placeholder: "Share useful feedback", text: $reviewText, axisVertical: true, lineLimit: 3...8)
                }
            }

            if let error { SQNotice(text: error, kind: .error) }

            SQPrimaryButton(
                title: busy ? "Saving…" : "Save review",
                systemImage: "checkmark",
                isLoading: busy,
                isEnabled: !busy
            ) {
                busy = true
                Task {
                    do {
                        try await model.submitReview(editionId: item.editionId, rating: rating, body: reviewText)
                        dismiss()
                    } catch {
                        self.error = error.localizedDescription
                        busy = false
                    }
                }
            }
        }
    }
}
