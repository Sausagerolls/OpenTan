import XCTest
@testable import OpenTanEngine

/// The published two-player variant: two neutral players, two dice rolls a
/// turn, and trade tokens.
final class TwoPlayerVariantTests: XCTestCase {
    private func variantGame(seed: UInt64 = 42) throws -> GameState {
        try startedGame(players: ["A", "B"], seed: seed, variant: true)
    }

    // MARK: - Set-up

    func testTwoNeutralPlayersJoinWithOneSettlementEach() throws {
        let game = try variantGame()
        XCTAssertEqual(game.realPlayers.count, 2)
        XCTAssertEqual(game.neutralPlayers.count, 2)

        for neutral in game.neutralPlayers {
            let owned = game.board.buildings.values.filter { $0.owner == neutral.id }
            XCTAssertEqual(owned.count, 1, "each neutral player starts with one settlement")
            XCTAssertEqual(owned.first?.kind, .settlement)
            XCTAssertEqual(neutral.settlementsLeft, Rules.settlementSupply - 1)
            XCTAssertEqual(game.board.roads.values.filter { $0 == neutral.id }.count, 0)
        }
    }

    func testNeutralSettlementsObeyTheDistanceRule() throws {
        let game = try variantGame()
        let corners = game.board.buildings.compactMap { vertex, building in
            game.players[building.owner].isNeutral ? vertex : nil
        }
        XCTAssertEqual(corners.count, 2)
        XCTAssertFalse(Geometry.neighbors(of: corners[0]).contains(corners[1]))
    }

    func testTheSecondSettlementStillPaysOutInTheVariant() throws {
        let game = try variantGame()
        for player in game.realPlayers {
            XCTAssertGreaterThan(
                player.handCount, 0,
                "\(player.name) should collect from their second settlement"
            )
            XCTAssertLessThanOrEqual(player.handCount, 3)
        }
    }

    func testRealPlayersStartWithFiveTradeTokens() throws {
        let game = try variantGame()
        for player in game.realPlayers {
            XCTAssertGreaterThanOrEqual(player.tradeTokens, Rules.startingTradeTokens)
        }
        let held = game.players.reduce(0) { $0 + $1.tradeTokens }
        XCTAssertEqual(held + game.tradeTokenSupply, Rules.tradeTokenPool)
    }

    func testOnlyRealPlayersTakeATurn() throws {
        var game = try variantGame()
        var seen: Set<Int> = []
        for _ in 0..<6 {
            seen.insert(game.currentPlayer)
            game.advanceTurnForTesting()
        }
        XCTAssertEqual(seen, [0, 1])
    }

    func testCoastAndDesertSettlementsPayTradeTokens() throws {
        var game = GameState(
            playerNames: ["A", "B"],
            options: GameOptions(twoPlayerVariant: true),
            seed: 77
        )
        let desert = game.board.tiles.values.first { $0.terrain == .desert }!.hex

        func bonus(of vertex: VertexID) -> Int {
            var value = 0
            if vertex.hexes.contains(desert) { value += Rules.desertSettlementTokens }
            if vertex.hexes.contains(where: { game.board.tiles[$0] == nil }) { value += Rules.coastSettlementTokens }
            return value
        }

        let spot = Placement.setupSettlementSpots(board: game.board)
            .sorted()
            .max { bonus(of: $0) < bonus(of: $1) }!
        XCTAssertGreaterThan(bonus(of: spot), 0, "the board should offer a coastal or desert corner")

        let before = game.players[game.currentPlayer].tradeTokens
        let owner = game.currentPlayer
        try game.apply(.placeSetupSettlement(spot))
        XCTAssertEqual(game.players[owner].tradeTokens, before + bonus(of: spot))
    }

    // MARK: - Two rolls a turn

    func testATurnRollsTwiceWithDifferentTotals() throws {
        var game = try variantGame()
        XCTAssertEqual(game.rollsRemaining, 2)

        try game.apply(.rollDice)
        let first = game.dice.map { $0.0 + $0.1 }
        XCTAssertNotNil(first)
        XCTAssertEqual(game.rollsRemaining, 1)
        if case .main = game.phase {
            XCTFail("the building phase must wait for the second roll")
        }

        try rollThroughToMain(&game)
        let second = game.dice.map { $0.0 + $0.1 }
        if first != 7, second != nil {
            XCTAssertNotEqual(first, second, "the second roll has to show a different total")
        }
        XCTAssertEqual(game.rollsRemaining, 0)
    }

    func testEveryPairOfRollsDiffers() throws {
        for seed in UInt64(1)...25 {
            var game = try variantGame(seed: seed)
            try game.apply(.rollDice)
            guard case .preRoll = game.phase else { continue }
            let first = game.dice!.0 + game.dice!.1
            try game.apply(.rollDice)
            let second = game.dice!.0 + game.dice!.1
            XCTAssertNotEqual(first, second, "seed \(seed)")
        }
    }

    func testNeutralPlayersNeverCollectResources() throws {
        var game = try variantGame()
        let neutralCorner = game.board.buildings.first { game.players[$0.value.owner].isNeutral }!
        let hex = neutralCorner.key.hexes.first { game.board.tile(at: $0)?.terrain.resource != nil }!
        let tile = game.board.tile(at: hex)!

        game.produceForTesting(total: tile.number!)
        XCTAssertEqual(game.players[neutralCorner.value.owner].handCount, 0)
    }

    // MARK: - Building for the neutral players

    func testBuildingARoadOwesTheNeutralPlayersAPiece() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.giveForTesting(.brick, 1, to: 0)
        game.giveForTesting(.lumber, 1, to: 0)

        try game.apply(.buildRoad(Placement.roadSpots(for: 0, board: game.board).sorted().first!))
        // The neutral players have no roads yet, so no settlement can connect
        // and a road is the only legal gift.
        XCTAssertEqual(game.phase, .neutralPlacement(mustBeRoad: true))

        let neutral = game.neutralPlayers[0].id
        let spot = game.neutralRoadSpots(for: neutral).sorted().first!
        try game.apply(.placeNeutralRoad(neutral: neutral, edge: spot))
        XCTAssertEqual(game.board.roads[spot], neutral)
        XCTAssertEqual(game.phase, .main)
    }

    func testYouCannotBuildAgainUntilTheNeutralPieceIsPlaced() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.giveForTesting(.brick, 2, to: 0)
        game.giveForTesting(.lumber, 2, to: 0)

        let spots = Placement.roadSpots(for: 0, board: game.board).sorted()
        try game.apply(.buildRoad(spots[0]))
        XCTAssertThrowsError(try game.apply(.buildRoad(spots[1]))) { error in
            XCTAssertEqual(error as? GameError, .wrongPhase)
        }
        XCTAssertThrowsError(try game.apply(.endTurn)) { error in
            XCTAssertEqual(error as? GameError, .wrongPhase)
        }
    }

    func testANeutralSettlementBecomesLegalOnceTheNeutralHasRoads() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        let neutral = game.neutralPlayers[0].id

        // Two rounds of building, each one handing the same neutral a road.
        for _ in 0..<2 {
            game.giveForTesting(.brick, 1, to: 0)
            game.giveForTesting(.lumber, 1, to: 0)
            try game.apply(.buildRoad(Placement.roadSpots(for: 0, board: game.board).sorted().first!))
            let road = game.neutralRoadSpots(for: neutral).sorted().first!
            try game.apply(.placeNeutralRoad(neutral: neutral, edge: road))
        }

        XCTAssertTrue(game.anyNeutralSettlementSpotExists)

        game.giveForTesting(.brick, 1, to: 0)
        game.giveForTesting(.lumber, 1, to: 0)
        try game.apply(.buildRoad(Placement.roadSpots(for: 0, board: game.board).sorted().first!))
        XCTAssertEqual(game.phase, .neutralPlacement(mustBeRoad: false))

        let corner = game.neutralSettlementSpots(for: neutral).sorted().first!
        try game.apply(.placeNeutralSettlement(neutral: neutral, vertex: corner))
        XCTAssertEqual(game.board.buildings[corner]?.owner, neutral)
        XCTAssertEqual(game.phase, .main)
    }

    func testCitiesAndDevelopmentCardsOweTheNeutralPlayersNothing() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()

        game.giveForTesting(.grain, 2, to: 0)
        game.giveForTesting(.ore, 3, to: 0)
        try game.apply(.buildCity(Placement.citySpots(for: 0, board: game.board).sorted().first!))
        XCTAssertEqual(game.phase, .main)

        game.giveForTesting(.wool, 1, to: 0)
        game.giveForTesting(.grain, 1, to: 0)
        game.giveForTesting(.ore, 1, to: 0)
        try game.apply(.buyDevelopmentCard)
        XCTAssertEqual(game.phase, .main)
    }

    func testNeutralPlayersCanTakeTheLongestRoad() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        let neutral = game.neutralPlayers[0].id

        for _ in 0..<6 {
            game.giveForTesting(.brick, 1, to: 0)
            game.giveForTesting(.lumber, 1, to: 0)
            guard let mine = Placement.roadSpots(for: 0, board: game.board).sorted().first else { break }
            try game.apply(.buildRoad(mine))
            guard let theirs = game.neutralRoadSpots(for: neutral).sorted().first else { break }
            try game.apply(.placeNeutralRoad(neutral: neutral, edge: theirs))
        }
        XCTAssertGreaterThanOrEqual(game.players[neutral].longestRoadLength, 1)
        // Whoever leads, the award is computed over neutral players too.
        let holder = game.players.first { $0.hasLongestRoad }
        if let holder {
            XCTAssertEqual(
                holder.longestRoadLength,
                game.players.map(\.longestRoadLength).max()
            )
        }
    }

    // MARK: - Trade tokens

    func testAnActionCostsOneTokenWhileLevelAndTwoWhileAhead() throws {
        var game = try variantGame()
        XCTAssertEqual(game.tradeTokenCost(for: 0), 1, "both players start level")

        game.forceMainPhaseForTesting()
        game.giveForTesting(.grain, 2, to: 0)
        game.giveForTesting(.ore, 3, to: 0)
        try game.apply(.buildCity(Placement.citySpots(for: 0, board: game.board).sorted().first!))
        XCTAssertEqual(game.tradeTokenCost(for: 0), 2, "the leader pays two")
        XCTAssertEqual(game.tradeTokenCost(for: 1), 1)
    }

    func testForcedTradeSwapsTwoCardsEachWay() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.clearHandsForTesting()
        game.giveForTesting(.ore, 2, to: 0)
        game.giveForTesting(.wool, 4, to: 1)

        let myHand = game.players[0].handCount
        let theirHand = game.players[1].handCount
        let tokens = game.players[0].tradeTokens
        let cost = game.tradeTokenCost(for: 0)

        try game.apply(.forcedTrade(give: [.ore: 2]))

        XCTAssertEqual(game.players[0].tradeTokens, tokens - cost)
        XCTAssertEqual(game.players[0].handCount, myHand, "two in, two out")
        XCTAssertEqual(game.players[1].handCount, theirHand)
        XCTAssertEqual(game.players[0].count(of: .ore), 0)
        XCTAssertEqual(game.players[1].count(of: .ore), 2)
    }

    func testForcedTradeMustOfferExactlyTwoCards() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.giveForTesting(.ore, 3, to: 0)
        game.giveForTesting(.wool, 2, to: 1)

        XCTAssertThrowsError(try game.apply(.forcedTrade(give: [.ore: 1]))) { error in
            XCTAssertEqual(error as? GameError, .invalidTrade)
        }
        XCTAssertThrowsError(try game.apply(.forcedTrade(give: [.ore: 3]))) { error in
            XCTAssertEqual(error as? GameError, .invalidTrade)
        }
    }

    func testForcedTradeTakesTheLastCardFromAOneCardHand() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.clearHandsForTesting()
        game.giveForTesting(.ore, 2, to: 0)
        game.giveForTesting(.wool, 1, to: 1)

        try game.apply(.forcedTrade(give: [.ore: 2]))
        XCTAssertEqual(game.players[0].count(of: .wool), 1)
        XCTAssertEqual(game.players[1].count(of: .wool), 0)
        XCTAssertEqual(game.players[1].count(of: .ore), 2)
    }

    func testMovingTheRobberBackToTheDesertCostsTokens() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        let desert = game.board.tiles.values.first { $0.terrain == .desert }!.hex
        game.setRobberForTesting(game.board.hexes.first { $0 != desert }!)

        let tokens = game.players[0].tradeTokens
        let cost = game.tradeTokenCost(for: 0)
        try game.apply(.moveRobberToDesert)

        XCTAssertEqual(game.board.robber, desert)
        XCTAssertEqual(game.players[0].tradeTokens, tokens - cost)
    }

    func testRunningOutOfTokensBlocksTheAction() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.setTradeTokensForTesting(0, for: 0)
        game.giveForTesting(.ore, 2, to: 0)
        game.giveForTesting(.wool, 2, to: 1)

        XCTAssertThrowsError(try game.apply(.forcedTrade(give: [.ore: 2]))) { error in
            XCTAssertEqual(error as? GameError, .notEnoughTradeTokens)
        }
    }

    func testTradingAKnightBackInPaysTwoTokensOncePerTurn() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.setKnightsForTesting(2, for: 0)
        game.setTradeTokensForTesting(0, for: 0)

        try game.apply(.exchangeKnightForTokens)
        XCTAssertEqual(game.players[0].knightsPlayed, 1)
        XCTAssertEqual(game.players[0].tradeTokens, Rules.knightExchangeTokens)

        XCTAssertThrowsError(try game.apply(.exchangeKnightForTokens)) { error in
            XCTAssertEqual(error as? GameError, .knightExchangeUsed)
        }
    }

    func testDiscardingAKnightCanCostTheLargestArmy() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.setKnightsForTesting(3, for: 0)
        game.setKnightsForTesting(2, for: 1)
        game.setLargestArmyForTesting(0)

        try game.apply(.exchangeKnightForTokens)
        XCTAssertEqual(game.players[0].knightsPlayed, 2)
        XCTAssertFalse(game.players[0].hasLargestArmy, "two knights is below the threshold")
        XCTAssertFalse(game.players[1].hasLargestArmy)
    }

    func testDiscardingAKnightHandsTheArmyOverWhenTheOpponentLeads() throws {
        var game = try variantGame()
        game.forceMainPhaseForTesting()
        game.setKnightsForTesting(4, for: 0)
        game.setKnightsForTesting(4, for: 1)
        game.setLargestArmyForTesting(0)

        try game.apply(.exchangeKnightForTokens)
        XCTAssertEqual(game.players[0].knightsPlayed, 3)
        XCTAssertFalse(game.players[0].hasLargestArmy)
        XCTAssertTrue(game.players[1].hasLargestArmy, "the opponent now has the most")
    }

    func testTokenActionsAreRejectedOutsideTheVariant() throws {
        var game = try startedGame(players: ["A", "B", "C"])
        game.forceMainPhaseForTesting()
        game.giveForTesting(.ore, 2, to: 0)
        XCTAssertThrowsError(try game.apply(.forcedTrade(give: [.ore: 2]))) { error in
            XCTAssertEqual(error as? GameError, .notAvailableInThisGame)
        }
        XCTAssertThrowsError(try game.apply(.moveRobberToDesert)) { error in
            XCTAssertEqual(error as? GameError, .notAvailableInThisGame)
        }
    }

    func testVariantGameRoundTripsThroughJSON() throws {
        var game = try variantGame()
        try game.apply(.rollDice)
        let data = try JSONEncoder().encode(game)
        let restored = try JSONDecoder().decode(GameState.self, from: data)

        XCTAssertTrue(restored.options.twoPlayerVariant)
        XCTAssertEqual(restored.neutralPlayers.count, 2)
        XCTAssertEqual(restored.rollsRemaining, game.rollsRemaining)
        XCTAssertEqual(restored.tradeTokenSupply, game.tradeTokenSupply)
        XCTAssertEqual(restored.players[0].tradeTokens, game.players[0].tradeTokens)
    }
}
