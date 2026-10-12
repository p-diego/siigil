import Foundation
import Testing
@testable import Siigil

private func tokens(_ d: UserDefaults, _ side: String) -> [String]? { d.stringArray(forKey: "siigil.bar.\(side)") }

// Primo avvio, o chi non ha mai cambiato niente: le due mascotte di oggi coi loro predefiniti, e le liste di oggi con loro
// al posto di cat e dog.
@Test func firstLaunchMakesTodaysTwoMascots() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    #expect(s.mascots.count == 2)
    let ai = s.mascots[0], system = s.mascots[1]
    #expect(ai.shape == .mostro && ai.body == 0xF5F7FC && ai.eyes == 0x14141A && ai.voice == .bubble)
    #expect(ai.function == .ai(agents: [.claude, .codex]))
    #expect(ai.sounds && ai.volume == 35 && ai.captions && ai.renewedBadge && ai.quotaInMenu && ai.background && ai.besideNotch)
    #expect(system.shape == .mirtillo && system.body == 0x739EFA && system.eyes == 0x14141A && system.voice == .bottle)
    #expect(system.function == .system(kinds: [.cpu, .heat, .memory]))
    #expect(system.sounds && system.volume == 35 && system.captions && system.background && !system.besideNotch)
    for m in s.mascots { #expect(m.eyeSize == 1 && m.eyeLift == 0 && m.eyeSpread == 1 && m.size == 1) }   // gli occhi e la grandezza di oggi
    #expect(tokens(d, "left") == ["workspaces", "hidden"])
    #expect(tokens(d, "right") == ["mascot:\(ai.id.uuidString)", "mascot:\(system.id.uuidString)", "focus", "wifi", "volume", "battery", "clock"])
}

// Chi aggiorna ritrova tutto com'era: colori (anche dalle versioni del 7/10), suoni, fumetti, quota nel menu, sfondo, notch.
@Test func updatingKeepsEverythingTheyHad() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(3, forKey: "siigil.catMascot")   // la versione nera del 7/10: corpo nero, occhi bianchi
    d.set(0xE8483F, forKey: "siigil.dogBodyColor")
    for (key, value) in [("meow", false), ("captions", false), ("renewedBadge", false), ("quotaEnabled", false),
                         ("codexQuotaEnabled", true), ("catBackground", false), ("catBesideNotch", false), ("bark", false),
                         ("dogCaptions", false), ("dogBackground", false), ("dogBesideNotch", true)] {
        d.set(value, forKey: "siigil.\(key)")
    }
    d.set(80, forKey: "siigil.meowVolume"); d.set(10, forKey: "siigil.barkVolume")
    let s = Settings(defaults: d)
    let ai = s.mascots[0], system = s.mascots[1]
    #expect(ai.body == 0x14141A && ai.eyes == 0xF5F7FC)
    #expect(!ai.sounds && ai.volume == 80 && !ai.captions && !ai.renewedBadge && ai.quotaInMenu && !ai.background && !ai.besideNotch)
    #expect(system.body == 0xE8483F && system.eyes == 0x14141A)
    #expect(!system.sounds && system.volume == 10 && !system.captions && !system.background && system.besideNotch)
    // Tutte e due le quote spente: niente quota nel menu né "Sessione rinnovata!" (nella 0.31 era grigio), quindi non si
    // scarica niente.
    let (o, oname) = fresh(); defer { o.removePersistentDomain(forName: oname) }
    o.set(false, forKey: "siigil.quotaEnabled"); o.set(false, forKey: "siigil.codexQuotaEnabled")
    let off = Settings(defaults: o).mascots
    #expect(!off[0].quotaInMenu && !off[0].renewedBadge)
    #expect(quotaAccounts(off, isOn: { _ in true }, accountsPage: false) == [])
}

// Nella barra prendono il posto di cat e dog, dove stavano; una spenta nasce spenta ma resta nell'elenco; un widget che
// questa versione non conosce si scarta.
@Test func theyTakeTheCatAndDogPlacesInTheBar() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(["workspaces", "dog"], forKey: "siigil.left")
    d.set(["teapot", "clock"], forKey: "siigil.right")   // il gatto era spento
    let s = Settings(defaults: d)
    #expect(s.mascots.count == 2)
    #expect(tokens(d, "left") == ["workspaces", "mascot:\(s.mascots[1].id.uuidString)"])
    #expect(tokens(d, "right") == ["clock"])
}

// Le chiavi di prima non si toccano (la 0.31 riaperta le ritrova) e la migrazione si fa una volta sola.
@Test func oldKeysStayAndTheMigrationRunsOnce() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(["cat", "clock"], forKey: "siigil.right"); d.set(false, forKey: "siigil.meow")
    let first = Settings(defaults: d).mascots
    #expect(d.stringArray(forKey: "siigil.right") == ["cat", "clock"] && d.object(forKey: "siigil.left") == nil)
    #expect(d.object(forKey: "siigil.catBodyColor") == nil && d.object(forKey: "siigil.meow") as? Bool == false)
    d.set(true, forKey: "siigil.meow")   // cambiata dopo, per esempio dalla 0.31: non conta più
    let second = Settings(defaults: d).mascots
    #expect(second == first && !second[0].sounds)
}

// Un valore che questa versione non sa leggere (una versione futura con una voce nuova): le due mascotte di prima, il
// valore resta com'è, le liste della barra non si scrivono, e se ne tiene una copia una volta sola.
@Test func anUnreadableValueIsNotOverwrittenAtLaunch() throws {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let valid = try JSONEncoder().encode([Mascot(shape: .mirtillo, body: 0x739EFA, eyes: 0x14141A, voice: .bottle, function: .system(kinds: [.cpu]))])
    let future = Data(String(decoding: valid, as: UTF8.self).replacingOccurrences(of: #""bottle""#, with: #""kazoo""#).utf8)
    #expect(future != valid)
    d.set(future, forKey: "siigil.mascots")
    let s = Settings(defaults: d)
    #expect(s.mascots.map(\.shape) == [.mostro, .mirtillo])
    #expect(d.data(forKey: "siigil.mascots") == future)
    #expect(d.object(forKey: "siigil.bar.left") == nil && d.object(forKey: "siigil.bar.right") == nil)
    #expect(d.data(forKey: "siigil.mascots.unreadable") == future)
    let later = Data(#"[{"shape":"stella"}]"#.utf8)   // un altro valore illeggibile: la copia resta la prima
    d.set(later, forKey: "siigil.mascots")
    _ = Settings(defaults: d)
    #expect(d.data(forKey: "siigil.mascots.unreadable") == future)
}

// Il formato salvato (spec §7): un elenco scritto a mano con tutte le chiavi si legge così, chiave per chiave.
@Test func theSavedFormatIsPinned() throws {
    let json = #"""
    [{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","shape":"mostro","body":16119804,"eyes":1315866,"voice":"bubble",
      "function":{"ai":{"agents":["Claude"]}},"sounds":true,"volume":35,"captions":false,"renewedBadge":true,"quotaInMenu":false,
      "background":true,"besideNotch":true,"eyeSize":1.1,"eyeLift":-2,"eyeSpread":0.9,"size":1.25},
     {"id":"6F9619FF-8B86-D011-B42D-00C04FC96500","shape":"cloud","body":7577338,"eyes":1315866,"voice":"bottle",
      "function":{"system":{"kinds":["cpu","memory"]}},"sounds":false,"volume":80,"captions":true,"renewedBadge":true,
      "quotaInMenu":true,"background":false,"besideNotch":false,"eyeSize":1,"eyeLift":0,"eyeSpread":1,"size":0.7}]
    """#
    let m = try JSONDecoder().decode([Mascot].self, from: Data(json.utf8))
    #expect(m.count == 2 && m[0].id == UUID(uuidString: "6F9619FF-8B86-D011-B42D-00C04FC964FF"))
    #expect(m[0].shape == .mostro && m[0].body == 0xF5F7FC && m[0].eyes == 0x14141A && m[0].voice == .bubble)
    #expect(m[0].function == .ai(agents: [.claude]) && m[0].sounds && m[0].volume == 35 && !m[0].captions && m[0].renewedBadge)
    #expect(!m[0].quotaInMenu && m[0].background && m[0].besideNotch)
    #expect(m[0].eyeSize == 1.1 && m[0].eyeLift == -2 && m[0].eyeSpread == 0.9 && m[0].size == 1.25)
    #expect(m[1].shape == .cloud && m[1].body == 0x739EFA && m[1].voice == .bottle && m[1].function == .system(kinds: [.cpu, .memory]))
    #expect(!m[1].sounds && m[1].volume == 80 && !m[1].background && m[1].size == 0.7)
    #expect(try JSONDecoder().decode([Mascot].self, from: JSONEncoder().encode(m)) == m)   // e si riscrive uguale
}

@Test func mascotsAreSavedInListOrder() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.mascots[0].volume = 80; s.mascots[0].eyeSize = 1.2; s.mascots[0].eyeLift = -3; s.mascots[0].eyeSpread = 0.9; s.mascots[0].size = 1.25
    s.mascots.append(Mascot(shape: .mirtillo, body: 0xE8483F, eyes: 0x14141A, voice: .bubble, function: .system(kinds: [.memory])))
    let t = Settings(defaults: d)
    #expect(t.mascots == s.mascots && t.mascots[0].volume == 80 && t.mascots[2].function.kinds == [.memory])
    #expect(t.mascots[0].eyeSize == 1.2 && t.mascots[0].eyeLift == -3 && t.mascots[0].eyeSpread == 0.9 && t.mascots[0].size == 1.25)
}

@Test func barItemsRoundTripThroughTheirTokens() {
    let id = UUID()
    #expect(BarItem("clock") == .widget(.clock) && BarItem.widget(.clock).token == "clock")
    #expect(BarItem("mascot:\(id.uuidString)") == .mascot(id) && BarItem.mascot(id).token == "mascot:\(id.uuidString)")
    #expect(BarItem("mascot:nope") == nil && BarItem("teapot") == nil)
    #expect(BarItem.mascot(id).isMascot && !BarItem.widget(.clock).isMascot)
}

@Test func aFunctionKnowsWhatItWatches() {
    let ai = MascotFunction.ai(agents: [.codex]), system = MascotFunction.system(kinds: [.cpu, .memory])
    #expect(ai.isAI && ai.agents == [.codex] && ai.kinds.isEmpty)
    #expect(!system.isAI && system.kinds == [.cpu, .memory] && system.agents.isEmpty)
    #expect(Agent(rawValue: "Claude") == .claude && Agent(rawValue: "Codex") == .codex)   // il nome: nei menu e nelle mascotte salvate
}
