import Foundation
import Testing
@testable import Siigil

// Regola di riapertura (spec benvenuto §2): qualcosa era a posto e ora non lo è. Chiavi nuove o sparite non contano.
@Test func regressedOnlyWhenSomethingWasOKAndIsNot() {
    #expect(regressed(previous: ["fda": true], now: ["fda": false]))
    #expect(!regressed(previous: ["fda": true], now: ["fda": true]))
    #expect(!regressed(previous: ["fda": false], now: ["fda": false]))   // mai stato a posto
    #expect(!regressed(previous: [:], now: ["fda": false]))              // chiave nuova (widget appena acceso)
    #expect(!regressed(previous: ["fda": true], now: [:]))               // chiave sparita (widget spento)
    #expect(regressed(previous: ["fda": true, "codex": true], now: ["fda": true, "codex": false]))
}

// Stesso criterio di main.swift per "copia installata".
@Test func inApplicationsForSystemAndUserFolders() {
    #expect(inApplications("/Applications/Siigil.app"))
    #expect(inApplications("/Users/x/Applications/Siigil.app"))
    #expect(!inApplications("/Volumes/Siigil/Siigil.app"))
    #expect(!inApplications("/Users/x/Git/siigil/.build/Siigil.app"))
}

// Finding 1 della revisione finale: dal disco immagine o da una copia tradotta la finestra deve aprirsi da sola.
@Test func launchedFromDiskImageForVolumesAndAppTranslocation() {
    #expect(launchedFromDiskImage("/Volumes/Siigil/Siigil.app"))
    #expect(launchedFromDiskImage("/private/var/folders/xx/T/AppTranslocation/ABCD/d/Siigil.app"))
    #expect(!launchedFromDiskImage("/Applications/Siigil.app"))
    #expect(!launchedFromDiskImage("/Users/x/Applications/Siigil.app"))
    #expect(!launchedFromDiskImage("/Users/x/Git/siigil/.build/Siigil.app"))
}

@Test func destinationPrefersSystemApplications() {
    let home = URL(fileURLWithPath: "/Users/x")
    #expect(applicationsDestination(applicationsWritable: true, home: home).path == "/Applications/Siigil.app")
    #expect(applicationsDestination(applicationsWritable: false, home: home).path == "/Users/x/Applications/Siigil.app")
}

// La fotografia (spec §2) contiene solo ciò che un aggiornamento può rompere: permessi TCC dei widget accesi e gli hook
// che esistono. Scorciatoia DND e AeroSpace non ci sono; i widget spenti e le integrazioni assenti nemmeno.
@Test func snapshotOnlyCoversWhatUpdatesBreak() {
    let s = snapshot(missing: [.fullDiskAccess, .dndShortcut],
                     hooks: ["claude-code": .installed, "codex": .outdated, "gemini": .missing("no ~/.gemini")],
                     focusOn: true, wifiOn: true)
    #expect(s == ["fda": false, "location": true, "claude-code": true, "codex": false])
    #expect(snapshot(missing: [], hooks: [:], focusOn: false, wifiOn: false).isEmpty)
    #expect(snapshot(missing: [.location], hooks: [:], focusOn: false, wifiOn: true) == ["location": false])
}
