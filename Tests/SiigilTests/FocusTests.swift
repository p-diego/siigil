import Foundation
import Testing
@testable import Siigil

// Fixture nella struttura dei file di ~/Library/DoNotDisturb/DB (Task 4, step 0).
private func assertions(_ modes: [String]) -> Data {
    let records = modes.map { ["assertionDetails": ["assertionDetailsModeIdentifier": $0]] }
    return try! JSONSerialization.data(withJSONObject: ["data": [["storeAssertionRecords": records]]])
}

private func configurations(_ symbols: [String: String]) -> Data {
    let configs = symbols.mapValues { ["mode": ["symbolImageName": $0]] }
    return try! JSONSerialization.data(withJSONObject: ["data": [["modeConfigurations": configs]]])
}

@Test func activeFocusModeReadsTheLastRecord() {
    #expect(activeFocusMode(assertions: assertions([dndMode])) == dndMode)
    #expect(activeFocusMode(assertions: assertions(["com.apple.sleep.sleep-mode", dndMode])) == dndMode)
}

@Test func activeFocusModeIsNilWhenNothingIsActive() {
    #expect(activeFocusMode(assertions: assertions([])) == nil)
    #expect(activeFocusMode(assertions: try! JSONSerialization.data(withJSONObject: ["data": [[String: Any]()]])) == nil)
}

// Review Focus 1: formato cambiato in parte o file rotto → nil, niente crash.
@Test func activeFocusModeIsNilForOddFiles() {
    #expect(activeFocusMode(assertions: try! JSONSerialization.data(withJSONObject: ["data": [Any]()])) == nil)
    #expect(activeFocusMode(assertions: try! JSONSerialization.data(withJSONObject: ["data": [["storeAssertionRecords": [["other": 1]]]]])) == nil)
    #expect(activeFocusMode(assertions: Data("not json".utf8)) == nil)
}

@Test func focusSymbolComesFromTheModeConfiguration() {
    let data = configurations(["com.apple.sleep.sleep-mode": "bed.double.fill"])
    #expect(focusSymbol(configurations: data, mode: "com.apple.sleep.sleep-mode") == "bed.double.fill")
    #expect(focusSymbol(configurations: data, mode: dndMode) == nil)
    #expect(focusSymbol(configurations: Data("{}".utf8), mode: dndMode) == nil)
}

// Review Focus 2: simboli privati delle modalità personalizzate → la luna, non una pillola vuota.
@Test func unknownSymbolsFallBackToTheMoon() {
    #expect(validSymbol("bed.double.fill") == "bed.double.fill")
    #expect(validSymbol("not.a.real.symbol.siigil") == "moon.fill")
}
