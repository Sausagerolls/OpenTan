# App Store listing

The text below is what is live on the App Store Connect listing for version 1.0.
Keep this file and the listing in step.

- **App ID**: 6814579804
- **Bundle ID**: com.opentan.OpenTan
- **SKU**: opentan-001
- **Primary locale**: en-GB
- **Category**: Games, with Board and Strategy as subcategories. Entertainment second.
- **Age rating**: 4+
- **Copyright**: 2026 Jake Watts

## Name

OpenTan

## Subtitle

Pass and play island trading

## Promotional text

Two to six players share one device. Build roads and towns, trade for what you
need, race to ten points. No accounts, no network, no adverts.

## Keywords

board game,dice,hex,strategy,trading,pass and play,local multiplayer,offline,tabletop,family

## Description

See [description.txt](description.txt).

## URLs

- Marketing: https://github.com/Sausagerolls/OpenTan
- Support: https://github.com/Sausagerolls/OpenTan/issues
- Privacy policy: https://github.com/Sausagerolls/OpenTan/blob/main/docs/PRIVACY.md

## Screenshots

Five per device, captured by `ScreenshotTests` in the UI test target:

```sh
xcodebuild test -project OpenTan.xcodeproj -scheme OpenTan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
  -resultBundlePath shots.xcresult \
  -only-testing:OpenTanUITests/ScreenshotTests
xcrun xcresulttool export attachments --path shots.xcresult --output-path shots
```

iPhone 6.9 inch comes out at 1320x2868 and goes in the 6.7 inch set. The 13 inch
iPad comes out at 2064x2752.
