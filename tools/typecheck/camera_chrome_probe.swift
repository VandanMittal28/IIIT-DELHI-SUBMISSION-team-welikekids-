// Mirrors every SQ component call-site introduced into CameraGuidanceView.swift, which the
// main harness cannot type-check because ARKit and CLLocationManager heading updates have no
// macOS equivalent. If a component's signature changes, this probe fails even though the
// camera file itself is never compiled here.
//
// Not part of the app target.

import SwiftUI

private struct CameraChromeProbe: View {
    static let overlayTint = SQTint(red: 0.05, green: 0.06, blue: 0.06)
    @State private var stepIndex = 0
    @State private var isSimulating = false
    @State private var simulatedProgress = 0.0
    let steps: [String]
    let dismiss: () -> Void

    var body: some View {
        ZStack {
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

            VStack(alignment: .leading, spacing: SQSpace.sm) {
                Text("Step \(stepIndex + 1) of \(steps.count)")
                    .font(SQFont.badge)
                    .foregroundStyle(SQColor.lime)
                Text("instruction").font(SQFont.rowTitle)
                Text("10 m · walkway").font(SQFont.meta)
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

            SQEmptyState(
                message: "Camera unavailable. Use map, text, or voice guidance. Camera access can be changed in Settings.",
                systemImage: "camera.fill"
            )
            .padding(.horizontal, SQSpace.margin)

            ProgressView("Requesting camera access…")
                .tint(.white)
                .font(SQFont.body)
                .foregroundStyle(.white)

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
                        isSimulating = true
                    }
                }
            }
            .padding(.top, SQSpace.xs)

            Capsule().fill(SQColor.lime).frame(height: 5)
        }
        .environment(\.sqTint, Self.overlayTint)
    }
}
