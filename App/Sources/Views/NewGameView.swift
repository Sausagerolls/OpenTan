import SwiftUI
import OpenTanEngine

/// Seat count, names and the handful of rule switches worth exposing.
struct NewGameView: View {
    var onStart: ([String], GameOptions) -> Void
    var onCancel: () -> Void

    @State private var names: [String] = ["Player 1", "Player 2", "Player 3"]
    @State private var layout: BoardLayout = .standard
    @State private var balancedNumbers = true
    @State private var victoryTarget = Rules.defaultVictoryTarget
    @State private var discardLimit = Rules.defaultDiscardLimit
    @State private var specialBuild = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Players") {
                    ForEach(names.indices, id: \.self) { index in
                        HStack {
                            Circle()
                                .fill(PlayerColor.palette[index % PlayerColor.palette.count].swiftUIColor)
                                .frame(width: 16, height: 16)
                            TextField("Name", text: $names[index])
                                .textInputAutocapitalization(.words)
                        }
                    }
                    HStack {
                        Button {
                            names.append("Player \(names.count + 1)")
                            syncLayout()
                        } label: {
                            Label("Add player", systemImage: "plus.circle")
                        }
                        .disabled(names.count >= PlayerColor.palette.count)
                        Spacer()
                        Button(role: .destructive) {
                            names.removeLast()
                            syncLayout()
                        } label: {
                            Label("Remove", systemImage: "minus.circle")
                        }
                        .disabled(names.count <= 2)
                    }
                }

                Section("Board") {
                    Picker("Layout", selection: $layout) {
                        Text("Standard (19 tiles)").tag(BoardLayout.standard)
                        Text("Large (30 tiles)").tag(BoardLayout.large)
                    }
                    Toggle("Keep 6 and 8 apart", isOn: $balancedNumbers)
                    if names.count >= 5 && layout == .standard {
                        Label("Five or six players need the large board.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section("House rules") {
                    Stepper("Victory points to win: \(victoryTarget)", value: $victoryTarget, in: 3...18)
                    Stepper("Discard above \(discardLimit) cards", value: $discardLimit, in: 5...20)
                    Toggle("Special build phase", isOn: $specialBuild)
                }

                Section {
                    Button {
                        onStart(cleanedNames, options)
                    } label: {
                        Text("Start game").frame(maxWidth: .infinity)
                    }
                    .disabled(names.count < 2 || (names.count >= 5 && layout == .standard))
                }
            }
            .navigationTitle("New game")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .onAppear(perform: syncLayout)
            .onChange(of: names.count) { _, _ in syncLayout() }
        }
    }

    private var cleanedNames: [String] {
        names.enumerated().map { index, name in
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            return trimmed.isEmpty ? "Player \(index + 1)" : trimmed
        }
    }

    private var options: GameOptions {
        GameOptions(
            layout: layout,
            balancedNumbers: balancedNumbers,
            victoryTarget: victoryTarget,
            discardLimit: discardLimit,
            specialBuildPhase: specialBuild
        )
    }

    private func syncLayout() {
        let recommended = BoardLayout.recommended(forPlayerCount: names.count)
        if recommended == .large {
            layout = .large
            specialBuild = true
        } else if layout == .large && names.count < 5 {
            // A small table may still choose the big board on purpose.
            return
        }
    }
}
