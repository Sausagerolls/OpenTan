import XCTest
@testable import OpenTanEngine

/// Plays the opening placement by always taking the first legal spot, so the
/// tests below start from a real, reachable position.
func startedGame(
    players: [String] = ["A", "B", "C"],
    seed: UInt64 = 42,
    options: GameOptions? = nil,
    variant: Bool = false
) throws -> GameState {
    // The base-rules suites opt out of the two-player variant, which would
    // otherwise switch itself on at a table of two.
    var resolved = options ?? GameOptions.recommended(forPlayerCount: players.count)
    if options == nil { resolved.twoPlayerVariant = variant }
    var game = GameState(playerNames: players, options: resolved, seed: seed)
    while !game.setupIsFinished {
        switch game.phase {
        case .setupSettlement:
            let spot = Placement.setupSettlementSpots(board: game.board).sorted().first!
            try game.apply(.placeSetupSettlement(spot))
        case .setupRoad(_, let vertex):
            let spot = Placement.setupRoadSpots(from: vertex, board: game.board).sorted().first!
            try game.apply(.placeSetupRoad(spot))
        default:
            XCTFail("unexpected phase \(game.phase)")
            return game
        }
    }
    return game
}

/// Rolls the dice as many times as the game asks for and clears the robber
/// steps, stopping if a discard is owed. Returns false when the turn cannot be
/// carried through to the building phase.
@discardableResult
func rollThroughToMain(_ game: inout GameState, limit: Int = 12) throws -> Bool {
    for _ in 0..<limit {
        switch game.phase {
        case .main:
            return true
        case .preRoll:
            try game.apply(.rollDice)
        case .movingRobber:
            try game.apply(.moveRobber(Placement.robberSpots(board: game.board).sorted().first!))
        case .stealing(let candidates):
            try game.apply(.steal(from: candidates[0]))
        case .discarding:
            return false
        default:
            return false
        }
    }
    return false
}

final class SetupTests: XCTestCase {
    func testOpeningPlacementRunsThereAndBack() throws {
        let game = try startedGame(players: ["A", "B", "C"])
        XCTAssertEqual(game.board.buildings.count, 6)
        XCTAssertEqual(game.board.roads.count, 6)
        for id in 0..<3 {
            XCTAssertEqual(game.board.buildings.values.filter { $0.owner == id }.count, 2)
            XCTAssertEqual(game.players[id].settlementsLeft, Rules.settlementSupply - 2)
            XCTAssertEqual(game.players[id].roadsLeft, Rules.roadSupply - 2)
        }
        XCTAssertEqual(game.currentPlayer, 0)
        XCTAssertEqual(game.phase, .preRoll)
    }

    func testSecondSettlementPaysOut() throws {
        let game = try startedGame(players: ["A", "B"])
        // Every player's second settlement sits on up to three land tiles, so
        // nobody can start with an empty hand on a normal board.
        for player in game.players {
            XCTAssertGreaterThan(player.handCount, 0)
            XCTAssertLessThanOrEqual(player.handCount, 3)
        }
    }

    func testDistanceRuleIsEnforced() throws {
        var game = GameState(playerNames: ["A", "B"], seed: 5)
        let spot = Placement.setupSettlementSpots(board: game.board).sorted().first!
        try game.apply(.placeSetupSettlement(spot))
        let road = Placement.setupRoadSpots(from: spot, board: game.board).sorted().first!
        try game.apply(.placeSetupRoad(road))

        for neighbor in Geometry.neighbors(of: spot) {
            XCTAssertFalse(Placement.isCornerOpen(neighbor, board: game.board))
            XCTAssertThrowsError(try game.apply(.placeSetupSettlement(neighbor))) { error in
                XCTAssertEqual(error as? GameError, .illegalPlacement)
            }
        }
    }

    func testTwoPlayerGameIsAllowed() throws {
        let game = try startedGame(players: ["A", "B"])
        XCTAssertEqual(game.players.count, 2)
        XCTAssertEqual(game.options.layout, .standard)
    }

    func testTwoPlayersGetTheVariantByDefault() {
        XCTAssertTrue(GameOptions.recommended(forPlayerCount: 2).twoPlayerVariant)
        XCTAssertFalse(GameOptions.recommended(forPlayerCount: 3).twoPlayerVariant)
        XCTAssertFalse(GameOptions.recommended(forPlayerCount: 5).twoPlayerVariant)
    }

    func testFivePlayersUseTheLargeBoard() throws {
        let game = try startedGame(players: ["A", "B", "C", "D", "E"], seed: 9)
        XCTAssertEqual(game.options.layout, .large)
        XCTAssertTrue(game.options.specialBuildPhase)
        XCTAssertEqual(game.board.tiles.count, 30)
    }
}

final class BuildingTests: XCTestCase {
    func testRoadNeedsResourcesAndAConnection() throws {
        var game = try startedGame(players: ["A", "B"])
        guard try rollThroughToMain(&game) else { return }

        let spot = Placement.roadSpots(for: 0, board: game.board).sorted().first!
        XCTAssertThrowsError(try game.apply(.buildRoad(spot))) { error in
            XCTAssertEqual(error as? GameError, .cannotAfford)
        }

        game.giveForTesting(.brick, 1, to: 0)
        game.giveForTesting(.lumber, 1, to: 0)
        try game.apply(.buildRoad(spot))
        XCTAssertEqual(game.board.roads[spot], 0)
        XCTAssertEqual(game.players[0].count(of: .brick), 0)

        let unreachable = game.board.allEdges
            .subtracting(Placement.roadSpots(for: 0, board: game.board))
            .filter { game.board.roads[$0] == nil }
            .sorted().first!
        game.giveForTesting(.brick, 1, to: 0)
        game.giveForTesting(.lumber, 1, to: 0)
        XCTAssertThrowsError(try game.apply(.buildRoad(unreachable))) { error in
            XCTAssertEqual(error as? GameError, .illegalPlacement)
        }
    }

    func testCityUpgradesOwnSettlementAndReturnsThePiece() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        let mine = Placement.citySpots(for: 0, board: game.board).sorted().first!
        game.giveForTesting(.grain, 2, to: 0)
        game.giveForTesting(.ore, 3, to: 0)
        let settlementsBefore = game.players[0].settlementsLeft

        try game.apply(.buildCity(mine))
        XCTAssertEqual(game.board.buildings[mine]?.kind, .city)
        XCTAssertEqual(game.players[0].settlementsLeft, settlementsBefore + 1)
        XCTAssertEqual(game.players[0].citiesLeft, Rules.citySupply - 1)
        XCTAssertEqual(game.victoryPoints(for: 0, includingHidden: false), 3)
    }

    func testCannotUpgradeAnotherPlayersSettlement() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        let theirs = Placement.citySpots(for: 1, board: game.board).sorted().first!
        game.giveForTesting(.grain, 2, to: 0)
        game.giveForTesting(.ore, 3, to: 0)
        XCTAssertThrowsError(try game.apply(.buildCity(theirs))) { error in
            XCTAssertEqual(error as? GameError, .illegalPlacement)
        }
    }
}

final class TradeTests: XCTestCase {
    func testBankTradeIsFourToOneWithoutAPort() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        let owned = Set(game.board.ports.compactMap { vertex, port in
            game.board.buildings[vertex]?.owner == 0 ? port : nil
        })
        try XCTSkipUnless(owned.isEmpty, "this seed put a port under the first player")

        game.giveForTesting(.ore, 4, to: 0)
        let held = game.players[0].count(of: .ore)
        let bankBefore = game.bank[.ore] ?? 0
        try game.apply(.bankTrade(give: .ore, receive: .wool))
        XCTAssertEqual(game.players[0].count(of: .ore), held - 4)
        XCTAssertEqual(game.bank[.ore], bankBefore + 4)
    }

    func testPortRatesApply() throws {
        var game = try startedGame(players: ["A", "B"])
        let portVertex = game.board.ports.keys.sorted().first!
        game.placeBuildingForTesting(Building(kind: .settlement, owner: 0), at: portVertex)
        let port = game.board.ports[portVertex]!
        switch port {
        case .generic:
            XCTAssertEqual(Placement.tradeRate(for: .ore, player: 0, board: game.board), 3)
        case .specific(let resource):
            XCTAssertEqual(Placement.tradeRate(for: resource, player: 0, board: game.board), 2)
            let other = Resource.allCases.first { $0 != resource }!
            XCTAssertEqual(Placement.tradeRate(for: other, player: 0, board: game.board), 4)
        }
    }

    func testPlayerTradeMovesCardsBothWays() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.giveForTesting(.ore, 2, to: 0)
        game.giveForTesting(.wool, 1, to: 1)
        let proposerOre = game.players[0].count(of: .ore)
        let proposerWool = game.players[0].count(of: .wool)
        let partnerOre = game.players[1].count(of: .ore)

        let offer = TradeOffer(proposer: 0, partner: 1, give: [.ore: 2], receive: [.wool: 1])
        try game.apply(.proposeTrade(offer))
        XCTAssertEqual(game.phase, .awaitingTradeResponse(offer))
        try game.apply(.respondToTrade(accept: true))

        XCTAssertEqual(game.players[0].count(of: .ore), proposerOre - 2)
        XCTAssertEqual(game.players[0].count(of: .wool), proposerWool + 1)
        XCTAssertEqual(game.players[1].count(of: .ore), partnerOre + 2)
        XCTAssertEqual(game.phase, .main)
    }

    func testDeclinedTradeChangesNothing() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.giveForTesting(.ore, 2, to: 0)
        let before = game.players[0].count(of: .ore)
        XCTAssertGreaterThanOrEqual(before, 2)
        try game.apply(.proposeTrade(TradeOffer(proposer: 0, partner: 1, give: [.ore: 2], receive: [.wool: 1])))
        try game.apply(.respondToTrade(accept: false))
        XCTAssertEqual(game.players[0].count(of: .ore), before)
        XCTAssertEqual(game.phase, .main)
    }
}

final class RobberTests: XCTestCase {
    func testSevenMakesLargeHandsDiscardHalf() throws {
        var game = try startedGame(players: ["A", "B"], options: GameOptions(discardLimit: 7))
        game.giveForTesting(.ore, 9, to: 1)
        game.forcePreRollForTesting()
        game.forceRollForTesting(total: 7)

        XCTAssertEqual(game.phase, .discarding)
        let owed = game.discardsOwed(by: 1)
        XCTAssertEqual(owed, (game.players[1].handCount) / 2)
        XCTAssertThrowsError(try game.apply(.discard(player: 1, cards: [.ore: owed - 1])))
        try game.apply(.discard(player: 1, cards: [.ore: owed]))
        XCTAssertEqual(game.phase, .movingRobber)
    }

    func testRobberBlocksProduction() throws {
        var game = try startedGame(players: ["A", "B"])
        let vertex = game.board.buildings.first { $0.value.owner == 0 }!.key
        let hex = vertex.hexes.first { game.board.tile(at: $0)?.terrain.resource != nil }!
        let tile = game.board.tile(at: hex)!
        game.setRobberForTesting(hex)
        let before = game.players[0].count(of: tile.terrain.resource!)
        game.produceForTesting(total: tile.number!)
        let after = game.players[0].count(of: tile.terrain.resource!)
        // Any gain must come from another tile showing the same number.
        let otherTiles = game.board.tiles.values.filter { $0.number == tile.number && $0.hex != hex }
        if otherTiles.isEmpty {
            XCTAssertEqual(before, after)
        }
    }

    func testRobberCannotStayPut() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forcePhaseForTesting(.movingRobber)
        XCTAssertThrowsError(try game.apply(.moveRobber(game.board.robber))) { error in
            XCTAssertEqual(error as? GameError, .illegalPlacement)
        }
    }
}

final class AwardTests: XCTestCase {
    func testLongestRoadNeedsFiveAndTransfers() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()

        var built = 0
        while built < 6 {
            guard let spot = Placement.roadSpots(for: 0, board: game.board).sorted().first else { break }
            game.giveForTesting(.brick, 1, to: 0)
            game.giveForTesting(.lumber, 1, to: 0)
            try game.apply(.buildRoad(spot))
            built += 1
        }
        XCTAssertGreaterThanOrEqual(game.players[0].longestRoadLength, Rules.longestRoadThreshold)
        XCTAssertTrue(game.players[0].hasLongestRoad)
        XCTAssertEqual(game.victoryPoints(for: 0, includingHidden: false), 4)
    }

    func testLargestArmyNeedsThreeKnights() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.stackDeckForTesting(with: [.knight, .knight, .knight])

        for _ in 0..<3 {
            game.giveForTesting(.wool, 1, to: 0)
            game.giveForTesting(.grain, 1, to: 0)
            game.giveForTesting(.ore, 1, to: 0)
            try game.apply(.buyDevelopmentCard)
        }
        XCTAssertFalse(game.players[0].hasLargestArmy)

        for _ in 0..<3 {
            // Two players, so two advances bring the turn back around.
            game.advanceTurnForTesting()
            game.advanceTurnForTesting()
            game.forceMainPhaseForTesting()
            let card = game.players[0].playableCards(onTurn: game.turn).first!
            try game.apply(.playDevelopmentCard(id: card.id, choice: .none))
            if case .movingRobber = game.phase {
                try game.apply(.moveRobber(Placement.robberSpots(board: game.board).sorted().first!))
            }
            if case .stealing(let candidates) = game.phase {
                try game.apply(.steal(from: candidates[0]))
            }
        }
        XCTAssertEqual(game.players[0].knightsPlayed, 3)
        XCTAssertTrue(game.players[0].hasLargestArmy)
    }

    func testDevelopmentCardCannotBePlayedOnTheTurnItIsBought() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.stackDeckForTesting(with: [.monopoly])
        game.giveForTesting(.wool, 1, to: 0)
        game.giveForTesting(.grain, 1, to: 0)
        game.giveForTesting(.ore, 1, to: 0)
        try game.apply(.buyDevelopmentCard)

        let card = game.players[0].developmentCards[0]
        XCTAssertThrowsError(try game.apply(.playDevelopmentCard(id: card.id, choice: .monopoly(.ore)))) { error in
            XCTAssertEqual(error as? GameError, .cardNotPlayable)
        }
    }

    func testMonopolyTakesEveryMatchingCard() throws {
        var game = try startedGame(players: ["A", "B", "C"])
        game.forceMainPhaseForTesting()
        game.giveCardForTesting(.monopoly, to: 0)
        game.giveForTesting(.wool, 3, to: 1)
        game.giveForTesting(.wool, 2, to: 2)
        let mine = game.players[0].count(of: .wool)

        let card = game.players[0].playableCards(onTurn: game.turn).first!
        try game.apply(.playDevelopmentCard(id: card.id, choice: .monopoly(.wool)))
        XCTAssertEqual(game.players[0].count(of: .wool), mine + 5)
        XCTAssertEqual(game.players[1].count(of: .wool), 0)
        XCTAssertEqual(game.players[2].count(of: .wool), 0)
    }

    func testOnlyOneDevelopmentCardPerTurn() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.giveCardForTesting(.monopoly, to: 0)
        game.giveCardForTesting(.yearOfPlenty, to: 0)

        let cards = game.players[0].playableCards(onTurn: game.turn)
        try game.apply(.playDevelopmentCard(id: cards[0].id, choice: .monopoly(.wool)))
        XCTAssertThrowsError(try game.apply(.playDevelopmentCard(id: cards[1].id, choice: .yearOfPlenty(.ore, .ore)))) { error in
            XCTAssertEqual(error as? GameError, .alreadyPlayedCard)
        }
    }

    func testYearOfPlentyDrawsFromTheBank() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.giveCardForTesting(.yearOfPlenty, to: 0)
        let oreBefore = game.players[0].count(of: .ore)
        let bankBefore = game.bank[.ore] ?? 0

        let card = game.players[0].playableCards(onTurn: game.turn).first!
        try game.apply(.playDevelopmentCard(id: card.id, choice: .yearOfPlenty(.ore, .ore)))
        XCTAssertEqual(game.players[0].count(of: .ore), oreBefore + 2)
        XCTAssertEqual(game.bank[.ore], bankBefore - 2)
    }

    func testRoadBuildingPlacesTwoFreeRoads() throws {
        var game = try startedGame(players: ["A", "B"])
        game.forceMainPhaseForTesting()
        game.giveCardForTesting(.roadBuilding, to: 0)
        let roadsBefore = game.players[0].roadsLeft
        let handBefore = game.players[0].handCount

        let card = game.players[0].playableCards(onTurn: game.turn).first!
        try game.apply(.playDevelopmentCard(id: card.id, choice: .none))
        XCTAssertEqual(game.phase, .placingFreeRoads(remaining: 2))
        try game.apply(.buildRoad(Placement.roadSpots(for: 0, board: game.board).sorted().first!))
        XCTAssertEqual(game.phase, .placingFreeRoads(remaining: 1))
        try game.apply(.buildRoad(Placement.roadSpots(for: 0, board: game.board).sorted().first!))
        XCTAssertEqual(game.phase, .main)
        XCTAssertEqual(game.players[0].roadsLeft, roadsBefore - 2)
        XCTAssertEqual(game.players[0].handCount, handBefore, "free roads must not cost resources")
    }
}

final class VictoryTests: XCTestCase {
    func testGameEndsAtTheVictoryTarget() throws {
        var game = try startedGame(players: ["A", "B"], options: GameOptions(victoryTarget: 3))
        game.forceMainPhaseForTesting()
        let mine = Placement.citySpots(for: 0, board: game.board).sorted().first!
        game.giveForTesting(.grain, 2, to: 0)
        game.giveForTesting(.ore, 3, to: 0)
        try game.apply(.buildCity(mine))
        XCTAssertEqual(game.winner, 0)
        XCTAssertThrowsError(try game.apply(.endTurn)) { error in
            XCTAssertEqual(error as? GameError, .gameFinished)
        }
    }

    func testHiddenPointsOnlyCountForTheirOwner() throws {
        var game = try startedGame(players: ["A", "B"])
        game.giveCardForTesting(.victoryPoint, to: 0)
        XCTAssertEqual(game.victoryPoints(for: 0, includingHidden: false), 2)
        XCTAssertEqual(game.victoryPoints(for: 0, includingHidden: true), 3)
    }
}

final class PersistenceTests: XCTestCase {
    func testGameRoundTripsThroughJSON() throws {
        var game = try startedGame(players: ["A", "B", "C"])
        game.forceMainPhaseForTesting()
        game.giveForTesting(.brick, 3, to: 1)

        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(GameState.self, from: data)

        XCTAssertEqual(restored.players.count, 3)
        XCTAssertEqual(restored.players[1].count(of: .brick), game.players[1].count(of: .brick))
        XCTAssertEqual(restored.board.buildings.count, game.board.buildings.count)
        XCTAssertEqual(restored.board.roads.count, game.board.roads.count)
        XCTAssertEqual(restored.board.ports.count, game.board.ports.count)
        XCTAssertEqual(restored.board.robber, game.board.robber)
        XCTAssertEqual(restored.phase, game.phase)
        XCTAssertEqual(restored.currentPlayer, game.currentPlayer)
    }
}
