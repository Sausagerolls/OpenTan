import SwiftUI
import OpenTanEngine

struct HomeView: View {
    @Bindable var store: GameStore
    @State private var showingNewGame = false
    @State private var showingRules = false
    @State private var confirmingDiscard = false

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            VStack(spacing: 8) {
                Text("OpenTan")
                    .font(.system(size: 52, weight: .heavy, design: .rounded))
                Text("Pass-and-play settling for two to six")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 12) {
                if store.hasSavedGame, let game = store.game {
                    Button {
                        store.resume()
                    } label: {
                        VStack(spacing: 2) {
                            Text("Continue game").font(.headline)
                            Text(resumeSubtitle(game)).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                if store.hasSavedGame {
                    Button {
                        confirmingDiscard = true
                    } label: {
                        Text("New game").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button {
                        showingNewGame = true
                    } label: {
                        Text("New game").frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    showingRules = true
                } label: {
                    Text("Rules").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 40)

            Spacer()
            Text("Everything happens on this device. No accounts, no network.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .padding(.bottom, 20)
        }
        .sheet(isPresented: $showingNewGame) {
            NewGameView(
                onStart: { names, options in
                    store.startGame(playerNames: names, options: options)
                    showingNewGame = false
                },
                onCancel: { showingNewGame = false }
            )
        }
        .sheet(isPresented: $showingRules) {
            RulesView { showingRules = false }
        }
        .confirmationDialog(
            "Start a new game?",
            isPresented: $confirmingDiscard,
            titleVisibility: .visible
        ) {
            Button("Discard the saved game", role: .destructive) {
                store.abandonGame()
                showingNewGame = true
            }
            Button("Keep playing", role: .cancel) {}
        } message: {
            Text("The game in progress will be deleted.")
        }
    }

    private func resumeSubtitle(_ game: GameState) -> String {
        let names = game.players.map(\.name).joined(separator: ", ")
        return "Turn \(game.turn) — \(names)"
    }
}
