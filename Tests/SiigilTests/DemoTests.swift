import Foundation
import Testing
@testable import Siigil

// Gli spazi d'esempio: quattro, con le app in ordine di nome, pid che nessun processo vero può avere (macOS arriva a
// 99999), finestre con id unici e positivi (solo quelli sono finestre di AeroSpace), uno spazio a fuoco con Safari davanti
// e l'anello blu dell'agente su Terminale.
@Test func theDemoWorkspacesAreSampleAppsThatTouchNoRealProcess() {
    let d = DemoSpaces.start
    #expect(d.spaces.map(\.name) == ["1", "2", "3", "4"])
    #expect(d.spaces.map { $0.apps.map(\.name) } == [["Mail", "Safari"], ["Notes"], ["Music"], ["Terminal"]])
    let apps = d.spaces.flatMap(\.apps)
    #expect(apps.allSatisfy { $0.pid >= 100_000 })
    #expect(Set(apps.map(\.windowID)).count == apps.count && apps.allSatisfy { $0.windowID > 0 })
    #expect(d.reports.filter(\.workspace.isFocused).map(\.workspace.name) == ["1"])
    #expect(d.frontWindow == 1)   // Safari
    #expect(apps.first { $0.name == "Terminal" }?.agent == .working)
}

// Trascinare Musica dalla pillola 3 alla 1 (era davanti nel suo spazio, quindi lo spazio la segue): esce dalla 3, entra
// nella 1 in ordine di nome, e la 1 va a fuoco con Musica davanti. Su uno spazio che non c'è non succede niente.
@Test func movingAnAppInTheDemoOnlyChangesTheDemoSpaces() {
    var d = DemoSpaces.start
    d.switchTo("3")
    #expect(d.frontWindow == 4)
    d.move(window: 4, to: "1", follow: true)
    #expect(d.spaces.map { $0.apps.map(\.name) } == [["Mail", "Music", "Safari"], ["Notes"], [], ["Terminal"]])
    #expect(d.focused == "1" && d.frontWindow == 4)
    let before = d.spaces.map { $0.apps.map(\.windowID) }
    d.move(window: 2, to: "9", follow: false)
    #expect(d.spaces.map { $0.apps.map(\.windowID) } == before)
}

// Le impostazioni della demo stanno in una cartella a parte (non le vere), vuota a ogni avvio: quello che la demo vi scrive
// non resta per la volta dopo.
@Test func theDemoSettingsAreSeparateAndFresh() {
    let d = demoDefaults()
    defer { d.removePersistentDomain(forName: "com.siigil.demo") }
    let s = Settings(defaults: d)
    s.right = [.widget(.clock)]
    #expect(d.stringArray(forKey: "siigil.bar.right") == ["clock"])   // le scritture vanno nella cartella della demo
    #expect(demoDefaults().object(forKey: "siigil.bar.right") == nil)   // un avvio nuovo la trova vuota
}
