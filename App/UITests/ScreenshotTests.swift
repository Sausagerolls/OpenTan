import XCTest

/// Captures the App Store screenshots. Run against the phone and tablet
/// simulators Apple asks for, then pull the attachments out of the result
/// bundle with `xcrun xcresulttool export attachments`.
final class ScreenshotTests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureStoreScreenshots() {
        let menu = launch("--demo-none")
        XCTAssertTrue(menu.buttons["New game"].waitForExistence(timeout: 10))
        capture(menu, named: "01-home")

        let game = launch("--demo-game")
        XCTAssertTrue(
            game.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Roll dice'")).firstMatch
                .waitForExistence(timeout: 10)
        )
        capture(game, named: "02-board")

        game.buttons["Rules"].tap()
        XCTAssertTrue(game.navigationBars["Rules"].waitForExistence(timeout: 5))
        capture(game, named: "03-rules")
        game.buttons["Close"].tap()

        let two = launch("--demo-two-player")
        XCTAssertTrue(
            two.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Roll dice'")).firstMatch
                .waitForExistence(timeout: 10)
        )
        capture(two, named: "04-two-player")

        // Roll through to the building phase so the token action is offered.
        for _ in 0..<2 {
            let roll = two.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Roll dice'")).firstMatch
            if roll.exists { roll.tap() }
        }
        let tokens = two.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Trade tokens'")).firstMatch
        if tokens.waitForExistence(timeout: 5) {
            tokens.tap()
            if two.navigationBars["Trade tokens"].waitForExistence(timeout: 5) {
                capture(two, named: "05-trade-tokens")
            }
        }
    }

    private func launch(_ argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        return app
    }

    private func capture(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
