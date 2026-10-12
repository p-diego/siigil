import Foundation
import Testing
@testable import Siigil

// Ogni test ha la sua suite di UserDefaults, cancellata alla fine (la usano anche le prove di altri file).
func fresh() -> (UserDefaults, String) {
    let name = "siigil-test-\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}
private func w(_ ids: WidgetID...) -> [BarItem] { ids.map(BarItem.widget) }
// Le due mascotte nate dalla migrazione: il Monitor AI (il gatto di prima) e il Monitor di sistema (il cane).
private func pair(_ s: Settings) -> (ai: BarItem, system: BarItem) { (.mascot(s.mascots[0].id), .mascot(s.mascots[1].id)) }

@Test func defaultsMatchTodaysBehaviour() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    #expect(s.left == w(.workspaces, .hidden) && s.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock))
    #expect(s.showFrontAppName)
    #expect(s.clockFormat == clockDefaultFormat && s.quotaInterval == 5 && s.clockApp == "com.apple.iCal")
    #expect(!s.setupDone && s.setupSnapshot.isEmpty)
}

@Test func writesAreReadBackByANewInstance() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.showFrontAppName = false
    s.clockFormat = "HH:mm"; s.quotaInterval = 15; s.clockApp = ""
    s.right = w(.clock); s.left = []
    s.setupDone = true; s.setupSnapshot = ["fda": true, "location": false]
    let t = Settings(defaults: d)
    #expect(!t.showFrontAppName)
    #expect(t.clockFormat == "HH:mm" && t.quotaInterval == 15 && t.clockApp == "")
    #expect(t.right == w(.clock) && t.left == [])
    #expect(t.setupDone && t.setupSnapshot == ["fda": true, "location": false])
}

@Test func switchingOffRemovesAndOnRestoresCanonicalOrder() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    s.set(.battery, on: false)
    #expect(!s.isOn(.battery) && s.right == [ai, system] + w(.focus, .wifi, .volume, .clock))
    s.set(.battery, on: true)
    #expect(s.isOn(.battery) && s.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock))
    s.set(.battery, on: true)   // già accesa: non si duplica
    #expect(s.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock))
    s.set(.hidden, on: false); s.set(.hidden, on: true)
    #expect(s.left == w(.workspaces, .hidden))
}

@Test func settingLaunchAtLoginPersistsTheChoice() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.setLaunchAtLogin(false)   // SMAppService può fallire nel processo di test: la chiave va comunque scritta
    #expect(d.object(forKey: "siigil.launchAtLogin") as? Bool == false)
}

@Test func moveReordersAndChangesSideWithClampedIndex() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    s.move(.widget(.clock), to: .right, index: 1)
    #expect(s.right == [ai, system] + w(.clock, .focus, .wifi, .volume, .battery))   // tra le mascotte no: dopo di loro
    s.move(.widget(.wifi), to: .left, index: 99)
    #expect(s.left == w(.workspaces, .hidden, .wifi) && s.right == [ai, system] + w(.clock, .focus, .volume, .battery))
    s.move(.widget(.wifi), to: .left, index: -5)
    #expect(s.left == w(.wifi, .workspaces, .hidden))
}

// Una mascotte sta solo ai bordi dello spazio vuoto, ultima a sinistra o prima a destra, dovunque la si lasci e qualunque
// widget le si metta accanto: in mezzo ai widget il fumetto li coprirebbe.
@Test func mascotsStayAtTheEdgeOfTheirSide() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    s.move(.widget(.clock), to: .right, index: 0)
    #expect(s.right == [ai, system] + w(.clock, .focus, .wifi, .volume, .battery))
    s.move(ai, to: .left, index: 0)
    #expect(s.left == w(.workspaces, .hidden) + [ai])
    s.move(.widget(.wifi), to: .left, index: 99)
    #expect(s.left == w(.workspaces, .hidden, .wifi) + [ai])
    s.move(ai, to: .right, index: 3)
    #expect(s.right.first == ai && s.left == w(.workspaces, .hidden, .wifi))
}

// Le liste nuove si leggono come le vecchie: un widget sconosciuto (versione futura, refuso) si scarta, e anche una
// mascotte che non c'è più.
@Test func unknownItemsAreDroppedOnRead() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let ai = pair(Settings(defaults: d)).ai   // la prima apertura: migrazione
    d.set([ai.token, "mascot:\(UUID().uuidString)", "teapot", "clock"], forKey: "siigil.bar.right")
    d.set([String](), forKey: "siigil.bar.left")
    let s = Settings(defaults: d)
    #expect(s.right == [ai] + w(.clock) && s.left == [])
}

@Test func didHideMenuBarReadsItsKey() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    #expect(!Settings(defaults: d).didHideMenuBar)
    d.set(true, forKey: "siigil.didHideMenuBar")
    #expect(Settings(defaults: d).didHideMenuBar)
}

// Chi aveva già Siigil ha le liste salvate senza i widget nuovi: restano spenti e, accesi da Impostazioni, vanno dopo le
// mascotte nell'ordine dei casi, senza duplicati. Qui il cane era spento: il Monitor di sistema nasce spento.
@Test func savedListsKeepNewWidgetsOffUntilSwitchedOn() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(["cat", "volume", "battery", "clock"], forKey: "siigil.right")
    let s = Settings(defaults: d), (ai, system) = pair(s)
    #expect(s.right == [ai] + w(.volume, .battery, .clock) && !s.isOn(.wifi) && !s.isOn(.focus) && !s.isOn(system))
    s.set(.wifi, on: true)
    #expect(s.right == [ai] + w(.wifi, .volume, .battery, .clock))
    s.set(.focus, on: true); s.set(.focus, on: true)
    #expect(s.right == [ai] + w(.focus, .wifi, .volume, .battery, .clock))
}

// Una lista salvata da una versione di prima col cane in mezzo ai widget: al caricamento torna al bordo, dopo il gatto.
@Test func savedListWithTheDogInTheMiddleLoadsAtTheEdge() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(["cat", "focus", "dog", "wifi"], forKey: "siigil.right")
    let s = Settings(defaults: d), (ai, system) = pair(s)
    #expect(s.right == [ai, system] + w(.focus, .wifi))
}

@Test func didDisableTilingReadsItsKey() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    #expect(!Settings(defaults: d).didDisableTiling)
    d.set(true, forKey: "siigil.didDisableTiling")
    #expect(Settings(defaults: d).didDisableTiling)
}

@Test func appearanceDefaultsAreTodaysBar() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    #expect(s.barStyle == .glass && s.barAppearance == .automatic)
    #expect(s.edgeMargin == 6 && s.notchMargin == 6 && s.cornerRadius == 13)
}

@Test func appearanceIsSavedAndReadBack() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.barStyle = .nord; s.barAppearance = .dark; s.edgeMargin = 10; s.notchMargin = 20; s.cornerRadius = 4
    let again = Settings(defaults: d)
    #expect(again.barStyle == .nord && again.barAppearance == .dark)
    #expect(again.edgeMargin == 10 && again.notchMargin == 20 && again.cornerRadius == 4)
}

// Valori scritti a mano o da una versione futura: stile sconosciuto = vetro, numeri fuori limite = il limite,
// un numero che non è un numero = il default.
@Test func unknownStyleAndOutOfRangeNumbersFallBack() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set("solarized", forKey: "siigil.barStyle"); d.set("sepia", forKey: "siigil.barAppearance")
    d.set(99.0, forKey: "siigil.edgeMargin"); d.set(-5.0, forKey: "siigil.notchMargin"); d.set("tondo", forKey: "siigil.cornerRadius")
    let s = Settings(defaults: d)
    #expect(s.barStyle == .glass && s.barAppearance == .automatic)
    #expect(s.edgeMargin == 24 && s.notchMargin == 0 && s.cornerRadius == 13)
}

// Vetro sui temi spento e font di sistema, di default; un font sconosciuto torna a quello di sistema.
@Test func themeGlassAndFontDefaultToOffAndSystem() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    #expect(!Settings(defaults: d).themeGlass && Settings(defaults: d).barFont == .system && Settings(defaults: d).transparentGlass)
    d.set("comic-sans", forKey: "siigil.barFont")
    #expect(Settings(defaults: d).barFont == .system)
    d.set("jetBrains", forKey: "siigil.barFont")   // tolto il 4/10: chi l'aveva scelto torna a SF Pro
    #expect(Settings(defaults: d).barFont == .system)
}

@Test func themeGlassAndFontAreSavedAndReadBack() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.themeGlass = true; s.barFont = .serif; s.transparentGlass = false
    let again = Settings(defaults: d)
    #expect(again.themeGlass && again.barFont == .serif && !again.transparentGlass)
}

// Reset style: tutto l'aspetto torna com'era al primo avvio.
@Test func resetAppearanceRestoresTheDefaults() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.barStyle = .dracula; s.barAppearance = .light; s.themeGlass = true; s.transparentGlass = false
    s.edgeMargin = 20; s.notchMargin = 30; s.cornerRadius = 2; s.barFont = .serif
    s.mergedLeft = true; s.mergedRight = true
    s.resetAppearance()
    #expect(s.barStyle == .glass && s.barAppearance == .automatic && !s.themeGlass && s.transparentGlass)
    #expect(s.edgeMargin == 6 && s.notchMargin == 6 && s.cornerRadius == 13 && s.barFont == .system)
    #expect(!s.mergedLeft && !s.mergedRight)
}

// Le mascotte stanno ai bordi, attaccate al notch o ai widget: le liste nell'ordine in cui si vedono.
@Test func mascotsStayAtTheEdgeInTheOrderTheyAreSeen() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)   // di partenza: il Monitor AI al notch, quello di sistema ai widget
    #expect(s.besideNotch(ai) && !s.besideNotch(system) && !s.besideNotch(.widget(.clock)))
    s.move(system, to: .right, index: 4)
    #expect(s.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock))   // torna al bordo
    s.setBesideNotch(system, true); s.setBesideNotch(ai, false)
    s.move(ai, to: .right, index: 0)
    #expect(s.right == [system, ai] + w(.focus, .wifi, .volume, .battery, .clock))   // prima chi sta al notch
    s.move(system, to: .left, index: 0)
    #expect(s.left == w(.workspaces, .hidden) + [system] && s.right.first == ai)
    s.setBesideNotch(system, false)
    s.move(ai, to: .left, index: 0)
    #expect(s.left == w(.workspaces, .hidden) + [ai, system])   // entrambe ai widget: resta l'ordine della lista
    let t = Settings(defaults: d)
    #expect(!t.besideNotch(ai) && !t.besideNotch(system))   // il notch sta nella scheda della mascotte
}

// Colori della mascotte viva (spec mascotte viva §4) dalle versioni del 7/10 (2 bianca → corpo bianco e occhi neri, 3 nera
// → corpo nero e occhi bianchi), per colore e non tutto o niente; un numero strano salvato resta un colore.
@Test func mascotColorsComeFromTheOldVersions() {
    let (o, oname) = fresh(); defer { o.removePersistentDomain(forName: oname) }
    o.set(3, forKey: "siigil.catMascot"); o.set(2, forKey: "siigil.dogMascot"); o.set(-5, forKey: "siigil.dogEyeColor")
    let cat = legacyColors(o, "cat", version: "catMascot", body: 0xF5F7FC), dog = legacyColors(o, "dog", version: "dogMascot", body: 0x739EFA)
    #expect(cat.body == 0x14141A && cat.eyes == 0xF5F7FC && dog.body == 0xF5F7FC)
    #expect(dog.eyes >= 0 && dog.eyes <= 0xFFFFFF)
    let (p, pname) = fresh(); defer { p.removePersistentDomain(forName: pname) }
    p.set(3, forKey: "siigil.catMascot"); p.set(0xE8483F, forKey: "siigil.catBodyColor")
    let red = legacyColors(p, "cat", version: "catMascot", body: 0xF5F7FC)
    #expect(red.body == 0xE8483F && red.eyes == 0xF5F7FC)
    #expect(mascotSwatches.count == 12 && mascotSwatches.contains(0xF5F7FC) && mascotSwatches.contains(0x739EFA))
    #expect(mascotSwatchNames.count == mascotSwatches.count)   // un nome per colore, per VoiceOver
}

// Una mascotte nuova va a destra, dopo le altre mascotte e prima dei widget (spec §9, punto 9), in fondo all'elenco.
@Test func aNewMascotGoesRightAfterTheOtherMascots() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    let id = s.addMascot(.system(kinds: [.memory]))
    #expect(s.mascots.last?.id == id && s.mascots.count == 3)
    #expect(s.right == [ai, system, .mascot(id)] + w(.focus, .wifi, .volume, .battery, .clock))
    #expect(Settings(defaults: d).right == s.right)
}

// Spenta esce dalla barra e resta nell'elenco con le sue impostazioni; riaccesa torna a destra, dopo le altre mascotte.
@Test func aMascotSwitchedOffStaysInTheList() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    s.move(system, to: .left, index: 0)
    s.setMascot(s.mascots[1].id, on: false)
    #expect(!s.isOn(system) && s.mascots.count == 2 && !s.systemMonitorOn)
    s.setMascot(s.mascots[1].id, on: true)
    #expect(s.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock) && s.systemMonitorOn)
}

// Review Focus: una mascotte eliminata mentre la si trascinava non torna col rilascio, né col suo vecchio posto.
@Test func aDeletedMascotNeverComesBack() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s), id = s.mascots[1].id
    s.deleteMascot(id)
    #expect(s.mascots.map(\.id) == [s.mascots[0].id] && !s.isOn(system))
    s.move(system, to: .right, index: 0)   // il rilascio del trascinamento partito prima
    s.setBesideNotch(system, true)
    #expect(!s.isOn(system) && !s.besideNotch(system) && s.right.first == ai)
    let again = Settings(defaults: d)   // riaperta: non c'è nell'elenco né nella barra
    #expect(again.mascots.count == 1 && !again.isOn(system) && !(again.left + again.right).contains(system))
}

// Con le mascotte salvate ma senza le liste della barra (cancellate a mano): la barra di partenza, tutte le mascotte accese
// a destra prima dei widget.
@Test func withoutSavedBarListsTheBarStartsFromTheDefaults() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), (ai, system) = pair(s)
    s.move(ai, to: .left, index: 0)   // un posto diverso da quello di partenza
    d.removeObject(forKey: "siigil.bar.left"); d.removeObject(forKey: "siigil.bar.right")
    let t = Settings(defaults: d)
    #expect(t.left == w(.workspaces, .hidden) && t.right == [ai, system] + w(.focus, .wifi, .volume, .battery, .clock))
}

// Review Focus: le chiavi di prima non si scrivono mai, qualunque cosa si cambi (la 0.31 riaperta ritrova la sua barra).
@Test func oldKeysAreNeverWritten() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    d.set(["cat", "clock"], forKey: "siigil.right")
    let s = Settings(defaults: d), (ai, _) = pair(s)
    s.move(ai, to: .left, index: 0); s.set(.wifi, on: true); s.setBesideNotch(ai, false)
    s.deleteMascot(s.mascots[1].id); s.addMascot(.ai(agents: [.codex])); s.mascots[0].body = 0xE8483F
    #expect(d.stringArray(forKey: "siigil.right") == ["cat", "clock"] && d.object(forKey: "siigil.left") == nil)
    for key in ["catBesideNotch", "dogBesideNotch", "catBackground", "dogBackground", "catBodyColor", "catEyeColor",
                "dogBodyColor", "dogEyeColor", "captions", "dogCaptions", "renewedBadge", "meow", "meowVolume", "bark",
                "barkVolume", "quotaEnabled", "codexQuotaEnabled"] {
        #expect(d.object(forKey: "siigil.\(key)") == nil, "\(key)")
    }
}

// Siigil riaperto mentre gira (spec sezione Mascotte §10: nascoste tutte, si riaccendono da Impostazioni › Mascotte): senza
// mascotte nella barra le impostazioni si aprono sulla pagina Mascotte; con almeno una, come sempre.
@Test func reopeningSiigilShowsTheMascotsWhenNoneIsInTheBar() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    #expect(reopenPlace(s) == nil)
    s.setMascot(s.mascots[0].id, on: false)
    #expect(reopenPlace(s) == nil)   // ne resta una
    s.setMascot(s.mascots[1].id, on: false)
    #expect(reopenPlace(s) == SettingsPlace(page: .mascots))
    for m in s.mascots { s.deleteMascot(m.id) }
    #expect(reopenPlace(s) == SettingsPlace(page: .mascots))   // anche senza mascotte: lì c'è il +
}

// Chi suona con un doppione (dati delle build di prova: il + e la pagina non lo creano più): la mascotte più vecchia, anche
// se la più nuova sta più a sinistra nella barra (ordine di aggiunta, whoSounds).
@Test func withADuplicateTheOlderMascotSounds() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    s.deleteMascot(s.mascots[0].id)   // il Monitor AI di chi aggiorna: qui contano solo le due nuove
    let older = s.addMascot(.ai(agents: [.claude])), newer = s.addMascot(.ai(agents: [.claude]))
    s.move(.mascot(newer), to: .left, index: 0)
    #expect(s.whoSounds { $0.function.agents.contains(.claude) }?.id == older)
}
