import Foundation
import ServiceManagement

// Impostazioni (spec 2026-09-21-siigil-impostazioni-design.md). I widget e le mascotte della barra (BarItem) stanno in
// due liste, a sinistra e a destra del notch; uno assente da entrambe è spento.
enum WidgetID: String, CaseIterable {
    case workspaces, hidden, focus, wifi, bluetooth, nowPlaying, volume, battery, clock
    var defaultSide: Side { self == .workspaces || self == .hidden ? .left : .right }
}

enum Side { case left, right }

// I colori pronti della mascotte viva (spec mascotte viva §4), gli stessi per corpo e occhi, 0xRRGGBB: bianco Mostro,
// nero, rosso, arancio, giallo, verde, turchese, blu Mirtillo, viola, rosa, grigio, crema.
let mascotSwatches = [0xF5F7FC, 0x14141A, 0xE8483F, 0xF08A24, 0xF0B429, 0x3ECF8E, 0x2FBFA0, 0x739EFA, 0x8B5CF6, 0xE152B0, 0xA3A3A3, 0xF1EFE9]
// I loro nomi, nello stesso ordine: li legge VoiceOver (chiavi di Localizable.strings; "Black" e "Grey" c'erano già).
let mascotSwatchNames = ["White", "Black", "Red", "Orange", "Yellow", "Green", "Teal", "Blue", "Purple", "Pink", "Grey", "Cream"]
let clockDefaultFormat = "EEE d MMM HH:mm"   // come l'orologio della menu bar

// Su UserDefaults con chiavi `siigil.<nome>`; i default sono il comportamento di prima delle impostazioni.
// Scritta solo sul main, come BarState. `init(defaults:)` per i test; l'app usa `shared`.
// Le mascotte stanno solo ai bordi dello spazio vuoto del loro lato: in mezzo ai widget il fumetto li coprirebbe. Ognuna
// è attaccata al notch o ai widget (`besideNotch`, deciso da `nearNotch` in Rearrange.swift quando la lasci). Le liste
// sono nell'ordine in cui si vedono: a sinistra i widget, le mascotte attaccate ai widget, quelle attaccate al notch; a
// destra al contrario. Vale per ogni spostamento (move), e quindi per il ⌘-trascina, le impostazioni e l'accensione.
func mascotsAtTheEdge(left: [BarItem], right: [BarItem], besideNotch: (BarItem) -> Bool) -> (left: [BarItem], right: [BarItem]) {
    func widgets(_ l: [BarItem]) -> [BarItem] { l.filter { !$0.isMascot } }
    func mascots(_ l: [BarItem], atNotch: Bool) -> [BarItem] { l.filter { $0.isMascot && besideNotch($0) == atNotch } }
    return (widgets(left) + mascots(left, atNotch: false) + mascots(left, atNotch: true),
            mascots(right, atNotch: true) + mascots(right, atNotch: false) + widgets(right))
}

// Un elemento spostato su un lato all'indice dato (riportato dentro la lista), con le mascotte poi ai bordi del vuoto. Lo
// usano Settings.move al rilascio e la barra per l'anteprima mentre trascini: lo stesso risultato.
func moved(_ item: BarItem, to side: Side, index: Int, left: [BarItem], right: [BarItem],
           besideNotch: (BarItem) -> Bool) -> (left: [BarItem], right: [BarItem]) {
    var l = left.filter { $0 != item }, r = right.filter { $0 != item }
    if side == .left { l.insert(item, at: min(max(index, 0), l.count)) } else { r.insert(item, at: min(max(index, 0), r.count)) }
    return mascotsAtTheEdge(left: l, right: r, besideNotch: besideNotch)
}

// Un numero salvato, riportato nei suoi limiti; assente o non numerico = il default.
func clamped(_ value: Double?, to range: ClosedRange<Double>, default fallback: Double) -> Double {
    guard let value else { return fallback }
    return min(max(value, range.lowerBound), range.upperBound)
}

@Observable final class Settings {
    static let shared = Settings(defaults: demo == nil ? .standard : demoDefaults())   // la demo ha le sue (Demo.swift)
    private let defaults: UserDefaults

    // Chiavi nuove (spec sezione Mascotte §7): la 0.31 riaperta dopo legge e scrive le sue, `siigil.left` e `.right`.
    var left: [BarItem] { didSet { defaults.set(left.map(\.token), forKey: "siigil.bar.left") } }
    var right: [BarItem] { didSet { defaults.set(right.map(\.token), forKey: "siigil.bar.right") } }
    var showFrontAppName: Bool { didSet { defaults.set(showFrontAppName, forKey: "siigil.showFrontAppName") } }
    var bigArtwork: Bool { didSet { defaults.set(bigArtwork, forKey: "siigil.bigArtwork") } }   // In riproduzione: copertina grande nel menu
    var mergedLeft: Bool { didSet { defaults.set(mergedLeft, forKey: "siigil.mergedLeft") } }     // spazi in un blocco unico
    var mergedRight: Bool { didSet { defaults.set(mergedRight, forKey: "siigil.mergedRight") } }  // widget di destra in un blocco unico
    // Aspetto (spec temi): stile della barra, chiaro/scuro, margini dai bordi e dal notch, raggio delle pillole (13 = capsula).
    var barStyle: BarStyle { didSet { defaults.set(barStyle.rawValue, forKey: "siigil.barStyle") } }
    var barAppearance: BarAppearance { didSet { defaults.set(barAppearance.rawValue, forKey: "siigil.barAppearance") } }
    var edgeMargin: Double { didSet { defaults.set(edgeMargin, forKey: "siigil.edgeMargin") } }
    var notchMargin: Double { didSet { defaults.set(notchMargin, forKey: "siigil.notchMargin") } }
    var cornerRadius: Double { didSet { defaults.set(cornerRadius, forKey: "siigil.cornerRadius") } }
    var themeGlass: Bool { didSet { defaults.set(themeGlass, forKey: "siigil.themeGlass") } }   // vetro sopra un tema (27/9)
    var transparentGlass: Bool { didSet { defaults.set(transparentGlass, forKey: "siigil.transparentGlass") } }   // vetro su Trasparente; spento resta il velo (27/9)
    var barFont: BarFont { didSet { defaults.set(barFont.rawValue, forKey: "siigil.barFont") } }   // orologio e spazi (27/9)
    var clockFormat: String { didSet { defaults.set(clockFormat, forKey: "siigil.clockFormat") } }
    var clockApp: String { didSet { defaults.set(clockApp, forKey: "siigil.clockApp") } }   // bundle id dell'app che il click sull'orologio attiva; vuoto = niente
    var quotaInterval: Int { didSet { defaults.set(quotaInterval, forKey: "siigil.quotaInterval") } }   // minuti
    var setupDone: Bool { didSet { defaults.set(setupDone, forKey: "siigil.setupDone") } }   // la finestra Benvenuto è stata chiusa almeno una volta (spec benvenuto §2)
    var setupSnapshot: [String: Bool] { didSet { defaults.set(setupSnapshot, forKey: "siigil.setupSnapshot") } }   // ultima fotografia delle voci che un aggiornamento può rompere (Setup.swift)
    // Le mascotte, in ordine di aggiunta (spec sezione Mascotte §7): l'ordine dell'elenco delle Impostazioni e del menu
    // "Mascotte" (autore, 11/10: «le righe devono stare sempre in ordine di aggiunta»). Chiave nuova: le chiavi di prima non
    // si scrivono più.
    var mascots: [Mascot] { didSet { if let data = try? JSONEncoder().encode(mascots) { defaults.set(data, forKey: "siigil.mascots") } } }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        // Chiave assente = il default.
        func bool(_ key: String, _ fallback: Bool) -> Bool { defaults.object(forKey: "siigil.\(key)") as? Bool ?? fallback }
        showFrontAppName = bool("showFrontAppName", true)
        bigArtwork = bool("bigArtwork", true)
        mergedLeft = bool("mergedLeft", false)
        mergedRight = bool("mergedRight", false)
        barStyle = BarStyle(rawValue: defaults.string(forKey: "siigil.barStyle") ?? "") ?? .glass
        barAppearance = BarAppearance(rawValue: defaults.string(forKey: "siigil.barAppearance") ?? "") ?? .automatic
        edgeMargin = clamped(defaults.object(forKey: "siigil.edgeMargin") as? Double, to: 0...24, default: 6)
        notchMargin = clamped(defaults.object(forKey: "siigil.notchMargin") as? Double, to: 0...40, default: 6)
        cornerRadius = clamped(defaults.object(forKey: "siigil.cornerRadius") as? Double, to: 0...13, default: 13)
        themeGlass = bool("themeGlass", false)
        transparentGlass = bool("transparentGlass", true)
        barFont = BarFont(rawValue: defaults.string(forKey: "siigil.barFont") ?? "") ?? .system
        clockFormat = defaults.string(forKey: "siigil.clockFormat") ?? clockDefaultFormat
        clockApp = defaults.string(forKey: "siigil.clockApp") ?? "com.apple.iCal"
        quotaInterval = defaults.object(forKey: "siigil.quotaInterval") as? Int ?? 5
        // Le mascotte salvate o, la prima volta, le due di prima con le liste della barra (legacyMascots). La migrazione si
        // salva solo se la chiave non c'è: un valore che qui non si legge (una versione futura con una voce nuova) non si
        // cancella all'avvio.
        let data = defaults.data(forKey: "siigil.mascots")
        let saved = data.flatMap { try? JSONDecoder().decode([Mascot].self, from: $0) }
        // Illeggibile: se ne tiene una copia, una volta sola, prima che un cambiamento qui lo sovrascriva.
        if let data, saved == nil, defaults.object(forKey: "siigil.mascots.unreadable") == nil { defaults.set(data, forKey: "siigil.mascots.unreadable") }
        let migration = saved == nil ? legacyMascots(defaults) : nil
        let all = saved ?? migration?.mascots ?? []
        mascots = all
        if let migration, defaults.object(forKey: "siigil.mascots") == nil {
            if let data = try? JSONEncoder().encode(migration.mascots) { defaults.set(data, forKey: "siigil.mascots") }
            defaults.set(migration.left.map(\.token), forKey: "siigil.bar.left")
            defaults.set(migration.right.map(\.token), forKey: "siigil.bar.right")
        }
        // Le liste della barra: quelle salvate; appena migrato quelle di prima (legacyMascots); senza niente quelle di
        // partenza, con tutte le mascotte accese. Una mascotte che non c'è più, o un id sconosciuto, si scarta; le mascotte
        // tornano ai bordi anche in una lista scritta a mano (mascotsAtTheEdge).
        let ids = Set(all.map(\.id)), atNotch = Set(all.filter(\.besideNotch).map(\.id))
        func list(_ side: String, _ fallback: [BarItem]) -> [BarItem] {
            let tokens = migration == nil ? defaults.stringArray(forKey: "siigil.bar.\(side)")?.compactMap(BarItem.init) : nil
            return (tokens ?? fallback).filter { if case .mascot(let id) = $0 { ids.contains(id) } else { true } }
        }
        let widgets: [WidgetID] = [.focus, .wifi, .volume, .battery, .clock]
        (left, right) = mascotsAtTheEdge(left: list("left", migration?.left ?? [.widget(.workspaces), .widget(.hidden)]),
                                         right: list("right", migration?.right ?? all.map { .mascot($0.id) } + widgets.map(BarItem.widget)),
                                         besideNotch: { if case .mascot(let id) = $0 { atNotch.contains(id) } else { false } })
        setupDone = bool("setupDone", false)
        setupSnapshot = defaults.dictionary(forKey: "siigil.setupSnapshot") as? [String: Bool] ?? [:]
        menuBarHidden = Self.readMenuBarHidden()
        edgeTiling = Self.readEdgeTiling()
    }

    func isOn(_ item: BarItem) -> Bool { left.contains(item) || right.contains(item) }
    func isOn(_ w: WidgetID) -> Bool { isOn(.widget(w)) }
    func mascot(_ id: UUID) -> Mascot? { mascots.first { $0.id == id } }

    // Un fatto, un suono (spec sezione Mascotte §5): suona la prima mascotte, in ordine di aggiunta, accesa, con gli
    // effetti sonori, che vede il fatto; le altre reagiscono solo a vista. La chiamano AgentServer e Poller, una volta per
    // fatto: mai le viste, che sono una per schermo.
    func whoSounds(_ sees: (Mascot) -> Bool) -> Mascot? { mascots.first { $0.sounds && isOn(.mascot($0.id)) && sees($0) } }

    // Se una mascotte è attaccata al notch (i widget: mai).
    func besideNotch(_ item: BarItem) -> Bool { if case .mascot(let id) = item { mascot(id)?.besideNotch ?? false } else { false } }
    func setBesideNotch(_ item: BarItem, _ on: Bool) {
        if case .mascot(let id) = item, let i = mascots.firstIndex(where: { $0.id == id }) { mascots[i].besideNotch = on }
    }

    // Il Watchdog lavora solo se almeno un Monitor di sistema è nella barra (Poller).
    var systemMonitorOn: Bool { mascots.contains { !$0.function.isAI && isOn(.mascot($0.id)) } }

    // Reset style (pagina Aspetto): l'aspetto com'era al primo avvio.
    func resetAppearance() {
        barStyle = .glass; barAppearance = .automatic; themeGlass = false; transparentGlass = true
        edgeMargin = 6; notchMargin = 6; cornerRadius = 13; barFont = .system
        mergedLeft = false; mergedRight = false
    }

    // Un widget spento = tolto da entrambe le liste; acceso = nell'ordine canonico dei WidgetID sul lato di default.
    func set(_ w: WidgetID, on: Bool) {
        let item = BarItem.widget(w)
        guard on else { return off(item) }
        guard !isOn(item) else { return }
        let order = WidgetID.allCases
        let list = w.defaultSide == .left ? left : right
        let index = list.firstIndex { if case .widget(let x) = $0 { order.firstIndex(of: x)! > order.firstIndex(of: w)! } else { false } }
        move(item, to: w.defaultSide, index: index ?? list.count)
    }

    // Una mascotte accesa va a destra, dopo le altre mascotte e prima dei widget (spec sezione Mascotte §4 e §9, punto 9);
    // spenta esce dalla barra e resta nell'elenco con tutte le sue impostazioni.
    func setMascot(_ id: UUID, on: Bool) {
        let item = BarItem.mascot(id)
        guard on else { return off(item) }
        if !isOn(item) { move(item, to: .right, index: right.firstIndex { !$0.isMascot } ?? right.count) }
    }

    // Una mascotte nuova (il + di Impostazioni › Mascotte): aspetto a caso (newMascot), in fondo all'elenco, accesa.
    @discardableResult func addMascot(_ function: MascotFunction) -> UUID {
        let m = newMascot(function, existing: mascots)
        mascots.append(m)
        setMascot(m.id, on: true)
        return m.id
    }

    // Elimina una mascotte: esce dalla barra e dall'elenco, con le sue impostazioni.
    func deleteMascot(_ id: UUID) {
        off(.mascot(id))
        mascots.removeAll { $0.id == id }
    }

    private func off(_ item: BarItem) { left.removeAll { $0 == item }; right.removeAll { $0 == item } }

    // Riordino o cambio lato (⌘-trascina); l'indice viene riportato dentro la lista. Una mascotte eliminata nel frattempo
    // (il rilascio di un trascinamento partito prima) non torna.
    func move(_ item: BarItem, to side: Side, index: Int) {
        if case .mascot(let id) = item, mascot(id) == nil { return }
        (left, right) = moved(item, to: side, index: index, left: left, right: right, besideNotch: besideNotch)
    }

    // Avvio al login: lo stato vero è SMAppService, non UserDefaults; ma la scelta dell'utente va comunque su
    // defaults (`siigil.launchAtLogin`), perché main.swift la legge per non registrare di nuovo chi l'ha spenta.
    // `launchAtLogin` rispecchia lo stato di sistema dopo ogni tentativo e quando la pagina Generale si vede (Watching).
    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    private(set) var launchAtLoginError: String?

    // Barra dei menu di macOS (Impostazioni di Sistema › Barra dei menu › "Nascondi automaticamente"): chiave
    // `_HIHideMenuBar` nel dominio globale, non siigil.*. Si scrive solo quella chiave con CFPreferencesSetValue,
    // non l'intero dominio (persistentDomain/setPersistentDomain rimpiazzerebbe tutte le preferenze globali
    // dell'utente). La notifica distribuita la applica subito (misurato il 2026-09-21: nessun logout, nessun
    // permesso). Stored, così SwiftUI vede il cambio; refreshMenuBar() rilegge il dominio se l'utente l'ha
    // cambiata da Impostazioni di Sistema.
    var menuBarHidden: Bool {
        didSet {
            guard menuBarHidden != Self.readMenuBarHidden() else { return }
            CFPreferencesSetValue("_HIHideMenuBar" as CFString, NSNumber(value: menuBarHidden),
                                   kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
            DistributedNotificationCenter.default().post(name: Notification.Name("AppleInterfaceMenuBarHidingChangedNotification"), object: nil)
        }
    }
    func refreshMenuBar() { menuBarHidden = Self.readMenuBarHidden() }
    private static func readMenuBarHidden() -> Bool {
        (UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["_HIHideMenuBar"] as? NSNumber)?.boolValue ?? false
    }
    // Siigil l'ha nascosta da sé alla prima esecuzione installata (main.swift): la pagina Generale lo dice.
    var didHideMenuBar: Bool { defaults.bool(forKey: "siigil.didHideMenuBar") }

    // Snap delle finestre di macOS (Impostazioni di Sistema › Scrivania e Dock › Finestre): trascinare ai bordi,
    // trascinare verso l'alto per riempire lo schermo, ⌥ mentre si trascina. Tre chiavi di com.apple.WindowManager,
    // scritte insieme e applicate subito (provato il 2026-09-23); acceso se anche una sola è assente (nil = acceso)
    // o vera, spento solo se tutte e tre sono esplicitamente false — altrimenti chi ne aveva spenta solo una
    // vedrebbe il toggle già "spento" e il primo avvio non scriverebbe le altre due. Con AeroSpace l'aggancio di
    // macOS litiga con le sue tessere: Siigil lo spegne al primo avvio installato (main.swift).
    private static let edgeTilingKeys = ["EnableTilingByEdgeDrag", "EnableTopTilingByEdgeDrag", "EnableTilingOptionAccelerator"]
    var edgeTiling: Bool {
        didSet {
            guard edgeTiling != Self.readEdgeTiling() else { return }
            for key in Self.edgeTilingKeys {
                CFPreferencesSetValue(key as CFString, NSNumber(value: edgeTiling), "com.apple.WindowManager" as CFString,
                                      kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
            }
            CFPreferencesAppSynchronize("com.apple.WindowManager" as CFString)
        }
    }
    func refreshEdgeTiling() { edgeTiling = Self.readEdgeTiling() }
    private static func readEdgeTiling() -> Bool {
        edgeTilingKeys.contains { key in
            (CFPreferencesCopyValue(key as CFString, "com.apple.WindowManager" as CFString,
                                    kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? NSNumber)?.boolValue ?? true
        }
    }
    // Siigil l'ha spento da sé alla prima esecuzione installata: la pagina Generale lo dice.
    var didDisableTiling: Bool { defaults.bool(forKey: "siigil.didDisableTiling") }

    func setLaunchAtLogin(_ on: Bool) {
        defaults.set(on, forKey: "siigil.launchAtLogin")   // scritta comunque: la scelta è dell'utente anche se SMAppService fallisce
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLaunchAtLogin()
        } catch {
            // refresh prima: se register()/unregister() fallisce ma lo stato risulta lo stesso .enabled di prima
            // (es. unregister fallito), refresh lo pulirebbe da solo; l'errore vero, scritto dopo, vince sempre.
            refreshLaunchAtLogin()
            launchAtLoginError = error.localizedDescription
        }
    }

    // Rilegge lo stato di sistema: può cambiare da Impostazioni di Sistema senza passare da qui (es. l'utente
    // approva dopo un .requiresApproval). Pulisce l'errore solo quando torna .enabled: altrimenti un errore
    // vero (register/unregister fallito) resterebbe visibile finché lo stato non si sistema davvero.
    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        if status == .requiresApproval {
            launchAtLoginError = String(localized: "Approval required in System Settings › Login Items")
        } else if status == .enabled {
            launchAtLoginError = nil
        }
    }
}
