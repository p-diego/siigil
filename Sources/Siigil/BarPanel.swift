import AppKit
import SwiftUI

// Aree a sinistra e a destra del notch dello schermo del pannello; nil = nessun notch.
@Observable final class PanelGeometry {
    var leftWidth: CGFloat?
    var rightWidth: CGFloat?
}

// Pannello senza cornice sopra la menu bar di uno schermo: non prende il focus, sta su tutti
// gli spazi, non si muove con Mission Control. Uno per schermo (main.swift).
// macOS 27.2: la barra dei menu è del nuovo MenuBarAgent e le sue finestre restano sulla fascia alta anche da
// nascoste, sopra di noi, mangiandosi mouse e click (un click diventa "mostra la barra nascosta"; stesso bug aperto in
// SketchyBar #852, misurato qui l'1/10). Da lì in poi la barra sta un gradino SOPRA di loro e si scansa quando chiami
// la barra di sistema col mouse a filo del bordo alto, così quella scorre sopra come prima dell'aggiornamento.
// ponytail: pezza a una beta, tutta dietro `parkedMenuBar`; se una 27.x rimette le finestre fuori strada, toglierla.
let parkedMenuBar = ProcessInfo.processInfo.isOperatingSystemAtLeast(.init(majorVersion: 27, minorVersion: 2, patchVersion: 0))

// Abbassata mentre la barra di sistema è visibile (sta scendendo o è giù: la sua sentinella sparisce) col mouse
// nella fascia (< 44 pt; da abbassata a qualunque distanza: tipico un suo menu aperto col mouse in fondo), oppure
// col mouse FERMO a filo del bordo (`dwelling`, ~0,3 s: la stessa sosta con cui il sistema decide di farla
// scendere) — così siamo già sotto quando lei parte, invece di vederla sbucare da dietro. Lo sfioro di passaggio
// non abbassa: abbassarsi al tocco regalava alla trappola il click dopo (review 3/10). Gli avvisi di tracking dei
// menu su 27.2 non arrivano più (misurato l'1/10). Fuori dallo schermo della barra: infinito, cioè su.
func dodgesMenuBar(distanceFromTop d: CGFloat, lowered: Bool, visible: Bool, dwelling: Bool) -> Bool {
    dwelling || visible && (lowered || d < 44) && d != .infinity
}

// Una finestra copre lo schermo (video o gioco a schermo intero): alta quasi quanto lui E parte dentro la striscia
// della barra — dentro, non sopra: una finestra alta di uno schermo impilato sopra ha top molto negativo e non è di
// questo schermo (review 3/10: spegneva la barra dello schermo sotto). Le finestre di AeroSpace partono sotto la
// barra (y 39, il suo margine alto) e non contano; il video a schermo intero parte sotto il notch (y 33-34).
// Coordinate dall'alto, riferite allo schermo della barra.
func coversTheScreen(top: CGFloat, height: CGFloat, screenHeight: CGFloat, barHeight: CGFloat) -> Bool {
    (0..<barHeight).contains(top) && height >= screenHeight - 44
}

final class BarPanel: NSPanel {
    static let height: CGFloat = 38
    // Sotto la menu bar nativa (24): quando scende in auto-hide resta usabile sopra di noi. Con la menu bar
    // parcheggiata (27.2) invece sopra le sue finestre (25), altrimenti i click non arrivano; a cedere il passo
    // quando serve ci pensa dodge(mouse:).
    static let belowMenuBar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) - 1)
    static let aboveParkedMenuBar = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.statusWindow)) + 1)

    // AppKit spinge le finestre sotto la menu bar fuori dalla sua area: qui no, la barra sta in cima.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    private let geometry = PanelGeometry()

    init(screen: NSScreen, state: BarState) {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = parkedMenuBar ? Self.aboveParkedMenuBar : Self.belowMenuBar
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        isOpaque = false
        // Con la menu bar parcheggiata, i pixel trasparenti lascerebbero passare i click alla sua trappola sotto di
        // noi (macOS fa click-through sotto ~5 % di alpha): un velo invisibile rende nostra tutta la striscia, e la
        // barra di sistema scende solo dal bordo alto, come su 27.0. 1/255: lo scalino minimo sopra lo zero, basta
        // a tenere i click (misurato il 3/10: la soglia del click-through è qualunque alpha sopra lo zero), invisibile.
        backgroundColor = parkedMenuBar ? NSColor.black.withAlphaComponent(1.0 / 255) : .clear
        hasShadow = false
        canHide = false   // ⌘H "Nascondi Siigil" non deve portarsi via la barra
        move(to: screen)
        contentView = NSHostingView(rootView: BarView(state: state, geometry: geometry))
    }

    // La barra di sistema è visibile sopra questo schermo? Da nascosta, MenuBarAgent parcheggia la sua sentinella
    // (livello 25) sulla fascia alta; quando la barra scende, la sentinella sparisce e resta la barra vera (livello
    // 24, Window Server). Si guarda solo quando è l'ago della bilancia (abbassata e mouse lontano), con una memoria
    // di 0,2 s: niente sondaggi continui.
    private var edgeBeats = 0   // da quanti battiti il mouse è fermo a filo del bordo (dodge)
    private var barVisibleMemo: (at: Date, visible: Bool) = (.distantPast, false)
    private func systemBarVisible() -> Bool {
        if Date().timeIntervalSince(barVisibleMemo.at) < 0.2 { return barVisibleMemo.visible }
        guard let windows = windowsOnOurScreen() else { return false }   // nessuno schermo (TV spenta): fermi
        let parked = windows.contains { w, b in
            w[kCGWindowLayer as String] as? Int == 25 && w[kCGWindowOwnerName as String] as? String == "MenuBarAgent"
                && abs(b.minY) < 2
        }
        barVisibleMemo = (Date(), !parked)
        return !parked
    }

    // Le finestre a schermo che stanno sul nostro schermo (in orizzontale), con la y dalla sua cima: in coordinate CG
    // (origine in alto a sinistra dello schermo principale) la cima è frame.maxY. nil = nessuno schermo.
    private func windowsOnOurScreen() -> [(info: [String: Any], bounds: CGRect)]? {
        guard let mainMaxY = NSScreen.screens.first?.frame.maxY else { return nil }
        let top = mainMaxY - frame.maxY
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { w in
            guard let d = w[kCGWindowBounds as String] as? NSDictionary, let b = CGRect(dictionaryRepresentation: d),
                  b.minX < frame.maxX, b.maxX > frame.minX else { return nil }
            return (w, b.offsetBy(dx: 0, dy: -top))
        }
    }

    // A schermo intero la barra si fa invisibile (regola di sempre: niente barra lì; su 27.2, a quota alta, gli
    // spazi a schermo intero la inviterebbero). Solo alpha: mai orderOut, che spegne il glass dei pannelli dopo
    // (regola del glass). Si guarda al cambio di spazio (main.swift) e, da nascosta, a ogni battito per ricomparire.
    func hideIfCovered() {
        guard let windows = windowsOnOurScreen() else { return }   // nessuno schermo: fermi
        let screenHeight = NSScreen.screens.first { $0.frame.intersects(frame) }?.frame.height ?? 0
        let covered = windows.contains { w, b in
            guard w[kCGWindowLayer as String] as? Int == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  coversTheScreen(top: b.minY, height: b.height, screenHeight: screenHeight, barHeight: Self.height) else { return false }
            // Solo le app vere (Dock e ⌘Tab): le cornici di servizio come JankyBorders sporgono nella striscia e
            // sono alte quanto lo schermo, ma sono app .accessory — scambiarle per coperture inchiodava la barra.
            let pid = w[kCGWindowOwnerPID as String] as? pid_t ?? 0
            return NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular
        }
        let target: CGFloat = covered ? 0 : 1
        if alphaValue != target { alphaValue = target }
    }

    // Scansati o risali (solo con parkedMenuBar): chiamata dal battito in main.swift. Cambia solo il livello: il
    // pannello non si chiude né si ricrea mai (regola del glass).
    func dodge(mouse p: NSPoint) {
        // Si scansa solo lo schermo che ha la barra di sistema: con gli spazi condivisi tra gli schermi ce l'ha solo
        // il principale, e sugli altri la sentinella manca sempre (sembrerebbe "visibile": review 3/10, restava giù).
        guard NSScreen.screensHaveSeparateSpaces || NSScreen.screens.first.map({ frame.intersects($0.frame) }) == true else {
            if level != Self.aboveParkedMenuBar { level = Self.aboveParkedMenuBar }
            return
        }
        let inside = (frame.minX...frame.maxX).contains(p.x) && p.y <= frame.maxY
        let d = inside ? frame.maxY - p.y : .infinity
        edgeBeats = d < 2 ? edgeBeats + 1 : 0   // battiti consecutivi a filo del bordo (il battito fa da orologio)
        let lowered = level == Self.belowMenuBar
        // La visibilità (una lettura delle finestre, con memoria di 0,2 s) si paga solo quando può decidere:
        // abbassata, o mouse nella fascia.
        let visible = lowered || d < 44 ? systemBarVisible() : false
        let target = dodgesMenuBar(distanceFromTop: d, lowered: lowered, visible: visible, dwelling: edgeBeats >= 2)
            ? Self.belowMenuBar : Self.aboveParkedMenuBar
        if level != target { level = target }
    }

    // Lo stesso pannello su un altro schermo (o lo stesso con un altro notch/risoluzione).
    // Il notch passa da `geometry`, non da una nuova rootView: riassegnarla spegne la pressione del glass su volume e batteria.
    func move(to screen: NSScreen) {
        let f = screen.frame
        setFrame(NSRect(x: f.minX, y: f.maxY - Self.height, width: f.width, height: Self.height), display: true)
        geometry.leftWidth = screen.auxiliaryTopLeftArea?.width
        geometry.rightWidth = screen.auxiliaryTopRightArea?.width
    }
}
