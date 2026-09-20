import XCTest
@testable import OpenTanEngine

final class GeometryTests: XCTestCase {
    func testStandardLayoutHasNineteenTiles() {
        XCTAssertEqual(BoardLayout.standard.hexes.count, 19)
        XCTAssertEqual(Set(BoardLayout.standard.hexes).count, 19)
        XCTAssertEqual(BoardLayout.standard.terrains.count, 19)
        XCTAssertEqual(BoardLayout.standard.numbers.count, 18)
    }

    func testLargeLayoutHasThirtyTiles() {
        XCTAssertEqual(BoardLayout.large.hexes.count, 30)
        XCTAssertEqual(Set(BoardLayout.large.hexes).count, 30)
        XCTAssertEqual(BoardLayout.large.terrains.count, 30)
        XCTAssertEqual(BoardLayout.large.numbers.count, 28)
    }

    func testStandardBoardHasFiftyFourCornersAndSeventyTwoSides() {
        var rng = SeededGenerator(seed: 1)
        let board = BoardGenerator.make(layout: .standard, using: &rng)
        XCTAssertEqual(board.allVertices.count, 54)
        XCTAssertEqual(board.allEdges.count, 72)
    }

    func testEveryCornerHasThreeSidesAndThreeNeighbours() {
        var rng = SeededGenerator(seed: 2)
        let board = BoardGenerator.make(layout: .standard, using: &rng)
        for vertex in board.allVertices {
            XCTAssertEqual(Set(Geometry.edges(at: vertex)).count, 3)
            XCTAssertEqual(Set(Geometry.neighbors(of: vertex)).count, 3)
        }
    }

    func testSidesAndCornersAgree() {
        let hex = Hex(0, 0)
        for edge in Geometry.sides(of: hex) {
            let ends = Geometry.endpoints(of: edge)
            XCTAssertEqual(ends.count, 2)
            for end in ends {
                XCTAssertTrue(Geometry.edges(at: end).contains(edge))
            }
        }
    }

    func testCornerPositionMatchesHexCornerOffsets() {
        let centre = Geometry.center(of: Hex(0, 0))
        let offsets = Geometry.cornerOffsets()
        for vertex in Geometry.corners(of: Hex(0, 0)) {
            let point = Geometry.center(of: vertex)
            let matches = offsets.contains { offset in
                abs(centre.x + offset.x - point.x) < 0.0001 && abs(centre.y + offset.y - point.y) < 0.0001
            }
            XCTAssertTrue(matches, "corner \(vertex) is not on the hex outline")
        }
    }

    func testPortsCoverPairsOfCoastalCorners() {
        for layout in BoardLayout.allCases {
            var rng = SeededGenerator(seed: 7)
            let board = BoardGenerator.make(layout: layout, using: &rng)
            let expected = layout.portKinds.count
            XCTAssertEqual(board.ports.count, expected * 2, "\(layout) should place \(expected) two-corner ports")
            let specific = board.ports.values.filter { if case .specific = $0 { return true } else { return false } }
            XCTAssertEqual(Set(specific.map(\.displayName)).count, Resource.allCases.count)
        }
    }

    func testBalancedBoardKeepsSixesAndEightsApart() {
        for seed in UInt64(1)...20 {
            var rng = SeededGenerator(seed: seed)
            let board = BoardGenerator.make(layout: .standard, balanced: true, using: &rng)
            XCTAssertFalse(BoardGenerator.hasAdjacentHighNumbers(board.tiles))
        }
    }

    func testRobberStartsOnTheDesert() {
        var rng = SeededGenerator(seed: 11)
        let board = BoardGenerator.make(layout: .standard, using: &rng)
        XCTAssertEqual(board.tile(at: board.robber)?.terrain, .desert)
    }
}
