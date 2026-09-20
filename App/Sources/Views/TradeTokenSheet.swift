import SwiftUI
import OpenTanEngine

/// The two-player variant's trade token actions: force a trade, send the
/// robber back to the desert, or hand a knight back for more tokens.
struct TradeTokenSheet: View {
    let game: GameState
    var onForcedTrade: ([Resource: Int]) -> Void
    var onRobberToDesert: () -> Void
    var onKnightExchange: () -> Void
    var onCancel: () -> Void

    @State private var offered: [Resource: Int] = [:]

    private var me: Player { game.players[game.currentPlayer] }
    private var opponent: Player? { game.opponent.map { game.players[$0] } }
    private var cost: Int { game.tradeTokenCost(for: me.id) }
    private var canPay: Bool { me.tradeTokens >= cost }
    private var robberIsHome: Bool {
        game.board.tile(at: game.board.robber)?.terrain == .desert
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Your tokens")
                        Spacer()
                        Text("\(me.tradeTokens)").monospacedDigit().bold()
                    }
                    HStack {
                        Text("An action costs")
                        Spacer()
                        Text("\(cost)").monospacedDigit().bold()
                    }
                } footer: {
                    Text(cost == 1
                         ? "You are level or behind on victory points, so an action costs one token."
                         : "You are ahead on victory points, so an action costs two tokens.")
                }

                Section("Forced trade") {
                    if let opponent {
                        Text("Take \(Rules.forcedTradeCards) cards at random from \(opponent.name), who holds \(opponent.handCount). Choose \(Rules.forcedTradeCards) of your own to give back.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        ResourceCounter(title: "You give", limits: me.resources, amounts: $offered)
                        Button {
                            onForcedTrade(offered)
                        } label: {
                            Text("Force the trade").frame(maxWidth: .infinity)
                        }
                        .disabled(!canPay || offered.total != Rules.forcedTradeCards || opponent.handCount == 0)
                    }
                }

                Section("Move the robber") {
                    Button {
                        onRobberToDesert()
                    } label: {
                        Text("Send the robber to the desert").frame(maxWidth: .infinity)
                    }
                    .disabled(!canPay || robberIsHome)
                    if robberIsHome {
                        Text("The robber is already on the desert.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    Button {
                        onKnightExchange()
                    } label: {
                        Text("Trade in a knight for \(Rules.knightExchangeTokens) tokens")
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(me.knightsPlayed == 0 || game.hasExchangedKnightThisTurn)
                } header: {
                    Text("Replenish")
                } footer: {
                    Text("Once a turn you may discard one of your face-up knights. You have \(me.knightsPlayed). Doing so can cost you the largest army.")
                }
            }
            .navigationTitle("Trade tokens")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
            }
        }
    }
}
