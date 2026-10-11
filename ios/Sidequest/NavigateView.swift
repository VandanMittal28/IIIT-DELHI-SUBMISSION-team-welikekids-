import ARKit
import AVFoundation
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
                    } else { routeBuilder }
                }
            }
            .navigationTitle("Navigate")
            .task { if model.landmarks.isEmpty { await model.reloadLandmarks() };applyPreparedDestination() }
            .onChange(of:model.pendingNavigationDestinationId){applyPreparedDestination()}
            .refreshable { await model.reloadLandmarks() }
        }
    }

    private func applyPreparedDestination(){guard let id=model.pendingNavigationDestinationId,let landmark=model.landmarks.first(where:{$0.id==id})else{return};destination=landmark;model.consumeNavigationDestination()}

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
                    Text(start.facingInstruction ?? "Match the landmark around you, then face toward the route before confirming.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("I’m here — this matches") { confirmedHere = true }
                    if confirmedHere { Label("Landmark confirmed; orientation is still approximate.", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
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
            Button(plan.physicalValidationComplete ? "Start tracked camera guidance" : "Camera guidance needs validation") { showCamera = true }
                .disabled(!plan.physicalValidationComplete)
        }
        Section {
            Button("I’m lost — realign") { confirmedHere = false; model.clearRoute() }
                .foregroundStyle(.red)
            Text("Return to a known landmark and confirm it again. Sidequest does not infer precise indoor position from “I’m here.”")
                .font(.footnote).foregroundStyle(.secondary)
        }
        .fullScreenCover(isPresented: $showCamera) { CameraGuidanceView(instructions: plan.edges.map(\.instruction)) }
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
            Map { MapPolyline(coordinates: coordinates).stroke(.blue, lineWidth: 6) }
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
    let instructions: [String]
    @State private var permission: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var trackingMessage = "Move your phone slowly while tracking starts."

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if permission == .authorized {
                AnchoredARPreview(trackingMessage:$trackingMessage).ignoresSafeArea()
                VStack { Text(trackingMessage).font(.footnote).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(.top,60); Spacer(); Text(instructions.first ?? "Follow the published route.").padding().background(.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 16)).padding() }
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
    @Binding var trackingMessage:String
    func makeCoordinator()->Coordinator{Coordinator(message:$trackingMessage)}
    func makeUIView(context: Context) -> ARSCNView {
        let view = ARSCNView()
        view.session.delegate=context.coordinator
        view.automaticallyUpdatesLighting = true
        let configuration = ARWorldTrackingConfiguration()
        configuration.worldAlignment = .gravityAndHeading
        view.session.run(configuration)
        let arrow = SCNNode(geometry: SCNCone(topRadius: 0, bottomRadius: 0.18, height: 0.5))
        arrow.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
        arrow.eulerAngles.x = -.pi / 2
        arrow.position = SCNVector3(0, -0.25, -1.5)
        view.scene.rootNode.addChildNode(arrow)
        return view
    }
    func updateUIView(_ uiView: ARSCNView, context: Context) {}
    static func dismantleUIView(_ uiView: ARSCNView, coordinator: Coordinator) { uiView.session.pause() }
    @MainActor final class Coordinator:NSObject,@preconcurrency ARSessionDelegate{
        @Binding var message:String
        init(message:Binding<String>){_message=message}
        func session(_ session:ARSession,cameraDidChangeTrackingState camera:ARCamera){switch camera.trackingState{case .normal:message="Tracking aligned to the confirmed landmark direction.";case .notAvailable:message="Tracking unavailable — return to map guidance.";case .limited(let reason):message="Tracking limited (\(String(describing:reason))). Move slowly or return to the landmark."}}
        func sessionWasInterrupted(_ session:ARSession){message="Tracking interrupted — use map or voice until it recovers."}
    }
}
