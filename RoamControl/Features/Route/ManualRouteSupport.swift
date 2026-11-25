import MapKit
import SwiftUI

/// Toolbar button that opens the route menu (draw / import GPX).
struct ManualRouteMenuButton: View {
    let builder: ManualRouteBuilder
    let isDisabled: Bool

    var body: some View {
        Menu {
            Button {
                builder.startEditing()
            } label: {
                Label("Draw Route", systemImage: "pencil.and.scribble")
            }

            Button {
                builder.isShowingImporter = true
            } label: {
                Label("Import GPX…", systemImage: "square.and.arrow.down")
            }
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(builder.isActive ? Color.orange : Color.primary)
                .frame(width: 36, height: 36)
                .background(.regularMaterial, in: Circle())
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
                .frame(width: 44, height: 44)
        }
        .disabled(isDisabled)
        .accessibilityLabel("Draw or import a route")
    }
}

private struct ManualRouteSupportModifier: ViewModifier {
    let builder: ManualRouteBuilder
    let simulation: WalkingSimulationController
    let onFit: (MKMapRect) -> Void
    let onActivate: () -> Void

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: Binding(
                    get: { builder.isShowingImporter },
                    set: { builder.isShowingImporter = $0 }
                ),
                allowedContentTypes: ManualRouteBuilder.gpxContentTypes
            ) { result in
                guard !simulation.locksDestination else { return }
                builder.importGPX(result, simulation: simulation)
            }
            .alert(
                "Route",
                isPresented: Binding(
                    get: { builder.message != nil && !builder.isEditing },
                    set: { if !$0 { builder.message = nil } }
                ),
                actions: { Button("OK", role: .cancel) {} },
                message: { Text(builder.message ?? "") }
            )
            .onChange(of: builder.fitToken) { _, _ in
                onFit(builder.fitRect)
            }
            .onChange(of: builder.isActive) { _, isActive in
                if isActive { onActivate() }
            }
    }
}

extension View {
    /// Wires GPX import, error alerts, camera fitting and planner hand-off for the manual route builder.
    func manualRouteSupport(
        _ builder: ManualRouteBuilder,
        simulation: WalkingSimulationController,
        onFit: @escaping (MKMapRect) -> Void,
        onActivate: @escaping () -> Void
    ) -> some View {
        modifier(ManualRouteSupportModifier(
            builder: builder,
            simulation: simulation,
            onFit: onFit,
            onActivate: onActivate
        ))
    }
}
