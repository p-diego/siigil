import CoreGraphics
import Foundation

// La mascotte viva (spec 2026-10-10-siigil-mascotte-viva-design): il modello, senza disegno. Tre strati, come Grok Bot
// (analisi del 10/10): un fondo che non si ferma mai (respiro, ondeggio, occhi che vagano: onde calcolate dal tempo),
// gesti a orologio casuale (ciglia, occhiate, sbirciate, saltelli) e molle a passo fisso di 1/120 s che rendono morbido
// ogni cambio. I numeri a caso vengono da un generatore col seme: i test e il budget dei ridisegni girano sempre uguali.
// Tutto nelle unità della tela del prototipo (siigil-docs/prototipi-mascotte/base.swift): 100 = l'altezza della mascotte, 27 pt
// nella barra; y in giù; x verso il davanti (il lato del fumetto).

// SplitMix64: numeri a caso ripetibili.
struct SplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 {
        s &+= 0x9E37_79B9_7F4A_7C15
        var z = s
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// Una molla verso `target`: con zeta 1 arriva senza superarlo, sotto molleggia. Gli impulsi (saltelli, tremolii) si
// danno sulla velocità.
struct MascotSpring {
    var x: Double, v = 0.0, target: Double
    let omega: Double, zeta: Double
    init(_ x: Double, omega: Double, zeta: Double = 1) { self.x = x; target = x; self.omega = omega; self.zeta = zeta }
    mutating func step(_ h: Double) {
        v += (-2 * zeta * omega * v - omega * omega * (x - target)) * h
        x += v * h
    }
    func still(_ eps: Double) -> Bool { abs(x - target) < eps && abs(v) < eps * omega }
}

// La forma (spec sezione Mascotte §10): Mostro e Mirtillo, le due di prima, e sette come quelle di Grok, nell'ordine in cui
// si scelgono (autore, 11/10: tolto il triangolo rovesciato, aggiunto lo squircle). Salvata col suo nome. Sagome, occhi e
// pallino in MascotShapes.swift.
enum MascotKind: String, Codable, CaseIterable {
    case mostro, mirtillo, ball, pebble, squircle, capsule, hexagon, cloud, drop
}

// Dorme, lavora, ti aspetta, ha finito (Monitor AI); guarda un lavoro pesante, allarme (Monitor di sistema).
enum MascotMood { case sleep, work, wait, done, watch, alarm }

struct MascotInput: Equatable {
    var mood: MascotMood
    var dot = false        // il pallino di stato è fuori
    var hover: CGPoint?    // il puntatore sopra la mascotte, nella tela
    var pressed = false    // premuta col tasto sinistro: si schiaccia (spec pillole-mascotte §2)
}

// Un occhio: la barretta di oggi e le sue forme. Larghezza e altezza nella tela; curva da -1 (dorme, ‿) a 1 (felice, ︵);
// palpebra da 0 (aperto) a 1 (chiuso dall'alto).
struct EyePose: Equatable {
    var w, h, bend, lid: Double
    static let open = EyePose(w: 7.08, h: 15.3, bend: 0, lid: 0)
    static let wide = EyePose(w: 8.15, h: 17.6, bend: 0, lid: 0)
    static let half = EyePose(w: 7.08, h: 15.3, bend: 0, lid: 0.5)
    // gli occhi chiusi sono più grandi di prima (15,5 × 4,4 invece di 12,2 × 3,2): scelta dell'autore il 10/10, a misura vera
    // sembravano piccoli
    static let asleep = EyePose(w: 15.5, h: 4.4, bend: -1, lid: 0)
    static let happy = EyePose(w: 15.5, h: 4.4, bend: 1, lid: 0)
    static let wink = EyePose(w: 15.5, h: 4.4, bend: 0.6, lid: 0)
}

// Quello che si disegna in un istante.
struct MascotLook: Equatable {
    var gazeX = 0.0, gazeY = 0.0              // -1…1: x verso il davanti, y in giù
    var squash = 1.0                          // altezza del corpo (la larghezza fa il contrario, la base resta a terra)
    var tilt = 0.0                            // radianti, attorno al centro della base
    var lift = 0.0                            // da terra, nella tela
    var left = EyePose.asleep, right = EyePose.asleep
    var leftShift = CGVector.zero, rightShift = CGVector.zero   // ogni occhio vaga un poco per conto suo, nella tela
    var dot = 0.0                             // pallino: grandezza, 0 sparito, 1 intero (col rimbalzo un po' di più)
    var dotFade = 1.0                         // dal colore di prima (0) al nuovo (1)
    var z: Double?                            // la "z" che sale, 0…1
    var sparkle: Double?                      // le scintille, 0…1
    var turn = 0.0                            // il giro su se stessa (spec sezione Mascotte §10), 0…1: gli occhi fanno il giro della testa, a metà sono dietro
    var heart: Double?                        // il cuoricino dopo 4 clic veloci (spec pillole-mascotte §2), 0…1
    var dizzy: Double?                        // gli occhi a spirale dopo 4 clic veloci, 0…1
}

// Il passo dei ridisegni (spec §5): col solo fondo un decimo di punto, così l'ondeggio scorre morbido e non a spintarelle
// di mezzo pixel; nei gesti veloci, a 60 immagini al secondo, basta un quarto.
let visibleStep = 0.1, fastStep = 0.25

// Quanto si vede la differenza fra due istanti, in punti nella barra (0,27 pt per unità della tela): lo spostamento più
// grande di un pezzo. Il colore del pallino conta un decimo di punto ogni 3 % di passaggio.
func visibleDistance(_ a: MascotLook, _ b: MascotLook, _ g: MascotGeometry) -> Double {
    func eye(_ p: EyePose, _ q: EyePose) -> Double {
        max(abs(p.w - q.w), abs(p.h - q.h), abs(p.bend - q.bend) * 1.3, abs(p.lid - q.lid) * max(p.h, q.h))
    }
    func shift(_ p: CGVector, _ q: CGVector) -> Double { max(abs(p.dx - q.dx), abs(p.dy - q.dy)) }
    func opt(_ x: Double?, _ y: Double?, _ k: Double) -> Double {
        switch (x, y) {
        case let (x?, y?): abs(x - y) * k
        case (nil, nil): 0
        default: .infinity   // compare o sparisce: si disegna
        }
    }
    // ponytail: non conta lo scostamento della faccia dal pallino (mascotFigure); da contare se agli sguardi estremi si vede un ritardo
    let units = max(abs(a.gazeX - b.gazeX) * g.faceX, abs(a.gazeY - b.gazeY) * g.faceY,
                    abs(a.squash - b.squash) * 62, abs(a.tilt - b.tilt) * 42, abs(a.lift - b.lift),
                    eye(a.left, b.left) * g.eyes.size, eye(a.right, b.right) * g.eyes.size, shift(a.leftShift, b.leftShift),
                    shift(a.rightShift, b.rightShift), abs(a.dot - b.dot) * 24, opt(a.z, b.z, 10), opt(a.sparkle, b.sparkle, 8), opt(a.heart, b.heart, 90), opt(a.dizzy, b.dizzy, 120))
    // il giro: gli occhi scorrono sul cilindro della testa (raggio al più 45: le forme stanno fra 4 e 96), al più l'arco
    let turn = abs(a.turn - b.turn) * 2 * .pi * 45
    return max(max(units, turn) * 0.27, abs(a.dotFade - b.dotFade) * 3)
}

// La regola dei ridisegni, la stessa nella vista e nel test del budget: si rifà il disegno quando si vede, col passo del
// ritmo in corso.
func shouldRedraw(_ drawn: MascotLook, _ life: MascotLife) -> Bool {
    visibleDistance(drawn, life.look, life.geometry) >= (life.fastFrames ? fastStep : visibleStep)
}

private struct EyeSprings {
    var w, h, bend, lid: MascotSpring
    init(_ p: EyePose) {
        w = MascotSpring(p.w, omega: 22); h = MascotSpring(p.h, omega: 50)   // l'altezza svelta: batte le ciglia
        bend = MascotSpring(p.bend, omega: 22); lid = MascotSpring(p.lid, omega: 30)
    }
    var pose: EyePose { EyePose(w: w.x, h: h.x, bend: bend.x, lid: lid.x) }
    var still: Bool { w.still(0.1) && h.still(0.1) && bend.still(0.08) && lid.still(0.01) }   // il resto non si vede (~0,03 pt)
    mutating func aim(_ p: EyePose) { w.target = p.w; h.target = p.h; bend.target = p.bend; lid.target = p.lid }
    mutating func step(_ dt: Double) { w.step(dt); h.step(dt); bend.step(dt); lid.step(dt) }
}

// Le ampiezze del fondo per stato (spec §2): respiro (altezza in più al colmo), ondeggio (radianti), deriva degli occhi
// (unità della tela) e durata di un respiro. Circa 3–5 volte Grok in proporzione: alla nostra taglia il suo sparirebbe.
// Dormendo la deriva è 1,0 e non 0,6: copre i momenti in cui respiro e ondeggio sono fermi insieme (con 0,6 una prova da
// 2 minuti su 12 restava ferma più di 3 s, con 1,0 nessuna su 10 000: la più lunga 2,8 s).
private struct Background: Equatable {
    var breath, sway, drift: Double
    var period: ClosedRange<Double>
    static let asleep = Background(breath: 0.026, sway: 0.03, drift: 1.0, period: 9...11)
    static let awake = Background(breath: 0.02, sway: 0.045, drift: 0.9, period: 6.4...8.4)
    static let alarmed = Background(breath: 0.015, sway: 0.02, drift: 0.5, period: 2.4...3)
}

// Da 0 a 1 partendo e arrivando piano (smoothstep): il respiro e il giro su se stessa.
private func ease(_ k: Double) -> Double { k * k * (3 - 2 * k) }

// Un respiro da 0 a 1 e ritorno: inspira nel primo 40 %, espira nel 50 %, poi una pausa.
private func breathShape(_ p: Double) -> Double {
    let p = min(max(p, 0), 1)
    return p < 0.4 ? ease(p / 0.4) : p < 0.9 ? 1 - ease((p - 0.4) / 0.5) : 0
}

// La vita: l'umore dice l'attività (dorme, sbircia, legge, ti chiama, festeggia, allarme, ti guarda), l'attività
// programma i gesti, i gesti spostano i bersagli delle molle; sopra, il fondo. Quando nessuna molla si muove la fisica
// salta avanti fino al prossimo gesto: il fondo è fatto di onde calcolate dal tempo e non ha bisogno di passi.
struct MascotLife {
    static let step = 1.0 / 120
    static let gravity = 620.0   // nella tela al secondo²: un saltello alto 10 sta in aria ~0,36 s
    static let calmFPS = 15.0, fastFPS = 60.0   // i due ritmi della vista: il fondo, i gesti
    static let spinTime = 1.0                   // il giro su se stessa (spec sezione Mascotte §10)
    static var spinGap = 25.0...45.0            // ogni quanto, al lavoro; la modalità demo lo accorcia (Demo.swift)
    static let pressSquash = 0.8                 // premuta: l'altezza del corpo (spec pillole-mascotte §2, prova F1)
    static let quickTaps = 4, tapGap = 0.5       // 4 clic, ognuno entro mezzo secondo dal precedente (prova G1)
    static let heartTime = 1.4, dizzyTime = 1.8  // il cuoricino e gli occhi a spirale

    var geometry: MascotGeometry   // forma e occhi: la vista la cambia quando cambiano le impostazioni
    private(set) var look = MascotLook()
    private(set) var time = 0.0                  // secondi di vita
    private var acc = 0.0
    private var rng: SplitMix
    private var input = MascotInput(mood: .sleep)
    private var lastMood: MascotMood?            // per accorgersi di un "ha finito" nuovo
    private var activity = Activity.asleep
    private var peeking = false, peekHalf = false, cheering = false, drowsy = false, lookingUp = false
    private var blinkL = false, blinkR = false   // battito in corso, anche di un occhio solo
    private var wink: Int?                       // l'occhio dell'occhiolino in corso
    private var hopsLeft = 0
    private var readX = -0.45                    // dove è arrivata la lettura sulla riga

    private var gx = MascotSpring(0.1, omega: 18), gy = MascotSpring(0.4, omega: 18)
    private var squash = MascotSpring(1, omega: 28, zeta: 0.4)
    private var tilt = MascotSpring(0, omega: 30, zeta: 0.35)
    private var lift = 0.0, liftV = 0.0
    private var dot = MascotSpring(0, omega: 12, zeta: 0.55), fade = MascotSpring(1, omega: 8)
    private var eyes = [EyeSprings(.asleep), EyeSprings(.asleep)]
    private var zStart: Double?, sparkStart: Double?, spinStart: Double?
    private var wasPressed = false, taps = 0, lastTap = -Double.infinity   // i clic veloci (spec pillole-mascotte §2)
    private var heartStart: Double?, dizzyStart: Double?
    private var timers = [Double](repeating: .infinity, count: Gesture.allCases.count)   // istante di ogni gesto

    // Il fondo: fasi a caso per ogni mascotte (due onde dell'ondeggio, tre della deriva degli occhi), il respiro in corso,
    // le ampiezze che passano piano da uno stato all'altro.
    private let phases: [Double]
    private var breathStart = 0.0, breathLen = 10.0, breathGain = 1.0
    private var calm = Background.asleep, calmFrom = Background.asleep, calmSince = -100.0

    private enum Activity { case asleep, peek, read, call, cheer, alarmed, hover }
    private enum Gesture: Int, CaseIterable {
        case wake, nap, nodEnd, peekOpen, cheerEnd, blink, reopen, glance, glanceBack, unwink, saccade, lookUp, lookDown,
             shift, settle, z, hop, kick, tremble, spin, spinEnd, bowEnd
    }

    init(kind: MascotKind, seed: UInt64) {
        geometry = .of(kind)
        var r = SplitMix(s: seed)
        phases = (0..<5).map { _ in Double.random(in: 0..<(2 * .pi), using: &r) }
        rng = r
        breathLen = .random(in: Background.asleep.period, using: &rng)
        breathStart = -.random(in: 0..<breathLen, using: &rng)   // il primo respiro parte da un punto a caso: Mostro e Mirtillo non respirano insieme
        enter(.asleep, nap: 30)   // il primo sonno dura 30 s, come prima
        look = current
    }

    // Le molle si muovono: un gesto in corso o il saltello in volo. Il fondo non conta.
    var moving: Bool {
        lift > 0 || liftV != 0 || spinStart != nil
            || !(gx.still(0.008) && gy.still(0.008) && squash.still(0.002) && tilt.still(0.0025)
                 && dot.still(0.005) && fade.still(0.01) && eyes.allSatisfy(\.still))
    }

    // Servono 60 immagini al secondo: un gesto in corso, le scintille, o un gesto che parte prima della prossima immagine
    // lenta. Per il solo fondo ne bastano 15.
    var fastFrames: Bool {
        moving || sparkStart.map { time - $0 < 1.6 } == true || reacting || nextEventIn < 1 / Self.calmFPS
    }

    // Secondi al prossimo gesto (infinito se nessuno).
    var nextEventIn: Double { (timers.min() ?? .infinity) - time }

    // Avanza di `dt` secondi con l'ingresso di adesso.
    mutating func advance(_ dt: Double, input new: MascotInput) {
        input = new
        acc += max(0, dt)
        refresh()
        while acc >= Self.step {
            if !moving {   // molle ferme: salta fino al prossimo gesto (o fin dove arriva il tempo) senza fisica
                let n = min((acc / Self.step).rounded(.down), (nextEventIn / Self.step).rounded(.down))
                if n >= 1 { time += n * Self.step; acc -= n * Self.step; rollBreath(); continue }
            }
            tick()
            acc -= Self.step
        }
        look = current
    }

    // Il pallino cambia colore mentre è fuori: si ricomincia a sfumare.
    mutating func dotColorChanged() { fade.x = 0; fade.v = 0; look = current }

    // Le ampiezze del fondo adesso, anche a metà di un passaggio (~1,5 s).
    private var calmNow: Background {
        let k = 1 - exp(-(time - calmSince) / 0.5)
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * k }
        return Background(breath: mix(calmFrom.breath, calm.breath), sway: mix(calmFrom.sway, calm.sway),
                          drift: mix(calmFrom.drift, calm.drift), period: calm.period)
    }

    private var current: MascotLook {
        let bg = calmNow, w = 2 * Double.pi * time
        let breath = bg.breath * breathGain * breathShape((time - breathStart) / breathLen)
        let sway = bg.sway * (0.7 * sin(w / 12.6 + phases[0]) + 0.3 * sin(w / 37 + phases[1]))   // le onde di Grok
        func drift(_ e: Double) -> CGVector {   // e: 0 un occhio, 1 l'altro, sfasati come in Grok
            CGVector(dx: bg.drift * (0.75 * sin(w / 15 + phases[2] + e) + 0.25 * sin(w / 6.3 + phases[3] + 2 * e)),
                     dy: bg.drift * 0.5 * sin(w / 10.8 + phases[4] + e))
        }
        return MascotLook(gazeX: gx.x, gazeY: gy.x, squash: squash.x + breath, tilt: tilt.x + sway, lift: lift,
                          left: eyes[0].pose, right: eyes[1].pose, leftShift: drift(0), rightShift: drift(1),
                          dot: dot.x, dotFade: fade.x,
                          z: zStart.flatMap { time - $0 < 2.4 ? (time - $0) / 2.4 : nil },
                          sparkle: sparkStart.flatMap { time - $0 < 1.6 ? (time - $0) / 1.6 : nil },
                          turn: spinStart.map { ease(min(max((time - $0) / Self.spinTime, 0), 1)) } ?? 0,
                          heart: heartStart.flatMap { time - $0 < Self.heartTime ? (time - $0) / Self.heartTime : nil },
                          dizzy: dizzyStart.flatMap { time - $0 < Self.dizzyTime ? (time - $0) / Self.dizzyTime : nil })
    }

    // Un respiro dopo l'altro, ciascuno un po' diverso; dormendo ogni tanto un sospiro (circa uno su cinque).
    private mutating func rollBreath() {
        while time - breathStart >= breathLen {
            breathStart += breathLen
            let sigh = activity == .asleep && chance(0.2)
            breathLen = .random(in: calm.period, using: &rng) * (sigh ? 1.4 : 1)
            breathGain = sigh ? 1.8 : .random(in: 0.85...1.15, using: &rng)
        }
    }

    private mutating func tick() {
        let h = Self.step
        refresh()
        for g in Gesture.allCases where timers[g.rawValue] <= time + 1e-9 {
            timers[g.rawValue] = .infinity
            fire(g)
        }
        refresh()   // un gesto può cambiare attività (sveglia, nanna, fine dei saltelli)
        aim()
        gx.step(h); gy.step(h); squash.step(h); tilt.step(h); dot.step(h); fade.step(h)
        for i in eyes.indices { eyes[i].step(h) }
        if lift > 0 || liftV > 0 {   // in volo: la gravità lo riporta giù, all'atterraggio il corpo si schiaccia
            liftV -= Self.gravity * h
            lift += liftV * h
            if lift <= 0 { lift = 0; squash.v -= abs(liftV) * 0.008; liftV = 0 }
        }
        time += h
        rollBreath()
    }

    // Dall'ingresso all'attività. Un "ha finito" nuovo festeggia 2,4 s, poi dorme (come la mascotte di prima); il puntatore
    // sopra la mascotte vince su tutto tranne la festa.
    private mutating func refresh() {
        if input.pressed != wasPressed {   // premuta o lasciata: lasciata torna su (la molla rimbalza) e conta il clic
            wasPressed = input.pressed
            if !input.pressed { squash.target = 1; tapped() }
        }
        if input.mood != lastMood {
            cheering = input.mood == .done
            timers[Gesture.cheerEnd.rawValue] = cheering ? time + 2.4 : .infinity
            lastMood = input.mood
        }
        dot.target = input.dot ? 1 : 0
        let next: Activity
        if let p = input.hover, !cheering {   // ti guarda: verso il puntatore, nei limiti della faccia
            next = .hover
            gx.target = min(max((p.x - 50) / 30, -1), 1)
            gy.target = min(max((p.y - geometry.eyeY) / 25, -1), 1)
        } else {
            switch input.mood {
            case .sleep: next = peeking ? .peek : .asleep
            case .done: next = cheering ? .cheer : peeking ? .peek : .asleep
            case .work, .watch: next = .read
            case .wait: next = .call
            case .alarm: next = .alarmed
            }
        }
        if next != activity { enter(next) }
        // premuta vince sui gesti e sui cambi d'attività, che rimettono il corpo a 1 (saltelli, ciondolio, enter)
        if input.pressed { squash.target = Self.pressSquash }
    }

    private mutating func enter(_ a: Activity, nap: Double? = nil) {
        let from = activity
        activity = a
        peeking = a == .peek   // una sbirciata interrotta (lavoro, puntatore, "ha finito") non resta in sospeso
        let sleepy = a == .asleep || a == .peek
        // la risistemata (ogni 40–80 s) resta in attesa fra un sonno e una sbirciata: i risvegli (ogni 20–40 s) non la
        // cancellano, ogni altra attività sì
        for g in Gesture.allCases where g != .cheerEnd && !(sleepy && g == .settle) { timers[g.rawValue] = .infinity }
        blinkL = false; blinkR = false; wink = nil; drowsy = false; lookingUp = false; spinStart = nil
        squash.target = 1; tilt.target = 0
        let bg: Background = sleepy ? .asleep : a == .alarmed ? .alarmed : .awake
        if bg != calm { calmFrom = calmNow; calm = bg; calmSince = time }
        switch a {
        case .asleep:
            gx.target = 0.1; gy.target = 0.4
            let wait = nap ?? .random(in: 20...40, using: &rng)
            at(.wake, time + wait)
            after(.z, 4...8); after(.shift, 4...8)
            if timers[Gesture.settle.rawValue] == .infinity { after(.settle, 40...80) }   // una sola in attesa
            if from != .asleep {   // si addormenta ciondolando: la testa cade un poco e si piega (occhi aperti: a metà)
                drowsy = from != .cheer
                squash.target = 0.95
                let s = side(); tilt.v += 0.6 * s
                at(.nodEnd, time + 0.7)
            }
        case .peek:   // apre gli occhi piano, si guarda attorno, si riaddormenta
            peekHalf = true
            at(.peekOpen, time + 0.35); at(.glance, time + 0.6); at(.nap, time + 2.4)
        case .read:   // un battito a ogni cambio di stato, come Grok: nasconde il cambio degli occhi
            readX = -0.45; gx.target = readX; gy.target = 0.35
            at(.blink, time + 0.05); after(.saccade, 1.2...1.8); after(.lookUp, 15...25)
            if input.mood == .work { after(.spin, Self.spinGap) }   // il Monitor AI al lavoro, ogni tanto, un giro (spec §10)
        case .call:
            gx.target = 0.1; gy.target = -0.3
            at(.blink, time + 0.05); at(.hop, time + 0.3); after(.glance, 6...12)
        case .cheer:
            gx.target = 0; gy.target = -0.2
            hopsLeft = 2; at(.hop, time + 0.1); sparkStart = time
        case .alarmed:
            gx.target = 0; gy.target = -0.1
            at(.blink, time + 0.05); at(.tremble, time + 0.2)
        case .hover:
            at(.blink, time + 0.05)
        }
    }

    // Ogni quanto batte le ciglia: leggendo meno (come le persone), con gli occhi spalancati meno ancora.
    private var blinkEvery: ClosedRange<Double> {
        switch activity {
        case .read: 7...12
        case .alarmed: 6...9
        default: 4...8
        }
    }

    // Un clic lasciato: conta i clic veloci; al quarto una reazione a caso, 50 e 50. Durante una reazione i clic non contano
    // (finita, si ricomincia da zero).
    private mutating func tapped() {
        guard !reacting else { taps = 0; return }
        taps = time - lastTap <= Self.tapGap ? taps + 1 : 1
        lastTap = time
        guard taps >= Self.quickTaps else { return }
        taps = 0
        if Bool.random(using: &rng) { heartStart = time } else { dizzyStart = time }
    }

    private var reacting: Bool {
        heartStart.map { time - $0 < Self.heartTime } == true || dizzyStart.map { time - $0 < Self.dizzyTime } == true
    }

    private mutating func fire(_ g: Gesture) {
        switch g {
        case .wake: peeking = true
        case .nap: peeking = false
        case .nodEnd: drowsy = false; squash.target = 1
        case .peekOpen: peekHalf = false
        case .cheerEnd: cheering = false
        case .blink:   // tutti e due gli occhi, ogni tanto uno solo (un'asimmetria come Grok)
            let one = chance(0.2), right = Bool.random(using: &rng)
            blinkL = !one || !right; blinkR = !one || right
            at(.reopen, time + 0.12)
        case .reopen:
            blinkL = false; blinkR = false
            if chance(0.15) { at(.blink, time + 0.15) } else { after(.blink, blinkEvery) }
        case .glance:
            if activity == .peek {   // sbirciando: un'occhiata sola, poi si riaddormenta
                glanceAway(0.2...0.5)
            } else if chance(0.1) {   // ti aspetta: ogni tanto un occhiolino
                wink = Int.random(in: 0...1, using: &rng); at(.unwink, time + 0.35); after(.glance, 6...12)
            } else {   // guarda altrove, resta lì un poco, torna da te
                glanceAway(0.4...0.7); after(.glanceBack, 1.5...3); after(.glance, 6...12)
            }
        case .glanceBack: gx.target = 0.1; gy.target = -0.3
        case .unwink: wink = nil
        case .saccade:   // legge: un salto a destra; a fine riga torna a capo; con gli occhi alzati aspetta
            if lookingUp { at(.saccade, time + 0.5) }
            else if readX + 0.35 > 0.5 {   // a capo; il Monitor AI al lavoro con un piccolo inchino in avanti (spec §10)
                readX = -0.45; gx.target = readX; after(.saccade, 1.4...1.9)
                if input.mood == .work { tilt.target = 0.07; at(.bowEnd, time + 0.3) }
            }
            else {
                let jump = Double.random(in: 0.25...0.35, using: &rng)
                readX += jump; gx.target = readX
                after(.saccade, 1.2...1.8)
            }
        case .lookUp:   // alza gli occhi verso di te, poi torna a leggere
            lookingUp = true
            let x = Double.random(in: -0.1...0.3, using: &rng)
            gx.target = x; gy.target = -0.25
            after(.lookDown, 1.5...2.5); after(.lookUp, 15...25)
        case .lookDown: lookingUp = false; gx.target = readX; gy.target = 0.35
        case .shift:   // dormendo gli occhi chiusi si spostano appena
            let x = Double.random(in: -0.05...0.25, using: &rng), y = Double.random(in: 0.3...0.5, using: &rng)
            gx.target = x; gy.target = y
            after(.shift, 4...8)
        case .settle:   // si risistema: si piega un poco da una parte e ci resta
            let lean = Double.random(in: -0.04...0.04, using: &rng)
            tilt.target = lean; squash.v -= 0.3
            after(.settle, 40...80)
        case .z: zStart = time; after(.z, 30...40)
        case .hop: squash.target = 0.92; at(.kick, time + 0.08)   // si accuccia, poi stacca
        case .kick:
            if !input.pressed {   // premuta resta a terra (spec pillole-mascotte §2)
                squash.target = 1; squash.v += 1
                liftV = (2 * Self.gravity * (activity == .cheer ? 10 : 5)).squareRoot()
            }
            if activity == .cheer { hopsLeft -= 1; if hopsLeft > 0 { at(.hop, time + 0.55) } } else { after(.hop, 8...10) }
        case .tremble: let s = side(); tilt.v += 3.5 * s; after(.tremble, 3...5)
        case .bowEnd: tilt.target = 0
        // Il giro su se stessa, come Grok (spec sezione Mascotte §10): gli occhi fanno il giro della testa in un secondo
        // (mascotFigure), alla fine un saltellino. Solo al lavoro: se la funzione diventa Monitor di sistema la lettura
        // continua (stessa attività), i giri no.
        case .spin: if input.mood == .work { spinStart = time; at(.spinEnd, time + Self.spinTime) }
        case .spinEnd:
            spinStart = nil
            if !input.pressed { liftV = (2 * Self.gravity * 3).squareRoot() }   // premuta resta a terra (spec pillole-mascotte §2)
            if input.mood == .work { after(.spin, Self.spinGap) }
        }
    }

    // Gli occhi verso la forma dell'attività; occhiolino e ciglia sopra.
    private mutating func aim() {
        for i in eyes.indices {
            var p: EyePose
            switch activity {
            case .asleep: p = drowsy ? .half : .asleep
            case .peek: p = peekHalf ? .half : .open
            case .read, .call, .hover: p = .open
            case .cheer: p = .happy
            case .alarmed: p = .wide
            }
            if wink == i { p = .wink }
            if (i == 0 ? blinkL : blinkR), p.h > 6 { p.h = 1.25 }   // solo occhi aperti (gli archetti chiusi sono alti 4,4)
            eyes[i].aim(p)
        }
    }

    private mutating func glanceAway(_ r: ClosedRange<Double>) {
        gx.target = .random(in: r, using: &rng) * side()
        gy.target = .random(in: -0.2...0.3, using: &rng)
    }
    private mutating func at(_ g: Gesture, _ t: Double) { timers[g.rawValue] = t }
    private mutating func after(_ g: Gesture, _ r: ClosedRange<Double>) { timers[g.rawValue] = time + .random(in: r, using: &rng) }
    private mutating func chance(_ p: Double) -> Bool { .random(in: 0..<1, using: &rng) < p }
    private mutating func side() -> Double { Bool.random(using: &rng) ? 1 : -1 }
}
