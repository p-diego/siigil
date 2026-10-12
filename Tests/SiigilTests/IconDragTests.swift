import Foundation
import Testing
@testable import Siigil

// Cornici nello spazio "bar" (y verso il basso, barra alta 38): pillola "1" da 10 a 50, pillola "2" da 56 a 156.
private let pills: [String: CGRect] = [
    "1": CGRect(x: 10, y: 6, width: 40, height: 26),
    "2": CGRect(x: 56, y: 6, width: 100, height: 26),
]

@Test func dropOnAnotherPillTargetsIt() {
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 19), from: "1", pills: pills) == "2")
}

// Sulla stessa pillola, tra due pillole, sopra o sotto la barra: niente.
@Test func dropOnTheSamePillBetweenPillsOrOutsideTheBarIsNothing() {
    #expect(iconDropTarget(at: CGPoint(x: 20, y: 19), from: "1", pills: pills) == nil)
    #expect(iconDropTarget(at: CGPoint(x: 53, y: 19), from: "1", pills: pills) == nil)
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 40), from: "1", pills: pills) == nil)
    #expect(iconDropTarget(at: CGPoint(x: 80, y: -1), from: "1", pills: pills) == nil)
}

// Conta la colonna della pillola, non il suo rettangolo: il puntatore poco sopra o sotto la capsula, ma dentro la barra, vale.
@Test func dropAboveOrBelowTheCapsuleInsideTheBarCounts() {
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 2), from: "1", pills: pills) == "2")
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 36), from: "1", pills: pills) == "2")
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 0), from: "1", pills: pills) == "2")
    #expect(iconDropTarget(at: CGPoint(x: 80, y: 38), from: "1", pills: pills) == "2")
}

@Test func pillEdgesAreInclusive() {
    #expect(iconDropTarget(at: CGPoint(x: 56, y: 19), from: "1", pills: pills) == "2")
    #expect(iconDropTarget(at: CGPoint(x: 156, y: 19), from: "1", pills: pills) == "2")
}

@Test func moveArgsFollowOnlyWhenAsked() {
    #expect(moveWindowArgs(windowID: 42, to: "3", follow: false) == ["move-node-to-workspace", "--window-id", "42", "--", "3"])
    #expect(moveWindowArgs(windowID: 42, to: "3", follow: true)
            == ["move-node-to-workspace", "--focus-follows-window", "--window-id", "42", "--", "3"])
}
