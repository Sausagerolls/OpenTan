# Contributing to OpenTan

Thanks for taking a look. OpenTan is a pass-and-play board game for iPhone and
iPad with no network code, and the aim is to keep it that way.

## Getting set up

```sh
brew install xcodegen
xcodegen generate
open OpenTan.xcodeproj
```

`OpenTan.xcodeproj` is generated from `project.yml` and is not checked in. If you
add a file, run `xcodegen generate` again rather than editing the project in
Xcode.

## Where things go

The rules live in `Engine/`, a plain Swift package with no dependency on SwiftUI
or UIKit. The app in `App/` draws the board and collects taps, and it should not
contain rules of its own. If you find yourself checking whether a move is legal
inside a view, the check belongs in `Placement.swift` or `GameState.swift`.

## Tests

- Rules changes need a test in `Engine/Tests/OpenTanEngineTests`. Run them with
  `cd Engine && swift test`; the suite takes a couple of seconds.
- Changes to the board or the turn flow should keep the XCUITest suite passing:
  `xcodebuild test -project OpenTan.xcodeproj -scheme OpenTan -destination 'platform=iOS Simulator,name=iPhone 17'`.

## Style

Match the surrounding code. Comments explain why something is the way it is, not
what the next line does. Names spell things out.

## Things that will not be merged

- Online or multi-device play, accounts, or analytics.
- Trademarked names, artwork or text from the published board game.
- Third party dependencies, unless there is no reasonable alternative.

## Reporting a bug

Say which rule you expected, what happened instead, how many players were in the
game, and the phase you were in. A screenshot of the board and the game log
(the list icon in the top right) usually says the rest.
