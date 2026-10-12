import AppKit
import SwiftUI

// La finestra delle impostazioni è aperta. La finestra non viene mai distrutta e le cose animate (oggi l'anteprima viva
// della mascotte; allora i riquadri delle mascotte in pixel art) continuavano a ridisegnarsi da chiusa (misurato il 27/9:
// NSHostingView.layout ogni 0,3 s): si fermano con questa.
@Observable final class SettingsShown {
    static let shared = SettingsShown()
    var open = false
    // La pagina Account AI è quella della finestra. Da solo non basta: con la finestra chiusa la pagina non sparisce
    // (onDisappear non arriva) e resta vero; conta accountsVisible.
    var accountsShown = false
    var accountsVisible: Bool { open && accountsShown }   // si vede davvero: si aggiornano tutti e due gli account (Poller)
    var goTo: SettingsPlace?    // dove aprire la finestra (il menu di una mascotte: la sua pagina); lo consuma SettingsRoot
}

// Finestra impostazioni: una sola, mai distrutta (chiudere = nascondere), con la barra laterale come Impostazioni di
// Sistema (autore, 27/9: dopo sidebar e tab; le linee guida Apple per le app indicano i pannelli in toolbar, l'autore ha
// scelto la barra laterale costruita secondo le loro regole per barre laterali e split view).
// Siigil è LSUIElement: senza NSApp.activate la finestra non riceve i tasti. Posizione ricordata (autosave).
// La voce Impostazioni… dei menu delle mascotte e del menu dell'app: una sola (autore, 27/9); dal menu di una mascotte apre
// la sua pagina (spec sezione Mascotte §9, punto 2). L'azione si chiama openSettings apposta: macOS 26 dà da solo l'icona
// di sistema delle impostazioni alle voci con quell'azione (provato il 27/9 con una sonda: con openSettingsItem la voce
// restava senza).
final class SettingsMenuItem: NSMenuItem {
    private let place: SettingsPlace?

    init(key: String = "", mascot: UUID? = nil) {   // "," nel menu dell'app (⌘,, HIG "Settings")
        place = mascot.map { SettingsPlace(page: .mascots, mascot: $0) }
        super.init(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: key)
        target = self
    }
    required init(coder: NSCoder) { fatalError("init(coder:) non usato") }

    // Dopo la chiusura del menu, non dentro l'azione: aperta mentre NSMenu fa ancora il tracking la finestra s'impagina
    // male (vedi anche SettingsWindow.open, il vero motivo per cui restava dietro).
    @objc private func openSettings() {
        let place = place
        DispatchQueue.main.async { SettingsShown.shared.goTo = place; SettingsWindow.shared.open() }
    }
}

// Siigil riaperto mentre gira (Finder, Spotlight, Dock): le impostazioni, la porta che non dipende dalle mascotte (nascoste
// tutte, non resta un menu da cui aprirle; spec sezione Mascotte §10: si riaccendono da Impostazioni › Mascotte). Senza
// mascotte nella barra si apre sulla pagina Mascotte, se no come Impostazioni… del menu dell'app.
func reopenPlace(_ s: Settings) -> SettingsPlace? {
    s.mascots.contains { s.isOn(.mascot($0.id)) } ? nil : SettingsPlace(page: .mascots)
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard demo == nil else { return false }   // in demo niente Impostazioni: scriverebbero in quelle vere (Demo.swift)
        SettingsShown.shared.goTo = reopenPlace(.shared)
        SettingsWindow.shared.open()
        return false   // fatto qui: niente altro da riaprire
    }
}

final class SettingsWindow: NSWindow, NSWindowDelegate {
    static let shared = SettingsWindow()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: size.width, height: size.height),
                   styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)   // riduci acceso come Impostazioni di Sistema (screenshot dell'autore, 27/9); ingrandisci spento: la misura è fissa
        // Misura fissa: una finestra ridimensionabile AeroSpace la affianca alle altre, così invece la lascia fluttuare.
        isReleasedWhenClosed = false
        delegate = self
        // Come Impostazioni di Sistema: barra laterale a tutta altezza coi semafori dentro, toolbar unificata col titolo della
        // pagina e l'indietro delle schermate. Aspetto chiaro/scuro del Mac. La toolbar e il titolo li porta SwiftUI
        // (NSHostingController come contentViewController: sceneBridgingOptions .all).
        toolbarStyle = .unified
        contentViewController = NSHostingController(rootView: SettingsRoot())
        if !setFrameUsingName("Settings") { center() }
        setContentSize(size)   // l'autosave ricorda anche la misura: la posizione sì, la misura no
        setFrameAutosaveName("Settings")
    }

    // Barra laterale 220 + pagina 680: la riga dei sei stili di Aspetto (~580 pt) ci sta coi margini del form.
    private let size = NSSize(width: 900, height: 640)

    // Con la finestra aperta l'app è .regular: questo menu SI vede (mouse in alto), e AppKit usa il primo item
    // come menu dell'app (dalla posizione, non dal titolo). Il primo item è quindi il menu di Siigil; gli altri
    // instradano i tasti standard (⌘C/⌘V/⌘X/⌘A/⌘Z, ⌘W) nella finestra impostazioni attraverso la responder chain
    // (target nil, come il menu dell'app).
    static func makeMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let app = NSMenu(title: "Siigil")
        app.addItem(NSMenuItem(title: String(localized: "About Siigil"), action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        app.addItem(.separator())
        app.addItem(SettingsMenuItem(key: ","))   // HIG "Settings": la voce nel menu dell'app, con ⌘,
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: String(localized: "Hide Siigil"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: String(localized: "Quit Siigil"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = app
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(NSMenuItem(title: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: String(localized: "Window"))
        win.addItem(NSMenuItem(title: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        winItem.submenu = win
        return main
    }

    func open() {
        SettingsShown.shared.open = true
        Activation.opened(self)
    }

    func windowWillClose(_ notification: Notification) {
        SettingsShown.shared.open = false
        Activation.closed(self)
    }
}

// Siigil è accessory (niente Dock, niente ⌘-Tab): da lì NSApp.activate() non basta quando la chiamata parte da un
// NSMenu, alla chiusura del tracking AppKit rimette avanti l'app di prima (verificato il 2026-09-21 con System Events).
// Diventare un'app normale mentre una nostra finestra è aperta risolve; con due finestre (impostazioni e Benvenuto)
// si torna accessory solo quando si chiude l'ultima. Il menu dell'app (i ⌘-tasti, vedi makeMenu) si imposta quando si
// apre una finestra: prima non serve a nessuno.
enum Activation {
    private static var open: Set<ObjectIdentifier> = []

    static func opened(_ window: NSWindow) {
        NSApp.mainMenu = SettingsWindow.makeMenu()
        open.insert(ObjectIdentifier(window))
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func closed(_ window: NSWindow) {
        open.remove(ObjectIdentifier(window))
        if open.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}
