import AppKit
import Foundation

// Full immersione (spec 2026-09-22 §3). Nessuna API pubblica dice cosa è attivo: lo si legge dai file di
// ~/Library/DoNotDisturb/DB, come Stats, SaneBar, i plugin SketchyBar e Atoll. Formato fermo da macOS 12 a 27, non
// documentato: se cambia, le funzioni danno nil e il widget si nasconde. Serve l'Accesso completo al disco.

let dndMode = "com.apple.donotdisturb.mode.default"
let focusDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB")

private func firstDataItem(_ data: Data) -> [String: Any]? {
    ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap { ($0["data"] as? [[String: Any]])?.first }
}

// La modalità dell'ultima voce di Assertions.json. ponytail: con più modalità attive insieme vince l'ultima voce del
// file; ordinare per assertionStartDateTimestamp se capita di vedere quella sbagliata.
func activeFocusMode(assertions data: Data) -> String? {
    let records = firstDataItem(data)?["storeAssertionRecords"] as? [[String: Any]]
    return (records?.last?["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String
}

// Il simbolo SF della modalità, da ModeConfigurations.json.
func focusSymbol(configurations data: Data, mode: String) -> String? {
    let config = (firstDataItem(data)?["modeConfigurations"] as? [String: Any])?[mode] as? [String: Any]
    return (config?["mode"] as? [String: Any])?["symbolImageName"] as? String
}

// Le modalità personalizzate possono usare simboli privati: Image(systemName:) non disegnerebbe nulla.
func validSymbol(_ name: String) -> String {
    NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil ? name : "moon.fill"
}

// Assertions.json assente = nulla di attivo; illeggibile (senza permesso) = nil anche lui: lo distingue Impostazioni.
func readFocus() -> Focus? {
    guard let data = try? Data(contentsOf: focusDir.appendingPathComponent("Assertions.json")),
          let mode = activeFocusMode(assertions: data) else { return nil }
    let symbol = (try? Data(contentsOf: focusDir.appendingPathComponent("ModeConfigurations.json")))
        .flatMap { focusSymbol(configurations: $0, mode: mode) }
    return Focus(mode: mode, symbol: validSymbol(symbol ?? "moon.fill"))
}

// Senza Accesso completo al disco la cartella non si elenca (EPERM).
func focusReadable() -> Bool { (try? FileManager.default.contentsOfDirectory(atPath: focusDir.path)) != nil }

// Osserva la cartella: macOS riscrive i file in modo atomico, quindi cambia la cartella. Senza permesso non si apre:
// attach() non aggancia nulla e il Poller riprova al minuto, così dopo aver dato il permesso il widget si accende da solo.
final class FocusWatcher {
    private var source: DispatchSourceFileSystemObject?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) { self.onChange = onChange }

    func attach() {
        guard source == nil else { return }
        let fd = Darwin.open(focusDir.path, O_EVTONLY)   // Darwin.: System.swift ha un open(_:) per /usr/bin/open
        guard fd >= 0 else { return }
        let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        s.setEventHandler { [weak self] in self?.onChange() }
        s.setCancelHandler { close(fd) }
        s.resume()
        source = s
    }
}

// Accendere e spegnere Non disturbare da un'altra app è riservato ad Apple: lo fa una scorciatoia di Comandi rapidi
// (Imposta Full immersione › Non disturbare › Alterna), come Raycast e i plugin SketchyBar. Il nome è lo stesso in
// tutte le lingue.
let dndShortcut = "Siigil DND"

// Le tre scorciatoie (Non disturbare, Risparmio energetico, Bluetooth) girano tutte di qui. `shortcuts run` è
// bloccante (1-2 s): fuori dal main. Se fallisce perché la scorciatoia non c'è, la si propone da installare; se c'è ma
// fallisce lo stesso, beep. Alla fine `done(riuscita)` sul main (rilegge quello che è cambiato, o rimette com'era).
func runShortcut(_ name: String, then done: @escaping (_ ok: Bool) -> Void) {
    DispatchQueue.global().async {
        let ok = shell("/usr/bin/shortcuts", ["run", name], timeout: 15) != nil
        let missing = !ok && !shortcutNames().contains(name)
        DispatchQueue.main.async {
            if missing { installShortcut(name) } else if !ok { NSSound.beep() }
            done(ok)
        }
    }
}

// Dopo, si rilegge subito: l'osservatore della cartella lo farebbe comunque.
func toggleDND() { if demo == nil { runShortcut(dndShortcut) { if $0 { poller.refreshFocus() } } } }   // in demo niente scorciatoie

// La scorciatoia pronta sta nel bundle (Siigil DND esportata da Comandi rapidi; Siigil Low Power e Siigil Bluetooth
// create dall'autore, scaricate dal suo link iCloud e firmate con `shortcuts sign --mode anyone`, 4/10): aprirla
// mostra la richiesta "Aggiungi scorciatoia" di macOS. Se un giorno la firma non fosse più accettata, va rifirmata.
func installShortcut(_ name: String) {
    if let url = Bundle.main.url(forResource: name, withExtension: "shortcut") { open(url.path) }
}

// Risparmio energetico: come Non disturbare, lo alterna solo una scorciatoia (pmset vuole la password; la mia generata
// a mano non alternava nulla).
let lowPowerShortcut = "Siigil Low Power"

func toggleLowPower() { runShortcut(lowPowerShortcut) { if $0 { poller.refreshBattery() } } }

// Bluetooth acceso/spento (Imposta Bluetooth › Alterna): macOS lo dà alle app solo in lettura (Bluetooth.swift).
// Niente da rileggere dopo: il cambio lo annuncia CoreBluetooth.
let bluetoothShortcut = "Siigil Bluetooth"

// Le scorciatoie installate, in una lettura sola (`shortcuts list` costa ~1 s): bloccante, fuori dal main.
func shortcutNames() -> Set<String> {
    Set((shell("/usr/bin/shortcuts", ["list"]) ?? "").split(separator: "\n").map(String.init))
}
