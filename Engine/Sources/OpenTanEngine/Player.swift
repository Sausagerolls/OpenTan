import Foundation

public enum DevelopmentCard: String, Codable, CaseIterable, Sendable {
    case knight
    case roadBuilding
    case yearOfPlenty
    case monopoly
    case victoryPoint

    public var displayName: String {
        switch self {
        case .knight: return "Knight"
        case .roadBuilding: return "Road Building"
        case .yearOfPlenty: return "Year of Plenty"
        case .monopoly: return "Monopoly"
        case .victoryPoint: return "Victory Point"
        }
    }

    public var rulesText: String {
        switch self {
        case .knight:
            return "Move the robber, then steal one resource from a player with a building on the new tile."
        case .roadBuilding:
            return "Place two free roads."
        case .yearOfPlenty:
            return "Take any two resources from the bank."
        case .monopoly:
            return "Name a resource. Every other player gives you all of theirs."
        case .victoryPoint:
            return "Worth one victory point. Kept hidden until you win."
        }
    }

    /// Cards other than victory points are played for their effect.
    public var isPlayable: Bool { self != .victoryPoint }
}

public struct PlayerColor: Codable, Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var name: String

    public init(name: String, red: Double, green: Double, blue: Double) {
        self.name = name
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// The two spare sets of pieces the two-player variant lends to its
    /// imaginary neutral players.
    public static let neutralPalette: [PlayerColor] = [
        PlayerColor(name: "Slate", red: 0.42, green: 0.44, blue: 0.48),
        PlayerColor(name: "Sand", red: 0.72, green: 0.64, blue: 0.48)
    ]

    public static let palette: [PlayerColor] = [
        PlayerColor(name: "Red", red: 0.84, green: 0.22, blue: 0.20),
        PlayerColor(name: "Blue", red: 0.16, green: 0.42, blue: 0.78),
        PlayerColor(name: "Orange", red: 0.92, green: 0.54, blue: 0.14),
        PlayerColor(name: "White", red: 0.95, green: 0.95, blue: 0.93),
        PlayerColor(name: "Green", red: 0.20, green: 0.60, blue: 0.35),
        PlayerColor(name: "Purple", red: 0.51, green: 0.30, blue: 0.70)
    ]
}

/// A dev card plus the turn it was bought on, so the "not on the turn you buy
/// it" restriction can be enforced.
public struct HeldDevelopmentCard: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var card: DevelopmentCard
    public var boughtOnTurn: Int

    public init(id: UUID = UUID(), card: DevelopmentCard, boughtOnTurn: Int) {
        self.id = id
        self.card = card
        self.boughtOnTurn = boughtOnTurn
    }
}

public struct Player: Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var color: PlayerColor
    /// Neutral players exist only in the two-player variant. They own pieces
    /// and can hold the longest road, but they never take a turn and never
    /// collect resources.
    public var isNeutral: Bool = false
    /// Two-player variant currency, spent on forced trades and on sending the
    /// robber back to the desert.
    public var tradeTokens: Int = 0

    public var resources: [Resource: Int] = Resource.allCases.reduce(into: [:]) { $0[$1] = 0 }
    public var developmentCards: [HeldDevelopmentCard] = []
    public var knightsPlayed: Int = 0

    public var roadsLeft: Int = Rules.roadSupply
    public var settlementsLeft: Int = Rules.settlementSupply
    public var citiesLeft: Int = Rules.citySupply

    /// Longest run of connected roads, recomputed after every road placement.
    public var longestRoadLength: Int = 0
    public var hasLongestRoad: Bool = false
    public var hasLargestArmy: Bool = false

    public init(id: Int, name: String, color: PlayerColor, isNeutral: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.isNeutral = isNeutral
    }

    public var handCount: Int { resources.values.reduce(0, +) }

    public func count(of resource: Resource) -> Int { resources[resource] ?? 0 }

    public var hiddenVictoryPoints: Int {
        developmentCards.filter { $0.card == .victoryPoint }.count
    }

    public func canAfford(_ cost: [Resource: Int]) -> Bool {
        cost.allSatisfy { count(of: $0.key) >= $0.value }
    }

    public mutating func pay(_ cost: [Resource: Int]) {
        for (resource, amount) in cost {
            resources[resource, default: 0] -= amount
        }
    }

    public mutating func receive(_ resource: Resource, _ amount: Int = 1) {
        resources[resource, default: 0] += amount
    }

    /// Cards that may be played this turn: not victory points, not bought this
    /// turn, and one per turn is enforced by the game state.
    public func playableCards(onTurn turn: Int) -> [HeldDevelopmentCard] {
        developmentCards.filter { $0.card.isPlayable && $0.boughtOnTurn < turn }
    }
}

public enum Rules {
    public static let roadSupply = 15
    public static let settlementSupply = 5
    public static let citySupply = 4

    public static let roadCost: [Resource: Int] = [.brick: 1, .lumber: 1]
    public static let settlementCost: [Resource: Int] = [.brick: 1, .lumber: 1, .wool: 1, .grain: 1]
    public static let cityCost: [Resource: Int] = [.grain: 2, .ore: 3]
    public static let developmentCardCost: [Resource: Int] = [.wool: 1, .grain: 1, .ore: 1]

    public static let bankSupplyPerResource = 19
    public static let largestArmyThreshold = 3
    public static let longestRoadThreshold = 5
    public static let defaultDiscardLimit = 7
    public static let defaultVictoryTarget = 10

    // MARK: - Two-player variant

    /// Trade tokens in the box, shared by both players.
    public static let tradeTokenPool = 20
    public static let startingTradeTokens = 5
    /// Cards swapped in each direction by a forced trade.
    public static let forcedTradeCards = 2
    /// Tokens handed back for discarding a face-up knight.
    public static let knightExchangeTokens = 2
    public static let neutralPlayerCount = 2
    /// Token bonuses for a new settlement next to the desert and on the coast.
    public static let desertSettlementTokens = 2
    public static let coastSettlementTokens = 1

    /// The 25-card development deck.
    public static func developmentDeck(for layout: BoardLayout) -> [DevelopmentCard] {
        switch layout {
        case .standard:
            return Array(repeating: .knight, count: 14)
                + Array(repeating: .victoryPoint, count: 5)
                + Array(repeating: .roadBuilding, count: 2)
                + Array(repeating: .yearOfPlenty, count: 2)
                + Array(repeating: .monopoly, count: 2)
        case .large:
            return Array(repeating: .knight, count: 20)
                + Array(repeating: .victoryPoint, count: 5)
                + Array(repeating: .roadBuilding, count: 3)
                + Array(repeating: .yearOfPlenty, count: 3)
                + Array(repeating: .monopoly, count: 3)
        }
    }
}
