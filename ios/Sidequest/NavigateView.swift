import ARKit
import AVFoundation
import MapKit
import SwiftUI

struct NavigateView: View {
    @Environment(AppModel.self) private var model
    private enum NavigationMode: String, CaseIterable { case explore = "Explore", route = "Route" }
    @State private var mode: NavigationMode = .explore
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
                        VStack(spacing: 0) {
                            Picker("Navigation mode", selection: $mode) {
                                ForEach(NavigationMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.top, 8)
                            if mode == .explore { exploreContent } else { routeBuilder }
                        }
                    }
                }
            }
            .navigationTitle("Navigate")
            .task { if model.landmarks.isEmpty { await model.reloadLandmarks() };applyPreparedDestination() }
            .onChange(of:model.pendingNavigationDestinationId){applyPreparedDestination()}
            .refreshable { await model.reloadLandmarks() }
        }
    }

    private func applyPreparedDestination(){guard let id=model.pendingNavigationDestinationId,let landmark=model.landmarks.first(where:{$0.id==id})else{return};destination=landmark;mode = .route;model.consumeNavigationDestination()}

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
                    Text("Discover venues around campus, then start a verified route when you are ready.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Map(initialPosition: .region(exploreRegion)) {
                    ForEach(model.landmarks) { landmark in
                        if let latitude = landmark.latitude, let longitude = landmark.longitude {
                            Annotation(landmark.name, coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)) {
                                Button {
                                    destination = landmark
                                    mode = .route
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

                if let destination {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Selected destination", systemImage: "checkmark.circle.fill").font(.headline).foregroundStyle(Color.sidequestInk)
                        Text(destination.name).font(.title3.bold())
                        Text("Confirm your current landmark before starting the route. Sidequest will use the published graph and any current closures.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("Start route to \(destination.name)") { mode = .route }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.sidequestLime.opacity(0.28), in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
        }
    }

    @ViewBuilder private func landmarkExploreCard(_ landmark: Landmark) -> some View {
        Button {
            destination = landmark
            mode = .route
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
        Section("Route · \(Int(plan.totalDistanceMeters.rounded())) m") {
            if !plan.physicalValidationComplete {
                Label("This route has not been physically validated. Camera arrows are disabled; use map, text, or voice guidance.", systemImage: "exclamationmark.shield")
                    .font(.footnote).foregroundStyle(.orange)
            }
            RouteMap(nodes: plan.nodes, floorPlans: model.floorPlans, floorPlanURLs: model.floorPlanURLs).frame(height: 240).clipShape(RoundedRectangle(cornerRadius: 14))
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
            Button(cameraReady ? "Start aligned camera guidance" : "Camera guidance needs alignment data") { showCamera = true }
                .disabled(!cameraReady)
        }
        Section {
            Button("I’m lost — realign") { confirmedHere = false; model.clearRoute() }
                .foregroundStyle(.red)
            Text("Return to a known landmark and confirm it again. Sidequest does not infer precise indoor position from “I’m here.”")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraGuidanceView(steps: cameraSteps, confirmedFacingDegrees: start?.facingDegrees)
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
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var trackingMessage = "Move your phone slowly while tracking starts."
    @State private var stepIndex = 0

    private var step: RouteCameraStep? { steps.indices.contains(stepIndex) ? steps[stepIndex] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permission == .authorized, let step {
                if let confirmedFacingDegrees, let alignedBearing = step.bearingRelativeToConfirmedFacing(confirmedFacingDegrees) {
                    AnchoredARPreview(bearingDegrees: alignedBearing, stepID: step.id, trackingMessage: $trackingMessage).ignoresSafeArea()
                }
                VStack {
                    Text(step.bearingDegrees == nil ? "Spatial arrow unavailable for this transition." : trackingMessage).font(.footnote).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(.top, 60)
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
                ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text("Use map, text, or voice guidance. Camera access can be changed in Settings."))
                    .foregroundStyle(.white)
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
