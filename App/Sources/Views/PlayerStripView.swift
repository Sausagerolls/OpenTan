import SwiftUI
import OpenTanEngine

/// One card per player across the top: colour, name, public points and the
/// things everyone is allowed to see.
struct PlayerStripView: View {
    let game: GameState
    let viewer: Int?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(game.players) { player in
                    card(for: player)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private func card(for player: Player) -> some View {
        let isActive = player.id == game.actingPlayer
        let showHidden = player.id == viewer
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle()
                    .fill(player.color.swiftUIColor)
                    .frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.black.opacity(0.4)))
                Text(player.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            HStack(spacing: 8) {
                Label("\(game.victoryPoints(for: player.id, includingHidden: showHidden))", systemImage: "rosette")
                Label("\(player.handCount)", systemImage: "rectangle.on.rectangle")
                Label("\(player.developmentCards.count)", systemImage: "square.stack")
            }
            .font(.caption2)
            .labelStyle(.titleAndIcon)

            HStack(spacing: 6) {
                if player.hasLongestRoad {
                    Text("Longest road").badgeStyle()
                }
                if player.hasLargestArmy {
                    Text("Largest army").badgeStyle()
                }
                if player.knightsPlayed > 0 {
                    Text("\(player.knightsPlayed) ⚔︎").badgeStyle()
                }
            }
        }
        .padding(10)
        .frame(minWidth: 132, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? player.color.swiftUIColor.opacity(0.22) : Color.secondary.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? player.color.swiftUIColor : .clear, lineWidth: 2)
        )
    }
}

private struct BadgeStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.system(size: 9, weight: .semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary.opacity(0.22)))
    }
}

extension View {
    func badgeStyle() -> some View { modifier(BadgeStyle()) }
}
