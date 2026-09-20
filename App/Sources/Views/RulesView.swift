import SwiftUI
import OpenTanEngine

/// A short reference so the table does not need the printed rules to hand.
struct RulesView: View {
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("Goal") {
                    Text("Be the first to reach the victory point target, normally ten, on your own turn. Settlements are worth one point, cities two, and the longest road and largest army are worth two each.")
                }
                Section("Costs") {
                    cost("Road", Rules.roadCost)
                    cost("Settlement", Rules.settlementCost)
                    cost("City", Rules.cityCost)
                    cost("Development card", Rules.developmentCardCost)
                }
                Section("Turn order") {
                    Text("Roll the dice, collect from every tile showing that number, then build and trade in any order. You may play one development card per turn, and a knight may be played before you roll.")
                }
                Section("Placing") {
                    Text("A settlement needs an empty corner with all three neighbouring corners empty, and after the opening it must touch one of your own roads. A road must touch one of your roads or buildings, and an opponent's building blocks a road running through it.")
                }
                Section("The seven") {
                    Text("On a seven nobody collects. Every player holding more than the hand limit discards half, rounded down. The player who rolled then moves the robber to a different tile and steals one random card from a player with a building on it. The robbed tile produces nothing until the robber moves again.")
                }
                Section("Trading") {
                    Text("On your turn you may trade with any other player, or with the bank at four for one. A 3:1 port improves that to three for one, and a 2:1 port to two for one of the named resource. You must have a settlement or city on the port's corner.")
                }
                Section("Longest road and largest army") {
                    Text("The longest road is awarded at five connected segments and the largest army at three played knights. Each moves to whoever passes the current holder, and ties leave the card where it is.")
                }
                Section("Playing with two") {
                    Text("A game of two uses the published two-player variant. Two neutral players own pieces on the board: they take one settlement each at the start, never collect resources, never take a turn, and can hold the longest road.")
                    Text("You roll the dice twice on your turn, and the second roll must show a different total from the first. Both rolls pay out, and a seven still sends the robber.")
                    Text("Every road or settlement you build also gives one neutral player a free road or settlement, your choice. If no settlement is legal for them you must give a road. Cities and development cards give them nothing.")
                    Text("You start with five trade tokens. Spend one while you are level or behind on victory points, or two while you are ahead, to force a trade — two random cards from your opponent for two of your own choosing — or to send the robber back to the desert. Once a turn you may hand back a face-up knight for two tokens, which can cost you the largest army.")
                    Text("A new settlement next to the desert pays two tokens, one on the coast pays one, and a corner that is both pays three. This applies during the opening placement too.")
                }

                Section("Pass and play") {
                    Text("The screen is covered whenever the device should change hands, so hands stay private. Tap the hand bar to hide your cards again before passing.")
                }
            }
            .navigationTitle("Rules")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }

    private func cost(_ title: String, _ cost: [Resource: Int]) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Resource.allCases.compactMap { resource -> String? in
                guard let amount = cost[resource], amount > 0 else { return nil }
                return String(repeating: resource.glyph, count: amount)
            }.joined())
        }
    }
}
