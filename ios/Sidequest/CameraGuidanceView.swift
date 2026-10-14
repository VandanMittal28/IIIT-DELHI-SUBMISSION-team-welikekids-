import ARKit
import AVFoundation
import CoreLocation
import SwiftUI

// Camera and ARKit route guidance, split out of NavigateView.swift during the Luma redesign.
// Unchanged in behaviour: only the surrounding chrome was restyled. Kept in its own file so
// the rest of the navigation UI can be type-checked without ARKit (see tools/typecheck/run.sh).

struct CameraGuidanceView: View {
    /// Near-black tint so shared components (`SQCircleButton`, `SQEmptyState`, the buttons)
    /// render in their light-on-dark form over the camera feed.
    static let overlayTint = SQTint(red: 0.05, green: 0.06, blue: 0.06)

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
                            .font(SQFont.meta).padding(8).background(.ultraThinMaterial).clipShape(Capsule()).padding(.top, 60)
                        if simulationMode {
                            Text("Simulation only — this route is not physically validated. Use the map for real navigation.")
                                .font(SQFont.badge).foregroundStyle(SQColor.warning).padding(8).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: SQRadius.thumb, style: .continuous))
                        }
                    Spacer()
                    VStack(alignment: .leading, spacing: SQSpace.sm) {
                        Text("Step \(stepIndex + 1) of \(steps.count)")
                            .font(SQFont.badge)
                            .foregroundStyle(SQColor.lime)
                        Text(step.instruction).font(SQFont.rowTitle)
                        Text("\(Int(step.distanceMeters.rounded())) m · \(step.kind)").font(SQFont.meta)
                        if step.bearingDegrees == nil {
                            Label("No reliable spatial bearing for this transition. Follow the text, map, or voice instruction.", systemImage: "arrow.triangle.turn.up.right.diamond")
                                .font(SQFont.meta)
                        } else if let confirmedFacingDegrees {
                            Text("Aligned from the confirmed \(Int(confirmedFacingDegrees.rounded()))° landmark reference. The arrow is anchored to the stored route bearing.").font(SQFont.meta)
                        }
                        HStack(spacing: SQSpace.md) {
                            SQSecondaryButton(title: "Previous", systemImage: "chevron.left", isEnabled: stepIndex > 0) {
                                stepIndex = max(0, stepIndex - 1)
                            }
                            if stepIndex + 1 < steps.count {
                                SQPrimaryButton(title: "Next step", systemImage: "chevron.right") { stepIndex += 1 }
                            } else {
                                SQPrimaryButton(title: "Finish", systemImage: "checkmark") { dismiss() }
                            }
                        }
                        .padding(.top, SQSpace.xs)
                    }
                    .foregroundStyle(.white)
                    .padding(SQSpace.xl)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous))
                    .padding(SQSpace.margin)
                }
            } else if permission == .denied || permission == .restricted {
                if simulationMode, let step {
                    SimulatedCameraSurface(step: step)
                        .ignoresSafeArea()
                } else {
                    SQEmptyState(
                        message: "Camera unavailable. Use map, text, or voice guidance. Camera access can be changed in Settings.",
                        systemImage: "camera.fill"
                    )
                    .padding(.horizontal, SQSpace.margin)
                }
            } else {
                ProgressView("Requesting camera access…")
                    .tint(.white)
                    .font(SQFont.body)
                    .foregroundStyle(.white)
            }
            VStack {
                HStack {
                    Spacer()
                    SQCircleButton(systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Close camera guidance")
                }
                .padding(.horizontal, SQSpace.margin)
                .padding(.top, SQSpace.sm)
                Spacer()
            }
        }
        .environment(\.sqTint, Self.overlayTint)
        .task {
            if permission == .notDetermined {
                _ = await AVCaptureDevice.requestAccess(for: .video)
                permission = AVCaptureDevice.authorizationStatus(for: .video)
            }
        }
    }
}

struct SimulatedCameraSurface: View {
    let step: RouteCameraStep
    @State private var pulse = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [.black, SQColor.ink], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 18) {
                Image(systemName: "camera.viewfinder").font(.title).foregroundStyle(.white.opacity(0.7))
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 110, weight: .bold))
                    .foregroundStyle(SQColor.lime)
                    .shadow(color: .green.opacity(0.8), radius: pulse ? 20 : 8)
                    .scaleEffect(pulse ? 1.05 : 0.96)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
                Text("SIMULATED AR ARROW").font(SQFont.badge).foregroundStyle(SQColor.warning)
                Text(step.instruction).font(SQFont.rowTitle).multilineTextAlignment(.center).foregroundStyle(.white).padding(.horizontal, 24)
            }
        }
        .onAppear { pulse = true }
    }
}

struct CameraSimulationView: View {
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
                LinearGradient(colors: [.black, SQColor.ink], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
                VStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 46)).foregroundStyle(.white.opacity(0.7))
                    Text(camera.permission == .denied ? "Camera access is off" : "Camera preview unavailable")
                        .font(SQFont.rowTitle).foregroundStyle(.white)
                    Text("Compass guidance demo is still available over this preview.")
                        .font(SQFont.meta).foregroundStyle(.white.opacity(0.75))
                }
            }

            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("DEMO · EXPLORE GUIDANCE")
                            .font(SQFont.badge)
                            .foregroundStyle(SQColor.lime)
                        Text("To \(destination)")
                            .font(SQFont.rowTitle)
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }
                    Spacer(minLength: SQSpace.md)
                    SQCircleButton(systemImage: "xmark") { dismiss() }
                        .accessibilityLabel("Close guidance demo")
                }
                .padding(.top, SQSpace.sm)
                .padding(.horizontal, SQSpace.margin)
                Spacer()
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("SIMULATED LOCATION").font(SQFont.badge).foregroundStyle(SQColor.lime)
                        Spacer()
                        Text("\(Int(walkedMeters.rounded())) m / \(Int(plan.totalDistanceMeters.rounded())) m").font(SQFont.badge)
                    }
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.25)).frame(height: 5)
                            Capsule().fill(SQColor.lime).frame(width: max(5, geometry.size.width * simulatedProgress), height: 5)
                            Image(systemName: "location.fill").font(SQFont.meta).foregroundStyle(SQColor.lime)
                                .position(x: max(7, min(geometry.size.width - 7, geometry.size.width * simulatedProgress)), y: 9)
                        }
                    }
                    .frame(height: 18)
                    HStack {
                        Text(step == nil ? "Arrived" : "Step \(stepIndex + 1) of \(demoSteps.count)").font(SQFont.badge)
                        Spacer()
                        Text("\(Int(remainingMeters.rounded())) m left").font(SQFont.badge)
                    }
                    Text(step?.instruction ?? "You’ve arrived at \(destination)").font(SQFont.navTitle)
                    Label(accessibleRoute ? "Step-free route · lift and accessible corridors" : "Campus route · stairs and corridors", systemImage: accessibleRoute ? "figure.roll" : "figure.walk")
                        .font(SQFont.meta).foregroundStyle(.white.opacity(0.8))
                    if let step { Text("\(Int(step.distanceMeters.rounded())) m · \(step.kind)").font(SQFont.meta).foregroundStyle(.white.opacity(0.8)) }
                    if let heading = compass.heading {
                        Label("Phone compass \(Int(heading.rounded()))°", systemImage: "location.north.fill").font(SQFont.meta)
                    } else {
                        Label("Compass unavailable — arrow follows the route instruction", systemImage: "location.north.line").font(SQFont.meta)
                    }
                    HStack(spacing: SQSpace.md) {
                        SQSecondaryButton(title: "Restart", systemImage: "arrow.counterclockwise") {
                            isSimulating = false
                            simulatedProgress = 0
                        }
                        if simulatedProgress >= 1 {
                            SQPrimaryButton(title: "Finish", systemImage: "checkmark") { dismiss() }
                        } else {
                            SQPrimaryButton(
                                title: isSimulating ? "Simulating…" : "Simulate walking",
                                systemImage: "figure.walk",
                                isLoading: isSimulating,
                                isEnabled: !isSimulating
                            ) {
                                startSimulation()
                            }
                        }
                    }
                    .padding(.top, SQSpace.xs)
                }
                .foregroundStyle(.white)
                .padding(SQSpace.xl)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SQRadius.card, style: .continuous))
                .padding(SQSpace.margin)
            }
            GeometryReader { geometry in
                Image(systemName: "arrow.up")
                    .font(.system(size: 52, weight: .black))
                    .foregroundStyle(SQColor.lime)
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
        .environment(\.sqTint, CameraGuidanceView.overlayTint)
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

struct CameraPreviewLayer: UIViewRepresentable {
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

struct SimulatedArrowOverlay: View {
    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 92, weight: .bold))
                .foregroundStyle(SQColor.lime)
                .shadow(color: .black.opacity(0.8), radius: 10)
            Text("DEMO AR ARROW").font(SQFont.badge).foregroundStyle(SQColor.warning)
            Spacer().frame(height: 170)
        }
        .allowsHitTesting(false)
    }
}

struct AnchoredARPreview: UIViewRepresentable {
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
