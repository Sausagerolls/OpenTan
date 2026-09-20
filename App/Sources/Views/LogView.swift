import SwiftUI
import OpenTanEngine

struct LogView: View {
    let game: GameState
    var onClose: () -> Void

    var body: some View {
        NavigationStack {
            List(game.log.reversed()) { entry in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("T\(entry.turn)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .leading)
                    Text(entry.text).font(.callout)
                }
            }
            .navigationTitle("Game log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", action: onClose)
                }
            }
        }
    }
}
