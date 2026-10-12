import AppKit
import SwiftUI
import Testing
@testable import Siigil

// Il filtro scritto come dice la spec (§1): le caselle spuntate in ordine, unite da "e"; tutte: "Tutti" o "Tutto". I test
// girano senza le traduzioni: si vedono le chiavi inglesi.
@Test func filtersAreWrittenAsTheSpecSays() {
    #expect(MascotFunction.ai(agents: [.claude, .codex]).filterName == "All")
    #expect(MascotFunction.ai(agents: [.codex]).filterName == "Codex")
    #expect(MascotFunction.system(kinds: [.cpu, .heat, .memory]).filterName == "Everything")
    #expect(MascotFunction.system(kinds: [.memory]).filterName == "Memory")
    #expect(MascotFunction.system(kinds: [.memory, .cpu]).filterName == "CPU and memory")
    #expect(MascotFunction.system(kinds: [.heat, .memory]).filterName == "Heat and memory")
    #expect(MascotFunction.system(kinds: [.cpu]).filterName == "CPU" && MascotFunction.system(kinds: [.heat]).filterName == "Heat")
    #expect(MascotFunction.system(kinds: [.heat, .cpu]).filterName == "CPU and heat")   // in ordine, la seconda minuscola
    #expect(MascotVoice.bubble.name == "Bubble" && MascotVoice.bottle.name == "Bottle")
    let m = Mascot(shape: .mostro, body: 0, eyes: 0, voice: .bubble, function: .ai(agents: [.claude]))
    #expect(m.title == "AI monitor · Claude")
    #expect(Set(MascotKind.allCases.map(\.name)).count == MascotKind.allCases.count)   // un nome per forma, per VoiceOver
}

// L'ultima casella spuntata non si toglie; una casella dell'altra funzione non tocca niente (spec §1). Le cose libere
// quando si cambia funzione: changingFunctionTakesOnlyTheFreeThings.
@Test func theLastBoxStaysTicked() {
    let one = MascotFunction.ai(agents: [.claude])
    #expect(one.toggling(.claude) == one)
    #expect(one.toggling(.codex) == .ai(agents: [.claude, .codex]))
    #expect(MascotFunction.ai(agents: [.claude, .codex]).toggling(.claude) == .ai(agents: [.codex]))
    #expect(MascotFunction.system(kinds: [.memory]).toggling(.memory) == .system(kinds: [.memory]))
    #expect(MascotFunction.system(kinds: [.memory]).toggling(.cpu) == .system(kinds: [.cpu, .memory]))
    #expect(one.toggling(.cpu) == one)   // una casella dell'altra funzione non tocca niente
    #expect(MascotFunction.all(ai: true) == .ai(agents: [.claude, .codex]))
    #expect(MascotFunction.all(ai: false) == .system(kinds: [.cpu, .heat, .memory]))
}

// Il disegno fermo dell'elenco: la mascotte coi suoi colori (qui il corpo rosso, sotto gli occhi), trasparente sopra la
// testa. Il colore si guarda a spanne: la bitmap passa per lo spazio colore dello schermo.
@MainActor @Test func theThumbnailIsTheMascotStanding() throws {
    let m = Mascot(shape: .mirtillo, body: 0xE8483F, eyes: 0x14141A, voice: .bottle, function: .system(kinds: [.cpu]))
    let rep = try #require(mascotThumbnail(m, height: 54).tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
    let body = try #require(rep.colorAt(x: rep.pixelsWide / 2, y: rep.pixelsHigh * 4 / 5)?.usingColorSpace(.sRGB))
    #expect(body.alphaComponent > 0.9 && body.redComponent > 0.8 && body.greenComponent < 0.5 && body.blueComponent < 0.5)
    #expect(rep.colorAt(x: rep.pixelsWide / 2, y: 2)?.alphaComponent == 0)
    // Sveglia, sguardo dritto: l'occhio sinistro ha il colore degli occhi (qui nero) al centro e, aperto (alto 15 unità),
    // anche 4 unità sopra e sotto; chiuso (una riga alta 4) no. Il pixel è quello che contiene il punto.
    let g = MascotGeometry.of(m), scale = Double(rep.pixelsHigh) / 100
    let x = Int((Double(rep.pixelsWide) - Double(rep.pixelsHigh)) / 2 + (50 - g.eyeGap) * scale)
    for dy in [-4.0, 0, 4] {
        let eye = try #require(rep.colorAt(x: x, y: Int((g.eyeY + dy) * scale))?.usingColorSpace(.sRGB))
        #expect(eye.alphaComponent > 0.9 && eye.redComponent < 0.25 && eye.greenComponent < 0.25 && eye.blueComponent < 0.25, "\(dy): \(eye)")
    }
}

// Review Focus: eliminata una mascotte, indietro e avanti non riportano alla sua pagina.
@Test func theHistoryForgetsDeletedMascots() {
    let a = UUID(), b = UUID()
    let list = SettingsPlace(page: .general)
    let history = [SettingsPlace(page: .ai), list, SettingsPlace(page: .general, mascot: a), list, SettingsPlace(page: .general, mascot: b)]
    #expect(pruned(history, alive: [b], here: SettingsPlace(page: .pills)) == [SettingsPlace(page: .ai), list, SettingsPlace(page: .general, mascot: b)])
    // Eliminata dalla sua pagina si torna all'elenco: un passo indietro verso l'elenco stesso sarebbe a vuoto, e va via.
    #expect(pruned([SettingsPlace(page: .ai), list, SettingsPlace(page: .general, mascot: a)], alive: [], here: list) == [SettingsPlace(page: .ai)])
}

// I cursori in percento mostrano il numero scelto: 113 resta 113 (1,13 × 100 = 112,99…), su tutto l'intervallo.
@Test func percentSlidersShowWhatWasChosen() {
    var stored = 1.0
    let slider = percent(Binding(get: { stored }, set: { stored = $0 }))
    for p in 70...125 {
        slider.wrappedValue = Double(p)
        #expect(Int(slider.wrappedValue) == p && abs(stored - Double(p) / 100) < 1e-12, "\(p)")
    }
}

// Una cosa guardata, una mascotte (autore, 11/10): le cose prese contano anche le mascotte nascoste.
@Test func takenThingsCountTheHiddenMascotsToo() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)   // le due di chi aggiorna: Monitor AI con tutti gli agenti, Monitor di sistema con tutto
    s.setMascot(s.mascots[0].id, on: false)
    #expect(s.mascots.taken().agents == Set(Agent.allCases) && s.mascots.taken().kinds == Set(AlarmKind.allCases))
    #expect(s.mascots.free(ai: true) == nil && s.mascots.free(ai: false) == nil)   // il +: tutte e due le voci grigie
}

// Il + crea la mascotte con le cose ancora libere: tolto Codex al primo Monitor AI, un Monitor AI con solo Codex; tolto il
// calore al Monitor di sistema, uno col solo calore.
@Test func thePlusTakesOnlyTheFreeThings() throws {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.mascots[0].function = s.mascots[0].function.toggling(.codex)
    s.mascots[1].function = s.mascots[1].function.toggling(.heat)
    let ai = s.addMascot(try #require(s.mascots.free(ai: true))), system = s.addMascot(try #require(s.mascots.free(ai: false)))
    #expect(s.mascot(ai)?.function == .ai(agents: [.codex]) && s.mascot(system)?.function == .system(kinds: [.heat]))
    #expect(s.mascots.free(ai: true) == nil && s.mascots.free(ai: false) == nil)
}

// Cambiare funzione prende solo le cose libere; niente se non ne resta nessuna.
@Test func changingFunctionTakesOnlyTheFreeThings() {
    let claude = Mascot(shape: .mostro, body: 0, eyes: 0, voice: .bubble, function: .ai(agents: [.claude]))
    let heat = Mascot(shape: .ball, body: 0, eyes: 0, voice: .bottle, function: .system(kinds: [.heat]))
    #expect([claude, heat].free(ai: true, for: heat.id) == .ai(agents: [.codex]))
    #expect([claude, heat].free(ai: false, for: claude.id) == .system(kinds: [.cpu, .memory]))
    var both = claude; both.function = .ai(agents: [.claude, .codex])
    #expect([both, heat].free(ai: true, for: heat.id) == nil)
    #expect([both, heat].free(ai: true, for: both.id) == .ai(agents: [.claude, .codex]))   // le sue non contano
}

// Una cosa di un'altra mascotte non si spunta; se per caso fosse già spuntata (un doppione delle build di prova) si può
// togliere, ma non rimettere. L'ultima spuntata resta.
@Test func aTakenThingIsNotTickedButCanBeUnticked() {
    #expect(MascotFunction.ai(agents: [.claude]).toggling(.codex, taken: [.codex]) == .ai(agents: [.claude]))
    #expect(MascotFunction.ai(agents: [.claude, .codex]).toggling(.codex, taken: [.codex]) == .ai(agents: [.claude]))
    #expect(MascotFunction.system(kinds: [.cpu]).toggling(.heat, taken: [.heat]) == .system(kinds: [.cpu]))
    #expect(MascotFunction.system(kinds: [.cpu, .heat]).toggling(.heat, taken: [.heat]) == .system(kinds: [.cpu]))
    #expect(MascotFunction.ai(agents: [.codex]).toggling(.codex, taken: [.codex]) == .ai(agents: [.codex]))
}

// Un fatto suona sulla sua mascotte: tolto Codex al Monitor AI di chi aggiorna, il + ne crea uno per Codex; rispuntare
// Codex sul primo non si può, e ogni agente suona sulla sua mascotte, anche spostata nella barra.
@Test func aFactSoundsOnItsOwnMascot() throws {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), first = s.mascots[0].id
    s.mascots[0].function = s.mascots[0].function.toggling(.codex)
    let codex = s.addMascot(try #require(s.mascots.free(ai: true)))
    s.move(.mascot(codex), to: .left, index: 0)
    s.mascots[0].function = s.mascots[0].function.toggling(.codex, taken: s.mascots.taken(except: first).agents)
    #expect(s.whoSounds { $0.function.agents.contains(.codex) }?.id == codex)
    #expect(s.whoSounds { $0.function.agents.contains(.claude) }?.id == first)
}

// Nella pagina di un Monitor AI, con tutto il sistema già di altre mascotte, si spegne solo il segmento "Monitor di
// sistema"; quello scelto resta acceso. Con qualcosa di libero sono accesi tutti e due. Si legge il controllo vero,
// disegnato fuori dallo schermo.
@MainActor @Test func onlyTheOtherFunctionSegmentIsDisabled() throws {
    _ = NSApplication.shared
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)   // le due di chi aggiorna: Monitor AI con tutti gli agenti, Monitor di sistema con tutto
    func segments() throws -> (control: Bool, ai: Bool, system: Bool) {
        let host = NSHostingView(rootView: MascotScreen(id: s.mascots[0].id, settings: s))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 1500), styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func find(_ v: NSView) -> NSSegmentedControl? { (v as? NSSegmentedControl) ?? v.subviews.lazy.compactMap(find).first }
        let seg = try #require(find(host))
        return withExtendedLifetime(window) { (seg.isEnabled, seg.isEnabled(forSegment: 0), seg.isEnabled(forSegment: 1)) }
    }
    let allTaken = try segments()
    #expect(allTaken.control && allTaken.ai && !allTaken.system, "\(allTaken)")
    // Con un doppione (dati delle build di prova) alla sua funzione non resta niente di libero: il segmento scelto non si
    // spegne lo stesso.
    let twin = s.addMascot(.ai(agents: Set(Agent.allCases)))
    let withTwin = try segments()
    #expect(withTwin.control && withTwin.ai && !withTwin.system, "\(withTwin)")
    s.deleteMascot(twin)
    s.mascots[1].function = .system(kinds: [.cpu])   // calore e memoria liberi
    let someFree = try segments()
    #expect(someFree.control && someFree.ai && someFree.system, "\(someFree)")
}
