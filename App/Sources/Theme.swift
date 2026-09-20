import SwiftUI
import OpenTanEngine

extension PlayerColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
}

extension Resource {
    var glyph: String {
        switch self {
        case .brick: return "🧱"
        case .lumber: return "🌲"
        case .wool: return "🐑"
        case .grain: return "🌾"
        case .ore: return "⛰️"
        }
    }

    var tint: Color {
        switch self {
        case .brick: return Color(red: 0.76, green: 0.36, blue: 0.24)
        case .lumber: return Color(red: 0.16, green: 0.42, blue: 0.24)
        case .wool: return Color(red: 0.56, green: 0.73, blue: 0.40)
        case .grain: return Color(red: 0.90, green: 0.73, blue: 0.24)
        case .ore: return Color(red: 0.45, green: 0.47, blue: 0.53)
        }
    }
}

extension Terrain {
    var fill: Color {
        switch self {
        case .hills: return Color(red: 0.76, green: 0.40, blue: 0.27)
        case .forest: return Color(red: 0.16, green: 0.38, blue: 0.24)
        case .pasture: return Color(red: 0.55, green: 0.74, blue: 0.42)
        case .fields: return Color(red: 0.91, green: 0.76, blue: 0.31)
        case .mountains: return Color(red: 0.49, green: 0.51, blue: 0.56)
        case .desert: return Color(red: 0.87, green: 0.81, blue: 0.62)
        }
    }

    var glyph: String {
        switch self {
        case .hills: return "🧱"
        case .forest: return "🌲"
        case .pasture: return "🐑"
        case .fields: return "🌾"
        case .mountains: return "⛰️"
        case .desert: return "🏜️"
        }
    }
}

enum Palette {
    static let sea = Color(red: 0.16, green: 0.42, blue: 0.62)
    static let coast = Color(red: 0.92, green: 0.86, blue: 0.70)
    static let highlight = Color.white
}

/// Dice numbers with the best odds are printed in red on the board, and the
/// dots under each number show how likely it is.
func pipCount(for number: Int) -> Int { 6 - abs(7 - number) }

func isHighProbability(_ number: Int) -> Bool { number == 6 || number == 8 }
