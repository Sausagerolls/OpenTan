import Foundation

public enum Resource: String, Codable, CaseIterable, Sendable, Hashable {
    case brick, lumber, wool, grain, ore

    public var displayName: String {
        switch self {
        case .brick: return "Brick"
        case .lumber: return "Lumber"
        case .wool: return "Wool"
        case .grain: return "Grain"
        case .ore: return "Ore"
        }
    }
}

public enum Terrain: String, Codable, CaseIterable, Sendable {
    case hills, forest, pasture, fields, mountains, desert

    public var resource: Resource? {
        switch self {
        case .hills: return .brick
        case .forest: return .lumber
        case .pasture: return .wool
        case .fields: return .grain
        case .mountains: return .ore
        case .desert: return nil
        }
    }

    public var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }
}

public enum TradePort: Codable, Hashable, Sendable {
    case generic                 // three of any one resource for one of your choice
    case specific(Resource)      // two of the named resource for one of your choice

    public var rate: Int {
        switch self {
        case .generic: return 3
        case .specific: return 2
        }
    }

    public var displayName: String {
        switch self {
        case .generic: return "3:1"
        case .specific(let resource): return "2:1 \(resource.displayName)"
        }
    }
}

public struct Tile: Codable, Hashable, Sendable {
    public let hex: Hex
    public let terrain: Terrain
    /// Dice number printed on the tile. `nil` on the desert.
    public let number: Int?

    public init(hex: Hex, terrain: Terrain, number: Int?) {
        self.hex = hex
        self.terrain = terrain
        self.number = number
    }
}

public enum BuildingKind: String, Codable, Sendable {
    case settlement, city

    public var victoryPoints: Int { self == .settlement ? 1 : 2 }
    public var yield: Int { self == .settlement ? 1 : 2 }
}

public struct Building: Codable, Hashable, Sendable {
    public var kind: BuildingKind
    public var owner: Int

    public init(kind: BuildingKind, owner: Int) {
        self.kind = kind
        self.owner = owner
    }
}

public struct Board: Codable, Sendable {
    public private(set) var tiles: [Hex: Tile]
    /// Port kind keyed by the two corners a player must build on to use it.
    public private(set) var ports: [VertexID: TradePort]
    public var robber: Hex
    public var buildings: [VertexID: Building] = [:]
    public var roads: [EdgeID: Int] = [:]

    public init(tiles: [Hex: Tile], ports: [VertexID: TradePort], robber: Hex) {
        self.tiles = tiles
        self.ports = ports
        self.robber = robber
    }

    public var hexes: [Hex] { tiles.keys.sorted() }

    /// Every corner that belongs to at least one land tile.
    public var allVertices: Set<VertexID> {
        var result: Set<VertexID> = []
        for hex in tiles.keys {
            result.formUnion(Geometry.corners(of: hex))
        }
        return result
    }

    /// Every side that belongs to at least one land tile.
    public var allEdges: Set<EdgeID> {
        var result: Set<EdgeID> = []
        for hex in tiles.keys {
            result.formUnion(Geometry.sides(of: hex))
        }
        return result
    }

    public func tile(at hex: Hex) -> Tile? { tiles[hex] }

    /// Ports a player can trade at, given the corners they have built on.
    public func ports(ownedBy player: Int) -> [TradePort] {
        ports.compactMap { vertex, port in
            buildings[vertex]?.owner == player ? port : nil
        }
    }

    /// Players with a building on a corner of `hex`, excluding `excluding`.
    public func playersAdjacent(to hex: Hex, excluding: Int? = nil) -> [Int] {
        var result: Set<Int> = []
        for vertex in Geometry.corners(of: hex) {
            if let owner = buildings[vertex]?.owner, owner != excluding {
                result.insert(owner)
            }
        }
        return result.sorted()
    }
}

public enum BoardLayout: String, Codable, CaseIterable, Sendable {
    /// Nineteen tiles, for two to four players.
    case standard
    /// Thirty tiles, for five or six players.
    case large

    public static func recommended(forPlayerCount count: Int) -> BoardLayout {
        count >= 5 ? .large : .standard
    }

    public var hexes: [Hex] {
        switch self {
        case .standard:
            return (-2...2).flatMap { r -> [Hex] in
                let start = -2 - min(r, 0)
                let count = 5 - abs(r)
                return (0..<count).map { Hex(start + $0, r) }
            }
        case .large:
            return (-3...3).flatMap { r -> [Hex] in
                let start = -3 - min(r, 0)
                let count = 6 - abs(r)
                return (0..<count).map { Hex(start + $0, r) }
            }
        }
    }

    public var terrains: [Terrain] {
        switch self {
        case .standard:
            return Array(repeating: .forest, count: 4)
                + Array(repeating: .pasture, count: 4)
                + Array(repeating: .fields, count: 4)
                + Array(repeating: .hills, count: 3)
                + Array(repeating: .mountains, count: 3)
                + [.desert]
        case .large:
            return Array(repeating: .forest, count: 6)
                + Array(repeating: .pasture, count: 6)
                + Array(repeating: .fields, count: 6)
                + Array(repeating: .hills, count: 5)
                + Array(repeating: .mountains, count: 5)
                + Array(repeating: .desert, count: 2)
        }
    }

    public var numbers: [Int] {
        switch self {
        case .standard:
            return [2, 3, 3, 4, 4, 5, 5, 6, 6, 8, 8, 9, 9, 10, 10, 11, 11, 12]
        case .large:
            return [2, 2, 3, 3, 3, 4, 4, 4, 5, 5, 5, 6, 6, 6,
                    8, 8, 8, 9, 9, 9, 10, 10, 10, 11, 11, 11, 12, 12]
        }
    }

    public var portKinds: [TradePort] {
        switch self {
        case .standard:
            return Resource.allCases.map(TradePort.specific) + Array(repeating: .generic, count: 4)
        case .large:
            return Resource.allCases.map(TradePort.specific) + Array(repeating: .generic, count: 6)
        }
    }
}

public enum BoardGenerator {
    /// Builds a random board for `layout`.
    ///
    /// When `balanced` is true the shuffle is repeated until no two tiles
    /// bearing a 6 or an 8 touch each other, which is the usual house rule for
    /// keeping the high-probability numbers apart.
    public static func make(layout: BoardLayout, balanced: Bool = true, using rng: inout some RandomNumberGenerator) -> Board {
        let hexes = layout.hexes
        var tiles: [Hex: Tile] = [:]
        var attempts = 0

        repeat {
            attempts += 1
            var terrains = layout.terrains.shuffled(using: &rng)
            var numbers = layout.numbers.shuffled(using: &rng)
            tiles = [:]
            for hex in hexes {
                let terrain = terrains.removeLast()
                let number = terrain == .desert ? nil : numbers.removeLast()
                tiles[hex] = Tile(hex: hex, terrain: terrain, number: number)
            }
        } while balanced && attempts < 500 && hasAdjacentHighNumbers(tiles)

        let robber = tiles.values.first { $0.terrain == .desert }?.hex ?? hexes[0]
        let ports = makePorts(layout: layout, hexes: Set(hexes), using: &rng)
        return Board(tiles: tiles, ports: ports, robber: robber)
    }

    static func hasAdjacentHighNumbers(_ tiles: [Hex: Tile]) -> Bool {
        for (hex, tile) in tiles where tile.number == 6 || tile.number == 8 {
            for neighbor in hex.neighbors {
                guard let other = tiles[neighbor] else { continue }
                if other.number == 6 || other.number == 8 { return true }
            }
        }
        return false
    }

    /// Coastal edges in ring order, starting due east and running clockwise.
    static func coastalEdges(hexes: Set<Hex>) -> [EdgeID] {
        var edges: Set<EdgeID> = []
        for hex in hexes {
            for (index, neighbor) in hex.neighbors.enumerated() where !hexes.contains(neighbor) {
                _ = index
                edges.insert(EdgeID([hex, neighbor]))
            }
        }
        // The outline of both layouts is convex, so sorting the edge midpoints
        // by angle around the board centre reproduces the ring order.
        let centre = centroid(of: hexes)
        return edges.sorted { lhs, rhs in
            angle(of: Geometry.center(of: lhs), around: centre) < angle(of: Geometry.center(of: rhs), around: centre)
        }
    }

    static func centroid(of hexes: Set<Hex>) -> Point {
        let points = hexes.map(Geometry.center(of:))
        let count = Double(points.count)
        return Point(x: points.reduce(0) { $0 + $1.x } / count, y: points.reduce(0) { $0 + $1.y } / count)
    }

    static func angle(of point: Point, around centre: Point) -> Double {
        atan2(point.y - centre.y, point.x - centre.x)
    }

    static func makePorts(layout: BoardLayout, hexes: Set<Hex>, using rng: inout some RandomNumberGenerator) -> [VertexID: TradePort] {
        let ring = coastalEdges(hexes: hexes)
        let kinds = layout.portKinds.shuffled(using: &rng)
        guard !ring.isEmpty, !kinds.isEmpty else { return [:] }

        // Spread the ports evenly around the coast and give the whole ring a
        // random rotation so two boards rarely start the same way.
        let offset = Int.random(in: 0..<ring.count, using: &rng)
        var ports: [VertexID: TradePort] = [:]
        for (index, kind) in kinds.enumerated() {
            let position = (offset + index * ring.count / kinds.count) % ring.count
            for vertex in Geometry.endpoints(of: ring[position]) {
                ports[vertex] = kind
            }
        }
        return ports
    }
}
