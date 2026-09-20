import SwiftUI
import OpenTanEngine

/// Draws the whole board in a single canvas and turns taps into placements.
///
/// Zoom and pan are folded into the same transform the drawing uses, so a tap
/// can be mapped straight back to board coordinates without unwinding any
/// view modifiers.
struct BoardView: View {
    let game: GameState
    let highlightedVertices: Set<VertexID>
    let highlightedEdges: Set<EdgeID>
    let highlightedHexes: Set<Hex>
    var onVertex: (VertexID) -> Void
    var onEdge: (EdgeID) -> Void
    var onHex: (Hex) -> Void

    @State private var zoom: CGFloat = 1
    @State private var liveZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var livePan: CGSize = .zero
    @State private var pulse = false

    /// Leaves room for the port badges that sit outside the coastline.
    private let margin = 2.0

    var body: some View {
        GeometryReader { proxy in
            let layout = Layout(
                board: game.board,
                size: proxy.size,
                margin: margin,
                zoom: zoom * liveZoom,
                pan: CGSize(width: pan.width + livePan.width, height: pan.height + livePan.height)
            )

            Canvas { context, _ in
                draw(in: &context, layout: layout)
            }
            .background(Palette.sea)
            .contentShape(Rectangle())
            .onTapGesture { point in
                handleTap(at: point, layout: layout)
            }
            .gesture(
                SimultaneousGesture(
                    MagnifyGesture()
                        .onChanged { liveZoom = $0.magnification }
                        .onEnded { _ in
                            zoom = min(max(zoom * liveZoom, 0.6), 4)
                            liveZoom = 1
                        },
                    DragGesture()
                        .onChanged { livePan = $0.translation }
                        .onEnded { _ in
                            pan.width += livePan.width
                            pan.height += livePan.height
                            livePan = .zero
                        }
                )
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    zoom = 1
                    pan = .zero
                }
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Drawing

    private func draw(in context: inout GraphicsContext, layout: Layout) {
        drawPorts(in: &context, layout: layout)
        for hex in game.board.hexes {
            drawTile(hex, in: &context, layout: layout)
        }
        drawRoads(in: &context, layout: layout)
        drawRobber(in: &context, layout: layout)
        drawBuildings(in: &context, layout: layout)
        drawHighlights(in: &context, layout: layout)
    }

    private func hexPath(_ hex: Hex, layout: Layout, inset: Double = 0) -> Path {
        let centre = Geometry.center(of: hex)
        var path = Path()
        for (index, offset) in Geometry.cornerOffsets().enumerated() {
            let radius = 1 - inset
            let point = layout.point(Point(x: centre.x + offset.x * radius, y: centre.y + offset.y * radius))
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }

    private func drawTile(_ hex: Hex, in context: inout GraphicsContext, layout: Layout) {
        guard let tile = game.board.tile(at: hex) else { return }
        let path = hexPath(hex, layout: layout, inset: 0.02)
        context.fill(path, with: .color(tile.terrain.fill))
        context.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: max(1, layout.scale * 0.02))

        let centre = layout.point(Geometry.center(of: hex))
        context.draw(
            Text(tile.terrain.glyph).font(.system(size: layout.scale * 0.38)),
            at: CGPoint(x: centre.x, y: centre.y - layout.scale * 0.36)
        )

        guard let number = tile.number else { return }
        let radius = layout.scale * 0.26
        let token = Path(ellipseIn: CGRect(
            x: centre.x - radius, y: centre.y - radius + layout.scale * 0.16,
            width: radius * 2, height: radius * 2
        ))
        context.fill(token, with: .color(Palette.coast))
        context.stroke(token, with: .color(.black.opacity(0.4)), lineWidth: 1)

        let tokenCentre = CGPoint(x: centre.x, y: centre.y + layout.scale * 0.16)
        context.draw(
            Text("\(number)")
                .font(.system(size: layout.scale * 0.3, weight: .bold, design: .rounded))
                .foregroundStyle(isHighProbability(number) ? Color.red : Color.black),
            at: CGPoint(x: tokenCentre.x, y: tokenCentre.y - layout.scale * 0.04)
        )
        context.draw(
            Text(String(repeating: "•", count: pipCount(for: number)))
                .font(.system(size: layout.scale * 0.16, weight: .bold))
                .foregroundStyle(isHighProbability(number) ? Color.red : Color.black),
            at: CGPoint(x: tokenCentre.x, y: tokenCentre.y + layout.scale * 0.16)
        )
    }

    private func drawPorts(in context: inout GraphicsContext, layout: Layout) {
        for (pair, port) in portPairs {
            let a = Geometry.center(of: pair.0)
            let b = Geometry.center(of: pair.1)
            let mid = Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let outward = normalise(Point(x: mid.x - layout.boardCentre.x, y: mid.y - layout.boardCentre.y))
            let badge = Point(x: mid.x + outward.x * 0.55, y: mid.y + outward.y * 0.55)
            let badgePoint = layout.point(badge)

            for vertex in [pair.0, pair.1] {
                var line = Path()
                line.move(to: badgePoint)
                line.addLine(to: layout.point(Geometry.center(of: vertex)))
                context.stroke(line, with: .color(.white.opacity(0.7)), lineWidth: max(1, layout.scale * 0.04))
            }

            let radius = layout.scale * 0.3
            let circle = Path(ellipseIn: CGRect(
                x: badgePoint.x - radius, y: badgePoint.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.fill(circle, with: .color(Palette.coast))
            context.stroke(circle, with: .color(.black.opacity(0.35)), lineWidth: 1)

            switch port {
            case .generic:
                context.draw(
                    Text("3:1").font(.system(size: layout.scale * 0.19, weight: .bold)).foregroundStyle(.black),
                    at: badgePoint
                )
            case .specific(let resource):
                context.draw(
                    Text(resource.glyph).font(.system(size: layout.scale * 0.22)),
                    at: CGPoint(x: badgePoint.x, y: badgePoint.y - layout.scale * 0.08)
                )
                context.draw(
                    Text("2:1").font(.system(size: layout.scale * 0.15, weight: .bold)).foregroundStyle(.black),
                    at: CGPoint(x: badgePoint.x, y: badgePoint.y + layout.scale * 0.13)
                )
            }
        }
    }

    private func drawRoads(in context: inout GraphicsContext, layout: Layout) {
        for (edge, owner) in game.board.roads {
            let ends = Geometry.endpoints(of: edge).map { layout.point(Geometry.center(of: $0)) }
            guard ends.count == 2 else { continue }
            var path = Path()
            path.move(to: ends[0])
            path.addLine(to: ends[1])
            context.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: layout.scale * 0.2, lineCap: .round))
            context.stroke(
                path,
                with: .color(game.players[owner].color.swiftUIColor),
                style: StrokeStyle(lineWidth: layout.scale * 0.14, lineCap: .round)
            )
        }
    }

    private func drawBuildings(in context: inout GraphicsContext, layout: Layout) {
        for (vertex, building) in game.board.buildings {
            let point = layout.point(Geometry.center(of: vertex))
            let colour = game.players[building.owner].color.swiftUIColor
            let size = layout.scale * (building.kind == .city ? 0.34 : 0.26)
            let rect = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
            let shape = building.kind == .city
                ? Path(roundedRect: rect, cornerRadius: size * 0.2)
                : housePath(in: rect)
            context.fill(shape, with: .color(colour))
            context.stroke(shape, with: .color(.black.opacity(0.7)), lineWidth: max(1, layout.scale * 0.03))
        }
    }

    private func housePath(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY - rect.height * 0.1))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY - rect.height * 0.1))
        path.closeSubpath()
        return path
    }

    private func drawRobber(in context: inout GraphicsContext, layout: Layout) {
        // Sits to one side of the tile so the number token stays readable.
        let centre = layout.point(Geometry.center(of: game.board.robber))
        let radius = layout.scale * 0.22
        let spot = CGPoint(x: centre.x - layout.scale * 0.44, y: centre.y + layout.scale * 0.12)
        let body = Path(ellipseIn: CGRect(
            x: spot.x - radius, y: spot.y - radius, width: radius * 2, height: radius * 2
        ))
        context.fill(body, with: .color(.black.opacity(0.88)))
        context.stroke(body, with: .color(.white.opacity(0.9)), lineWidth: max(1.5, layout.scale * 0.03))
        context.draw(
            Text("🦹").font(.system(size: layout.scale * 0.26)),
            at: spot
        )
    }

    private func drawHighlights(in context: inout GraphicsContext, layout: Layout) {
        let alpha = pulse ? 0.9 : 0.45

        for hex in highlightedHexes {
            let path = hexPath(hex, layout: layout, inset: 0.08)
            context.stroke(path, with: .color(.white.opacity(alpha)), lineWidth: max(2, layout.scale * 0.06))
        }

        for edge in highlightedEdges {
            let ends = Geometry.endpoints(of: edge).map { layout.point(Geometry.center(of: $0)) }
            guard ends.count == 2 else { continue }
            var path = Path()
            path.move(to: ends[0])
            path.addLine(to: ends[1])
            context.stroke(
                path,
                with: .color(.white.opacity(alpha)),
                style: StrokeStyle(lineWidth: layout.scale * 0.1, lineCap: .round, dash: [layout.scale * 0.12, layout.scale * 0.1])
            )
        }

        for vertex in highlightedVertices {
            let point = layout.point(Geometry.center(of: vertex))
            let radius = layout.scale * 0.18
            let circle = Path(ellipseIn: CGRect(
                x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2
            ))
            context.stroke(circle, with: .color(.white.opacity(alpha)), lineWidth: max(2, layout.scale * 0.05))
        }
    }

    // MARK: - Hit testing

    private func handleTap(at point: CGPoint, layout: Layout) {
        let threshold = layout.scale * 0.45

        if let vertex = nearest(in: highlightedVertices, to: point, layout: layout, position: Geometry.center(of:)),
           vertex.distance < threshold {
            onVertex(vertex.value)
            return
        }
        if let edge = nearest(in: highlightedEdges, to: point, layout: layout, position: Geometry.center(of:)),
           edge.distance < threshold {
            onEdge(edge.value)
            return
        }
        if let hex = nearest(in: highlightedHexes, to: point, layout: layout, position: Geometry.center(of:)),
           hex.distance < layout.scale {
            onHex(hex.value)
        }
    }

    private func nearest<T>(
        in candidates: Set<T>,
        to point: CGPoint,
        layout: Layout,
        position: (T) -> Point
    ) -> (value: T, distance: CGFloat)? {
        candidates
            .map { candidate -> (value: T, distance: CGFloat) in
                let screen = layout.point(position(candidate))
                return (candidate, hypot(screen.x - point.x, screen.y - point.y))
            }
            .min { $0.distance < $1.distance }
    }

    private func normalise(_ point: Point) -> Point {
        let length = (point.x * point.x + point.y * point.y).squareRoot()
        guard length > 0 else { return Point(x: 0, y: -1) }
        return Point(x: point.x / length, y: point.y / length)
    }

    /// Ports are stored per corner; the board shows one badge per pair.
    private var portPairs: [(pair: (VertexID, VertexID), port: TradePort)] {
        var seen: Set<VertexID> = []
        var result: [(pair: (VertexID, VertexID), port: TradePort)] = []
        for vertex in game.board.ports.keys.sorted() {
            guard !seen.contains(vertex), let port = game.board.ports[vertex] else { continue }
            guard let partner = Geometry.neighbors(of: vertex)
                .first(where: { !seen.contains($0) && game.board.ports[$0] == port }) else { continue }
            seen.insert(vertex)
            seen.insert(partner)
            result.append((pair: (vertex, partner), port: port))
        }
        return result
    }

    /// Maps board coordinates onto the view, including zoom and pan.
    struct Layout {
        let scale: CGFloat
        let boardCentre: Point
        let size: CGSize
        let pan: CGSize

        init(board: Board, size: CGSize, margin: Double, zoom: CGFloat, pan: CGSize) {
            let centres = board.hexes.map(Geometry.center(of:))
            let minX = (centres.map(\.x).min() ?? 0) - margin
            let maxX = (centres.map(\.x).max() ?? 0) + margin
            let minY = (centres.map(\.y).min() ?? 0) - margin
            let maxY = (centres.map(\.y).max() ?? 0) + margin
            boardCentre = Point(x: (minX + maxX) / 2, y: (minY + maxY) / 2)
            let base = min(size.width / (maxX - minX), size.height / (maxY - minY))
            scale = base * zoom
            self.size = size
            self.pan = pan
        }

        func point(_ p: Point) -> CGPoint {
            CGPoint(
                x: (p.x - boardCentre.x) * scale + size.width / 2 + pan.width,
                y: (p.y - boardCentre.y) * scale + size.height / 2 + pan.height
            )
        }
    }
}
