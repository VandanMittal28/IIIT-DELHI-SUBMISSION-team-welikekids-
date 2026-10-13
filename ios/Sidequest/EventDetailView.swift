import CoreImage
import CoreImage.CIFilterBuiltins
import MapKit
import SwiftUI

// The cover-tinted event page from screenshots 04 and 05. The whole screen takes a colour
// sampled from the event's cover art; every section uses the label + hairline pattern; the
// floating back/share circles cross-fade into an inline nav bar as the page scrolls.
//
// Split out of DiscoverView.swift during the redesign (PLAN.md decision 11).

// MARK: - Cover tint sampling

enum SQCoverTintSampler {
    /// Averages the cover image down to a single colour, then pushes it into the deep,
    /// slightly desaturated band that makes white text legible (`SQTint.fromCoverSample`).
    /// Returns nil whenever the image can't be fetched or decoded — the caller keeps the
    /// brand-ink fallback in that case.
    static func sample(url: URL) async -> SQTint? {
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let image = CIImage(data: data) else { return nil }
        let extent = image.extent
        guard extent.width >= 1, extent.height >= 1, !extent.isInfinite else { return nil }

        let filter = CIFilter.areaAverage()
        filter.inputImage = image
        filter.extent = extent
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        pixel.withUnsafeMutableBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            context.render(
                output,
                toBitmap: base,
                rowBytes: 4,
                bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                format: .RGBA8,
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
        }
        return SQTint.fromCoverSample(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }
}

/// Reports how far the page has scrolled so the inline nav bar can fade in (screenshot 05).
private struct SQScrollOffsetKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

// MARK: - Screen

struct EventDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let event: EventFeedItem
    let comparing: Bool
    let setComparing: (Bool) -> Void

    @State private var tint: SQTint = .fallback
    @State private var hasSampledTint = false
    @State private var scrollOffset: CGFloat = 0
    @State private var message: String?
    @State private var errorMessage: String?
    @State private var isLoadingDetails = false

    /// The inline nav bar takes over once the cover has scrolled most of the way off.
    private var navBarOpacity: Double {
        let start: CGFloat = 120
        let end: CGFloat = 220
        return Double(min(1, max(0, (-scrollOffset - start) / (end - start))))
    }

    private var sessions: [EventSessionScheduleItem] {
        model.sessionsByEdition[event.editionId] ?? []
    }

    private var currentReview: EditionReviewSummary? {
        model.reviewSummariesByEvent[event.id]?.first { $0.editionId == event.editionId }
    }

    private var previousReview: (average: Double, sampleSize: Int)? {
        let prior = (model.reviewSummariesByEvent[event.id] ?? []).filter { $0.editionId != event.editionId }
        let count = prior.reduce(0) { $0 + $1.sampleSize }
        guard count > 0 else { return nil }
        let total = prior.reduce(0.0) { $0 + $1.averageRating * Double($1.sampleSize) }
        return (total / Double(count), count)
    }

    private var registration: JourneyItem? { model.registration(for: event.editionId) }

    private var campus: CampusPoint? {
        model.campuses.first { $0.name.localizedCaseInsensitiveCompare(event.collegeName) == .orderedSame }
    }

    private var dateLine: String {
        let day = event.startsAt.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        let start = event.startsAt.formatted(date: .omitted, time: .shortened)
        let end = event.endsAt.formatted(date: .omitted, time: .shortened)
        return "\(day), \(start) – \(end)"
    }

    private var shareText: String {
        "\(event.title) · \(dateLine) · \(event.organizationName), \(event.collegeName)"
    }

    var body: some View {
        ZStack(alignment: .top) {
            tint.gradient.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: SQScrollOffsetKey.self,
                            value: proxy.frame(in: .named("detail")).minY
                        )
                    }
                    .frame(height: 0)

                    coverBlock
                        .padding(.top, SQSize.floatingCircle + SQSpace.xl)

                    Text(event.title)
                        .font(SQFont.display)
                        .foregroundStyle(tint.textPrimary)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, SQSpace.xl)

                    Text(dateLine)
                        .font(SQFont.lede)
                        .foregroundStyle(tint.textSecondary)
                        .padding(.top, 6)

                    actionRow
                        .padding(.top, SQSpace.xl)

                    if let message { SQNotice(text: message, kind: .success).padding(.top, SQSpace.lg) }
                    if let errorMessage { SQNotice(text: errorMessage, kind: .error).padding(.top, SQSpace.lg) }

                    locationSection.padding(.top, SQSpace.xxl)
                    hostSection.padding(.top, SQSpace.xxl)
                    if !sessions.isEmpty || isLoadingDetails { scheduleSection.padding(.top, SQSpace.xxl) }
                    feedbackSection.padding(.top, SQSpace.xxl)
                    if let eligibility = event.eligibility, !eligibility.isEmpty {
                        eligibilitySection(eligibility).padding(.top, SQSpace.xxl)
                    }
                    aboutSection.padding(.top, SQSpace.xxl)
                }
                .padding(.horizontal, SQSpace.margin)
                .padding(.bottom, SQSpace.tabBarClearance)
            }
            .coordinateSpace(name: "detail")
            .onPreferenceChange(SQScrollOffsetKey.self) { scrollOffset = $0 }

            chrome
        }
        .environment(\.sqTint, tint)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        .task {
            isLoadingDetails = true
            defer { isLoadingDetails = false }
            do { try await model.loadEventDetails(for: event) }
            catch { errorMessage = error.localizedDescription }
        }
        .task(id: model.eventImageURLs[event.id]) {
            guard !hasSampledTint, let url = model.eventImageURLs[event.id] else { return }
            if let sampled = await SQCoverTintSampler.sample(url: url) {
                hasSampledTint = true
                withAnimation(.easeInOut(duration: 0.35)) { tint = sampled }
            }
        }
    }

    // MARK: Chrome

    /// Floating circles over the cover, cross-fading into the inline bar from screenshot 05.
    private var chrome: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(tint.base.opacity(0.55))
                .ignoresSafeArea(edges: .top)
                .opacity(navBarOpacity)
                .allowsHitTesting(false)

            HStack(spacing: SQSpace.md) {
                SQCircleButton(systemImage: "chevron.left") { dismiss() }
                    .accessibilityLabel("Back")

                Text(event.title)
                    .font(SQFont.rowTitle)
                    .foregroundStyle(tint.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(navBarOpacity)

                Spacer(minLength: SQSpace.sm)

                if navBarOpacity > 0.5, registration == nil {
                    SQCircleButton(systemImage: "ticket") { Task { await register() } }
                        .accessibilityLabel("Register")
                        .transition(.opacity)
                }
                ShareLink(item: shareText) {
                    ZStack {
                        Circle().fill(tint.controlFill)
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(tint.textPrimary)
                    }
                    .frame(width: SQSize.floatingCircle, height: SQSize.floatingCircle)
                }
                .accessibilityLabel("Share event")
            }
            .padding(.horizontal, SQSpace.margin)
            .frame(height: SQSize.floatingCircle)
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, SQSpace.sm)
        }
        .frame(height: SQSize.floatingCircle + SQSpace.lg)
        .animation(.easeInOut(duration: 0.2), value: navBarOpacity > 0.5)
    }

    // MARK: Cover

    /// Cover image with the "Featured" strip joined to its bottom corners (screenshot 04).
    private var coverBlock: some View {
        VStack(spacing: 0) {
            Group {
                if let url = model.eventImageURLs[event.id] {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else if phase.error != nil {
                            coverPlaceholder
                        } else {
                            coverPlaceholder.overlay(ProgressView().tint(.white))
                        }
                    }
                } else {
                    coverPlaceholder
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipped()

            HStack(spacing: SQSpace.sm) {
                Image(systemName: "laurel.leading")
                Text("\(event.category) · \(event.collegeName)")
                    .lineLimit(1)
                Image(systemName: "laurel.trailing")
            }
            .font(SQFont.body)
            .foregroundStyle(tint.textPrimary.opacity(0.85))
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: SQRadius.cover, style: .continuous))
    }

    private var coverPlaceholder: some View {
        ZStack {
            Color.white.opacity(0.10)
            Text(String(event.title.prefix(1)).uppercased())
                .font(SQFont.monogram(72))
                .foregroundStyle(tint.textSecondary)
        }
    }

    // MARK: Actions

    private var actionRow: some View {
        HStack(spacing: SQSpace.md) {
            if let registration {
                SQTallAction(
                    title: registration.status == "registered" ? "Registered" : "Waitlisted",
                    systemImage: registration.status == "registered" ? "checkmark.seal.fill" : "clock.badge",
                    prominent: true,
                    isEnabled: false
                ) {}
            } else {
                SQTallAction(
                    title: model.registrationStates[event.editionId] == .loading ? "Confirming…" : "Register",
                    systemImage: "ticket",
                    prominent: true,
                    isEnabled: model.registrationStates[event.editionId] != .loading
                ) {
                    Task { await register() }
                }
            }

            SQTallAction(
                title: model.savedEventIds.contains(event.id) ? "Saved" : "Save",
                systemImage: model.savedEventIds.contains(event.id) ? "bookmark.fill" : "bookmark"
            ) {
                Task {
                    do { try await model.toggleSaved(eventId: event.id) }
                    catch { errorMessage = error.localizedDescription }
                }
            }

            Menu {
                Button(comparing ? "Remove from comparison" : "Add to comparison",
                       systemImage: comparing ? "checkmark.square.fill" : "square.on.square") {
                    setComparing(!comparing)
                }
                if let destination = event.destinationLandmarkId {
                    Button("Navigate to venue", systemImage: "location.north.fill") {
                        model.prepareNavigation(to: destination)
                        dismiss()
                    }
                }
                ShareLink(item: shareText) { Label("Share event", systemImage: "square.and.arrow.up") }
            } label: {
                VStack(spacing: 10) {
                    Image(systemName: "ellipsis").font(.system(size: 22, weight: .semibold))
                    Text("More").font(SQFont.bodyEmphasis)
                }
                .foregroundStyle(tint.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: SQSize.tallAction)
                .background(tint.controlFill, in: RoundedRectangle(cornerRadius: SQRadius.control, style: .continuous))
            }
            .accessibilityLabel("More actions")
        }
    }

    // MARK: Sections

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "Location")

            HStack(alignment: .top, spacing: SQSpace.lg) {
                VStack(alignment: .leading, spacing: SQSpace.xs) {
                    Text(event.venueName ?? event.collegeName)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundStyle(tint.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    if event.venueName != nil {
                        Text(event.collegeName)
                            .font(SQFont.sectionLabel)
                            .foregroundStyle(tint.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: SQSpace.sm)
            }

            if let campus {
                Map(initialPosition: .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude),
                    latitudinalMeters: 700,
                    longitudinalMeters: 700
                ))) {
                    Marker(campus.name, coordinate: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude))
                }
                .frame(height: 230)
                .clipShape(RoundedRectangle(cornerRadius: SQRadius.map, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityLabel("Map of \(campus.name)")
            }

            if let destination = event.destinationLandmarkId {
                SQSecondaryButton(title: "Navigate to venue", systemImage: "location.north.fill") {
                    model.prepareNavigation(to: destination)
                    dismiss()
                }
            }
        }
    }

    private var hostSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "Host")
            HStack(spacing: 14) {
                SQAvatar(seed: event.organizationName, size: SQSize.avatarLarge)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.organizationName)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(tint.textPrimary)
                    Text(event.collegeName)
                        .font(SQFont.sectionLabel)
                        .foregroundStyle(tint.textSecondary)
                }
                .multilineTextAlignment(.leading)
                Spacer(minLength: SQSpace.sm)
                Text(event.priceLabel)
                    .font(SQFont.rowTitle)
                    .foregroundStyle(tint.textPrimary)
            }
        }
    }

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "Schedule")
            if isLoadingDetails && sessions.isEmpty {
                Text("Loading published sessions…")
                    .font(SQFont.body)
                    .foregroundStyle(tint.textSecondary)
            }
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: SQSpace.xs) {
                    Text(session.title)
                        .font(SQFont.rowTitle)
                        .foregroundStyle(tint.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("\(session.startsAt.formatted(date: .abbreviated, time: .shortened)) – \(session.endsAt.formatted(date: .omitted, time: .shortened))")
                        .font(SQFont.body)
                        .foregroundStyle(tint.textSecondary)
                    if let venue = session.venueName {
                        SQMetaItem(
                            systemImage: "mappin.circle",
                            text: [venue, session.campusName].compactMap { $0 }.joined(separator: ", ")
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, SQSpace.sm)
            }
        }
    }

    private var feedbackSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "Verified attendee feedback")
            ratingRow(
                label: "This edition",
                value: currentReview.map {
                    "\(String(format: "%.1f", $0.averageRating)) / 5 · \($0.sampleSize) \($0.sampleSize == 1 ? "review" : "reviews")"
                } ?? "No reviews yet"
            )
            ratingRow(
                label: "Previous editions",
                value: previousReview.map {
                    "\(String(format: "%.1f", $0.average)) / 5 · \($0.sampleSize) \($0.sampleSize == 1 ? "review" : "reviews")"
                } ?? "No reviews yet"
            )
        }
    }

    private func ratingRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: SQSpace.lg) {
            Text(label)
                .font(SQFont.sectionLabel)
                .foregroundStyle(tint.textSecondary)
            Spacer(minLength: SQSpace.sm)
            Text(value)
                .font(SQFont.sectionLabel)
                .foregroundStyle(tint.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 2)
    }

    private func eligibilitySection(_ eligibility: String) -> some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "Eligibility")
            Text(eligibility)
                .font(SQFont.sectionLabel)
                .foregroundStyle(tint.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: SQSpace.md) {
            SQSectionLabel(title: "About Event")
            Text(event.description)
                .font(SQFont.prose)
                .foregroundStyle(tint.textPrimary)
                .lineSpacing(8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Behaviour

    private func register() async {
        message = nil
        errorMessage = nil
        do {
            let result = try await model.register(for: event)
            message = result.status == "registered"
                ? "Registration confirmed. Your opaque pass is ready in Journey."
                : "You’re on the waitlist at position \(result.waitlistPosition ?? 0)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
