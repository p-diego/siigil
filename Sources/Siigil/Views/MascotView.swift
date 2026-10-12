import AppKit
import SwiftUI

// La mascotte nella barra, in punti: alta 27 (0,27 pt per unità della tela), larga 31,5.
let mascotBarSize = CGSize(width: 31.5, height: 27)

// La grandezza della mascotte nella barra (spec sezione Mascotte §10): dal 70 % al massimo che non taglia saltelli,
// pallino e "z", che stanno tutti dentro la tela (MascotShapesTests). La tela, alta 27 pt × grandezza e alzata di 1,5 pt ×
// grandezza nella pillola alta 26 al centro della barra alta 38, ha la cima a 19 − 15 × grandezza punti dalla cima della
// barra: entra fino a 1,27, arrotondato a 1,25.
let mascotSizes = 0.7...1.25

// Lo spazio sopra la tela nella barra, in unità della tela (spec pillole-mascotte §2): la cima della tela sta a 19 − 15 ×
// grandezza punti dalla cima della barra (mascotSizes); lì sale il cuoricino.
func barHeadroom(_ size: Double) -> Double { max(0, 19 - 15 * size) / (0.27 * size) }

// La mascotte viva (spec mascotte viva §5–6) in una vista che si disegna da sé in draw(_:), come un'immagine che cambia:
// mai CAAnimation (nel vetro tiene il compositore a 120 Hz, misurato il 24/9). Non sta mai ferma, quindi il displayLink
// gira finché la mascotte si vede: 15 immagini al secondo col solo fondo, 60 nei gesti (`fastFrames`), una sola quando
// nessuno la vede (finestra del tutto trasparente, o non visibile per macOS); si ridisegna solo quando si vede
// (shouldRedraw). Il puntatore sopra: un'area di tracciamento, niente monitor globali.
struct LiveMascot: NSViewRepresentable {
    let geometry: MascotGeometry   // forma e occhi: cambiarli non ricrea la mascotte, che continua a vivere
    let bodyHex: Int
    let eyesHex: Int
    let mood: MascotMood
    let dot: Color?
    var mirrored = false
    var running = true   // Impostazioni chiuse: ferma
    var headroom = 0.0   // lo spazio sopra la tela, in unità della tela (MascotNSView.headroom)

    func makeNSView(context: Context) -> MascotNSView { MascotNSView(geometry: geometry) }

    func updateNSView(_ view: MascotNSView, context: Context) {
        if view.geometry != geometry { view.geometry = geometry }
        if view.headroom != headroom { view.headroom = headroom }
        view.update(colors: MascotColors(body: cgColor(hex: bodyHex), eyes: cgColor(hex: eyesHex),
                                         dot: dot.map { $0.resolve(in: context.environment).cgColor }),
                    mood: mood, mirrored: mirrored, running: running)
    }

    static func dismantleNSView(_ view: MascotNSView, coordinator: ()) { view.stop() }   // widget spento: niente displayLink orfani
}

final class MascotNSView: NSView {
    private var life: MascotLife
    private var input = MascotInput(mood: .sleep)
    private(set) var drawn: MascotLook   // l'ultimo disegno vero (i test lo guardano)
    private var colors = MascotColors(body: cgColor(hex: 0xF5F7FC), eyes: cgColor(hex: 0x14141A), dot: nil)
    private var dotFrom: CGColor?   // il colore del pallino prima dell'ultimo cambio: il nuovo ci sfuma sopra
    private var mirrored = false
    private var running = true
    private var link: CADisplayLink?
    private var clock = CACurrentMediaTime()

    var isAnimating: Bool { link.map { !$0.isPaused } ?? false }
    var framesPerSecond: Float? { link?.preferredFrameRateRange.preferred }   // il ritmo del displayLink, per i test

    var geometry: MascotGeometry {   // forma e occhi (spec sezione Mascotte §10): si ridisegna, la vita continua
        get { life.geometry }
        set { life.geometry = newValue; needsDisplay = true }
    }

    // Lo spazio sopra la tela, in unità della tela (spec pillole-mascotte §2): la vista è più alta di tanto e lì sale il
    // cuoricino; non prende clic né puntatore.
    var headroom = 0.0 {
        didSet { if headroom != oldValue { needsDisplay = true; updateTrackingAreas() } }
    }

    // La tela nella vista (y in giù): sotto lo spazio in più.
    private var canvasRect: CGRect {
        let top = bounds.height * headroom / (100 + headroom)
        return CGRect(x: 0, y: top, width: bounds.width, height: bounds.height - top)
    }

    init(geometry: MascotGeometry) {
        life = MascotLife(kind: geometry.shape, seed: .random(in: 0...UInt64.max))   // ognuna col suo ritmo: mai ciglia insieme
        life.geometry = geometry
        drawn = life.look
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) non usato") }

    override var isFlipped: Bool { true }   // y in giù, come la tela

    func update(colors new: MascotColors, mood: MascotMood, mirrored m: Bool, running r: Bool) {
        let next = MascotInput(mood: mood, dot: new.dot != nil, hover: input.hover, pressed: input.pressed)
        let recolor = new.dot != nil && colors.dot != nil && new.dot != colors.dot
        let changed = next != input || r != running || recolor
        // Il tempo passato da fermi si gioca con l'ingresso di prima: col nuovo, un "ha finito" arrivato dopo una pausa
        // si consumerebbe tutto dentro un salto invisibile (saltelli e scintille persi).
        if changed { advance() }
        if recolor, let shown = colors.dot {
            // cambia colore mentre è fuori: sfuma da quello che si vede adesso; da dentro esce già col nuovo
            if life.look.dot > 0.01 {
                dotFrom = mixColor(dotFrom ?? shown, shown, life.look.dotFade)
                life.dotColorChanged()
            } else { dotFrom = nil }
        }
        if new.body != colors.body || new.eyes != colors.eyes || m != mirrored { needsDisplay = true }
        colors = MascotColors(body: new.body, eyes: new.eyes, dot: new.dot ?? colors.dot)   // spento: rientra col suo colore
        mirrored = m
        input = next; running = r
        if changed { resume() }
    }

    func stop() { link?.invalidate(); link = nil }

    // Riparte (o si ferma, con le Impostazioni chiuse o fuori dalla finestra): la vita recupera il tempo passato e il
    // displayLink gira al ritmo giusto.
    private func resume() {
        guard running, window != nil else { link?.isPaused = true; return }
        advance()
        if link == nil {
            let l = displayLink(target: self, selector: #selector(tick(_:)))
            l.add(to: .main, forMode: .common)   // .common: avanza anche con un menu aperto
            link = l
        }
        link?.isPaused = false
        pace()
    }

    @objc private func tick(_ link: CADisplayLink) {
        advance()
        pace()
    }

    // Niente da vedere: la finestra del tutto trasparente (la barra nascosta da hideIfCovered, che tocca solo
    // l'alpha) o che macOS dice non visibile: Mac bloccato con lo schermo acceso, salvaschermo, finestra coperta del
    // tutto (spec mascotte più leggere).
    private var invisible: Bool { window.map { $0.alphaValue == 0 || !$0.occlusionState.contains(.visible) } ?? true }

    // 60 immagini al secondo nei gesti (o appena prima che partano), 15 col solo fondo (spec §5), 1 quando nessuno la
    // vede (dalla barra nascosta il passo giusto torna al battito dopo che si rivede, fino a un secondo; da coperta
    // subito, perché macOS avvisa: occlusionChanged).
    private func pace() {
        let fps = Float(invisible ? 1 : life.fastFrames ? MascotLife.fastFPS : MascotLife.calmFPS)
        if link?.preferredFrameRateRange.preferred != fps {
            link?.preferredFrameRateRange = CAFrameRateRange(minimum: fps, maximum: fps, preferred: fps)
        }
    }

    private func advance() {
        let now = CACurrentMediaTime()
        // Al massimo un minuto alla volta (dopo un sonno del Mac): la vita salta avanti senza fisica quando le molle sono
        // ferme, e i suoi gesti in programma restano al loro posto (il più lontano è la risistemata, fra 40 e 80 s: oltre il
        // minuto arriva dopo).
        life.advance(min(now - clock, 60), input: input)
        clock = now
        // Nascosta non si ridisegna e `drawn` resta l'ultimo disegno vero: appena si rivede, il primo battito lo confronta
        // con la vita di adesso e rifà quel che serve.
        if !invisible, shouldRedraw(drawn, life) { drawn = life.look; needsDisplay = true }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: nil)
        // Fuori dalla finestra il rilascio del mouse non arriva più: non restare schiacciata al ritorno.
        if window == nil { input.pressed = false; stop(); return }
        clock = CACurrentMediaTime(); resume()
        NotificationCenter.default.addObserver(self, selector: #selector(occlusionChanged),
                                               name: NSWindow.didChangeOcclusionStateNotification, object: window)
    }

    // Coperta o di nuovo visibile (Mac bloccato e sbloccato): il passo giusto subito, e tornata visibile il primo passo
    // rifà quello che serve.
    @objc private func occlusionChanged() { resume() }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var c = colors
        if let to = c.dot, let from = dotFrom { c.dot = mixColor(from, to, drawn.dotFade) }
        drawMascot(life.geometry, drawn, c, in: ctx, size: bounds.size, mirrored: mirrored, headroom: headroom)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: canvasRect, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways], owner: self))
    }
    override func mouseEntered(with event: NSEvent) { hover(event) }
    override func mouseMoved(with event: NSEvent) { hover(event) }
    override func mouseExited(with event: NSEvent) { advance(); input.hover = nil; resume() }
    private func hover(_ event: NSEvent) {
        advance()   // il tempo passato da fermi, col puntatore di prima
        input.hover = canvasPoint(convert(event.locationInWindow, from: nil), size: bounds.size, mirrored: mirrored, headroom: headroom)
        resume()
    }

    // Lo spazio sopra la tela lascia passare i clic a quello che c'è sotto.
    override func hitTest(_ point: NSPoint) -> NSView? {
        canvasRect.contains(convert(point, from: superview)) ? super.hitTest(point) : nil
    }

    // Premuta col tasto sinistro (spec pillole-mascotte §2): si schiaccia; lasciata rimbalza e conta il clic. Col ⌘ no: è
    // il ⌘-trascina. Il clic prosegue verso SwiftUI come prima (tap, ⌘-trascina, pressione del vetro).
    override func mouseDown(with event: NSEvent) {
        if !event.modifierFlags.contains(.command) { press(true) }
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        press(false)
        super.mouseUp(with: event)
    }
    private func press(_ on: Bool) {
        guard input.pressed != on else { return }
        advance(); input.pressed = on; resume()
    }
}

// Un colore scelto col selettore di sistema come 0xRRGGBB: in sRGB, quello fuori gamma (P3) riportato dentro.
func hexValue(_ c: Color) -> Int {
    let r = c.resolve(in: EnvironmentValues())
    func byte(_ x: Float) -> Int { Int((min(max(Double(x), 0), 1) * 255).rounded()) }
    return byte(r.red) << 16 | byte(r.green) << 8 | byte(r.blue)
}
