import CoreLocation
import MapKit
import SwiftUI

/// Polyline plus draggable waypoint handles. Add inside a `Map { … }` builder.
struct ManualRouteMapContent: MapContent {
    let builder: ManualRouteBuilder
    let proxy: MapProxy

    var body: some MapContent {
        if builder.displayPoints.count >= 2 {
            MapPolyline(coordinates: builder.displayPoints.map(\.coordinate))
                .stroke(.orange, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }

        if builder.showsHandles {
            ForEach(builder.handles) { handle in
                Annotation("", coordinate: handle.point.coordinate, anchor: .center) {
                    ManualRouteHandleView(builder: builder, proxy: proxy, handle: handle)
                }
            }
        } else if builder.isEditing || builder.prepared != nil {
            if let first = builder.displayPoints.first {
                Annotation("Start", coordinate: first.coordinate, anchor: .center) {
                    ManualRouteDot(colour: .green, size: 16)
                }
            }
            if builder.displayPoints.count >= 2, let last = builder.displayPoints.last {
                Annotation("End", coordinate: last.coordinate, anchor: .center) {
                    ManualRouteDot(colour: .red, size: 16)
                }
            }
        }
    }
}

struct ManualRouteDot: View {
    let colour: Color
    let size: CGFloat

    var body: some View {
        Circle()
            .fill(colour)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(.white, lineWidth: 2.5))
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
    }
}

private struct ManualRouteHandleView: View {
    let builder: ManualRouteBuilder
    let proxy: MapProxy
    let handle: ManualRouteHandle
    @State private var isDragging = false

    var body: some View {
        ManualRouteDot(colour: colour, size: isDragging ? 28 : 22)
            .frame(width: 44, height: 44)
            .contentShape(Circle())
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDragging {
                            isDragging = true
                            builder.beginDrag()
                        }
                        guard let coordinate = proxy.convert(value.location, from: .global) else { return }
                        builder.movePoint(at: handle.id, to: coordinate)
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            .accessibilityLabel(label)
    }

    private var colour: Color {
        switch handle.role {
        case .start: .green
        case .middle: .orange
        case .end: .red
        }
    }

    private var label: String {
        switch handle.role {
        case .start: "Route start point"
        case .middle: "Route point \(handle.id + 1)"
        case .end: "Route end point"
        }
    }
}

/// Transparent drawing surface that captures finger strokes while freehand mode is on.
/// Apply with `.overlay { … }` on the `Map`.
struct ManualRouteFreehandLayer: View {
    let builder: ManualRouteBuilder
    let proxy: MapProxy
    @State private var isDrawing = false
    @State private var toleranceMetres = 4.0

    var body: some View {
        if builder.isEditing && builder.mode == .freehand {
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .global)
                        .onChanged { value in
                            if !isDrawing {
                                isDrawing = true
                                toleranceMetres = metresPerFewPoints(near: value.location)
                                builder.beginStroke()
                            }
                            guard let coordinate = proxy.convert(value.location, from: .global) else { return }
                            builder.appendStrokePoint(coordinate, minimumSpacing: toleranceMetres / 3)
                        }
                        .onEnded { value in
                            if let coordinate = proxy.convert(value.location, from: .global) {
                                builder.appendStrokePoint(coordinate, minimumSpacing: 0)
                            }
                            builder.endStroke(tolerance: toleranceMetres)
                            isDrawing = false
                        }
                )
        }
    }

    /// Simplification tolerance ≈ 4 screen points at the current zoom, never below 1.5 m.
    private func metresPerFewPoints(near point: CGPoint) -> Double {
        let offset = CGPoint(x: point.x + 4, y: point.y)
        guard
            let a = proxy.convert(point, from: .global),
            let b = proxy.convert(offset, from: .global)
        else { return 4 }
        let metres = RouteGeometry.distance(GeoPoint(a), GeoPoint(b))
        return min(max(metres, 1.5), 250)
    }
}
