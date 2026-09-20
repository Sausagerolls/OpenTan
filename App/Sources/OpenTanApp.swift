import SwiftUI
import OpenTanEngine

@main
struct OpenTanApp: App {
    @State private var store = GameStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}

struct ContentView: View {
    @Bindable var store: GameStore

    var body: some View {
        NavigationStack {
            if store.isPlaying, store.game != nil {
                GameView(store: store) {
                    store.leaveToMenu()
                }
            } else {
                HomeView(store: store)
            }
        }
        .tint(.accentColor)
    }
}
