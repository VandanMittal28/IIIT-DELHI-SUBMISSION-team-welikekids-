// Stand-ins that let the iOS app's SwiftUI sources be type-checked against the macOS SDK.
//
// Why this exists: there is no Xcode on the build machine for this branch, so `xcodebuild`
// and the iOS Simulator are unavailable (see PLAN.md). `swiftc -typecheck` against the macOS
// SDK is the strongest verification left, but the app uses iOS-only API. Each shim below is a
// no-op or a minimal re-declaration with the *same signature* as the real iOS API, so a
// mismatched argument label, a wrong type or a missing member still fails the check.
//
// A shim can hide a genuine iOS-only problem (an API that exists with a different signature on
// iOS, or availability), so this harness proves "the code is internally consistent", not "the
// code builds for iOS". It is not part of the app target.

import CoreGraphics
import SwiftUI

#if os(macOS)

// MARK: - UIKit stand-ins

typealias UIImage = NSImage

extension NSImage {
    convenience init?(data: Data, scale: CGFloat) { self.init(data: data) }
    convenience init(cgImage: CGImage) { self.init(cgImage: cgImage, size: .zero) }
    func jpegData(compressionQuality: CGFloat) -> Data? { nil }
}

extension Image {
    init(uiImage: NSImage) { self.init(nsImage: uiImage) }
}

enum UIApplication {
    static let shared = UIApplicationStub()
    struct UIApplicationStub {
        func registerForRemoteNotifications() {}
    }
}

// MARK: - iOS-only View modifiers

enum NavigationBarItem { enum TitleDisplayMode { case inline, large, automatic } }

enum TextInputAutocapitalization {
    case never, words, sentences, characters
}

enum UIKeyboardType { case `default`, decimalPad, numberPad, emailAddress, URL }
typealias UIKeyboardTypeAlias = UIKeyboardType

extension View {
    func navigationBarTitleDisplayMode(_ mode: NavigationBarItem.TitleDisplayMode) -> some View { self }
    func textInputAutocapitalization(_ value: TextInputAutocapitalization?) -> some View { self }
    func keyboardType(_ type: UIKeyboardType) -> some View { self }
    func fullScreenCover<Content: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss, content: content)
    }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
    func toolbarBackground<S: ShapeStyle>(_ style: S, for bars: ToolbarPlacementStub...) -> some View { self }
    func persistentSystemOverlays(_ visibility: Visibility) -> some View { self }
    func scrollBounceBehavior(_ behavior: ScrollBounceBehaviorStub, axes: Axis.Set = .vertical) -> some View { self }
}

enum ToolbarPlacementStub { case navigationBar, tabBar, bottomBar }
enum ScrollBounceBehaviorStub { case automatic, always, basedOnSize }

// Placements that only exist on iOS.
extension ToolbarItemPlacement {
    static var topBarLeading: ToolbarItemPlacement { .automatic }
    static var topBarTrailing: ToolbarItemPlacement { .automatic }
}

// MARK: - PhotosUI

struct PhotosPickerItem: Equatable, Hashable {
    func loadTransferable<T>(type: T.Type) async throws -> T? { nil }
}

struct PhotosPicker<Label: View>: View {
    init(selection: Binding<PhotosPickerItem?>, matching filter: PHPickerFilterStub? = nil, @ViewBuilder label: () -> Label) {
        self.label = label()
    }
    var label: Label
    var body: some View { label }
}

enum PHPickerFilterStub { case images, videos }

// MARK: - Notifications

enum UNAuthorizationOptionsStub { case alert, badge, sound }

// MARK: - CameraGuidanceView.swift

// That file is excluded from the typecheck because ARKit and UIViewRepresentable have no
// macOS equivalent. These stand-ins keep its call sites in NavigateView honest: the
// initialiser signatures must match the real ones.

struct CameraGuidanceView: View {
    let steps: [RouteCameraStep]
    let confirmedFacingDegrees: Double?
    let simulationMode: Bool
    var body: some View { EmptyView() }
}

struct CameraSimulationView: View {
    let plan: RoutePlan
    let floorPlans: [UUID: FloorPlan]
    let destination: String
    let accessibleRoute: Bool
    var body: some View { EmptyView() }
}

#endif
