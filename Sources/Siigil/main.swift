import AppKit
import ServiceManagement

// --demo con una scena che non c'è: niente Siigil normale al suo posto (impostazioni vere, AeroSpace, primo avvio).
if CommandLine.arguments.contains("--demo"), demo == nil {
    print("uso: Siigil --demo workspaces|mascots|widgets")
    exit(2)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()   // riaprire Siigil apre le impostazioni (reopenPlace); NSApp tiene il delegate debole
app.delegate = appDelegate

// Il primo avvio della copia installata (in una cartella Applications, non la build di sviluppo), ogni voce una volta
// sola e mai contro una scelta già fatta dall'utente: avvio al login (registrazione idempotente; mai se ha già scelto
// dalle Impostazioni, anche "spento"); barra dei menu di macOS nascosta (la barra di Siigil prende il suo posto; chi la
// rimette non viene contraddetto); snap delle finestre spento (con AeroSpace si pestano i piedi). Le chiavi "fatto una
// volta" si scrivono sempre, e il loro valore dice se è stato davvero Siigil a cambiare qualcosa, non se era già così
// per conto suo (M8: il footer di Impostazioni › Generale si fida di questo valore).
if demo == nil, inApplications(Bundle.main.bundlePath) {   // mai in demo (Demo.swift)
    let defaults = UserDefaults.standard, settings = Settings.shared
    if defaults.object(forKey: "siigil.launchAtLogin") == nil { try? SMAppService.mainApp.register() }
    if defaults.object(forKey: "siigil.didHideMenuBar") == nil {
        defaults.set(!settings.menuBarHidden, forKey: "siigil.didHideMenuBar")
        settings.menuBarHidden = true
    }
    if defaults.object(forKey: "siigil.didDisableTiling") == nil {
        defaults.set(settings.edgeTiling, forKey: "siigil.didDisableTiling")
        settings.edgeTiling = false
    }
}

let state = BarState()
let poller = Poller(state: state)
let agents = AgentServer(state: state) { poller.tick() }

// Una barra per schermo. I pannelli non si chiudono mai: chiudere o nascondere un pannello più vecchio spegne
// la pressione del glass interattivo in quelli creati dopo (misurato su macOS 27.0, vedi ANALISI.md).
// Quando gli schermi cambiano si spostano; quello di uno schermo sparito è il più giovane e viene solo nascosto.
var panels: [BarPanel] = []
func showPanels() {
    let screens = NSScreen.screens
    for (i, screen) in screens.enumerated() {
        if i == panels.count { panels.append(BarPanel(screen: screen, state: state)) } else { panels[i].move(to: screen) }
        panels[i].orderFrontRegardless()
        if parkedMenuBar { panels[i].hideIfCovered() }   // un pannello nuovo o spostato nasce già giusto
    }
    panels[screens.count...].forEach { $0.orderOut(nil) }
}
// La notifica arriva a raffica (3-5 volte per dock/undock/risveglio): un solo rebuild dopo 0,3 s.
// Con la menu bar parcheggiata (27.2, BarPanel.swift): un battito guarda dov'è il mouse e scansa o rialza la barra.
// Niente monitor del mouse a eventi: visti all'opera, rendevano a scatti l'evidenziazione nei menu di Siigil
// (misurato l'1/10); il battito (barTick) ha il ritmo dei fotogrammi delle mascotte di una volta, in .common così batte
// anche a menu aperto.
if parkedMenuBar {
    let barTick: TimeInterval = 0.15
    let beat = Timer(timeInterval: barTick, repeats: true) { _ in
        for p in panels {
            p.dodge(mouse: NSEvent.mouseLocation)
            if p.alphaValue == 0 { p.hideIfCovered() }   // da nascosta: pronta a ricomparire appena la copertura va via
        }
    }
    beat.tolerance = barTick / 3
    RunLoop.main.add(beat, forMode: .common)
    // Entrare o uscire da uno spazio (anche a schermo intero) è il momento in cui una finestra può coprire lo
    // schermo; una seconda occhiata dopo l'assestamento, perché la lista delle finestre può arrivare in ritardo.
    NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { _ in
        for p in panels { p.hideIfCovered() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { for p in panels { p.hideIfCovered() } }
    }
}
var rebuild: DispatchWorkItem?
NotificationCenter.default.addObserver(
    forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
) { _ in
    debounce(&rebuild, after: 0.3, showPanels)
}

if let demo {
    // La modalità demo (Demo.swift): dati in memoria e un copione; niente giro della barra, agenti, permessi, Benvenuto.
    MainActor.assumeIsolated { Demo.start(demo) }
} else {
    MainActor.assumeIsolated { NowPlaying.start() }   // "In riproduzione": gli annunci di Spotify e Music (NowPlaying.swift)
    poller.start()
    // Benvenuto (spec 2026-09-25): al primo avvio della copia installata, e dopo un aggiornamento se un permesso è sparito
    // (dal disco immagine o da una copia tradotta si apre subito, non da qui: showSetupIfNeeded). Da un Timer, come
    // l'avviso di prima: tiene i 2 s di attesa a barra già visibile e gira fuori da un blocco GCD.
    // Il CLLocationManager nasce qui, non al controllo: appena creato dice "mai chiesta" finché macOS non risponde (meno di
    // 1 s), e il Benvenuto la contava come permesso perso a ogni avvio (misurato il 2026-09-26).
    _ = locationManager
    Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { _ in showSetupIfNeeded() }
    ejectInstallerDiskImage()   // dopo "Move to Applications": il DMG dell'installazione non resta montato
    agents.start()
}
showPanels()
app.run()
