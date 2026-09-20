import SwiftUI
import OpenTanEngine

/// Covers the screen between players so nobody sees somebody else's hand.
struct HandoverView: View {
    let player: Player
    let reason: String
    var onReady: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThickMaterial)
                .ignoresSafeArea()
            VStack(spacing: 18) {
                Circle()
                    .fill(player.color.swiftUIColor)
                    .frame(width: 64, height: 64)
                    .overlay(Circle().stroke(.black.opacity(0.3), lineWidth: 2))
                Text("Pass the device to")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text(player.name)
                    .font(.largeTitle.bold())
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                Button(action: onReady) {
                    Text("I'm \(player.name)")
                        .font(.headline)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(player.color.swiftUIColor)
            }
        }
    }
}

/// Final screen with the scores revealed.
struct WinnerView: View {
    let game: GameState
    let winner: Int
    var onNewGame: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle().fill(.ultraThickMaterial).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("🏆").font(.system(size: 64))
                Text("\(game.players[winner].name) wins")
                    .font(.largeTitle.bold())
                VStack(spacing: 6) {
                    ForEach(game.players) { player in
                        HStack {
                            Circle().fill(player.color.swiftUIColor).frame(width: 12, height: 12)
                            Text(player.name)
                            Spacer()
                            Text("\(game.victoryPoints(for: player.id, includingHidden: true)) points")
                                .monospacedDigit()
                        }
                    }
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.12)))
                .padding(.horizontal, 40)

                HStack(spacing: 12) {
                    Button("Look at the board", action: onDismiss)
                    Button("New game", action: onNewGame)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }
}
