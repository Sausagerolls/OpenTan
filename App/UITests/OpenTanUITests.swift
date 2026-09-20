import XCTest

/// Drives the real app far enough to prove the board accepts taps and the
/// turn flow advances. Launches with `--demo-game`, which starts a three
/// player game with the opening placement already made.
final class OpenTanUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = launch(with: "--demo-game")
    }

    @discardableResult
    private func launch(with argument: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [argument]
        app.launch()
        self.app = app
        return app
    }

    func testRollingTheDiceMovesTheTurnOn() {
        let roll = app.buttons["Roll dice"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10), "the demo game should open on the roll step")
        roll.tap()

        // After a roll the turn either continues, or a seven sends the player
        // to the robber or the discard step.
        let endTurn = app.buttons["End turn"]
        let robberPrompt = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'robber'")).firstMatch
        let discardPrompt = app.staticTexts.containing(NSPredicate(format: "label CONTAINS[c] 'discard'")).firstMatch

        let moved = endTurn.waitForExistence(timeout: 5)
            || robberPrompt.waitForExistence(timeout: 2)
            || discardPrompt.waitForExistence(timeout: 2)
        XCTAssertTrue(moved, "rolling should move the game to the next step")
    }

    func testHandStaysHiddenUntilItIsAskedFor() {
        let reveal = app.buttons.containing(NSPredicate(format: "label BEGINSWITH 'Show'")).firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 10), "hands start covered")
        reveal.tap()
        XCTAssertFalse(reveal.exists, "tapping the bar reveals the hand")
    }

    func testBuildingARoadFromTheActionBar() {
        let roll = app.buttons["Roll dice"]
        XCTAssertTrue(roll.waitForExistence(timeout: 10))
        roll.tap()

        let endTurn = app.buttons["End turn"]
        guard endTurn.waitForExistence(timeout: 5) else {
            // A seven interrupted the turn; the other tests cover that path.
            return
        }
        XCTAssertTrue(app.buttons.containing(NSPredicate(format: "label CONTAINS 'Road'")).firstMatch.exists)
        endTurn.tap()

        let handover = app.buttons.containing(NSPredicate(format: "label BEGINSWITH \"I'm\"")).firstMatch
        XCTAssertTrue(handover.waitForExistence(timeout: 5), "the screen is covered between players")
    }

    func testTappingTheBoardPlacesTheOpeningSettlement() {
        launch(with: "--demo-setup")

        let settlementPrompt = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS[c] 'place your first settlement'"))
            .firstMatch
        XCTAssertTrue(settlementPrompt.waitForExistence(timeout: 10), "a new game opens on the opening placement")

        // The canvas has no accessibility elements of its own, so tap it by
        // coordinate. Any tap lands on the nearest legal corner.
        let board = app.descendants(matching: .any).matching(identifier: "board").firstMatch
        let target = board.exists ? board : app.windows.firstMatch
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()

        let roadPrompt = app.staticTexts
            .containing(NSPredicate(format: "label CONTAINS[c] 'place a road'"))
            .firstMatch
        XCTAssertTrue(roadPrompt.waitForExistence(timeout: 5), "placing a settlement asks for the matching road")
    }
}
