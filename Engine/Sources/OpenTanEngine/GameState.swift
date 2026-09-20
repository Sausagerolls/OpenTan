import Foundation

public struct GameOptions: Codable, Sendable, Equatable {
    public var layout: BoardLayout
    public var balancedNumbers: Bool
    public var victoryTarget: Int
    public var discardLimit: Int
    /// The five- and six-player game gives everyone a chance to build between
    /// turns. Off by default on the small board.
    public var specialBuildPhase: Bool

    public init(
        layout: BoardLayout = .standard,
        balancedNumbers: Bool = true,
        victoryTarget: Int = Rules.defaultVictoryTarget,
        discardLimit: Int = Rules.defaultDiscardLimit,
        specialBuildPhase: Bool = false
    ) {
        self.layout = layout
        self.balancedNumbers = balancedNumbers
        self.victoryTarget = victoryTarget
        self.discardLimit = discardLimit
        self.specialBuildPhase = specialBuildPhase
    }

    public static func recommended(forPlayerCount count: Int) -> GameOptions {
        let layout = BoardLayout.recommended(forPlayerCount: count)
        return GameOptions(layout: layout, specialBuildPhase: layout == .large)
    }
}

public enum Phase: Codable, Hashable, Sendable {
    /// Opening placement. `round` is 1 for the first settlement and 2 for the
    /// second, which is played in reverse seating order.
    case setupSettlement(round: Int)
    case setupRoad(round: Int, from: VertexID)
    /// Before the dice: the player may play one development card or roll.
    case preRoll
    /// A seven was rolled and players over the hand limit must discard.
    case discarding
    case movingRobber
    case stealing(candidates: [Int])
    case main
    case placingFreeRoads(remaining: Int)
    case awaitingTradeResponse(TradeOffer)
    /// Five- and six-player games: everyone else may buy between turns.
    case specialBuild(player: Int)
    case gameOver(winner: Int)
}

public struct TradeOffer: Codable, Hashable, Sendable {
    public var proposer: Int
    public var partner: Int
    public var give: [Resource: Int]
    public var receive: [Resource: Int]

    public init(proposer: Int, partner: Int, give: [Resource: Int], receive: [Resource: Int]) {
        self.proposer = proposer
        self.partner = partner
        self.give = give.filter { $0.value > 0 }
        self.receive = receive.filter { $0.value > 0 }
    }
}

public enum GameAction: Sendable {
    case placeSetupSettlement(VertexID)
    case placeSetupRoad(EdgeID)
    case rollDice
    case discard(player: Int, cards: [Resource: Int])
    case moveRobber(Hex)
    case steal(from: Int)
    case buildRoad(EdgeID)
    case buildSettlement(VertexID)
    case buildCity(VertexID)
    case buyDevelopmentCard
    case playDevelopmentCard(id: UUID, choice: DevelopmentChoice)
    case bankTrade(give: Resource, receive: Resource)
    case proposeTrade(TradeOffer)
    case respondToTrade(accept: Bool)
    case endTurn
    case endSpecialBuild
}

public enum DevelopmentChoice: Sendable, Equatable {
    case none
    case yearOfPlenty(Resource, Resource)
    case monopoly(Resource)
}

public enum GameError: Error, LocalizedError, Equatable {
    case wrongPhase
    case notYourTurn
    case illegalPlacement
    case cannotAfford
    case outOfPieces
    case deckEmpty
    case bankEmpty(Resource)
    case cardNotPlayable
    case alreadyPlayedCard
    case invalidDiscard
    case invalidTrade
    case gameFinished

    public var errorDescription: String? {
        switch self {
        case .wrongPhase: return "That is not allowed right now."
        case .notYourTurn: return "It is not your turn."
        case .illegalPlacement: return "You cannot build there."
        case .cannotAfford: return "You do not have the resources for that."
        case .outOfPieces: return "You have no pieces of that kind left."
        case .deckEmpty: return "The development card deck is empty."
        case .bankEmpty(let resource): return "The bank is out of \(resource.displayName.lowercased())."
        case .cardNotPlayable: return "That card cannot be played now."
        case .alreadyPlayedCard: return "You have already played a development card this turn."
        case .invalidDiscard: return "That is not the right number of cards to discard."
        case .invalidTrade: return "That trade is not valid."
        case .gameFinished: return "The game is over."
        }
    }
}

/// A single line in the running game log, shown to every player.
public struct LogEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var turn: Int
    public var text: String

    public init(id: UUID = UUID(), turn: Int, text: String) {
        self.id = id
        self.turn = turn
        self.text = text
    }
}

public struct GameState: Codable, Sendable {
    public private(set) var options: GameOptions
    public private(set) var board: Board
    public private(set) var players: [Player]
    public private(set) var bank: [Resource: Int]
    public private(set) var developmentDeck: [DevelopmentCard]

    public private(set) var currentPlayer: Int
    public private(set) var phase: Phase
    public private(set) var turn: Int
    public private(set) var dice: (Int, Int)?
    public private(set) var log: [LogEntry] = []

    /// Set while the opening placement runs in reverse seating order.
    private var setupOrder: [Int] = []
    private var setupIndex: Int = 0
    private var playedCardThisTurn = false
    private var phaseAfterRobber: Phase = .main
    private var pendingDiscards: [Int: Int] = [:]
    private var seed: UInt64

    private enum CodingKeys: String, CodingKey {
        case options, board, players, bank, developmentDeck, currentPlayer, phase, turn
        case diceA, diceB, log, setupOrder, setupIndex, playedCardThisTurn
        case phaseAfterRobber, pendingDiscards, seed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = try container.decode(GameOptions.self, forKey: .options)
        board = try container.decode(Board.self, forKey: .board)
        players = try container.decode([Player].self, forKey: .players)
        bank = try container.decode([Resource: Int].self, forKey: .bank)
        developmentDeck = try container.decode([DevelopmentCard].self, forKey: .developmentDeck)
        currentPlayer = try container.decode(Int.self, forKey: .currentPlayer)
        phase = try container.decode(Phase.self, forKey: .phase)
        turn = try container.decode(Int.self, forKey: .turn)
        log = try container.decode([LogEntry].self, forKey: .log)
        setupOrder = try container.decode([Int].self, forKey: .setupOrder)
        setupIndex = try container.decode(Int.self, forKey: .setupIndex)
        playedCardThisTurn = try container.decode(Bool.self, forKey: .playedCardThisTurn)
        phaseAfterRobber = try container.decode(Phase.self, forKey: .phaseAfterRobber)
        pendingDiscards = try container.decode([Int: Int].self, forKey: .pendingDiscards)
        seed = try container.decode(UInt64.self, forKey: .seed)
        if let a = try container.decodeIfPresent(Int.self, forKey: .diceA),
           let b = try container.decodeIfPresent(Int.self, forKey: .diceB) {
            dice = (a, b)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(options, forKey: .options)
        try container.encode(board, forKey: .board)
        try container.encode(players, forKey: .players)
        try container.encode(bank, forKey: .bank)
        try container.encode(developmentDeck, forKey: .developmentDeck)
        try container.encode(currentPlayer, forKey: .currentPlayer)
        try container.encode(phase, forKey: .phase)
        try container.encode(turn, forKey: .turn)
        try container.encode(log, forKey: .log)
        try container.encode(setupOrder, forKey: .setupOrder)
        try container.encode(setupIndex, forKey: .setupIndex)
        try container.encode(playedCardThisTurn, forKey: .playedCardThisTurn)
        try container.encode(phaseAfterRobber, forKey: .phaseAfterRobber)
        try container.encode(pendingDiscards, forKey: .pendingDiscards)
        try container.encode(seed, forKey: .seed)
        try container.encodeIfPresent(dice?.0, forKey: .diceA)
        try container.encodeIfPresent(dice?.1, forKey: .diceB)
    }

    public init(playerNames: [String], options: GameOptions? = nil, seed: UInt64? = nil) {
        precondition(playerNames.count >= 2, "a game needs at least two players")
        let resolved = options ?? GameOptions.recommended(forPlayerCount: playerNames.count)
        self.options = resolved
        self.seed = seed ?? UInt64.random(in: UInt64.min...UInt64.max)

        var rng = SeededGenerator(seed: self.seed)
        board = BoardGenerator.make(layout: resolved.layout, balanced: resolved.balancedNumbers, using: &rng)
        players = playerNames.enumerated().map { index, name in
            Player(id: index, name: name, color: PlayerColor.palette[index % PlayerColor.palette.count])
        }
        let supply = resolved.layout == .large ? 24 : Rules.bankSupplyPerResource
        bank = Resource.allCases.reduce(into: [:]) { $0[$1] = supply }
        developmentDeck = Rules.developmentDeck(for: resolved.layout).shuffled(using: &rng)

        let order = Array(players.indices)
        setupOrder = order + order.reversed()
        setupIndex = 0
        currentPlayer = setupOrder[0]
        phase = .setupSettlement(round: 1)
        turn = 1
        log = [LogEntry(turn: 1, text: "Game started with \(playerNames.count) players.")]
    }

    // MARK: - Derived state

    public var currentPlayerObject: Player { players[currentPlayer] }

    public var winner: Int? {
        if case .gameOver(let winner) = phase { return winner }
        return nil
    }

    public func victoryPoints(for player: Int, includingHidden: Bool) -> Int {
        var points = board.buildings.values
            .filter { $0.owner == player }
            .reduce(0) { $0 + $1.kind.victoryPoints }
        if players[player].hasLongestRoad { points += 2 }
        if players[player].hasLargestArmy { points += 2 }
        if includingHidden { points += players[player].hiddenVictoryPoints }
        return points
    }

    /// Cards a player must still discard after a seven.
    public func discardsOwed(by player: Int) -> Int { pendingDiscards[player] ?? 0 }

    public var playersOwingDiscards: [Int] { pendingDiscards.keys.sorted() }

    public var hasPlayedDevelopmentCardThisTurn: Bool { playedCardThisTurn }

    // MARK: - Action entry point

    public mutating func apply(_ action: GameAction) throws {
        if case .gameOver = phase, !isDiscard(action) { throw GameError.gameFinished }

        switch action {
        case .placeSetupSettlement(let vertex): try placeSetupSettlement(vertex)
        case .placeSetupRoad(let edge): try placeSetupRoad(edge)
        case .rollDice: try rollDice()
        case .discard(let player, let cards): try discard(player: player, cards: cards)
        case .moveRobber(let hex): try moveRobber(to: hex)
        case .steal(let victim): try steal(from: victim)
        case .buildRoad(let edge): try buildRoad(edge)
        case .buildSettlement(let vertex): try buildSettlement(vertex)
        case .buildCity(let vertex): try buildCity(vertex)
        case .buyDevelopmentCard: try buyDevelopmentCard()
        case .playDevelopmentCard(let id, let choice): try playDevelopmentCard(id: id, choice: choice)
        case .bankTrade(let give, let receive): try bankTrade(give: give, receive: receive)
        case .proposeTrade(let offer): try proposeTrade(offer)
        case .respondToTrade(let accept): try respondToTrade(accept: accept)
        case .endTurn: try endTurn()
        case .endSpecialBuild: try endSpecialBuild()
        }
    }

    private func isDiscard(_ action: GameAction) -> Bool {
        if case .discard = action { return true }
        return false
    }

    // MARK: - Opening placement

    private mutating func placeSetupSettlement(_ vertex: VertexID) throws {
        guard case .setupSettlement(let round) = phase else { throw GameError.wrongPhase }
        guard Placement.isCornerOpen(vertex, board: board) else { throw GameError.illegalPlacement }

        board.buildings[vertex] = Building(kind: .settlement, owner: currentPlayer)
        players[currentPlayer].settlementsLeft -= 1
        note("\(players[currentPlayer].name) placed a settlement.")

        if round == 2 {
            // The second settlement pays out the tiles around it immediately.
            for hex in vertex.hexes {
                guard let tile = board.tile(at: hex), let resource = tile.terrain.resource else { continue }
                grant(resource, 1, to: currentPlayer)
            }
        }
        phase = .setupRoad(round: round, from: vertex)
    }

    private mutating func placeSetupRoad(_ edge: EdgeID) throws {
        guard case .setupRoad(let round, let vertex) = phase else { throw GameError.wrongPhase }
        guard Placement.setupRoadSpots(from: vertex, board: board).contains(edge) else {
            throw GameError.illegalPlacement
        }

        board.roads[edge] = currentPlayer
        players[currentPlayer].roadsLeft -= 1
        recomputeLongestRoad()
        note("\(players[currentPlayer].name) placed a road.")

        setupIndex += 1
        if setupIndex >= setupOrder.count {
            currentPlayer = setupOrder[0]
            phase = .preRoll
            note("Opening placement finished. \(players[currentPlayer].name) starts.")
            return
        }
        currentPlayer = setupOrder[setupIndex]
        let nextRound = setupIndex < players.count ? 1 : 2
        _ = round
        phase = .setupSettlement(round: nextRound)
    }

    // MARK: - Dice and production

    private mutating func rollDice() throws {
        guard case .preRoll = phase else { throw GameError.wrongPhase }
        var rng = SeededGenerator(seed: nextSeed())
        let a = Int.random(in: 1...6, using: &rng)
        let b = Int.random(in: 1...6, using: &rng)
        dice = (a, b)
        let total = a + b
        note("\(players[currentPlayer].name) rolled \(total).")

        if total == 7 {
            startRobberSequence()
        } else {
            produce(for: total)
            phase = .main
        }
    }

    private mutating func startRobberSequence() {
        pendingDiscards = [:]
        for player in players where player.handCount > options.discardLimit {
            pendingDiscards[player.id] = player.handCount / 2
        }
        phaseAfterRobber = .main
        phase = pendingDiscards.isEmpty ? .movingRobber : .discarding
        if !pendingDiscards.isEmpty {
            note("Players over \(options.discardLimit) cards must discard half.")
        }
    }

    /// Hands out resources for a dice total, honouring the robber and the
    /// bank's supply. If the bank cannot pay every claim on a resource, and
    /// more than one player is owed it, nobody receives that resource.
    private mutating func produce(for total: Int) {
        var claims: [Resource: [Int: Int]] = [:]
        for (hex, tile) in board.tiles {
            guard tile.number == total, hex != board.robber, let resource = tile.terrain.resource else { continue }
            for vertex in Geometry.corners(of: hex) {
                guard let building = board.buildings[vertex] else { continue }
                claims[resource, default: [:]][building.owner, default: 0] += building.kind.yield
            }
        }

        for (resource, byPlayer) in claims.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
            let demand = byPlayer.values.reduce(0, +)
            let available = bank[resource] ?? 0
            if demand <= available {
                for (player, amount) in byPlayer.sorted(by: { $0.key < $1.key }) {
                    grant(resource, amount, to: player)
                }
            } else if byPlayer.count == 1, let (player, _) = byPlayer.first, available > 0 {
                grant(resource, available, to: player)
                note("The bank ran low: \(players[player].name) took the last \(available) \(resource.displayName.lowercased()).")
            } else {
                note("The bank is out of \(resource.displayName.lowercased()); nobody collects it.")
            }
        }
    }

    // MARK: - Robber

    private mutating func discard(player: Int, cards: [Resource: Int]) throws {
        guard case .discarding = phase else { throw GameError.wrongPhase }
        guard let owed = pendingDiscards[player] else { throw GameError.wrongPhase }
        let total = cards.values.reduce(0, +)
        guard total == owed else { throw GameError.invalidDiscard }
        guard cards.allSatisfy({ players[player].count(of: $0.key) >= $0.value && $0.value >= 0 }) else {
            throw GameError.invalidDiscard
        }

        for (resource, amount) in cards {
            players[player].resources[resource, default: 0] -= amount
            bank[resource, default: 0] += amount
        }
        pendingDiscards[player] = nil
        note("\(players[player].name) discarded \(total) cards.")

        if pendingDiscards.isEmpty {
            phase = .movingRobber
        }
    }

    private mutating func moveRobber(to hex: Hex) throws {
        guard case .movingRobber = phase else { throw GameError.wrongPhase }
        guard Placement.robberSpots(board: board).contains(hex) else { throw GameError.illegalPlacement }

        board.robber = hex
        note("\(players[currentPlayer].name) moved the robber.")

        let candidates = board.playersAdjacent(to: hex, excluding: currentPlayer)
            .filter { players[$0].handCount > 0 }
        if candidates.isEmpty {
            phase = phaseAfterRobber
        } else if candidates.count == 1 {
            try steal(from: candidates[0], force: true)
        } else {
            phase = .stealing(candidates: candidates)
        }
    }

    private mutating func steal(from victim: Int) throws {
        guard case .stealing(let candidates) = phase, candidates.contains(victim) else {
            throw GameError.wrongPhase
        }
        try steal(from: victim, force: true)
    }

    private mutating func steal(from victim: Int, force: Bool) throws {
        var pool: [Resource] = []
        for resource in Resource.allCases {
            pool.append(contentsOf: Array(repeating: resource, count: players[victim].count(of: resource)))
        }
        guard !pool.isEmpty else {
            phase = phaseAfterRobber
            return
        }
        var rng = SeededGenerator(seed: nextSeed())
        let stolen = pool.randomElement(using: &rng)!
        players[victim].resources[stolen, default: 0] -= 1
        players[currentPlayer].receive(stolen)
        note("\(players[currentPlayer].name) stole a card from \(players[victim].name).")
        phase = phaseAfterRobber
    }

    // MARK: - Building

    private mutating func buildRoad(_ edge: EdgeID) throws {
        let free: Bool
        switch phase {
        case .main, .specialBuild: free = false
        case .placingFreeRoads: free = true
        default: throw GameError.wrongPhase
        }

        guard players[currentBuilder].roadsLeft > 0 else { throw GameError.outOfPieces }
        guard Placement.canBuildRoad(edge, for: currentBuilder, board: board) else {
            throw GameError.illegalPlacement
        }
        if !free {
            guard players[currentBuilder].canAfford(Rules.roadCost) else { throw GameError.cannotAfford }
            spend(Rules.roadCost, by: currentBuilder)
        }

        board.roads[edge] = currentBuilder
        players[currentBuilder].roadsLeft -= 1
        recomputeLongestRoad()
        note("\(players[currentBuilder].name) built a road.")

        if case .placingFreeRoads(let remaining) = phase {
            let left = remaining - 1
            phase = left > 0 && Placement.roadSpots(for: currentBuilder, board: board).isEmpty == false
                ? .placingFreeRoads(remaining: left)
                : .main
        }
        checkForWinner()
    }

    private mutating func buildSettlement(_ vertex: VertexID) throws {
        guard isBuildPhase else { throw GameError.wrongPhase }
        guard players[currentBuilder].settlementsLeft > 0 else { throw GameError.outOfPieces }
        guard Placement.settlementSpots(for: currentBuilder, board: board).contains(vertex) else {
            throw GameError.illegalPlacement
        }
        guard players[currentBuilder].canAfford(Rules.settlementCost) else { throw GameError.cannotAfford }

        spend(Rules.settlementCost, by: currentBuilder)
        board.buildings[vertex] = Building(kind: .settlement, owner: currentBuilder)
        players[currentBuilder].settlementsLeft -= 1
        // A new settlement can cut an opponent's road in two.
        recomputeLongestRoad()
        note("\(players[currentBuilder].name) built a settlement.")
        checkForWinner()
    }

    private mutating func buildCity(_ vertex: VertexID) throws {
        guard isBuildPhase else { throw GameError.wrongPhase }
        guard players[currentBuilder].citiesLeft > 0 else { throw GameError.outOfPieces }
        guard let building = board.buildings[vertex],
              building.owner == currentBuilder,
              building.kind == .settlement else { throw GameError.illegalPlacement }
        guard players[currentBuilder].canAfford(Rules.cityCost) else { throw GameError.cannotAfford }

        spend(Rules.cityCost, by: currentBuilder)
        board.buildings[vertex] = Building(kind: .city, owner: currentBuilder)
        players[currentBuilder].citiesLeft -= 1
        players[currentBuilder].settlementsLeft += 1
        note("\(players[currentBuilder].name) built a city.")
        checkForWinner()
    }

    private mutating func buyDevelopmentCard() throws {
        guard isBuildPhase else { throw GameError.wrongPhase }
        guard !developmentDeck.isEmpty else { throw GameError.deckEmpty }
        guard players[currentBuilder].canAfford(Rules.developmentCardCost) else { throw GameError.cannotAfford }

        spend(Rules.developmentCardCost, by: currentBuilder)
        let card = developmentDeck.removeLast()
        players[currentBuilder].developmentCards.append(
            HeldDevelopmentCard(card: card, boughtOnTurn: turn)
        )
        note("\(players[currentBuilder].name) bought a development card.")
        checkForWinner()
    }

    // MARK: - Development cards

    private mutating func playDevelopmentCard(id: UUID, choice: DevelopmentChoice) throws {
        switch phase {
        case .preRoll, .main: break
        default: throw GameError.wrongPhase
        }
        guard !playedCardThisTurn else { throw GameError.alreadyPlayedCard }
        guard let index = players[currentPlayer].developmentCards.firstIndex(where: { $0.id == id }) else {
            throw GameError.cardNotPlayable
        }
        let held = players[currentPlayer].developmentCards[index]
        guard held.card.isPlayable, held.boughtOnTurn < turn else { throw GameError.cardNotPlayable }

        switch held.card {
        case .knight:
            players[currentPlayer].developmentCards.remove(at: index)
            players[currentPlayer].knightsPlayed += 1
            playedCardThisTurn = true
            note("\(players[currentPlayer].name) played a knight.")
            recomputeLargestArmy()
            phaseAfterRobber = isPreRoll ? .preRoll : .main
            phase = .movingRobber

        case .roadBuilding:
            guard !Placement.roadSpots(for: currentPlayer, board: board).isEmpty,
                  players[currentPlayer].roadsLeft > 0 else { throw GameError.cardNotPlayable }
            players[currentPlayer].developmentCards.remove(at: index)
            playedCardThisTurn = true
            let free = min(2, players[currentPlayer].roadsLeft)
            note("\(players[currentPlayer].name) played Road Building.")
            phase = .placingFreeRoads(remaining: free)

        case .yearOfPlenty:
            guard case .yearOfPlenty(let first, let second) = choice else { throw GameError.cardNotPlayable }
            guard (bank[first] ?? 0) > 0, (bank[second] ?? 0) >= (first == second ? 2 : 1) else {
                throw GameError.bankEmpty(first)
            }
            players[currentPlayer].developmentCards.remove(at: index)
            playedCardThisTurn = true
            grant(first, 1, to: currentPlayer)
            grant(second, 1, to: currentPlayer)
            note("\(players[currentPlayer].name) played Year of Plenty.")

        case .monopoly:
            guard case .monopoly(let resource) = choice else { throw GameError.cardNotPlayable }
            players[currentPlayer].developmentCards.remove(at: index)
            playedCardThisTurn = true
            var taken = 0
            for other in players.indices where other != currentPlayer {
                let amount = players[other].count(of: resource)
                players[other].resources[resource] = 0
                players[currentPlayer].receive(resource, amount)
                taken += amount
            }
            note("\(players[currentPlayer].name) monopolised \(resource.displayName.lowercased()) and took \(taken).")

        case .victoryPoint:
            throw GameError.cardNotPlayable
        }
        checkForWinner()
    }

    // MARK: - Trading

    private mutating func bankTrade(give: Resource, receive: Resource) throws {
        // Trading with the bank is part of your own turn; the special build
        // phase only allows buying and building.
        guard case .main = phase else { throw GameError.wrongPhase }
        guard give != receive else { throw GameError.invalidTrade }
        let rate = Placement.tradeRate(for: give, player: currentBuilder, board: board)
        guard players[currentBuilder].count(of: give) >= rate else { throw GameError.cannotAfford }
        guard (bank[receive] ?? 0) > 0 else { throw GameError.bankEmpty(receive) }

        players[currentBuilder].resources[give, default: 0] -= rate
        bank[give, default: 0] += rate
        grant(receive, 1, to: currentBuilder)
        note("\(players[currentBuilder].name) traded \(rate) \(give.displayName.lowercased()) for 1 \(receive.displayName.lowercased()).")
    }

    private mutating func proposeTrade(_ offer: TradeOffer) throws {
        guard case .main = phase else { throw GameError.wrongPhase }
        guard offer.proposer == currentPlayer, offer.partner != currentPlayer else { throw GameError.invalidTrade }
        guard players.indices.contains(offer.partner) else { throw GameError.invalidTrade }
        guard !offer.give.isEmpty || !offer.receive.isEmpty else { throw GameError.invalidTrade }
        guard offer.give.allSatisfy({ players[currentPlayer].count(of: $0.key) >= $0.value }) else {
            throw GameError.cannotAfford
        }
        phase = .awaitingTradeResponse(offer)
    }

    private mutating func respondToTrade(accept: Bool) throws {
        guard case .awaitingTradeResponse(let offer) = phase else { throw GameError.wrongPhase }
        defer { phase = .main }
        guard accept else {
            note("\(players[offer.partner].name) declined the trade.")
            return
        }
        guard offer.give.allSatisfy({ players[offer.proposer].count(of: $0.key) >= $0.value }),
              offer.receive.allSatisfy({ players[offer.partner].count(of: $0.key) >= $0.value }) else {
            throw GameError.invalidTrade
        }
        for (resource, amount) in offer.give {
            players[offer.proposer].resources[resource, default: 0] -= amount
            players[offer.partner].receive(resource, amount)
        }
        for (resource, amount) in offer.receive {
            players[offer.partner].resources[resource, default: 0] -= amount
            players[offer.proposer].receive(resource, amount)
        }
        note("\(players[offer.proposer].name) traded with \(players[offer.partner].name).")
    }

    // MARK: - Turn flow

    private mutating func endTurn() throws {
        guard case .main = phase else { throw GameError.wrongPhase }
        checkForWinner()
        if case .gameOver = phase { return }

        if options.specialBuildPhase, players.count > 1 {
            let next = (currentPlayer + 1) % players.count
            if next != currentPlayer {
                phase = .specialBuild(player: next)
                return
            }
        }
        advanceTurn()
    }

    private mutating func endSpecialBuild() throws {
        guard case .specialBuild(let player) = phase else { throw GameError.wrongPhase }
        let next = (player + 1) % players.count
        if next == currentPlayer {
            advanceTurn()
        } else {
            phase = .specialBuild(player: next)
        }
    }

    private mutating func advanceTurn() {
        currentPlayer = (currentPlayer + 1) % players.count
        turn += 1
        dice = nil
        playedCardThisTurn = false
        phase = .preRoll
    }

    // MARK: - Awards

    private mutating func recomputeLongestRoad() {
        for index in players.indices {
            players[index].longestRoadLength = Placement.longestRoad(for: index, board: board)
        }
        let holder = players.firstIndex { $0.hasLongestRoad }
        let best = players.map(\.longestRoadLength).max() ?? 0
        guard best >= Rules.longestRoadThreshold else {
            if let holder {
                players[holder].hasLongestRoad = false
                note("\(players[holder].name) lost the longest road.")
            }
            return
        }

        let leaders = players.filter { $0.longestRoadLength == best }.map(\.id)
        // The current holder keeps the card on a tie.
        if let holder, players[holder].longestRoadLength == best { return }
        guard leaders.count == 1, let winner = leaders.first else {
            if let holder {
                players[holder].hasLongestRoad = false
                note("\(players[holder].name) lost the longest road; it is tied.")
            }
            return
        }
        if let holder { players[holder].hasLongestRoad = false }
        players[winner].hasLongestRoad = true
        note("\(players[winner].name) has the longest road (\(best)).")
    }

    private mutating func recomputeLargestArmy() {
        let best = players.map(\.knightsPlayed).max() ?? 0
        guard best >= Rules.largestArmyThreshold else { return }
        if let holder = players.firstIndex(where: { $0.hasLargestArmy }),
           players[holder].knightsPlayed >= best { return }
        let leaders = players.filter { $0.knightsPlayed == best }.map(\.id)
        guard leaders.count == 1, let winner = leaders.first else { return }
        for index in players.indices { players[index].hasLargestArmy = false }
        players[winner].hasLargestArmy = true
        note("\(players[winner].name) has the largest army (\(best) knights).")
    }

    private mutating func checkForWinner() {
        // Only the player whose turn it is can win, because hidden victory
        // point cards are revealed on their own turn.
        let points = victoryPoints(for: currentPlayer, includingHidden: true)
        if points >= options.victoryTarget {
            phase = .gameOver(winner: currentPlayer)
            note("\(players[currentPlayer].name) wins with \(points) victory points.")
        }
    }

    // MARK: - Helpers

    /// During a five- or six-player special build phase the acting player is
    /// not the one whose turn it is.
    private var currentBuilder: Int {
        if case .specialBuild(let player) = phase { return player }
        return currentPlayer
    }

    public var actingPlayer: Int { currentBuilder }

    private var isBuildPhase: Bool {
        switch phase {
        case .main, .specialBuild: return true
        default: return false
        }
    }

    private var isPreRoll: Bool {
        if case .preRoll = phase { return true }
        return false
    }

    private mutating func spend(_ cost: [Resource: Int], by player: Int) {
        players[player].pay(cost)
        for (resource, amount) in cost {
            bank[resource, default: 0] += amount
        }
    }

    private mutating func grant(_ resource: Resource, _ amount: Int, to player: Int) {
        let available = min(amount, bank[resource] ?? 0)
        guard available > 0 else { return }
        bank[resource, default: 0] -= available
        players[player].receive(resource, available)
    }

    private mutating func note(_ text: String) {
        log.append(LogEntry(turn: turn, text: text))
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }

    private mutating func nextSeed() -> UInt64 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return seed
    }
}

/// Deterministic generator so a game can be replayed from its seed.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        state = seed == 0 ? 0x4d595df4d0f33173 : seed
    }

    public mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

extension GameState {
    /// Hooks used by the test suite to set up a position directly instead of
    /// playing the game towards it.
    mutating func giveForTesting(_ resource: Resource, _ amount: Int, to player: Int) {
        players[player].resources[resource, default: 0] += amount
        bank[resource, default: 0] -= amount
    }

    mutating func stackDeckForTesting(with cards: [DevelopmentCard]) {
        developmentDeck = cards
    }

    mutating func setKnightsForTesting(_ count: Int, for player: Int) {
        players[player].knightsPlayed = count
    }

    mutating func giveCardForTesting(_ card: DevelopmentCard, to player: Int) {
        players[player].developmentCards.append(
            HeldDevelopmentCard(card: card, boughtOnTurn: turn - 1)
        )
    }

    mutating func forcePhaseForTesting(_ newPhase: Phase) {
        phase = newPhase
    }

    mutating func forceMainPhaseForTesting() {
        phase = .main
    }

    mutating func forcePreRollForTesting() {
        phase = .preRoll
    }

    /// Replays the dice step with a chosen total.
    mutating func forceRollForTesting(total: Int) {
        dice = (total / 2, total - total / 2)
        if total == 7 {
            startRobberSequence()
        } else {
            produce(for: total)
            phase = .main
        }
    }

    mutating func produceForTesting(total: Int) {
        produce(for: total)
    }

    mutating func advanceTurnForTesting() {
        advanceTurn()
    }

    mutating func placeBuildingForTesting(_ building: Building, at vertex: VertexID) {
        board.buildings[vertex] = building
    }

    mutating func setRobberForTesting(_ hex: Hex) {
        board.robber = hex
    }

    var setupIsFinished: Bool {
        switch phase {
        case .setupSettlement, .setupRoad: return false
        default: return true
        }
    }
}
