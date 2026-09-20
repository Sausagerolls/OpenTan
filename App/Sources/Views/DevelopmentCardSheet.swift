import SwiftUI
import OpenTanEngine

/// Lists the acting player's development cards and collects the extra choice
/// that Year of Plenty and Monopoly need.
struct DevelopmentCardSheet: View {
    let game: GameState
    var onPlay: (UUID, DevelopmentChoice) -> Void
    var onCancel: () -> Void

    @State private var pendingYearOfPlenty: HeldDevelopmentCard?
    @State private var pendingMonopoly: HeldDevelopmentCard?
    @State private var firstPick: Resource = .brick
    @State private var secondPick: Resource = .brick

    private var me: Player { game.players[game.actingPlayer] }

    var body: some View {
        NavigationStack {
            List {
                if me.developmentCards.isEmpty {
                    Text("You have no development cards.")
                        .foregroundStyle(.secondary)
                }

                Section {
                    ForEach(me.developmentCards) { held in
                        row(held)
                    }
                } footer: {
                    Text("A card cannot be played on the turn you buy it, and only one card may be played per turn. Victory point cards stay hidden until you win.")
                }
            }
            .navigationTitle("Development cards")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onCancel)
                }
            }
            .sheet(item: $pendingYearOfPlenty) { card in
                choicePicker(title: "Year of Plenty", count: 2) {
                    onPlay(card.id, .yearOfPlenty(firstPick, secondPick))
                }
            }
            .sheet(item: $pendingMonopoly) { card in
                choicePicker(title: "Monopoly", count: 1) {
                    onPlay(card.id, .monopoly(firstPick))
                }
            }
        }
    }

    private func row(_ held: HeldDevelopmentCard) -> some View {
        let playable = held.card.isPlayable
            && held.boughtOnTurn < game.turn
            && !game.hasPlayedDevelopmentCardThisTurn
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(held.card.displayName).font(.headline)
                Spacer()
                if playable {
                    Button("Play") { play(held) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                }
            }
            Text(held.card.rulesText)
                .font(.caption)
                .foregroundStyle(.secondary)
            if held.boughtOnTurn >= game.turn {
                Text("Bought this turn.")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }
        }
        .padding(.vertical, 2)
    }

    private func play(_ held: HeldDevelopmentCard) {
        switch held.card {
        case .yearOfPlenty: pendingYearOfPlenty = held
        case .monopoly: pendingMonopoly = held
        default: onPlay(held.id, .none)
        }
    }

    private func choicePicker(title: String, count: Int, confirm: @escaping () -> Void) -> some View {
        NavigationStack {
            Form {
                Picker("First", selection: $firstPick) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        Text("\(resource.glyph) \(resource.displayName)").tag(resource)
                    }
                }
                if count == 2 {
                    Picker("Second", selection: $secondPick) {
                        ForEach(Resource.allCases, id: \.self) { resource in
                            Text("\(resource.glyph) \(resource.displayName)").tag(resource)
                        }
                    }
                }
                Button("Play card") { confirm() }
            }
            .navigationTitle(title)
        }
    }
}
