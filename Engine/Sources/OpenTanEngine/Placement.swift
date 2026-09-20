import Foundation

/// Pure placement and scoring rules. Everything here reads the board and
/// answers a question about it; nothing mutates game state.
public enum Placement {
    /// The distance rule: a settlement needs an empty corner with all three
    /// neighbouring corners empty too.
    public static func isCornerOpen(_ vertex: VertexID, board: Board) -> Bool {
        guard board.allVertices.contains(vertex), board.buildings[vertex] == nil else { return false }
        return Geometry.neighbors(of: vertex).allSatisfy { board.buildings[$0] == nil }
    }

    /// Corners a player may take during the opening placement, where the
    /// distance rule applies but the road connection rule does not.
    public static func setupSettlementSpots(board: Board) -> Set<VertexID> {
        board.allVertices.filter { isCornerOpen($0, board: board) }
    }

    /// Corners a player may build a settlement on during normal play: open by
    /// the distance rule and touching one of their own roads.
    public static func settlementSpots(for player: Int, board: Board) -> Set<VertexID> {
        var result: Set<VertexID> = []
        for (edge, owner) in board.roads where owner == player {
            for vertex in Geometry.endpoints(of: edge) where isCornerOpen(vertex, board: board) {
                result.insert(vertex)
            }
        }
        return result
    }

    public static func citySpots(for player: Int, board: Board) -> Set<VertexID> {
        Set(board.buildings.compactMap { vertex, building in
            building.owner == player && building.kind == .settlement ? vertex : nil
        })
    }

    /// A road may be added to an empty side of a land tile that touches one of
    /// the player's own roads or buildings. A corner held by an opponent
    /// breaks the connection through it.
    public static func canBuildRoad(_ edge: EdgeID, for player: Int, board: Board) -> Bool {
        guard board.allEdges.contains(edge), board.roads[edge] == nil else { return false }
        return Geometry.endpoints(of: edge).contains { vertex in
            connects(at: vertex, for: player, board: board)
        }
    }

    static func connects(at vertex: VertexID, for player: Int, board: Board) -> Bool {
        if let building = board.buildings[vertex] {
            return building.owner == player
        }
        return Geometry.edges(at: vertex).contains { board.roads[$0] == player }
    }

    public static func roadSpots(for player: Int, board: Board) -> Set<EdgeID> {
        board.allEdges.filter { canBuildRoad($0, for: player, board: board) }
    }

    /// Sides touching a corner, used for the free road that follows each
    /// opening settlement.
    public static func setupRoadSpots(from vertex: VertexID, board: Board) -> Set<EdgeID> {
        Set(Geometry.edges(at: vertex).filter { board.allEdges.contains($0) && board.roads[$0] == nil })
    }

    /// Tiles the robber may be moved to: any land tile except the one it is on.
    public static func robberSpots(board: Board) -> Set<Hex> {
        Set(board.tiles.keys).subtracting([board.robber])
    }

    /// Longest unbroken run of a player's roads, counted in segments.
    ///
    /// A run may not use the same segment twice but may pass through a corner
    /// more than once, and it stops at a corner held by another player.
    public static func longestRoad(for player: Int, board: Board) -> Int {
        let owned = board.roads.filter { $0.value == player }.map(\.key)
        guard !owned.isEmpty else { return 0 }

        // Adjacency from each corner to the player's roads leaving it.
        var roadsAtVertex: [VertexID: [EdgeID]] = [:]
        for edge in owned {
            for vertex in Geometry.endpoints(of: edge) {
                roadsAtVertex[vertex, default: []].append(edge)
            }
        }

        func isBlocked(_ vertex: VertexID) -> Bool {
            guard let building = board.buildings[vertex] else { return false }
            return building.owner != player
        }

        var best = 0
        var used: Set<EdgeID> = []

        func walk(from vertex: VertexID, length: Int) {
            best = max(best, length)
            guard !isBlocked(vertex) else { return }
            for edge in roadsAtVertex[vertex] ?? [] where !used.contains(edge) {
                guard let next = Geometry.endpoints(of: edge).first(where: { $0 != vertex }) else { continue }
                used.insert(edge)
                walk(from: next, length: length + 1)
                used.remove(edge)
            }
        }

        for edge in owned {
            for vertex in Geometry.endpoints(of: edge) {
                walk(from: vertex, length: 0)
            }
        }
        return best
    }

    /// Best bank exchange rate a player has for a resource, given their ports.
    public static func tradeRate(for resource: Resource, player: Int, board: Board) -> Int {
        var rate = 4
        for port in board.ports(ownedBy: player) {
            switch port {
            case .generic:
                rate = min(rate, 3)
            case .specific(let kind) where kind == resource:
                rate = min(rate, 2)
            case .specific:
                continue
            }
        }
        return rate
    }
}
