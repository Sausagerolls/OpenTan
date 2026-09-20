import SwiftUI
import OpenTanEngine

/// Shown after a seven to every player holding more than the hand limit.
struct DiscardSheet: View {
    let player: Player
    let owed: Int
    var onDiscard: ([Resource: Int]) -> Void

    @State private var chosen: [Resource: Int] = [:]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("\(player.name) holds \(player.handCount) cards and must discard \(owed).")
                        .font(.callout)
                }
                Section {
                    ResourceCounter(title: "Discard", limits: player.resources, amounts: $chosen)
                }
                Section {
                    HStack {
                        Text("Selected")
                        Spacer()
                        Text("\(chosen.total) of \(owed)")
                            .monospacedDigit()
                            .foregroundStyle(chosen.total == owed ? .green : .secondary)
                    }
                }
            }
            .navigationTitle("Discard")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Discard") { onDiscard(chosen) }
                        .disabled(chosen.total != owed)
                }
            }
        }
    }
}
