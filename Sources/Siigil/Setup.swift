import AppKit
import Foundation
import SwiftUI

// La finestra Benvenuto (spec 2026-09-25-siigil-benvenuto-design.md): lista di controllo al primo avvio, riaperta una
// volta quando un aggiornamento azzera un permesso. Qui le regole pure; il modello, le azioni e la finestra seguono.

// La fotografia (Settings.setupSnapshot) contiene solo le voci che un aggiornamento può rompere, chiave → a posto.
// `regressed`: qualcosa era a posto e ora non lo è. Chiavi nuove o sparite (widget acceso o spento) non contano.
func regressed(previous: [String: Bool], now: [String: Bool]) -> Bool {
    previous.contains { key, wasOK in wasOK && now[key] == false }
}

// Stesso criterio di main.swift per "copia installata": sotto una cartella Applications, di sistema o dell'utente.
func inApplications(_ bundlePath: String) -> Bool { bundlePath.contains("/Applications/") }

// Vero se il bundle gira dal disco immagine del DMG (montato sotto /Volumes) o da una copia tradotta da Gatekeeper
// (Scaricati, prima della quarantena): il Benvenuto deve apparire anche lì, non solo dalla copia installata.
func launchedFromDiskImage(_ bundlePath: String) -> Bool {
    bundlePath.hasPrefix("/Volumes/") || bundlePath.contains("/AppTranslocation/")
}

// Dove spostare l'app: /Applications se scrivibile (utente amministratore), altrimenti ~/Applications.
func applicationsDestination(applicationsWritable: Bool, home: URL) -> URL {
    (applicationsWritable ? URL(fileURLWithPath: "/Applications") : home.appendingPathComponent("Applications"))
        .appendingPathComponent("Siigil.app")
}

// La fotografia: permessi TCC dei widget accesi (chiavi "fda", "location") e ogni integrazione che esiste (chiave = id,
// a posto = installata). Scorciatoia DND e AeroSpace non ci sono: non riaprono la finestra.
func snapshot(missing: Set<Missing>, hooks: [String: IntegrationStatus], focusOn: Bool, wifiOn: Bool) -> [String: Bool] {
    var s = hooks.filter { !$0.value.isMissing }.mapValues { $0 == .installed }
    if focusOn { s["fda"] = !missing.contains(.fullDiskAccess) }
    if wifiOn { s["location"] = !missing.contains(.location) }
    return s
}

// MARK: AeroSpace

let aerospaceBundle = "bobko.aerospace"
func aerospaceInstalled() -> Bool { NSWorkspace.shared.urlForApplication(withBundleIdentifier: aerospaceBundle) != nil }
func aerospaceRunning() -> Bool { !runningApps(bundle: aerospaceBundle).isEmpty }
let homebrewPath = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"].first { FileManager.default.isExecutableFile(atPath: $0) }
let aerospaceGuideURL = "https://nikitabobko.github.io/AeroSpace/guide#installation"

// Con Homebrew: il Terminale con il cask già in esecuzione (come per Codex). Senza: la guida di AeroSpace.
func installAerospaceInTerminal() {
    guard let brew = homebrewPath else { open(aerospaceGuideURL); return }
    openTerminal(script: "printf '\\nInstalling AeroSpace with Homebrew.\\n\\n'\n'\(brew)' install --cask nikitabobko/tap/aerospace\nprintf '\\nDone. Open AeroSpace from Applications, then come back to Siigil.\\n'\n", name: "aerospace")
}

// MARK: Spostamento in Applicazioni

// Questa copia gira dal DMG o da Scaricati: la copia in una cartella Applications, le toglie la quarantena (l'utente ha
// già approvato quest'app una volta: non deve rifarlo per la copia), la lancia come istanza nuova (`open -n`: con lo
// stesso bundle id in esecuzione, `open` da solo attiverebbe questa) ed esce. La copia nuova espelle il DMG all'avvio.
func moveToApplications() throws {
    let fm = FileManager.default
    let dest = applicationsDestination(applicationsWritable: fm.isWritableFile(atPath: "/Applications"), home: fm.homeDirectoryForCurrentUser)
    try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
    // ponytail: se la copia sotto fallisce, la copia vecchia è già sparita (l'errore comunque si vede in rosso);
    // copiare con un nome temporaneo e sostituire con `replaceItemAt` se capita davvero.
    if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }   // una copia vecchia: sostituita
    try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
    _ = shell("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
    open("-n", dest.path, "--args", "--eject-installer")   // solo la copia nata da uno spostamento espelle il DMG
    NSApp.terminate(nil)
}

// La copia installata, all'avvio: se è nata da "Move to Applications" (passato `--eject-installer`, §5) e il DMG
// dell'installazione è ancora montato, lo espelle qualche secondo dopo, quando la vecchia copia è uscita. Senza quel
// flag non tocca il DMG: altrimenti ogni avvio della copia installata lo espellerebbe, anche quando è già smontato o
// non c'entra niente con questo lancio. Fuori dal main, errori ignorati.
// ponytail: guarda solo /Volumes/Siigil, il nome del volume di make dmg.
func ejectInstallerDiskImage() {
    let volume = "/Volumes/Siigil"
    guard CommandLine.arguments.contains("--eject-installer"),
          inApplications(Bundle.main.bundlePath), FileManager.default.fileExists(atPath: volume + "/Siigil.app") else { return }
    DispatchQueue.global().asyncAfter(deadline: .now() + 5) { _ = shell("/usr/bin/hdiutil", ["detach", volume], timeout: 15) }
}

// MARK: Modello

// Lo stato delle voci del Benvenuto (spec §1). `refresh()`: i controlli veloci sul main (path, AeroSpace, Posizione),
// quelli bloccanti fuori (Assertions.json, `shortcuts list`, i JSON degli hook), risultato sul main; poi la fotografia.
@Observable final class SetupModel {
    static let shared = SetupModel()
    enum AerospaceState { case running, installedNotRunning, notInstalled }

    var isInApplications = true
    var aerospace = AerospaceState.running
    var missing: Set<Missing> = []
    var hooks: [String: IntegrationStatus] = [:]
    var moveError: String?   // l'errore dell'ultimo "Sposta in Applicazioni"
    var step = 0   // passo corrente della finestra: qui e non in WelcomeView, che viene ricreata a ogni apertura

    func refresh() {
        isInApplications = inApplications(Bundle.main.bundlePath)
        aerospace = aerospaceRunning() ? .running : aerospaceInstalled() ? .installedNotRunning : .notInstalled
        let noLocation = locationMissing()
        let s = Settings.shared
        DispatchQueue.global().async {
            let missing = readMissing(noLocation: noLocation)
            let hooks = Dictionary(uniqueKeysWithValues: integrations.map { ($0.id, $0.status()) })
            DispatchQueue.main.async {
                self.missing = missing
                self.hooks = hooks
                // Solo la copia installata scrive la fotografia: una build di sviluppo o la copia nel DMG condivide
                // lo stesso dominio defaults e non deve sovrascrivere quella della copia vera (§6 delle findings).
                if inApplications(Bundle.main.bundlePath) {
                    s.setupSnapshot = snapshot(missing: missing, hooks: hooks, focusOn: s.isOn(.focus), wifiOn: s.isOn(.wifi))
                }
            }
        }
    }
}

// Chiamata 2 s dopo l'avvio (main.swift). Dal disco immagine o da una copia tradotta, sotto: si apre subito. Dalla
// copia installata: al primo avvio sempre; poi solo se una voce della fotografia era a posto e ora non lo è. La
// fotografia si riscrive in ogni caso: una regressione apre la finestra una volta, non a ogni avvio. Le build di
// sviluppo non aprono mai niente da sole.
func showSetupIfNeeded() {
    let path = Bundle.main.bundlePath
    // Dal disco immagine o da una copia tradotta: si apre subito, senza leggere né scrivere la fotografia (quella
    // esiste solo per la copia installata, §6). Le build di sviluppo restano zitte, come sempre.
    if launchedFromDiskImage(path) { WelcomeWindow.shared.open(); return }
    guard inApplications(path) else { return }
    let s = Settings.shared
    let noLocation = locationMissing()
    let focusOn = s.isOn(.focus), wifiOn = s.isOn(.wifi)
    DispatchQueue.global().async {
        let missing = readMissing(noLocation: noLocation, shortcut: false)
        let hooks = Dictionary(uniqueKeysWithValues: integrations.map { ($0.id, $0.status()) })
        let now = snapshot(missing: missing, hooks: hooks, focusOn: focusOn, wifiOn: wifiOn)
        DispatchQueue.main.async {
            let open = !s.setupDone || regressed(previous: s.setupSnapshot, now: now)
            s.setupSnapshot = now
            if open { WelcomeWindow.shared.open() }
        }
    }
}

// MARK: Finestra

// Una sola, mai distrutta (chiudere = nascondere), nello stile scuro delle impostazioni, senza sidebar. Misura fissa:
// una finestra ridimensionabile AeroSpace la affianca alle altre, così la lascia fluttuare. Chiuderla segna setupDone.
final class WelcomeWindow: NSWindow, NSWindowDelegate {
    static let shared = WelcomeWindow()

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 520, height: 520),
                   styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        title = String(localized: "Welcome to Siigil")   // Mission Control; nella finestra non si vede
        isReleasedWhenClosed = false
        delegate = self
        appearance = NSAppearance(named: .darkAqua)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        contentView = NSHostingView(rootView: WelcomeView(model: SetupModel.shared) { [weak self] in self?.close() })
        if !setFrameUsingName("Welcome") { center() }
        setContentSize(NSSize(width: 520, height: 520))   // l'autosave ricorda anche la misura: la posizione sì, la misura no
        setFrameAutosaveName("Welcome")
    }

    func open() {
        SetupModel.shared.step = 0   // riapertura da Impostazioni › Generali: sempre dal passo 1, non da dove l'ha lasciata l'ultima
        SetupModel.shared.refresh()
        Activation.opened(self)
    }

    // La finestra torna in primo piano dopo un permesso concesso altrove: rilegge le voci (spec §3).
    func windowDidBecomeKey(_ notification: Notification) { SetupModel.shared.refresh() }

    func windowWillClose(_ notification: Notification) {
        // Solo la copia installata: chiudere la finestra nella copia del DMG non deve far sparire il primo avvio
        // della copia vera in Applicazioni.
        if inApplications(Bundle.main.bundlePath) { Settings.shared.setupDone = true }
        Activation.closed(self)
    }
}
