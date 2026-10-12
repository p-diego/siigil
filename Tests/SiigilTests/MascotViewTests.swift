import AppKit
import SwiftUI
import Testing
@testable import Siigil

@Test func agentStatesBecomeMoods() {
    #expect(aiMood(nil) == .sleep && aiMood(.working) == .work && aiMood(.waiting) == .wait && aiMood(.done) == .done)
}

// Il pallino del Watchdog come il suo fumetto: arancione, rosso se grave, nessuno senza allarme (spec §3).
@Test func watchdogDotFollowsTheAlarm() {
    #expect(watchdogDot(nil, palette: nil) == nil)
    #expect(watchdogDot(.heat(severe: true), palette: nil) == .red)
    #expect(watchdogDot(.memory(critical: false), palette: nil) == .orange)
}

// Review Focus 4: widget spento, Impostazioni chiuse, vista fuori dalla finestra = niente displayLink né timer.
@MainActor @Test func liveMascotStopsWhenNotRunning() {
    _ = NSApplication.shared
    let view = MascotNSView(geometry: .of(.mostro))
    view.frame = NSRect(origin: .zero, size: mascotBarSize)
    view.update(colors: testColors, mood: .wait, mirrored: false, running: true)
    #expect(!view.isAnimating)   // senza finestra non parte nulla
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView!.addSubview(view)
    view.update(colors: testColors, mood: .wait, mirrored: false, running: true)
    #expect(view.isAnimating)    // in finestra, ti aspetta: si muove
    view.update(colors: testColors, mood: .wait, mirrored: false, running: false)
    #expect(!view.isAnimating)   // Impostazioni chiuse
    view.update(colors: testColors, mood: .wait, mirrored: false, running: true)
    view.removeFromSuperview()
    #expect(!view.isAnimating)   // fuori dalla finestra
}

// Review Focus 5: un colore dal selettore di sistema, anche fuori da sRGB, si salva come 0xRRGGBB valido.
@Test func pickedColorsBecomeSRGBHex() {
    for hex in mascotSwatches { #expect(hexValue(Color(hex: hex)) == hex) }
    let p3 = hexValue(Color(.displayP3, red: 1, green: 0, blue: 0))
    #expect(p3 >> 16 == 0xFF && p3 >= 0 && p3 <= 0xFFFFFF)
}

// Una finestra di prova visibile per macOS, finché non la si copre: fuori dallo schermo una NSWindow non è mai visibile
// (`occlusionState` senza `.visible`) e la mascotte non si ridisegnerebbe.
final class TestWindow: NSWindow {
    var covered = false
    override var occlusionState: NSWindow.OcclusionState { covered ? [] : .visible }
}

// La mascotte in una finestra fuori schermo visibile per macOS, con l'alpha dato: 0 è la barra nascosta da
// hideIfCovered (solo alpha).
@MainActor private func mascotInWindow(alpha: CGFloat) -> (view: MascotNSView, window: TestWindow) {
    _ = NSApplication.shared
    let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40), styleMask: .borderless, backing: .buffered, defer: false)
    window.alphaValue = alpha
    let view = MascotNSView(geometry: .of(.mostro))
    view.frame = NSRect(origin: .zero, size: mascotBarSize)
    window.contentView!.addSubview(view)
    return (view, window)
}

private let testColors = MascotColors(body: cgColor(hex: 0xF5F7FC), eyes: cgColor(hex: 0x14141A), dot: nil)

// Barra nascosta da hideIfCovered (finestra del tutto trasparente): il displayLink batte una volta al secondo; appena si
// vede, di nuovo 15 o 60.
@MainActor @Test func hiddenWindowSlowsTheLinkToOnePerSecond() {
    let (view, window) = mascotInWindow(alpha: 0)
    withExtendedLifetime(window) {
        view.update(colors: testColors, mood: .wait, mirrored: false, running: true)
        #expect(view.isAnimating && view.framesPerSecond == 1)
        window.alphaValue = 1
        view.update(colors: testColors, mood: .work, mirrored: false, running: true)   // un cambio rimette il passo
        #expect([Float(MascotLife.calmFPS), Float(MascotLife.fastFPS)].contains(view.framesPerSecond ?? 0))
    }
}

// Cambiare forma o occhi dalle Impostazioni (spec sezione Mascotte §10) non ferma la mascotte viva: si ridisegna e continua.
@MainActor @Test func changingTheGeometryKeepsTheMascotAlive() {
    let (view, window) = mascotInWindow(alpha: 1)
    withExtendedLifetime(window) {
        view.update(colors: testColors, mood: .wait, mirrored: false, running: true)
        view.needsDisplay = false
        view.geometry = .of(.ball, EyeSettings(size: 1.2))
        #expect(view.isAnimating && view.needsDisplay && view.geometry == .of(.ball, EyeSettings(size: 1.2)))
    }
}

// Nascosta non si ridisegna (`drawn`, l'ultimo disegno vero, resta quello); visibile sì. Il tempo passa davvero: serve a
// far cambiare la mascotte (da addormentata a che legge) fra un ingresso e l'altro.
@MainActor @Test func hiddenWindowDoesNotRedraw() {
    let hidden = mascotInWindow(alpha: 0), shown = mascotInWindow(alpha: 1)
    withExtendedLifetime((hidden.window, shown.window)) {
        let (hiddenBefore, shownBefore) = (hidden.view.drawn, shown.view.drawn)
        for m in [hidden.view, shown.view] { m.update(colors: testColors, mood: .work, mirrored: false, running: true) }
        Thread.sleep(forTimeInterval: 0.3)
        for m in [hidden.view, shown.view] { m.update(colors: testColors, mood: .wait, mirrored: false, running: true) }   // advance() con 0,3 s di lettura
        #expect(hidden.view.drawn == hiddenBefore)
        #expect(shown.view.drawn != shownBefore)
    }
}

// Barra che nessuno vede (Mac bloccato con lo schermo acceso, salvaschermo: macOS la dice non visibile): come la barra
// nascosta, un battito al secondo e nessun ridisegno (spec mascotte più leggere). Appena torna visibile riparte subito,
// senza aspettare il battito, e il primo passo rifà quello che serve.
@MainActor @Test func coveredWindowPausesTheMascot() {
    let (view, window) = mascotInWindow(alpha: 1)
    withExtendedLifetime(window) {
        view.update(colors: testColors, mood: .work, mirrored: false, running: true)
        window.covered = true
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        #expect(view.isAnimating && view.framesPerSecond == 1)
        let before = view.drawn
        Thread.sleep(forTimeInterval: 0.3)
        view.update(colors: testColors, mood: .wait, mirrored: false, running: true)   // advance() con 0,3 s di lettura
        #expect(view.drawn == before)
        window.covered = false
        NotificationCenter.default.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        #expect([Float(MascotLife.calmFPS), Float(MascotLife.fastFPS)].contains(view.framesPerSecond ?? 0))
        #expect(view.drawn != before)
    }
}

// Un clic del tasto sinistro sulla vista, nel suo punto (15, 15).
@MainActor private func click(_ view: MascotNSView, _ type: NSEvent.EventType, _ flags: NSEvent.ModifierFlags = []) {
    let e = NSEvent.mouseEvent(with: type, location: NSPoint(x: 15, y: 15), modifierFlags: flags, timestamp: 0,
                               windowNumber: view.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    type == .leftMouseDown ? view.mouseDown(with: e) : view.mouseUp(with: e)
}

// Lascia passare `seconds` e fa avanzare la vita: un cambio d'umore forza advance() (la vista avanza da sola solo col
// displayLink, che nei test non batte).
@MainActor private func pass(_ view: MascotNSView, _ seconds: Double, mood: MascotMood) {
    Thread.sleep(forTimeInterval: seconds)
    view.update(colors: testColors, mood: mood, mirrored: false, running: true)
}

// Premuta (spec pillole-mascotte §2): il tasto sinistro la schiaccia, lasciato torna; col ⌘ no, ed è il ⌘-trascina:
// 4 ⌘-clic veloci non fanno partire nessuna reazione (Review Focus 3).
@MainActor @Test func pressingTheViewSquashesTheMascot() {
    let (view, window) = mascotInWindow(alpha: 1)
    withExtendedLifetime(window) {
        view.update(colors: testColors, mood: .sleep, mirrored: false, running: true)
        click(view, .leftMouseDown)
        pass(view, 0.25, mood: .work)
        #expect(view.drawn.squash < 0.9)
        click(view, .leftMouseUp)
        pass(view, 0.6, mood: .sleep)
        #expect(view.drawn.squash > 0.95)
        for _ in 0..<4 {
            click(view, .leftMouseDown, .command); pass(view, 0.05, mood: .work)
            click(view, .leftMouseUp, .command); pass(view, 0.1, mood: .sleep)
        }
        #expect(view.drawn.squash > 0.95 && view.drawn.heart == nil && view.drawn.dizzy == nil)
    }
}

// Lo spazio sopra la tela (dove sale il cuoricino) non prende clic: passano a quello che c'è sotto.
@MainActor @Test func theRoomAboveTheCanvasLetsClicksThrough() {
    let (view, window) = mascotInWindow(alpha: 1)
    withExtendedLifetime(window) {
        view.frame = NSRect(x: 0, y: 0, width: mascotBarSize.width, height: mascotBarSize.height + 4)
        view.headroom = 4 / 0.27
        // contentView non è girata: y in su; i 4 pt in alto sono lo spazio sopra la tela
        #expect(view.hitTest(NSPoint(x: 15, y: mascotBarSize.height + 2)) == nil)
        #expect(view.hitTest(NSPoint(x: 15, y: 10)) === view)
    }
}
