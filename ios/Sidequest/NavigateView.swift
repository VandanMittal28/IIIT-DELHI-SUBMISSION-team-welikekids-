import ARKit
import AVFoundation
import CoreLocation
import MapKit
import SwiftUI

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
            Group {
                switch model.navigationState {
                case .idle where model.landmarks.isEmpty,
                     .loading where model.landmarks.isEmpty:
                    ProgressView("Loading published campus routes…")
                case .failed(let message) where model.landmarks.isEmpty:
                    ContentUnavailableView("Routes unavailable", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text(message))
                default:
                    if model.landmarks.isEmpty {
                        ContentUnavailableView("No published landmarks", systemImage: "mappin.slash", description: Text("A college administrator must publish validated campus data before navigation can begin."))
                    } else {
                        exploreContent
                    }
                }
            }
            .navigationTitle("Navigate")
            .task { if model.landmarks.isEmpty { await model.reloadLandmarks() };applyPreparedDestination() }
            .onChange(of:model.pendingNavigationDestinationId){applyPreparedDestination()}
            .onChange(of: destination) { model.clearRoute() }
            .onChange(of: accessibleOnly) { model.clearRoute() }
            .refreshable { await model.reloadLandmarks() }
            .fullScreenCover(isPresented: $showCamera) {
                if let plan = model.routePlan {
                    let steps = plan.cameraSteps(floorPlans: model.floorPlans)
                    if !plan.physicalValidationComplete {
                        CameraSimulationView(plan: plan, floorPlans: model.floorPlans, destination: destination?.name ?? "Destination", accessibleRoute: accessibleOnly)
                    } else {
                        CameraGuidanceView(steps: steps, confirmedFacingDegrees: start?.facingDegrees, simulationMode: false)
                    }
                } else {
                    ContentUnavailableView("Route unavailable", systemImage: "point.topleft.down.to.point.bottomright.curvepath", description: Text("Calculate the route again to open camera guidance."))
                }
            }
        }
    }

    private func applyPreparedDestination(){guard let id=model.pendingNavigationDestinationId,let landmark=model.landmarks.first(where:{$0.id==id})else{return};destination=landmark;model.consumeNavigationDestination()}

    private var exploreRegion: MKCoordinateRegion {
        let points = model.landmarks.compactMap { landmark -> CLLocationCoordinate2D? in
            guard let latitude = landmark.latitude, let longitude = landmark.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard !points.isEmpty else {
            if let campus = model.campuses.first {
                return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: campus.latitude, longitude: campus.longitude), latitudinalMeters: 500, longitudinalMeters: 500)
            }
            return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 28.5458, longitude: 77.2732), latitudinalMeters: 500, longitudinalMeters: 500)
        }
        let latitude = points.map(\.latitude).reduce(0, +) / Double(points.count)
        let longitude = points.map(\.longitude).reduce(0, +) / Double(points.count)
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), latitudinalMeters: 500, longitudinalMeters: 500)
    }

    private var exploreContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explore IIIT Delhi").font(.title2.bold())
                    Text("Choose where you are, choose where you’re going, then follow the compass-guided camera preview.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 12) {
                    Label("Where are you?", systemImage: "location.circle.fill").font(.headline)
                    Picker("I’m at", selection: $start) {
                        Text("Select your current landmark").tag(nil as Landmark?)
                        ForEach(model.landmarks) { Text($0.name).tag(Optional($0)) }
                    }
                    .onChange(of: start) { confirmedHere = false; model.clearRoute() }
                    if let start {
                        if let photo = model.landmarkPhotoURLs[start.id] {
                            AsyncImage(url: photo) { image in image.resizable().scaledToFill() } placeholder: { ProgressView() }
                                .frame(height: 125).frame(maxWidth: .infinity).clipped().clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        Button(confirmedHere ? "Starting landmark confirmed ✓" : "I’m here — confirm this landmark") { confirmedHere = true }
                            .buttonStyle(.bordered)
                    }
                    Label("Where do you want to go?", systemImage: "mappin.and.ellipse").font(.headline).padding(.top, 4)
                    Picker("Destination", selection: $destination) {
                        Text("Select a destination").tag(nil as Landmark?)
                        ForEach(model.landmarks.filter { $0.id != start?.id }) { Text($0.name).tag(Optional($0)) }
                    }
                    Toggle("Accessible route", isOn: $accessibleOnly)
                    Button {
                        guard let start, let destination else { return }
                        Task {
                            await model.calculateRoute(from: start, to: destination, accessibleOnly: accessibleOnly)
                            if model.routePlan != nil { showCamera = true }
                        }
                    } label: {
                        Label("Preview camera simulation demo", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(start == nil || destination == nil || !confirmedHere || start == destination)
                    if !confirmedHere {
                        Text("Confirm where you are to enable the route preview.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color.sidequestMist, in: RoundedRectangle(cornerRadius: 18))

                if case .failed(let message) = model.navigationState {
                    Label(message, systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(.red)
                    Button("Try route again") {
                        guard let start, let destination else { return }
                        Task {
                            await model.calculateRoute(from: start, to: destination, accessibleOnly: accessibleOnly)
                            if model.routePlan != nil { showCamera = true }
                        }
                    }
                }

                if let plan = model.routePlan { routePreview(plan) }

                Map(initialPosition: .region(exploreRegion)) {
                    ForEach(model.landmarks) { landmark in
                        if let latitude = landmark.latitude, let longitude = landmark.longitude {
                            Annotation(landmark.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                                Button {
                                    destination = landmark
                                    model.clearRoute()
                                } label: {
                                    Image(systemName: destination?.id == landmark.id ? "mappin.circle.fill" : "mappin.circle")
                                        .font(.title2).foregroundStyle(Color.sidequestInk).padding(4)
                                        .background(.white, in: Circle())
                                }
                                .accessibilityLabel("Explore \(landmark.name)")
                            }
                        }
                    }
                }
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(alignment: .topLeading) {
                    Label("Tap a pin to choose a destination", systemImage: "hand.tap")
                        .font(.caption.bold()).padding(9).background(.ultraThinMaterial, in: Capsule()).padding(10)
                }

                HStack {
                    Text("Nearby on campus").font(.headline)
                    Spacer()
                    Text("\(model.landmarks.count) places").font(.caption).foregroundStyle(.secondary)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(model.landmarks) { landmark in landmarkExploreCard(landmark) }
                    }
                }

            }
            .padding()
        }
    }

    @ViewBuilder private func landmarkExploreCard(_ landmark: Landmark) -> some View {
        Button {
            destination = landmark
            model.clearRoute()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                if let url = model.landmarkPhotoURLs[landmark.id] {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.sidequestLime.opacity(0.22) }
                        .frame(width: 190, height: 105).clipped()
                } else {
                    ZStack { Color.sidequestLime.opacity(0.22); Image(systemName: "building.2.fill").font(.largeTitle).foregroundStyle(Color.sidequestInk) }
                        .frame(width: 190, height: 105)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(landmark.name).font(.subheadline.bold()).lineLimit(2)
                    Text(landmark.coordinateKind == "outdoor" ? "Outdoor landmark" : "Indoor venue")
                        .font(.caption).foregroundStyle(.secondary)
                    Label("Navigate here", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption.bold()).foregroundStyle(Color.sidequestInk)
                }
                .padding(.horizontal, 10).padding(.bottom, 10)
            }
            .frame(width: 190, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        }
        .buttonStyle(.plain)
    }

    private func routePreview(_ plan: RoutePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Route preview", systemImage: "point.topleft.down.to.point.bottomright.curvepath").font(.headline)
            Text("\(start?.name ?? "Starting landmark") → \(destination?.name ?? "Destination")")
                .font(.subheadline)
            Label(accessibleOnly ? "Step-free route · lift where mapped" : "Standard campus route · stairs where mapped",
                  systemImage: accessibleOnly ? "figure.roll" : "figure.walk")
                .font(.caption).foregroundStyle(.secondary)
            Text("Walking distance · \(Int(plan.totalDistanceMeters.rounded())) m")
                .font(.title3.bold())
            if !plan.physicalValidationComplete {
                Text("Demo route from the published campus graph · not physically validated")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(Array(plan.edges.enumerated()), id: \.element.id) { index, edge in
                HStack(alignment: .top, spacing: 8) {
                    Text("\(index + 1)").font(.caption.bold()).frame(width: 22, height: 22).background(Color.sidequestLime).clipShape(Circle())
                    VStack(alignment: .leading) {
                        Text(edge.instruction).font(.subheadline)
                        Text("\(Int(edge.distanceMeters.rounded())) m walking · \(edge.kind)").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Button("Preview camera simulation demo") { showCamera = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.sidequestLime.opacity(0.22), in: RoundedRectangle(cornerRadius: 18))
    }

    private var routeBuilder: some View {
        Form {
            Section("Start with a landmark") {
                Picker("I’m at", selection: $start) {
                    Text("Choose a landmark").tag(nil as Landmark?)
                    ForEach(model.landmarks) { Text($0.name).tag(Optional($0)) }
                }
                if let start {
                    if let photoURL=model.landmarkPhotoURLs[start.id] {
                        AsyncImage(url:photoURL) { image in image.resizable().scaledToFit() } placeholder: { ProgressView().frame(maxWidth:.infinity,minHeight:140) }
                            .frame(maxHeight:240).frame(maxWidth:.infinity).clipShape(RoundedRectangle(cornerRadius:14))
                            .accessibilityLabel("Reference photo for \(start.name)")
                    }
                    if let facingDegrees = start.facingDegrees {
                        Text("\(start.facingInstruction ?? "Face the stored reference direction.") Stored reference: \(Int(facingDegrees.rounded()))°.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("Match the landmark around you before confirming. This landmark has no facing reference, so camera arrows will stay disabled.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("I’m here and facing this direction") { confirmedHere = true }
                    if confirmedHere { Label("Landmark and facing direction confirmed. Tracking can still drift; use the map if alignment looks wrong.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            Section("Destination") {
                Picker("Go to", selection: $destination) {
                    Text("Choose a destination").tag(nil as Landmark?)
                    ForEach(model.landmarks) { Text($0.name).tag(Optional($0)) }
                }
                Toggle("Accessible route only", isOn: $accessibleOnly)
                Button("Calculate from published graph") {
                    guard let start, let destination else { return }
                    Task { await model.calculateRoute(from: start, to: destination, accessibleOnly: accessibleOnly) }
                }.disabled(!confirmedHere || start == nil || destination == nil || start == destination)
            }
            if case .failed(let message) = model.navigationState {
                Section { Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red) }
            }
            if let plan = model.routePlan { route(plan) }
        }
        .onChange(of: start) { confirmedHere = false; model.clearRoute() }
    }

    @ViewBuilder private func route(_ plan: RoutePlan) -> some View {
        let cameraSteps = plan.cameraSteps(floorPlans: model.floorPlans)
        let cameraReady = plan.physicalValidationComplete && start?.facingDegrees != nil && cameraSteps.contains { $0.bearingDegrees != nil }
        let simulationReady = !plan.physicalValidationComplete && confirmedHere && start?.facingDegrees != nil && !cameraSteps.isEmpty
        Section("Route · \(Int(plan.totalDistanceMeters.rounded())) m") {
            if !plan.physicalValidationComplete {
                Label("This route has not been physically validated. Camera arrows are disabled; use map, text, or voice guidance.", systemImage: "exclamationmark.shield")
                    .font(.footnote).foregroundStyle(.orange)
            }
            RouteMap(nodes: plan.nodes, floorPlans: model.floorPlans, floorPlanURLs: model.floorPlanURLs).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
            if plan.nodes.contains(where: { node in
                node.coordinateKind == "indoor_floor" && (node.floorId.map { model.floorPlans[$0] == nil } ?? true)
            }) {
                Label("Indoor floor plan not supplied yet. Building B indoor directions are a text-only simulation.", systemImage: "building.2.crop.circle")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(Array(plan.edges.enumerated()), id: \.element.id) { index, edge in
                HStack(alignment: .top) {
                    Text("\(index + 1)").font(.caption.bold()).frame(width: 24, height: 24).background(Color.sidequestLime).clipShape(Circle())
                    VStack(alignment: .leading) { Text(edge.instruction); Text("\(Int(edge.distanceMeters.rounded())) m · \(edge.kind)").font(.caption).foregroundStyle(.secondary) }
                }
            }
            Button("Speak directions") { speak(plan.edges.map(\.instruction)) }
            if plan.physicalValidationComplete && !cameraReady {
                Label("Camera arrows need a stored facing direction and route geometry. Map, text, and voice remain available.", systemImage: "viewfinder.circle")
                    .font(.footnote).foregroundStyle(.orange)
            }
            if simulationReady {
                Button("Preview camera simulation (demo)") { showCamera = true }
                    .buttonStyle(.bordered)
            } else {
                Button(cameraReady ? "Start aligned camera guidance" : "Camera guidance needs alignment data") { showCamera = true }
                    .disabled(!cameraReady)
            }
        }
        Section {
            Button("I’m lost — realign") { confirmedHere = false; model.clearRoute() }
                .foregroundStyle(.red)
            Text("Return to a known landmark and confirm it again. Sidequest does not infer precise indoor position from “I’m here.”")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }

    private func speak(_ instructions: [String]) {
        speaker.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: instructions.joined(separator: ". Next, "))
        utterance.voice = AVSpeechSynthesisVoice(language: "en-IN")
        speaker.speak(utterance)
    }
}

private struct RouteMap: View {
    let nodes: [RouteNode]
    let floorPlans: [UUID: FloorPlan]
    let floorPlanURLs: [UUID: URL]
    var coordinates: [CLLocationCoordinate2D] { nodes.compactMap { node in
        guard let lat = node.latitude, let lon = node.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    } }
    var body: some View {
        if let floorId = nodes.compactMap(\.floorId).first, let floor=floorPlans[floorId], let url=floorPlanURLs[floorId] {
            FloorRouteMap(floor:floor,url:url,nodes:nodes.filter{$0.floorId==floorId})
        } else if coordinates.isEmpty {
            ContentUnavailableView("Indoor plan unavailable", systemImage: "building.2", description: Text("The published floor image could not be loaded. Continue with the stored text and voice steps."))
        } else {
            let center = coordinates[coordinates.count / 2]
            Map(initialPosition: .region(MKCoordinateRegion(center: center, latitudinalMeters: 180, longitudinalMeters: 180))) {
                MapPolyline(coordinates: coordinates).stroke(.blue, lineWidth: 6)
                ForEach(Array(coordinates.enumerated()), id: \.offset) { index, coordinate in
                    Marker(index == 0 ? "Start" : (index == coordinates.count - 1 ? "Destination" : "Step \(index)"), coordinate: coordinate)
                }
            }
            .mapStyle(.standard)
        }
    }
}

private struct FloorRouteMap:View{
    let floor:FloorPlan;let url:URL;let nodes:[RouteNode]
    var body:some View{GeometryReader{proxy in
        let imageRatio=CGFloat(floor.imageWidthPixels)/CGFloat(floor.imageHeightPixels);let boxRatio=proxy.size.width/proxy.size.height
        let size=boxRatio>imageRatio ? CGSize(width:proxy.size.height*imageRatio,height:proxy.size.height):CGSize(width:proxy.size.width,height:proxy.size.width/imageRatio)
        let origin=CGPoint(x:(proxy.size.width-size.width)/2,y:(proxy.size.height-size.height)/2)
        ZStack{AsyncImage(url:url){image in image.resizable().scaledToFit()}placeholder:{ProgressView()}
            Canvas{context,_ in var path=Path();for(index,node) in nodes.enumerated(){guard let x=node.xPixels,let y=node.yPixels else{continue};let point=CGPoint(x:origin.x+CGFloat(x)/CGFloat(floor.imageWidthPixels)*size.width,y:origin.y+CGFloat(y)/CGFloat(floor.imageHeightPixels)*size.height);if index==0{path.move(to:point)}else{path.addLine(to:point)}};context.stroke(path,with:.color(.blue),style:StrokeStyle(lineWidth:6,lineCap:.round,lineJoin:.round))}
        }.accessibilityLabel("Route on \(floor.name) floor plan")
    }}
}

private struct CameraGuidanceView: View {
    @Environment(\.dismiss) private var dismiss
    let steps: [RouteCameraStep]
    let confirmedFacingDegrees: Double?
    let simulationMode: Bool
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var trackingMessage = "Move your phone slowly while tracking starts."
    @State private var stepIndex = 0

    private var step: RouteCameraStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permission == .authorized, let step {
                if ARWorldTrackingConfiguration.isSupported,
                   let confirmedFacingDegrees,
                   let alignedBearing = step.bearingRelativeToConfirmedFacing(confirmedFacingDegrees) {
                    AnchoredARPreview(bearingDegrees: alignedBearing, stepID: step.id, trackingMessage: $trackingMessage).ignoresSafeArea()
                } else if simulationMode {
                    SimulatedCameraSurface(step: step)
                        .ignoresSafeArea()
                }
                if simulationMode {
                    SimulatedArrowOverlay()
                }
                    VStack {
                        Label(step.bearingDegrees == nil ? "Spatial arrow unavailable for this transition." : (simulationMode ? "DEMO · simulated live camera guidance" : "Live camera guidance · turn your phone to follow the anchored arrow"), systemImage: step.bearingDegrees == nil ? "exclamationmark.triangle" : "location.north.line.fill")
                            .font(.footnote).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(.top, 60)
                        if simulationMode {
                            Text("Simulation only — this route is not physically validated. Use the map for real navigation.")
                                .font(.caption.bold()).foregroundStyle(.orange).padding(8).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
                        }
                    Spacer()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Step \(stepIndex + 1) of \(steps.count)").font(.caption.bold())
                        Text(step.instruction).font(.headline)
                        Text("\(Int(step.distanceMeters.rounded())) m · \(step.kind)").font(.caption)
                        if step.bearingDegrees == nil {
                            Label("No reliable spatial bearing for this transition. Follow the text, map, or voice instruction.", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(.caption)
                        } else if let confirmedFacingDegrees {
                            Text("Aligned from the confirmed \(Int(confirmedFacingDegrees.rounded()))° landmark reference. The arrow is anchored to the stored route bearing.").font(.caption)
                        }
                        HStack {
                            Button("Previous") { stepIndex = max(0, stepIndex - 1) }.disabled(stepIndex == 0)
                            Spacer()
                            if stepIndex + 1 < steps.count { Button("Next step") { stepIndex += 1 } }
                            else { Button("Finish") { dismiss() } }
                        }
                    }
                    .padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16)).padding()
                }
            } else if permission == .denied || permission == .restricted {
                if simulationMode, let step {
                    SimulatedCameraSurface(step: step)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text("Use map, text, or voice guidance. Camera access can be changed in Settings."))
                        .foregroundStyle(.white)
                }
            } else { ProgressView("Requesting camera access…").tint(.white).foregroundStyle(.white) }
            VStack { HStack { Spacer(); Button("Done") { dismiss() }.buttonStyle(.borderedProminent).padding() }; Spacer() }
        }
        .task {
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

private struct SimulatedCameraSurface: View {
    let step: RouteCameraStep
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, Color(red: 0.08, green: 0.12, blue: 0.10)], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Image(systemName: "camera.viewfinder").font(.title).foregroundStyle(.white.opacity(0.7))
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 110, weight: .bold))
                    .foregroundStyle(Color.sidequestLime)
                    .shadow(color: .green.opacity(0.8), radius: pulse ? 20 : 8)
                    .scaleEffect(pulse ? 1.05 : 0.96)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("SIMULATED AR ARROW").font(.caption.bold()).foregroundStyle(.orange)
                Text(step.instruction).font(.headline).multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal, 24)
            }
        }
        .onAppear { pulse = true }
    }
}

private struct CameraSimulationView: View {
    @Environment(\.dismiss) private var dismiss
    let plan: RoutePlan
    let floorPlans: [UUID: FloorPlan]
    let destination: String
    let accessibleRoute: Bool
    @StateObject private var camera = CameraPreviewModel()
    @StateObject private var compass = CompassHeadingModel()
    @State private var initialHeading: CLLocationDirection?
    @State private var simulatedProgress = 0.0
    @State private var isSimulating = false

    private struct DemoStep: Identifiable {
        let id: UUID
        let instruction: String
        let distanceMeters: Double
        let kind: String
        let bearingDegrees: Double?
        let fallbackTurnDegrees: Double
    }
    private var demoSteps: [DemoStep] {
        let cameraSteps = plan.cameraSteps(floorPlans: floorPlans)
        return plan.edges.enumerated().map { index, edge in
            let words = edge.instruction.lowercased()
            let fallbackTurn = words.contains("right") ? 90.0 : (words.contains("left") ? 270.0 : 0.0)
            return DemoStep(id: edge.id, instruction: edge.instruction, distanceMeters: edge.distanceMeters,
                            kind: edge.kind, bearingDegrees: cameraSteps.indices.contains(index) ? cameraSteps[index].bearingDegrees : nil,
                            fallbackTurnDegrees: fallbackTurn)
        }
    }
    private var stepIndex: Int { min(Int(simulatedProgress * Double(max(1, demoSteps.count))), demoSteps.count) }
    private var step: DemoStep? { demoSteps.indices.contains(stepIndex) ? demoSteps[stepIndex] : nil }
    private var walkedMeters: Double { plan.totalDistanceMeters * simulatedProgress }
    private var remainingMeters: Double { plan.totalDistanceMeters * (1 - simulatedProgress) }
    private var relativeArrowDegrees: Double {
        guard let heading = compass.heading else { return step?.fallbackTurnDegrees ?? 0 }
        let cumulativeTurn = demoSteps.prefix(stepIndex + (step == nil ? 0 : 1)).reduce(0.0) { total, item in
            total + item.fallbackTurnDegrees
        }
        let baseHeading = initialHeading ?? demoSteps.first?.bearingDegrees ?? step?.bearingDegrees ?? heading
        let hasTurnInstruction = demoSteps.prefix(stepIndex + (step == nil ? 0 : 1)).contains { $0.fallbackTurnDegrees != 0 }
        let desiredHeading = hasTurnInstruction ? baseHeading + cumulativeTurn : (step?.bearingDegrees ?? baseHeading)
        let difference = (desiredHeading - heading).truncatingRemainder(dividingBy: 360)
        return difference >= 0 ? difference : difference + 360
    }

    var body: some View {
        ZStack {
            if camera.permission == .authorized, camera.isReady {
                CameraPreviewLayer(session: camera.session).ignoresSafeArea()
            } else {
                LinearGradient(colors: [Color(red: 0.03, green: 0.06, blue: 0.05), Color(red: 0.11, green: 0.17, blue: 0.13)], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 46)).foregroundStyle(.white.opacity(0.7))
                    Text(camera.permission == .denied ? "Camera access is off" : "Camera preview unavailable")
                        .font(.headline).foregroundStyle(.white)
                    Text("Compass guidance demo is still available over this preview.").font(.caption).foregroundStyle(.white.opacity(0.75))
                }
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEMO · EXPLORE GUIDANCE").font(.caption.bold()).foregroundStyle(Color.sidequestLime)
                        Text("To \(destination)").font(.headline).foregroundStyle(.white)
                    }
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(.borderedProminent)
                }
                .padding(.top, 14).padding(.horizontal)
                Spacer()
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SIMULATED LOCATION").font(.caption.bold()).foregroundStyle(Color.sidequestLime)
                        Spacer()
                        Text("\(Int(walkedMeters.rounded())) m / \(Int(plan.totalDistanceMeters.rounded())) m").font(.caption.bold())
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                            Capsule().fill(Color.sidequestLime).frame(width: max(5, geometry.size.width * simulatedProgress), height: 5)
                            Image(systemName: "location.fill").font(.caption).foregroundStyle(Color.sidequestLime)
                                .position(x: max(7, min(geometry.size.width - 7, geometry.size.width * simulatedProgress)), y: 9)
                        }
                    }
                    .frame(height: 18)
                    HStack {
                        Text(step == nil ? "Arrived" : "Step \(stepIndex + 1) of \(demoSteps.count)").font(.caption.bold())
                        Spacer()
                        Text("\(Int(remainingMeters.rounded())) m left").font(.caption.bold())
                    }
                    Text(step?.instruction ?? "You’ve arrived at \(destination)").font(.title3.bold())
                    Label(accessibleRoute ? "Step-free route · lift and accessible corridors" : "Campus route · stairs and corridors", systemImage: accessibleRoute ? "figure.roll" : "figure.walk")
                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                    if let step { Text("\(Int(step.distanceMeters.rounded())) m · \(step.kind)").font(.caption).foregroundStyle(.white.opacity(0.8)) }
                    if let heading = compass.heading {
                        Label("Phone compass \(Int(heading.rounded()))°", systemImage: "location.north.fill").font(.caption)
                    } else {
                        Label("Compass unavailable — arrow follows the route instruction", systemImage: "location.north.line").font(.caption)
                    }
                    HStack {
                        Button("Restart") { isSimulating = false; simulatedProgress = 0 }
                        Spacer()
                        if simulatedProgress >= 1 {
                            Button("Finish") { dismiss() }.buttonStyle(.borderedProminent)
                        } else {
                            Button(isSimulating ? "Simulating…" : "Simulate walking") { startSimulation() }
                                .buttonStyle(.borderedProminent).disabled(isSimulating)
                        }
                    }
                }
                .foregroundStyle(.white).padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18)).padding()
            }
            GeometryReader { geometry in
                Image(systemName: "arrow.up")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(Color.sidequestLime)
                    .shadow(color: .black.opacity(0.85), radius: 9)
                    .rotationEffect(.degrees(relativeArrowDegrees))
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .accessibilityLabel("Compass direction arrow")
                    .allowsHitTesting(false)
            }
        }
        .task {
            await camera.requestAndStart()
            compass.start()
        }
        .onChange(of: compass.heading) { _, newHeading in
            if initialHeading == nil { initialHeading = newHeading }
        }
        .onDisappear { isSimulating = false; camera.stop(); compass.stop() }
    }

    private func startSimulation() {
        guard !isSimulating else { return }
        isSimulating = true
        Task { @MainActor in
            while simulatedProgress < 1 {
                try? await Task.sleep(for: .milliseconds(180))
                simulatedProgress = min(1, simulatedProgress + 0.02)
            }
            isSimulating = false
        }
    }
}

@MainActor private final class CameraPreviewModel: ObservableObject {
    let session = AVCaptureSession()
    @Published var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @Published var isReady = false

    func requestAndStart() async {
        if permission == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .video)
            permission = AVCaptureDevice.authorizationStatus(for: .video)
        }
        guard permission == .authorized, !isReady else { return }
        session.beginConfiguration()
        do {
            session.sessionPreset = .high
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                session.commitConfiguration(); return
            }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input) else { session.commitConfiguration(); return }
            session.addInput(input)
            session.commitConfiguration()
            session.startRunning()
            isReady = true
        } catch {
            session.commitConfiguration()
            if session.isRunning { session.stopRunning() }
            isReady = false
        }
    }

    func stop() { if session.isRunning { session.stopRunning() }; isReady = false }
}

private struct CameraPreviewLayer: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> CameraPreviewHost {
        let view = CameraPreviewHost()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }
    func updateUIView(_ uiView: CameraPreviewHost, context: Context) { uiView.previewLayer.session = session }
}

private final class CameraPreviewHost: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
}

@MainActor private final class CompassHeadingModel: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var heading: CLLocationDirection?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 2
        manager.headingOrientation = .portrait
    }
    func start() {
        guard CLLocationManager.headingAvailable() else { return }
        if manager.authorizationStatus == .notDetermined { manager.requestWhenInUseAuthorization() }
        manager.startUpdatingHeading()
    }
    func stop() { manager.stopUpdatingHeading() }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let reading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        if reading >= 0 { heading = reading }
    }
}

private struct SimulatedArrowOverlay: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 92, weight: .bold))
                .foregroundStyle(Color.sidequestLime)
                .shadow(color: .black.opacity(0.8), radius: 10)
            Text("DEMO AR ARROW").font(.caption.bold()).foregroundStyle(.orange)
            Spacer().frame(height: 170)
        }
        .allowsHitTesting(false)
    }
}

private struct AnchoredARPreview: UIViewRepresentable {
    let bearingDegrees: Double
    let stepID: UUID
    @Binding var trackingMessage:String
    func makeCoordinator()->Coordinator{Coordinator(message:$trackingMessage)}
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.delegate = context.coordinator
        view.session.delegate=context.coordinator
        view.automaticallyUpdatesLighting = true
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravity
        view.session.run(configuration)
        context.coordinator.attach(to: view)
        context.coordinator.update(bearingDegrees: bearingDegrees, stepID: stepID)
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) { context.coordinator.update(bearingDegrees: bearingDegrees, stepID: stepID) }
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) { uiView.session.pause() }
    @MainActor final class Coordinator:NSObject,@preconcurrency ARSessionDelegate,@preconcurrency ARSCNViewDelegate{
        @Binding var message:String
        private weak var view: ARSCNView?
        private var bearingDegrees: Double?
        private var stepID: UUID?
        private var routeAnchor: ARAnchor?
        init(message:Binding<String>){_message=message}
        func attach(to view: ARSCNView) { self.view = view }
        func update(bearingDegrees: Double, stepID: UUID) {
            guard self.stepID != stepID || self.bearingDegrees != bearingDegrees else { return }
            self.bearingDegrees = bearingDegrees
            self.stepID = stepID
            if let routeAnchor { view?.session.remove(anchor: routeAnchor) }
            routeAnchor = nil
            if case .normal = view?.session.currentFrame?.camera.trackingState { placeRouteAnchor() }
        }
        private func placeRouteAnchor() {
            guard routeAnchor == nil, let view, let frame = view.session.currentFrame, let bearingDegrees else { return }
            let radians = Float(bearingDegrees * .pi / 180)
            let cameraPosition = frame.camera.transform.columns.3
            var transform = simd_float4x4(simd_quatf(angle: -radians, axis: SIMD3<Float>(0, 1, 0)))
            transform.columns.3 = SIMD4<Float>(
                cameraPosition.x + sin(radians) * 1.5,
                cameraPosition.y - 0.2,
                cameraPosition.z - cos(radians) * 1.5,
                1
            )
            let anchor = ARAnchor(name: "sidequest-route-step", transform: transform)
            routeAnchor = anchor
            view.session.add(anchor: anchor)
        }
        func renderer(_ renderer: SCNSceneRenderer, nodeFor anchor: ARAnchor) -> SCNNode? {
            guard anchor.identifier == routeAnchor?.identifier else { return nil }
            let arrow = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.18, height: 0.52))
            arrow.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
            arrow.eulerAngles.x = -.pi / 2
            return arrow
        }
        func session(_ session:ARSession,cameraDidChangeTrackingState camera:ARCamera){switch camera.trackingState{case .normal:message="Tracking is stable. The arrow is anchored to the stored route bearing.";placeRouteAnchor();case .notAvailable:message="Tracking unavailable — return to map guidance.";case .limited(let reason):message="Tracking limited (\(String(describing:reason))). Move slowly or return to the landmark."}}
        func sessionWasInterrupted(_ session:ARSession){message="Tracking interrupted — use map or voice until it recovers."}
        func sessionInterruptionEnded(_ session: ARSession) { message = "Tracking resumed. Return to the confirmed landmark if the arrow has drifted."; routeAnchor = nil; placeRouteAnchor() }
    }
}
