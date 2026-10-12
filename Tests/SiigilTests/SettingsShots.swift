import AppKit
import SwiftUI
import Testing
@testable import Siigil

// Le pagine della sezione Mascotte in PNG, chiare e scure, solo a richiesta: per mostrarle all'autore senza aprire
// finestre sullo schermo (la finestra non va mai davanti; disegna AppKit, controlli compresi). Su una suite di
// UserDefaults a parte: le impostazioni vere non si toccano.
//   SETTINGS_SHOTS=<cartella> swift test --filter settingsShots
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["SETTINGS_SHOTS"] != nil))
func settingsShots() throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SETTINGS_SHOTS"]!)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    // Una cosa guardata, una mascotte: le due di chi aggiorna, una con Claude e una con CPU e memoria, poi Codex (nascosta)
    // e il calore. Nelle pagine delle due la casella dell'altra cosa è grigia, "Già di un'altra mascotte".
    let s = Settings(defaults: d)
    s.mascots[0].function = .ai(agents: [.claude])
    s.mascots[1].function = .system(kinds: [.cpu, .memory])
    let codex = s.addMascot(.ai(agents: [.codex]))
    s.addMascot(.system(kinds: [.heat]))
    s.setMascot(codex, on: false)
    let empty = Settings(defaults: d)
    empty.mascots = []
    let pages: [(String, AnyView)] = [
        ("mascots", AnyView(Form { MascotsPage(open: { _ in }, settings: s) }.formStyle(.grouped))),
        ("mascots-empty", AnyView(Form { MascotsPage(open: { _ in }, settings: empty) }.formStyle(.grouped))),
        ("mascot-ai", AnyView(MascotScreen(id: s.mascots[0].id, settings: s))),
        ("mascot-system", AnyView(MascotScreen(id: s.mascots[1].id, settings: s))),
    ]
    for (file, page) in pages {
        for dark in [false, true] { try shot(page, dark: dark, to: out.appendingPathComponent("\(file)-\(dark ? "dark" : "light").png")) }
    }
}

@MainActor private func shot(_ page: AnyView, dark: Bool, to url: URL) throws {
    _ = NSApplication.shared
    let frame = NSRect(x: 0, y: 0, width: 680, height: 1500)   // la pagina della finestra delle Impostazioni, tutta in altezza
    let host = NSHostingView(rootView: page.modifier(PageBackground()).environment(\.colorScheme, dark ? .dark : .light))
    host.frame = frame
    let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    window.contentView = host
    host.layoutSubtreeIfNeeded()
    let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
    host.cacheDisplay(in: host.bounds, to: rep)
    try #require(rep.representation(using: .png, properties: [:])).write(to: url)
}
