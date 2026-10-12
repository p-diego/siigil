import AppKit
import SwiftUI

// Azioni del menu contestuale sulle icone (porting di sketchybar/helpers/apps/apps.m):
// nessun permesso richiesto, `terminate` chiede la chiusura come cmd+q.
func showApp(_ app: AppEntry) {
    guard let a = NSRunningApplication(processIdentifier: app.pid) else { return }
    a.unhide()            // il focus da solo non mostra un'app nascosta
    // Solo gli id positivi sono finestre di AeroSpace: le voci ridotte (negative) e le nascoste (0) attivano l'app.
    if app.windowID > 0 { focusWindow(id: app.windowID); return }
    // Senza una finestra da mettere a fuoco (nascosta, minimizzata, chiusa): il "reopen" del Dock.
    // activate() da un'app mai attiva viene rifiutato da macOS 14+.
    if let url = a.bundleURL { open(url.path) }
}

// Va alla finestra di una sessione: dal clic su un Monitor AI e da Mostra finestra nel suo menu (spec sessioni §3). Se
// la sessione aspettava, l'attesa è vista e si toglie (waiting non scade da sola; se l'agente aspetta ancora davvero, il
// prossimo hook la rimette).
func showSession(_ s: AgentSession) {
    if let app = place(of: s.id, in: state.reports.flatMap(\.apps) + state.hidden) { showApp(app) }
    if s.state == .waiting { resetSessions([s.id]) }
}

// Toglie delle sessioni e rifà la barra: Reimposta l'agente sull'icona (le sue sessioni) e nel menu di una mascotte (una).
func resetSessions(_ ids: [String]) {
    state.sessions = state.sessions.filter { !ids.contains($0.key) }
    poller.tick()
}

// Vista in overlay che al tasto destro apre `menu()` ancorato in basso a sinistra, come un sottomenu
// (.contextMenu di SwiftUI si apre dove sta il mouse). Esiste solo per il tasto destro: agli altri
// click è trasparente, così il tap SwiftUI sotto arriva.
class RightClickMenuView: NSView {
    func menu() -> NSMenu { NSMenu() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        NSApp.currentEvent?.type == .rightMouseDown ? super.hitTest(point) : nil
    }
    // In demo nessun menu: il Wi-Fi e il Bluetooth leggerebbero reti e dispositivi veri già costruendolo (Demo.swift).
    override func rightMouseDown(with event: NSEvent) { if demo == nil { pop() } }
    func pop() { popUpFromBar(menu(), in: self) }
}

// Ogni tendina della barra si apre da qui. Chiara o scura come la barra (Aspetto), non come il Mac: con la barra su
// Chiaro e il Mac scuro le tendine restavano scure (autore, 4/10; i colori del tema no, solo l'aspetto). I sottomenu
// ereditano. y = -12: a -4 un menu da 4 voci collide con la zona della menu bar e macOS 27 lo fa scorrere (prima voce
// nascosta dietro la freccia) invece di spostarlo; a -12 il menu esce nello stesso punto di prima senza scroll.
// `refresh`: i menu che si aggiornano da aperti (Wi-Fi, Bluetooth) lo ricevono ogni secondo. popUp blocca finché il
// menu è aperto, quindi il timer vive esattamente quanto il menu; modo .common: gira anche durante il tracking.
@MainActor func popUpFromBar(_ menu: NSMenu, in view: NSView, refresh: (() -> Void)? = nil) {
    menu.appearance = NSAppearance(named: barIsDark() ? .darkAqua : .aqua)
    let timer = refresh.map { r in Timer(timeInterval: 1, repeats: true) { _ in r() } }
    if let timer { RunLoop.main.add(timer, forMode: .common) }
    menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -12), in: view)
    timer?.invalidate()
}

// Mostra / Nascondi / Chiudi sull'icona di un'app.
struct AppMenu: NSViewRepresentable {
    let app: AppEntry
    func makeNSView(context: Context) -> AppMenuView { AppMenuView(app: app) }
    func updateNSView(_ view: AppMenuView, context: Context) { view.app = app }
}

final class AppMenuView: RightClickMenuView {
    var app: AppEntry
    init(app: AppEntry) { self.app = app; super.init(frame: .zero) }
    required init?(coder: NSCoder) { nil }

    override func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(String(localized: "Show"), #selector(showIt), target: self))
        menu.addItem(NSMenuItem(String(localized: "Hide"), #selector(hideIt), target: self))
        menu.addItem(NSMenuItem(String(localized: "Quit"), #selector(quitIt), target: self))
        // Claude Code non manda nessun hook quando lo interrompi tu: l'anello resterebbe finché non scade.
        if app.agent != nil {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(String(localized: "Reset agent"), #selector(resetAgent), target: self))
        }
        return menu
    }

    @objc private func showIt() { showApp(app) }
    @objc private func hideIt() { NSRunningApplication(processIdentifier: app.pid)?.hide() }
    @objc private func quitIt() { NSRunningApplication(processIdentifier: app.pid)?.terminate() }

    // Le sessioni che questa icona mostra, non tutte quelle dell'app: con due finestre, azzerare quella bloccata
    // spegneva anche l'attesa dell'altra (27/9).
    @objc private func resetAgent() { resetSessions(app.sessionIDs) }
}
