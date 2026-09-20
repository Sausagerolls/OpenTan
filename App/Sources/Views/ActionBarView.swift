import SwiftUI
import OpenTanEngine

/// The controls for whatever the game is waiting for, plus the running prompt
/// that tells the table what to do next.
struct ActionBarView: View {
    let game: GameState
    @Binding var selection: BoardSelection
    @Binding var neutralTarget: Int?
    @Binding var neutralPiece: NeutralPiece
    var perform: (GameAction) -> Void
    var openTrade: () -> Void
    var openCards: () -> Void
    var openDiscard: () -> Void
    var openTokens: () -> Void
    var neutralSpotCount: (Int, NeutralPiece) -> Int

    private var me: Player { game.players[game.actingPlayer] }

    var body: some View {
        VStack(spacing: 10) {
            Text(prompt)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private var prompt: String {
        switch game.phase {
        case .setupSettlement(let round):
            return "\(me.name): place your \(round == 1 ? "first" : "second") settlement on a highlighted corner."
        case .setupRoad:
            return "\(me.name): place a road on one of the highlighted sides."
        case .preRoll:
            if game.rollsRemaining > 1 {
                return "\(me.name): roll the dice, or play a development card first. Two rolls this turn."
            }
            if game.options.twoPlayerVariant {
                return "\(me.name): roll again. The second roll must show a different total."
            }
            return "\(me.name): roll the dice, or play a development card first."
        case .neutralPlacement(let mustBeRoad):
            return mustBeRoad
                ? "\(me.name): the neutral players have nowhere to settle, so give one of them a free road."
                : "\(me.name): give a neutral player a free road or settlement."
        case .discarding:
            let names = game.playersOwingDiscards.map { game.players[$0].name }
            return "Seven rolled. Waiting on: \(names.joined(separator: ", "))."
        case .movingRobber:
            return "\(me.name): tap a tile to move the robber."
        case .stealing:
            return "\(me.name): choose who to steal from."
        case .main:
            if let dice = game.dice {
                return "\(me.name) rolled \(dice.0 + dice.1). Build, trade, or end your turn."
            }
            return "\(me.name): build, trade, or end your turn."
        case .placingFreeRoads(let remaining):
            return "Road Building: place \(remaining) more free road\(remaining == 1 ? "" : "s")."
        case .awaitingTradeResponse(let offer):
            return "\(game.players[offer.proposer].name) offers \(offer.give.summary) for \(offer.receive.summary)."
        case .specialBuild(let player):
            return "\(game.players[player].name): special build phase — you may buy and build."
        case .gameOver(let winner):
            return "\(game.players[winner].name) has won."
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch game.phase {
        case .setupSettlement, .setupRoad, .movingRobber, .placingFreeRoads:
            EmptyView()

        case .neutralPlacement(let mustBeRoad):
            neutralControls(mustBeRoad: mustBeRoad)

        case .preRoll:
            HStack(spacing: 10) {
                Button {
                    perform(.rollDice)
                } label: {
                    Label(game.rollsRemaining > 1 ? "Roll dice (1 of 2)" : "Roll dice", systemImage: "die.face.5")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                Button(action: openCards) {
                    Label("Cards", systemImage: "square.stack")
                }
                .buttonStyle(.bordered)
                .disabled(me.developmentCards.isEmpty)
            }

        case .discarding:
            Button(action: openDiscard) {
                Label("Discard cards", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .stealing(let candidates):
            HStack(spacing: 10) {
                ForEach(candidates, id: \.self) { victim in
                    Button {
                        perform(.steal(from: victim))
                    } label: {
                        VStack(spacing: 2) {
                            Text(game.players[victim].name).font(.subheadline.weight(.semibold))
                            Text("\(game.players[victim].handCount) cards").font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(game.players[victim].color.swiftUIColor)
                }
            }

        case .awaitingTradeResponse:
            HStack(spacing: 10) {
                Button("Decline") { perform(.respondToTrade(accept: false)) }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)
                Button("Accept") { perform(.respondToTrade(accept: true)) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            }

        case .main, .specialBuild:
            buildControls

        case .gameOver:
            EmptyView()
        }
    }

    private var buildControls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                buildButton(.road, title: "Road", cost: Rules.roadCost, pieces: me.roadsLeft)
                buildButton(.settlement, title: "Settlement", cost: Rules.settlementCost, pieces: me.settlementsLeft)
                buildButton(.city, title: "City", cost: Rules.cityCost, pieces: me.citiesLeft)
            }
            HStack(spacing: 8) {
                Button {
                    perform(.buyDevelopmentCard)
                } label: {
                    VStack(spacing: 2) {
                        Text("Buy card").font(.caption.weight(.semibold))
                        Text(costLabel(Rules.developmentCardCost)).font(.system(size: 10))
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(!me.canAfford(Rules.developmentCardCost) || game.developmentDeck.isEmpty)

                Button(action: openCards) {
                    Label("Cards", systemImage: "square.stack").font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(me.developmentCards.isEmpty)

                if case .main = game.phase {
                    Button(action: openTrade) {
                        Label("Trade", systemImage: "arrow.left.arrow.right").font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            if game.options.twoPlayerVariant, case .main = game.phase {
                Button(action: openTokens) {
                    Label("Trade tokens (\(me.tradeTokens))", systemImage: "circle.hexagongrid")
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            if case .specialBuild = game.phase {
                Button("Done") { perform(.endSpecialBuild) }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    perform(.endTurn)
                } label: {
                    Text("End turn").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    /// Picks which neutral player gets the free piece, and whether it is a
    /// road or a settlement. The board takes the tap that places it.
    private func neutralControls(mustBeRoad: Bool) -> some View {
        VStack(spacing: 8) {
            Picker("Piece", selection: $neutralPiece) {
                ForEach(NeutralPiece.allCases) { piece in
                    Text(piece.title).tag(piece)
                }
            }
            .pickerStyle(.segmented)
            .disabled(mustBeRoad)

            HStack(spacing: 8) {
                ForEach(game.neutralPlayers) { neutral in
                    let count = neutralSpotCount(neutral.id, neutralPiece)
                    Button {
                        neutralTarget = neutral.id
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(neutral.color.swiftUIColor)
                                .frame(width: 12, height: 12)
                            Text(neutral.name).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(neutralTarget == neutral.id ? .accentColor : nil)
                    .disabled(count == 0)
                }
            }
        }
    }

    private func buildButton(_ kind: BoardSelection, title: String, cost: [Resource: Int], pieces: Int) -> some View {
        let affordable = me.canAfford(cost) && pieces > 0
        return Button {
            selection = selection == kind ? .none : kind
        } label: {
            VStack(spacing: 2) {
                Text(title).font(.caption.weight(.semibold))
                Text(costLabel(cost)).font(.system(size: 10))
                Text("\(pieces) left").font(.system(size: 9)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(selection == kind ? .accentColor : nil)
        .disabled(!affordable)
    }

    private func costLabel(_ cost: [Resource: Int]) -> String {
        Resource.allCases.compactMap { resource in
            guard let amount = cost[resource], amount > 0 else { return nil }
            return String(repeating: resource.glyph, count: amount)
        }
        .joined()
    }
}
