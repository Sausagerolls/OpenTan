import SwiftUI
import OpenTanEngine

/// Bank and port trades, plus offers to another player at the table.
struct TradeSheet: View {
    let game: GameState
    var onBankTrade: (Resource, Resource) -> Void
    var onPropose: (TradeOffer) -> Void
    var onCancel: () -> Void

    @State private var mode: Mode = .bank
    @State private var give: Resource = .brick
    @State private var receive: Resource = .ore
    @State private var partner: Int = 0
    @State private var giveAmounts: [Resource: Int] = [:]
    @State private var receiveAmounts: [Resource: Int] = [:]

    enum Mode: String, CaseIterable { case bank = "Bank & ports", player = "Another player" }

    private var me: Player { game.players[game.actingPlayer] }
    private var rate: Int { Placement.tradeRate(for: give, player: me.id, board: game.board) }

    var body: some View {
        NavigationStack {
            Form {
                Picker("Trade with", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                switch mode {
                case .bank: bankSection
                case .player: playerSection
                }
            }
            .navigationTitle("Trade")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
            }
        }
        .onAppear {
            partner = game.players.first { $0.id != me.id }?.id ?? 0
        }
    }

    private var bankSection: some View {
        Group {
            Section("Give") {
                Picker("Give", selection: $give) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        Text("\(resource.glyph) \(resource.displayName) — you hold \(me.count(of: resource))")
                            .tag(resource)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Receive") {
                Picker("Receive", selection: $receive) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        Text("\(resource.glyph) \(resource.displayName)").tag(resource)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section {
                Button {
                    onBankTrade(give, receive)
                } label: {
                    Text("Give \(rate) \(give.displayName.lowercased()) for 1 \(receive.displayName.lowercased())")
                        .frame(maxWidth: .infinity)
                }
                .disabled(give == receive || me.count(of: give) < rate)
                Text(rateExplanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rateExplanation: String {
        switch rate {
        case 2: return "You have a 2:1 port for \(give.displayName.lowercased())."
        case 3: return "You have a 3:1 port."
        default: return "Without a port the bank trades four for one."
        }
    }

    private var playerSection: some View {
        Group {
            Section("Partner") {
                Picker("Partner", selection: $partner) {
                    ForEach(game.players.filter { $0.id != me.id }) { player in
                        Text(player.name).tag(player.id)
                    }
                }
                .pickerStyle(.segmented)
            }
            Section {
                ResourceCounter(title: "You give", limits: me.resources, amounts: $giveAmounts)
            }
            Section {
                ResourceCounter(
                    title: "You receive",
                    limits: Resource.allCases.reduce(into: [:]) { $0[$1] = 19 },
                    amounts: $receiveAmounts
                )
            }
            Section {
                Button {
                    onPropose(TradeOffer(
                        proposer: me.id,
                        partner: partner,
                        give: giveAmounts,
                        receive: receiveAmounts
                    ))
                } label: {
                    Text("Offer \(giveAmounts.summary) for \(receiveAmounts.summary)")
                        .frame(maxWidth: .infinity)
                }
                .disabled(giveAmounts.total == 0 && receiveAmounts.total == 0)
                Text("Hand the device to \(game.players[partner].name) to accept or decline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
