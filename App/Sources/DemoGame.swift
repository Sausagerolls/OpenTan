import Foundation
import OpenTanEngine

/// Launch with `--demo-game` to jump straight into a mid-opening position.
/// Used for taking screenshots and for poking at the board during
/// development; it is never reachable from the app's own UI.
enum DemoGame {
    static var isRequested: Bool {
        startsInSetup || ProcessInfo.processInfo.arguments.contains("--demo-game")
    }

    /// `--demo-setup` opens a fresh game on the first opening placement.
    static var startsInSetup: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-setup")
    }

    static func make(playerNames: [String] = ["Ada", "Bram", "Cleo"]) -> GameState {
        var game = GameState(playerNames: playerNames, seed: 20_260_920)
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
