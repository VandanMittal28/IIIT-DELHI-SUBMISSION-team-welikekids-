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

    private func applyPreparedDestination(){
        guard let id=model.pendingNavigationDestinationId,let landmark=model.landmarks.first(where:{$0.id==id})else{return}
        destination=landmark
        if let startId=model.pendingNavigationStartId,let gate=model.landmarks.first(where:{$0.id==startId}) { start=gate;confirmedHere=false }
        model.consumeNavigationDestination()
    }

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
                        Button(confirmedHere ? "Starting landmark confirmed ✓" : "I’m here — confirm this landmark") {
                            confirmedHere = true
                            if let destination { Task { await model.calculateRoute(from:start,to:destination,accessibleOnly:accessibleOnly) } }
                        }
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

