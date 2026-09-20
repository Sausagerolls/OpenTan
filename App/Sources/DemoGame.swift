import Foundation
import OpenTanEngine

/// Launch with `--demo-game` to jump straight into a mid-opening position.
/// Used for taking screenshots and for poking at the board during
/// development; it is never reachable from the app's own UI.
enum DemoGame {
    static var isRequested: Bool {
        startsInSetup || isTwoPlayer || ProcessInfo.processInfo.arguments.contains("--demo-game")
    }

    /// `--demo-none` starts on the menu with no saved game, so the tests can
    /// drive the new game sheet from a known state.
    static var startsOnMenu: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-none")
    }

    /// `--demo-two-player` opens the published two-player variant, past the
    /// opening placement.
    static var isTwoPlayer: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-two-player")
    }

    /// `--demo-setup` opens a fresh game on the first opening placement.
    static var startsInSetup: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-setup")
    }

    static func make(playerNames: [String]? = nil) -> GameState {
        let names = playerNames ?? (isTwoPlayer ? ["Ada", "Bram"] : ["Ada", "Bram", "Cleo"])
        var game = GameState(
            playerNames: names,
            options: .recommended(forPlayerCount: names.count),
            seed: 20_260_920
        )
        if startsInSetup { return game }
        while true {
            do {
                switch game.phase {
                case .setupSettlement:
                    guard let spot = Placement.setupSettlementSpots(board: game.board)
                        .sorted()
                        .dropFirst(3)
                        .first else { return game }
                    try game.apply(.placeSetupSettlement(spot))
                case .setupRoad(_, let vertex):
                    guard let spot = Placement.setupRoadSpots(from: vertex, board: game.board).sorted().first else {
                        return game
                    }
                    try game.apply(.placeSetupRoad(spot))
                default:
                    return game
                }
            } catch {
                return game
            }
        }
    }
}
