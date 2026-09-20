import SwiftUI
import OpenTanEngine

/// The acting player's own cards. Pass-and-play means the hand starts covered
/// and is only shown while the owner is holding the device.
struct HandView: View {
    let player: Player
    let tradeTokens: Int?
    @Binding var revealed: Bool

    var body: some View {
        Group {
            if revealed {
                HStack(spacing: 10) {
                    ForEach(Resource.allCases, id: \.self) { resource in
                        chip(resource)
                    }
                    if !player.developmentCards.isEmpty {
                        Divider().frame(height: 22)
                        Label("\(player.developmentCards.count)", systemImage: "square.stack")
                            .font(.subheadline.weight(.semibold))
                    }
                    if let tradeTokens {
                        Divider().frame(height: 22)
                        Label("\(tradeTokens)", systemImage: "circle.hexagongrid")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.secondary.opacity(0.14)))
                .onTapGesture { revealed = false }
            } else {
                Button {
                    revealed = true
                } label: {
                    Label("Show \(player.name)'s hand (\(player.handCount) cards)", systemImage: "eye")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.secondary.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.snappy, value: revealed)
    }

    private func chip(_ resource: Resource) -> some View {
        let count = player.count(of: resource)
        return HStack(spacing: 3) {
            Text(resource.glyph)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
        }
        .opacity(count == 0 ? 0.35 : 1)
        .accessibilityLabel("\(count) \(resource.displayName)")
    }
}
