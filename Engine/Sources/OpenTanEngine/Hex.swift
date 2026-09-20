import Foundation

/// Axial coordinate of a pointy-top hexagon.
///
/// The whole board geometry is derived from hexes alone:
/// a vertex is the unordered set of the three hexes that meet at it, and an
/// edge is the unordered pair of the two hexes that share it. That keeps every
/// identifier integral and canonical, so corners and edges shared between
/// neighbouring tiles compare equal without any floating point rounding.
public struct Hex: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let q: Int
    public let r: Int

    public init(_ q: Int, _ r: Int) {
        self.q = q
        self.r = r
    }

    /// Third cube coordinate, implied by `q` and `r`.
    public var s: Int { -q - r }

    /// Directions in clockwise order starting at "east".
    public static let directions: [Hex] = [
        Hex(1, 0), Hex(1, -1), Hex(0, -1), Hex(-1, 0), Hex(-1, 1), Hex(0, 1)
    ]

    public func neighbor(_ index: Int) -> Hex {
        let d = Hex.directions[((index % 6) + 6) % 6]
        return Hex(q + d.q, r + d.r)
    }

    public var neighbors: [Hex] { (0..<6).map(neighbor) }

    public func isAdjacent(to other: Hex) -> Bool {
        neighbors.contains(other)
    }

    public static func < (lhs: Hex, rhs: Hex) -> Bool {
        (lhs.r, lhs.q) < (rhs.r, rhs.q)
    }

    public var description: String { "\(q),\(r)" }
}

extension Hex: CodingKeyRepresentable {
    public var codingKey: CodingKey { StringKey(description) }

    public init?<T: CodingKey>(codingKey: T) {
        let parts = codingKey.stringValue.split(separator: ",")
        guard parts.count == 2, let q = Int(parts[0]), let r = Int(parts[1]) else { return nil }
        self.init(q, r)
    }
}

/// A corner of the board, identified by the three hexes that meet there.
public struct VertexID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let hexes: [Hex]

    public init(_ hexes: [Hex]) {
        precondition(hexes.count == 3, "a vertex is shared by exactly three hexes")
        self.hexes = hexes.sorted()
    }

    public static func < (lhs: VertexID, rhs: VertexID) -> Bool {
        for (l, r) in zip(lhs.hexes, rhs.hexes) where l != r { return l < r }
        return false
    }

    public var description: String { hexes.map(\.description).joined(separator: "|") }
}

extension VertexID: CodingKeyRepresentable {
    public var codingKey: CodingKey { StringKey(description) }

    public init?<T: CodingKey>(codingKey: T) {
        let hexes = codingKey.stringValue.split(separator: "|").compactMap(Hex.init(text:))
        guard hexes.count == 3 else { return nil }
        self.init(hexes)
    }
}

/// A side of the board, identified by the two hexes that share it.
public struct EdgeID: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public let hexes: [Hex]

    public init(_ hexes: [Hex]) {
        precondition(hexes.count == 2, "an edge is shared by exactly two hexes")
        self.hexes = hexes.sorted()
    }

    public static func < (lhs: EdgeID, rhs: EdgeID) -> Bool {
        for (l, r) in zip(lhs.hexes, rhs.hexes) where l != r { return l < r }
        return false
    }

    public var description: String { hexes.map(\.description).joined(separator: "|") }
}

extension EdgeID: CodingKeyRepresentable {
    public var codingKey: CodingKey { StringKey(description) }

    public init?<T: CodingKey>(codingKey: T) {
        let hexes = codingKey.stringValue.split(separator: "|").compactMap(Hex.init(text:))
        guard hexes.count == 2 else { return nil }
        self.init(hexes)
    }
}

extension Hex {
    init?(text: Substring) {
        let parts = text.split(separator: ",")
        guard parts.count == 2, let q = Int(parts[0]), let r = Int(parts[1]) else { return nil }
        self.init(q, r)
    }
}

/// Minimal `CodingKey` used to give the geometry types stable dictionary keys.
struct StringKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

public enum Geometry {
    /// The hexes adjacent to both `a` and `b`. Two neighbouring hexes always
    /// share exactly two of them, one on each side of their common edge.
    public static func commonNeighbors(_ a: Hex, _ b: Hex) -> [Hex] {
        let lhs = Set(a.neighbors)
        return b.neighbors.filter { lhs.contains($0) }.sorted()
    }

    public static func corners(of hex: Hex) -> [VertexID] {
        (0..<6).map { VertexID([hex, hex.neighbor($0), hex.neighbor($0 + 1)]) }
    }

    public static func sides(of hex: Hex) -> [EdgeID] {
        (0..<6).map { EdgeID([hex, hex.neighbor($0)]) }
    }

    /// The two corners at the ends of an edge.
    public static func endpoints(of edge: EdgeID) -> [VertexID] {
        commonNeighbors(edge.hexes[0], edge.hexes[1]).map { VertexID(edge.hexes + [$0]) }
    }

    /// The three edges meeting at a corner.
    public static func edges(at vertex: VertexID) -> [EdgeID] {
        let h = vertex.hexes
        return [EdgeID([h[0], h[1]]), EdgeID([h[0], h[2]]), EdgeID([h[1], h[2]])]
    }

    /// The three corners one edge away from `vertex`.
    public static func neighbors(of vertex: VertexID) -> [VertexID] {
        edges(at: vertex).compactMap { edge in
            endpoints(of: edge).first { $0 != vertex }
        }
    }

    /// Unit-size layout position of a hex centre, pointy-top orientation.
    public static func center(of hex: Hex) -> Point {
        Point(
            x: 3.0.squareRoot() * (Double(hex.q) + Double(hex.r) / 2),
            y: 1.5 * Double(hex.r)
        )
    }

    public static func center(of vertex: VertexID) -> Point {
        let points = vertex.hexes.map(center(of:))
        return Point(
            x: points.reduce(0) { $0 + $1.x } / 3,
            y: points.reduce(0) { $0 + $1.y } / 3
        )
    }

    public static func center(of edge: EdgeID) -> Point {
        let a = center(of: edge.hexes[0])
        let b = center(of: edge.hexes[1])
        return Point(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
    }

    /// The six corner offsets of a unit hex, pointy-top orientation.
    public static func cornerOffsets() -> [Point] {
        (0..<6).map { index in
            let angle = Double.pi / 180 * (60 * Double(index) - 30)
            return Point(x: cos(angle), y: sin(angle))
        }
    }
}

public struct Point: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}
