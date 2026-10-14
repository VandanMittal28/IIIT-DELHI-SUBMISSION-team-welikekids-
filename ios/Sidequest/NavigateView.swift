import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

// Navigate, restyled with the grouped cards of screenshot 01, the horizontal photo rail of
// screenshot 03 ("Cities" → campus landmarks) and the floating map chrome of screenshot 06.
//
// This rewrite also reconnects four features that had become unreachable: the file carried a
// `routeBuilder` form — with the route map, voice guidance, floor-plan warnings and the
// "I'm lost — realign" escape hatch — that nothing referenced any more, because the explore
// layout had replaced it without carrying those parts over. They now live in the route
// preview, so the dead code could go (PLAN.md decision 10).

struct NavigateView: View {
    @Environment(AppModel.self) private var model
    @State private var start: Landmark?
    @State private var destination: Landmark?
    @State private var accessibleOnly = false
    @State private var confirmedHere = false
    @State private var showCamera = false
    private let speaker = AVSpeechSynthesizer()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                SQScreenHeader(title: "Navigate", avatarSeed: "Sidequest") {
                    if model.routePlan != nil {
                        SQActionCapsule {
                            SQCapsuleGlyph(systemImage: "speaker.wave.2", accessibilityTitle: "Speak directions") {
                                speak(model.routePlan?.edges.map(\.instruction) ?? [])
                            }
                            SQCapsuleGlyph(systemImage: "arrow.counterclockwise", accessibilityTitle: "I’m lost — realign") {
                                confirmedHere = false
                                model.clearRoute()
                            }
                        }
                    }
                }
                .padding(.bottom, SQSpace.lg)

                content
            }
            .background(SQColor.plainBackground.ignoresSafeArea())
            .toolbar(.hidden, for: .tabBar)
            .task {
                if model.landmarks.isEmpty { await model.reloadLandmarks() }
                applyPreparedDestination()
            }
            .onChange(of: model.pendingNavigationDestinationId) { applyPreparedDestination() }
            .onChange(of: destination) { model.clearRoute() }
            .onChange(of: accessibleOnly) { model.clearRoute() }
            .fullScreenCover(isPresented: $showCamera) { cameraCover }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.navigationState {
        case .idle where model.landmarks.isEmpty, .loading where model.landmarks.isEmpty:
            wrapper {
                SQEmptyState(
                    message: "Loading published campus routes…",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                .padding(.horizontal, SQSpace.margin)
            }
        case .failed(let message) where model.landmarks.isEmpty:
            wrapper {
                SQEmptyState(
                    message: "Routes unavailable. \(message)",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath",
                    actionTitle: "Try again"
                ) {
                    Task { await model.reloadLandmarks() }
                }
                .padding(.horizontal, SQSpace.margin)
            }
        default:
            if model.landmarks.isEmpty {
                wrapper {
                    SQEmptyState(
                        message: "A college administrator must publish validated campus data before navigation can begin.",
                        systemImage: "mappin.slash"
                    )
                    .padding(.horizontal, SQSpace.margin)
                }
            } else {
                exploreContent
            }
        }
    }

    private func wrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SQSpace.xxl) { content() }
                .padding(.top, SQSpace.sm)
                .padding(.bottom, SQSpace.tabBarClearance)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await model.reloadLandmarks() }
    }

    @ViewBuilder private var cameraCover: some View {
        if let plan = model.routePlan {
            let steps = plan.cameraSteps(floorPlans: model.floorPlans)
            if !plan.physicalValidationComplete {
                CameraSimulationView(
                    plan: plan,
                    floorPlans: model.floorPlans,
                    destination: destination?.name ?? "Destination",
                    accessibleRoute: accessibleOnly
                )
            } else {
                CameraGuidanceView(steps: steps, confirmedFacingDegrees: start?.facingDegrees, simulationMode: false)
            }
        } else {
            VStack(alignment: .leading, spacing: SQSpace.xl) {
                SQEmptyState(
                    message: "Route unavailable. Calculate the route again to open camera guidance.",
                    systemImage: "point.topleft.down.to.point.bottomright.curvepath"
                )
                SQSecondaryButton(title: "Close", systemImage: "xmark") { showCamera = false }
            }
            .padding(SQSpace.margin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, SQSpace.xxxl)
            .background(SQColor.background.ignoresSafeArea())
        }
    }

    // MARK: - Explore

    private var exploreContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SQSpace.cardToHeader) {
                SQSectionHeader(title: "Explore IIIT Delhi", subtitle: "\(model.landmarks.count) mapped places")

                Text("Choose where you are, choose where you’re going, then follow the compass-guided camera preview.")
                    .font(SQFont.body)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, SQSpace.margin)

                routePlanner
                    .padding(.horizontal, SQSpace.margin)

                if case .failed(let message) = model.navigationState {
                    VStack(alignment: .leading, spacing: SQSpace.md) {
                        SQNotice(text: message, kind: .error)
                        SQSecondaryButton(title: "Try route again", systemImage: "arrow.clockwise") {
                            calculateRoute(openCamera: true)
                        }
                    }
                    .padding(.horizontal, SQSpace.margin)
                }

                if let plan = model.routePlan {
                    routePreview(plan)
                        .padding(.horizontal, SQSpace.margin)
                }

                campusMap
                nearbySection
            }
            .padding(.bottom, SQSpace.tabBarClearance)
        }
        .refreshable { await model.reloadLandmarks() }
    }

    private var routePlanner: some View {
        VStack(alignment: .leading, spacing: SQSpace.lg) {
            SQCard {
                LandmarkPickerRow(
                    title: "Where are you?",
                    placeholder: "Select your current landmark",
                    systemImage: "location.circle.fill",
                    iconColor: SQColor.hueBlue,
                    landmarks: model.landmarks,
                    selection: $start
                )

                if let start {
                    SQInsetDivider()
                    VStack(alignment: .leading, spacing: SQSpace.md) {
                        if let photo = model.landmarkPhotoURLs[start.id] {
                            AsyncImage(url: photo) { phase in
                                if let image = phase.image {
                                    image.resizable().scaledToFill()
                                } else {
                                    ZStack { SQColor.surfaceAlt; ProgressView().controlSize(.small) }
                                }
                            }
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .clipped()
                            .clipShape(RoundedRectangle(cornerRadius: SQRadius.thumb, style: .continuous))
                            .accessibilityLabel("Reference photo for \(start.name)")
                        }

                        Text(facingGuidance(for: start))
                            .font(SQFont.meta)
                            .foregroundStyle(SQColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        SQSecondaryButton(
                            title: confirmedHere ? "Starting landmark confirmed" : "I’m here — confirm this landmark",
                            systemImage: confirmedHere ? "checkmark.circle.fill" : "mappin.circle",
                            isSelected: confirmedHere
                        ) {
                            confirmedHere = true
                            if destination != nil { calculateRoute(openCamera: false) }
                        }
                    }
                    .padding(SQSpace.cardInset)
                }
            }

            SQCard {
                LandmarkPickerRow(
                    title: "Where do you want to go?",
                    placeholder: "Select a destination",
                    systemImage: "mappin.and.ellipse",
                    iconColor: SQColor.huePink,
                    landmarks: model.landmarks.filter { $0.id != start?.id },
                    selection: $destination
                )
                SQInsetDivider()
                SQListRow(
                    title: "Accessible route",
                    subtitle: accessibleOnly ? "Step-free, lift where mapped" : "Standard route, stairs where mapped",
                    systemImage: "figure.roll",
                    iconColor: SQColor.hueGreen,
                    accessory: .none
                ) {
                    Toggle("", isOn: $accessibleOnly).labelsHidden()
                }
            }

            SQPrimaryButton(
                title: "Preview camera simulation demo",
                systemImage: "camera.viewfinder",
                isEnabled: start != nil && destination != nil && confirmedHere && start != destination
            ) {
                calculateRoute(openCamera: true)
            }

            if !confirmedHere {
                Text("Confirm where you are to enable the route preview.")
                    .font(SQFont.meta)
                    .foregroundStyle(SQColor.textSecondary)
                    .padding(.horizontal, SQSpace.cardInset)
            }
        }
    }

    private func facingGuidance(for landmark: Landmark) -> String {
        if let facingDegrees = landmark.facingDegrees {
            return "\(landmark.facingInstruction ?? "Face the stored reference direction.") Stored reference: \(Int(facingDegrees.rounded()))°."
        }
        return "Match the landmark around you before confirming. This landmark has no facing reference, so camera arrows will stay disabled."
    }

    // MARK: - Route preview

    @ViewBuilder private func routePreview(_ plan: RoutePlan) -> some View {
        let cameraSteps = plan.cameraSteps(floorPlans: model.floorPlans)
        let cameraReady = plan.physicalValidationComplete
            && start?.facingDegrees != nil
            && cameraSteps.contains { $0.bearingDegrees != nil }
        let missingFloorPlan = plan.nodes.contains { node in
            node.coordinateKind == "indoor_floor" && (node.floorId.map { model.floorPlans[$0] == nil } ?? true)
        }

        VStack(alignment: .leading, spacing: SQSpace.lg) {
            VStack(alignment: .leading, spacing: SQSpace.xs) {
                Text("\(Int(plan.totalDistanceMeters.rounded())) m walk")
                    .font(SQFont.sectionTitle)
                    .foregroundStyle(SQColor.textPrimary)
                Text("\(start?.name ?? "Starting landmark") → \(destination?.name ?? "Destination")")
                    .font(SQFont.body)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                SQMetaItem(
                    systemImage: accessibleOnly ? "figure.roll" : "figure.walk",
                    text: accessibleOnly ? "Step-free · lift where mapped" : "Standard · stairs where mapped"
                )
            }

            RouteMap(nodes: plan.nodes, floorPlans: model.floorPlans, floorPlanURLs: model.floorPlanURLs)
                .frame(height: 240)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: SQRadius.map, style: .continuous))

            if !plan.physicalValidationComplete {
                SQNotice(
                    text: "This route has not been physically validated. Camera arrows are disabled; use map, text, or voice guidance.",
                    kind: .warning
                )
            }
            if missingFloorPlan {
                SQNotice(
                    text: "Indoor floor plan not supplied yet. Indoor directions are a text-only simulation.",
                    kind: .info
                )
            }
            if plan.physicalValidationComplete && !cameraReady {
                SQNotice(
                    text: "Camera arrows need a stored facing direction and route geometry. Map, text, and voice remain available.",
                    kind: .warning
                )
            }

            VStack(alignment: .leading, spacing: SQSpace.md) {
                ForEach(Array(plan.edges.enumerated()), id: \.element.id) { index, edge in
                    HStack(alignment: .top, spacing: SQSpace.md) {
                        Text("\(index + 1)")
                            .font(SQFont.metaEmphasis)
                            .foregroundStyle(SQColor.ink)
                            .frame(width: 26, height: 26)
                            .background(SQColor.lime, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(edge.instruction)
                                .font(SQFont.body)
                                .foregroundStyle(SQColor.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("\(Int(edge.distanceMeters.rounded())) m walking · \(edge.kind)")
                                .font(SQFont.meta)
                                .foregroundStyle(SQColor.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }

            VStack(spacing: SQSpace.md) {
                SQPrimaryButton(
                    title: cameraReady ? "Start aligned camera guidance" : "Preview camera simulation demo",
                    systemImage: "camera.viewfinder"
                ) {
                    showCamera = true
                }
                HStack(spacing: SQSpace.md) {
                    SQSecondaryButton(title: "Speak directions", systemImage: "speaker.wave.2.fill") {
                        speak(plan.edges.map(\.instruction))
                    }
                    SQSecondaryButton(title: "I’m lost", systemImage: "arrow.counterclockwise", destructive: true) {
                        confirmedHere = false
                        model.clearRoute()
                    }
                }
                Text("Return to a known landmark and confirm it again. Sidequest does not infer precise indoor position from “I’m here.”")
                    .font(SQFont.meta)
                    .foregroundStyle(SQColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(SQSpace.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SQColor.lime.opacity(0.22), in: RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous))
    }

    // MARK: - Map and rail

    private var campusMap: some View {
        Map(initialPosition: .region(exploreRegion)) {
            ForEach(model.landmarks) { landmark in
                if let latitude = landmark.latitude, let longitude = landmark.longitude {
                    Annotation(landmark.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                        Button {
                            destination = landmark
                            model.clearRoute()
                        } label: {
                            MapThumbnailPin(title: landmark.name, imageURL: model.landmarkPhotoURLs[landmark.id])
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Navigate to \(landmark.name)")
                    }
                }
            }
        }
        .frame(height: 320)
        .clipShape(RoundedRectangle(cornerRadius: SQRadius.cover, style: .continuous))
        .overlay(alignment: .topLeading) {
            Text("Tap a pin to choose a destination")
                .font(SQFont.metaEmphasis)
                .foregroundStyle(SQColor.textPrimary)
                .padding(.horizontal, SQSpace.md)
                .padding(.vertical, SQSpace.sm)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(SQSpace.md)
        }
        .padding(.horizontal, SQSpace.margin)
    }

    private var nearbySection: some View {
        VStack(alignment: .leading, spacing: SQSpace.lg) {
            SQSectionHeader(title: "Nearby on campus", subtitle: "\(model.landmarks.count) places")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: SQSpace.md) {
                    ForEach(model.landmarks) { landmark in
                        LandmarkCard(
                            landmark: landmark,
                            imageURL: model.landmarkPhotoURLs[landmark.id],
                            isSelected: destination?.id == landmark.id
                        ) {
                            destination = landmark
                            model.clearRoute()
                        }
                    }
                }
                .padding(.horizontal, SQSpace.margin)
            }
        }
    }

    private var exploreRegion: MKCoordinateRegion {
        let points = model.landmarks.compactMap { landmark -> CLLocationCoordinate2D? in
            guard let latitude = landmark.latitude, let longitude = landmark.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard !points.isEmpty else {
            if let campus = model.campuses.first {
                return MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude),
                    latitudinalMeters: 500,
                    longitudinalMeters: 500
                )
            }
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: 28.5458, longitude: 77.2732),
                latitudinalMeters: 500,
                longitudinalMeters: 500
            )
        }
        let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let longitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            latitudinalMeters: 500,
            longitudinalMeters: 500
        )
    }

    // MARK: - Behaviour

    private func applyPreparedDestination() {
        guard let id = model.pendingNavigationDestinationId,
              let landmark = model.landmarks.first(where: { $0.id == id }) else { return }
        destination = landmark
        if let startId = model.pendingNavigationStartId,
           let gate = model.landmarks.first(where: { $0.id == startId }) {
            start = gate
            confirmedHere = false
        }
        model.consumeNavigationDestination()
    }

    private func calculateRoute(openCamera: Bool) {
        guard let start, let destination else { return }
        Task {
            await model.calculateRoute(from: start, to: destination, accessibleOnly: accessibleOnly)
            if openCamera, model.routePlan != nil { showCamera = true }
        }
    }

    private func speak(_ instructions: [String]) {
        guard !instructions.isEmpty else { return }
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: instructions.joined(separator: ". Next, "))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        speaker.speak(utterance)
    }
}

// MARK: - Picker row

/// A settings-style row that opens a menu of landmarks, instead of an inline wheel picker.
private struct LandmarkPickerRow: View {
    let title: String
    let placeholder: String
    let systemImage: String
    let iconColor: Color
    let landmarks: [Landmark]
    @Binding var selection: Landmark?

    var body: some View {
        Menu {
            Button(placeholder) { selection = nil }
            Divider()
            ForEach(landmarks) { landmark in
                Button(landmark.name) { selection = landmark }
            }
        } label: {
            SQListRow(
                title: title,
                subtitle: selection?.name ?? placeholder,
                systemImage: systemImage,
                iconColor: iconColor,
                accessory: .chevron
            )
        }
        .accessibilityLabel("\(title) \(selection?.name ?? placeholder)")
    }
}

// MARK: - Landmark card

/// The "Cities" rail card from screenshot 03, carrying a landmark photo.
private struct LandmarkCard: View {
    let landmark: Landmark
    let imageURL: URL?
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Group {
                    if let imageURL {
                        AsyncImage(url: imageURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                placeholder
                            }
                        }
                    } else {
                        placeholder
                    }
                }
                .frame(width: 200, height: 120)
                .clipped()

                VStack(alignment: .leading, spacing: SQSpace.xs) {
                    Text(landmark.name)
                        .font(SQFont.bodyEmphasis)
                        .foregroundStyle(SQColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(landmark.coordinateKind == "outdoor" ? "Outdoor landmark" : "Indoor venue")
                        .font(SQFont.meta)
                        .foregroundStyle(SQColor.textSecondary)
                    SQMetaItem(
                        systemImage: isSelected ? "checkmark.circle.fill" : "arrow.triangle.turn.up.right.diamond",
                        text: isSelected ? "Selected destination" : "Navigate here"
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SQSpace.md)
            }
            .frame(width: 200, alignment: .leading)
            .background(SQColor.surface, in: RoundedRectangle(cornerRadius: SQRadius.chip, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: SQRadius.chip, style: .continuous)
                    .stroke(isSelected ? SQColor.ink.opacity(0.4) : SQColor.separator, lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var placeholder: some View {
        ZStack {
            SQColor.lime.opacity(0.22)
            Image(systemName: "building.2.fill")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(SQColor.textSecondary)
        }
    }
}

// MARK: - Route map

private struct RouteMap: View {
    let nodes: [RouteNode]
    let floorPlans: [UUID: FloorPlan]
    let floorPlanURLs: [UUID: URL]

    private var coordinates: [CLLocationCoordinate2D] {
        nodes.compactMap { node in
            guard let latitude = node.latitude, let longitude = node.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        if let floorId = nodes.compactMap(\.floorId).first,
           let floor = floorPlans[floorId],
           let url = floorPlanURLs[floorId] {
            FloorRouteMap(floor: floor, url: url, nodes: nodes.filter { $0.floorId == floorId })
        } else if coordinates.isEmpty {
            ZStack {
                SQColor.surfaceAlt
                SQEmptyState(
                    message: "The published floor image could not be loaded. Continue with the stored text and voice steps.",
                    systemImage: "building.2"
                )
                .padding(SQSpace.lg)
            }
        } else {
            let center = coordinates[coordinates.count / 2]
            Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 180, longitudinalMeters: 180))) {
                MapPolyline(coordinates: coordinates).stroke(SQColor.ink, lineWidth: 6)
                ForEach(Array(coordinates.enumerated()), id: \.offset) { index, coordinate in
                    Marker(
                        index == 0 ? "Start" : (index == coordinates.count - 1 ? "Destination" : "Step \(index)"),
                        coordinate: coordinate
                    )
                }
            }
            .mapStyle(.standard)
        }
    }
}

private struct FloorRouteMap: View {
    let floor: FloorPlan
    let url: URL
    let nodes: [RouteNode]

    var body: some View {
        GeometryReader { proxy in
            let imageRatio = CGFloat(floor.imageWidthPixels) / CGFloat(floor.imageHeightPixels)
            let boxRatio = proxy.size.width / proxy.size.height
            let size = boxRatio > imageRatio
                ? CGSize(width: proxy.size.height * imageRatio, height: proxy.size.height)
                : CGSize(width: proxy.size.width, height: proxy.size.width / imageRatio)
            let origin = CGPoint(x: (proxy.size.width - size.width) / 2, y: (proxy.size.height - size.height) / 2)

            ZStack {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFit()
                } placeholder: {
                    ZStack { SQColor.surfaceAlt; ProgressView().controlSize(.small) }
                }
                Canvas { context, _ in
                    var path = Path()
                    for (index, node) in nodes.enumerated() {
                        guard let x = node.xPixels, let y = node.yPixels else { continue }
                        let point = CGPoint(
                            x: origin.x + CGFloat(x) / CGFloat(floor.imageWidthPixels) * size.width,
                            y: origin.y + CGFloat(y) / CGFloat(floor.imageHeightPixels) * size.height
                        )
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                    context.stroke(
                        path,
                        with: .color(SQColor.ink),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                    )
                }
            }
            .accessibilityLabel("Route on \(floor.name) floor plan")
        }
    }
}
