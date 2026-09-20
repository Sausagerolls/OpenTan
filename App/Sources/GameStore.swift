import Foundation
import Observation
import OpenTanEngine

/// The free piece the two-player variant owes a neutral player.
enum NeutralPiece: String, CaseIterable, Identifiable {
    case road, settlement
    var id: String { rawValue }
    var title: String { self == .road ? "Road" : "Settlement" }
}

/// What a tap on the board means right now.
enum BoardSelection: Equatable {
    case none
    case settlement
    case city
    case road
    case robber
}

/// Holds the game, decides who is allowed to look at the screen, and saves
/// after every change so a game survives the app being closed.
@Observable
final class GameStore {
    private(set) var game: GameState?
    var selection: BoardSelection = .none
    var message: String?
    /// The player the device has been handed to. Pass-and-play hides the
    /// screen until it matches the player who has to act.
    private(set) var deviceHolder: Int?
    var handRevealed = false
    /// Two-player variant: which neutral player the free piece goes to, and
    /// whether it is a road or a settlement.
    var neutralTarget: Int?
    var neutralPiece: NeutralPiece = .road
    /// False while the menu is on screen, even when a saved game exists.
    private(set) var isPlaying = false

    private let saveURL: URL

    init(saveURL: URL? = nil) {
        self.saveURL = saveURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("opentan-save.json")
        if DemoGame.startsOnMenu {
            game = nil
        } else if DemoGame.isRequested {
            game = DemoGame.make()
            isPlaying = true
        } else {
            game = Self.load(from: self.saveURL)
        }
        deviceHolder = game.map { Self.playerToAct(in: $0) }
    }

    // MARK: - Lifecycle

    func startGame(playerNames: [String], options: GameOptions) {
        game = GameState(playerNames: playerNames, options: options)
        selection = .none
        handRevealed = false
        deviceHolder = game.map { Self.playerToAct(in: $0) }
        isPlaying = true
        syncNeutralChoice()
        save()
    }

    func abandonGame() {
        game = nil
        deviceHolder = nil
        selection = .none
        isPlaying = false
        try? FileManager.default.removeItem(at: saveURL)
    }

    /// Opens the saved game again. The screen stays covered until whoever is
    /// due to act says they are holding the device.
    func resume() {
        guard let game else { return }
        deviceHolder = nil
        handRevealed = false
        selection = .none
        isPlaying = true
        _ = game
    }

    /// Goes back to the menu without deleting the save.
    func leaveToMenu() {
        isPlaying = false
        handRevealed = false
        selection = .none
    }

    var hasSavedGame: Bool { game != nil }

    // MARK: - Turn handover

    /// The player whose input the game is waiting for, which is not always the
    /// player whose turn it is.
    static func playerToAct(in game: GameState) -> Int {
        switch game.phase {
        case .discarding:
            return game.playersOwingDiscards.first ?? game.currentPlayer
        case .awaitingTradeResponse(let offer):
            return offer.partner
        case .specialBuild(let player):
            return player
        default:
            return game.currentPlayer
        }
    }

    var playerToAct: Int? { game.map { Self.playerToAct(in: $0) } }

    /// True while the screen should be covered because the device needs to
    /// change hands.
    var needsHandover: Bool {
        guard let game, game.winner == nil, let expected = playerToAct else { return false }
        return deviceHolder != expected
    }

    func acceptHandover() {
        deviceHolder = playerToAct
        handRevealed = false
        selection = .none
    }

    // MARK: - Actions

    func perform(_ action: GameAction) {
        guard var game else { return }
        do {
            try game.apply(action)
            self.game = game
            message = nil
            selection = .none
            syncNeutralChoice()
            if needsHandover { handRevealed = false }
            save()
        } catch {
            message = (error as? GameError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Routes a tap on the board to whatever the current selection means.
    func tapVertex(_ vertex: VertexID) {
        guard let game else { return }
        switch game.phase {
        case .setupSettlement:
            perform(.placeSetupSettlement(vertex))
        case .neutralPlacement:
            guard let neutral = neutralTarget else { return }
            perform(.placeNeutralSettlement(neutral: neutral, vertex: vertex))
        default:
            switch selection {
            case .settlement: perform(.buildSettlement(vertex))
            case .city: perform(.buildCity(vertex))
            default: break
            }
        }
    }

    func tapEdge(_ edge: EdgeID) {
        guard let game else { return }
        switch game.phase {
        case .setupRoad:
            perform(.placeSetupRoad(edge))
        case .placingFreeRoads:
            perform(.buildRoad(edge))
        case .neutralPlacement:
            guard let neutral = neutralTarget else { return }
            perform(.placeNeutralRoad(neutral: neutral, edge: edge))
        default:
            if selection == .road { perform(.buildRoad(edge)) }
        }
    }

    func tapHex(_ hex: Hex) {
        guard let game else { return }
        if case .movingRobber = game.phase {
            perform(.moveRobber(hex))
        }
    }

    // MARK: - Highlighted spots

    var highlightedVertices: Set<VertexID> {
        guard let game else { return [] }
        if case .setupSettlement = game.phase {
            return Placement.setupSettlementSpots(board: game.board)
        }
        if case .neutralPlacement = game.phase {
            guard neutralPiece == .settlement, let neutral = neutralTarget else { return [] }
            return game.neutralSettlementSpots(for: neutral)
        }
        switch selection {
        case .settlement: return Placement.settlementSpots(for: game.actingPlayer, board: game.board)
        case .city: return Placement.citySpots(for: game.actingPlayer, board: game.board)
        default: return []
        }
    }

    var highlightedEdges: Set<EdgeID> {
        guard let game else { return [] }
        switch game.phase {
        case .setupRoad(_, let vertex):
            return Placement.setupRoadSpots(from: vertex, board: game.board)
        case .placingFreeRoads:
            return Placement.roadSpots(for: game.actingPlayer, board: game.board)
        case .neutralPlacement:
            guard neutralPiece == .road, let neutral = neutralTarget else { return [] }
            return game.neutralRoadSpots(for: neutral)
        default:
            return selection == .road ? Placement.roadSpots(for: game.actingPlayer, board: game.board) : []
        }
    }

    var highlightedHexes: Set<Hex> {
        guard let game else { return [] }
        if case .movingRobber = game.phase { return Placement.robberSpots(board: game.board) }
        return []
    }

    /// Points the free piece at a neutral player who actually has somewhere to
    /// put it, and falls back to a road when no settlement is legal.
    func syncNeutralChoice() {
        guard let game, case .neutralPlacement(let mustBeRoad) = game.phase else {
            neutralTarget = nil
            return
        }
        if mustBeRoad { neutralPiece = .road }

        let neutrals = game.neutralPlayers.map(\.id)
        func hasSpots(_ neutral: Int) -> Bool {
            neutralPiece == .road
                ? !game.neutralRoadSpots(for: neutral).isEmpty
                : !game.neutralSettlementSpots(for: neutral).isEmpty
        }

        if let current = neutralTarget, neutrals.contains(current), hasSpots(current) { return }
        if let usable = neutrals.first(where: hasSpots) {
            neutralTarget = usable
            return
        }
        // Nowhere to put the chosen piece: switch to the other kind.
        neutralPiece = neutralPiece == .road ? .settlement : .road
        neutralTarget = neutrals.first(where: hasSpots) ?? neutrals.first
    }

    func spots(for neutral: Int, piece: NeutralPiece) -> Int {
        guard let game else { return 0 }
        return piece == .road
            ? game.neutralRoadSpots(for: neutral).count
            : game.neutralSettlementSpots(for: neutral).count
    }

    // MARK: - Persistence

    private func save() {
        guard let game else { return }
        do {
            let data = try JSONEncoder().encode(game)
            try data.write(to: saveURL, options: .atomic)
        } catch {
            message = "The game could not be saved."
        }
    }

    private static func load(from url: URL) -> GameState? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(GameState.self, from: data)
    }
}
