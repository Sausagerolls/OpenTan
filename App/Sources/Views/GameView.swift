import SwiftUI
import OpenTanEngine

struct GameView: View {
    @Bindable var store: GameStore
    var onQuit: () -> Void

    @State private var sheet: ActiveSheet?
    @State private var winnerDismissed = false

    enum ActiveSheet: String, Identifiable {
        case trade, cards, discard, tokens, log, rules
        var id: String { rawValue }
    }

    var body: some View {
        if let game = store.game {
            content(for: game)
        } else {
            ProgressView()
        }
    }

    private func content(for game: GameState) -> some View {
        VStack(spacing: 0) {
            PlayerStripView(game: game, viewer: store.deviceHolder)

            BoardView(
                game: game,
                highlightedVertices: store.highlightedVertices,
                highlightedEdges: store.highlightedEdges,
                highlightedHexes: store.highlightedHexes,
                onVertex: store.tapVertex,
                onEdge: store.tapEdge,
                onHex: store.tapHex
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .topTrailing) { boardOverlay(game) }

            if let message = store.message {
                Text(message)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.85))
            }

            HandView(
                player: game.players[game.actingPlayer],
                tradeTokens: game.options.twoPlayerVariant ? game.players[game.actingPlayer].tradeTokens : nil,
                revealed: $store.handRevealed
            )
                .padding(.vertical, 8)

            ActionBarView(
                game: game,
                selection: $store.selection,
                neutralTarget: $store.neutralTarget,
                neutralPiece: $store.neutralPiece,
                perform: store.perform,
                openTrade: { sheet = .trade },
                openCards: { sheet = .cards },
                openDiscard: { sheet = .discard },
                openTokens: { sheet = .tokens },
                neutralSpotCount: store.spots(for:piece:)
            )
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Quit", role: .destructive, action: onQuit)
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { sheet = .rules } label: { Image(systemName: "book") }
                Button { sheet = .log } label: { Image(systemName: "list.bullet.rectangle") }
            }
        }
        .navigationTitle("OpenTan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { which in
            sheetContent(which, game: game)
        }
        .overlay {
            if store.needsHandover, let next = store.playerToAct {
                HandoverView(
                    player: game.players[next],
                    reason: handoverReason(game),
                    onReady: store.acceptHandover
                )
                .transition(.opacity)
            } else if let winner = game.winner, !winnerDismissed {
                WinnerView(
                    game: game,
                    winner: winner,
                    onNewGame: onQuit,
                    onDismiss: { winnerDismissed = true }
                )
            }
        }
        .animation(.snappy, value: store.needsHandover)
        .onAppear { store.syncNeutralChoice() }
        .onChange(of: store.neutralPiece) { _, _ in store.syncNeutralChoice() }
        .onChange(of: game.phase) { _, newPhase in
            if case .discarding = newPhase, !store.needsHandover {
                sheet = .discard
            }
        }
    }

    private func boardOverlay(_ game: GameState) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            if let dice = game.dice {
                HStack(spacing: 4) {
                    Text("🎲 \(dice.0) + \(dice.1) = \(dice.0 + dice.1)")
                        .font(.caption.weight(.bold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(.thinMaterial))
            }
            if game.options.twoPlayerVariant {
                Text("Tokens left: \(game.tradeTokenSupply)")
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.thinMaterial))
            }
            Text("Deck: \(game.developmentDeck.count)")
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.thinMaterial))
        }
        .padding(10)
    }

    private func handoverReason(_ game: GameState) -> String {
        switch game.phase {
        case .discarding: return "You rolled into a seven and must discard."
        case .awaitingTradeResponse: return "A trade has been offered to you."
        case .specialBuild: return "Special build phase."
        default: return "It is your turn."
        }
    }

    @ViewBuilder
    private func sheetContent(_ which: ActiveSheet, game: GameState) -> some View {
        switch which {
        case .trade:
            TradeSheet(
                game: game,
                onBankTrade: { give, receive in
                    store.perform(.bankTrade(give: give, receive: receive))
                    sheet = nil
                },
                onPropose: { offer in
                    store.perform(.proposeTrade(offer))
                    sheet = nil
                },
                onCancel: { sheet = nil }
            )
        case .cards:
            DevelopmentCardSheet(
                game: game,
                onPlay: { id, choice in
                    store.perform(.playDevelopmentCard(id: id, choice: choice))
                    sheet = nil
                },
                onCancel: { sheet = nil }
            )
        case .discard:
            if let player = store.deviceHolder, game.discardsOwed(by: player) > 0 {
                DiscardSheet(
                    player: game.players[player],
                    owed: game.discardsOwed(by: player)
                ) { cards in
                    store.perform(.discard(player: player, cards: cards))
                    sheet = nil
                }
                .interactiveDismissDisabled()
            } else {
                Text("Nothing to discard.")
            }
        case .tokens:
            TradeTokenSheet(
                game: game,
                onForcedTrade: { give in
                    store.perform(.forcedTrade(give: give))
                    sheet = nil
                },
                onRobberToDesert: {
                    store.perform(.moveRobberToDesert)
                    sheet = nil
                },
                onKnightExchange: {
                    store.perform(.exchangeKnightForTokens)
                    sheet = nil
                },
                onCancel: { sheet = nil }
            )
        case .log:
            LogView(game: game) { sheet = nil }
        case .rules:
            RulesView { sheet = nil }
        }
    }
}
