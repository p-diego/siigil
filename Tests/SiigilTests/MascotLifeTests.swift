import CoreGraphics
import Foundation
import Testing
@testable import Siigil

// `seconds` secondi a passi di 1/60 s (come la vista) con lo stesso ingresso; `each` vede ogni istante.
func live(_ life: inout MascotLife, _ input: MascotInput, _ seconds: Double, each: (MascotLook) -> Void = { _ in }) {
    for _ in 0..<Int((seconds * 60).rounded()) { life.advance(1.0 / 60, input: input); each(life.look) }
}

// A passi di 1/60 s finché `done`, al più 60 secondi: quanti ce ne sono voluti, nil se non ci è arrivata (un test
// che aspetta un gesto non gira per sempre se il gesto non viene).
func live(_ life: inout MascotLife, _ input: MascotInput, until done: (MascotLook) -> Bool) -> Double? {
    var t = 0.0
    while !done(life.look) {
        guard t < 60 else { return nil }
        life.advance(1.0 / 60, input: input); t += 1.0 / 60
    }
    return t
}

// Ridisegni al secondo in media in 10 minuti di uno stato, coi due ritmi della vista (15 immagini al secondo per il fondo,
// 60 nei gesti) e la regola `shouldRedraw`.
func redrawsPerSecond(_ kind: MascotKind, _ input: MascotInput) -> Double {
    var life = MascotLife(kind: kind, seed: 7)
    life.advance(5, input: input)   // passato l'ingresso nello stato
    var drawn = life.look, count = 0, t = 0.0
    while t < 600 {
        let dt = 1 / (life.fastFrames ? MascotLife.fastFPS : MascotLife.calmFPS)
        life.advance(dt, input: input); t += dt
        if shouldRedraw(drawn, life) { drawn = life.look; count += 1 }
    }
    return Double(count) / 600
}

@Test func springsSettleWithoutOvershootWhenCriticallyDamped() {
    var s = MascotSpring(0, omega: 20); s.target = 1
    var peak = 0.0
    for _ in 0..<240 { s.step(1.0 / 120); peak = max(peak, s.x) }
    #expect(peak <= 1.001 && s.still(0.001))
    var b = MascotSpring(0, omega: 20, zeta: 0.4); b.target = 1
    peak = 0
    for _ in 0..<240 { b.step(1.0 / 120); peak = max(peak, b.x) }
    #expect(peak > 1.1)   // sotto lo smorzamento critico molleggia
}

@Test func visibleDistanceIsInPoints() {
    let a = MascotLook()
    #expect(visibleDistance(a, a, .of(.mostro)) == 0)
    var b = a; b.gazeX = 1
    #expect(abs(visibleDistance(a, b, .of(.mirtillo)) - MascotGeometry.of(.mirtillo).faceX * 0.27) < 1e-9)   // lo sguardo da 0 a 1 sposta la faccia di faceX
    b = a; b.z = 0.5
    #expect(visibleDistance(a, b, .of(.mostro)) == .infinity)   // la "z" che compare si disegna sempre
}

// Nel giro (spec §10) gli occhi scorrono attorno alla testa: visibleDistance non conta mai meno di quanto si spostano i loro
// bordi, e quando uno va dietro o torna è comunque un cambio da disegnare. Con la forma più larga, a passi di un centesimo.
@Test func visibleDistanceSeesTheEyesGoAround() {
    let g = MascotGeometry.of(.capsule)
    var a = MascotLook(); a.left = .open; a.right = .open; a.gazeX = -0.45
    for turn in stride(from: 0.0, to: 1, by: 0.01) {
        a.turn = turn
        var b = a; b.turn = turn + 0.01
        let ea = mascotFigure(g, a).eyes.map(\.boundingBoxOfPath), eb = mascotFigure(g, b).eyes.map(\.boundingBoxOfPath)
        let d = visibleDistance(a, b, g)
        if ea.count != eb.count { #expect(d >= visibleStep, "\(turn)"); continue }
        let moved = zip(ea, eb).map { max(abs($0.minX - $1.minX), abs($0.maxX - $1.maxX)) }.max() ?? 0
        #expect(moved * 0.27 <= d, "\(turn): gli occhi si spostano di \(moved * 0.27) pt, visti \(d)")
    }
}

@Test func sleepsThenPeeksAfterThirtySecondsThenSleepsAgain() {
    var life = MascotLife(kind: .mostro, seed: 1)
    let calm = MascotInput(mood: .sleep)
    live(&life, calm, 29)
    #expect(life.look.left.bend < -0.9 && life.look.left.h < 5)     // occhi chiusi ad archetto in giù (alti 4,4)
    live(&life, calm, 1.5)
    #expect(life.look.left.h > 10)                                   // a 30 s apre gli occhi
    live(&life, calm, 3)
    #expect(life.look.left.bend < -0.9)                              // e si riaddormenta
}

// Una sbirciata interrotta non resta in sospeso (spec: "torna a dormire come oggi", "se dormiva, si riaddormenta"): se nel
// mezzo arrivano il lavoro, il puntatore o un "ha finito", tornata a dormire la mascotte non riapre gli occhi.
@Test func aPeekCutShortLeavesNoPeekBehind() {
    let sleep = MascotInput(mood: .sleep)
    let cuts: [(MascotInput, Double)] = [(MascotInput(mood: .work), 3), (MascotInput(mood: .sleep, hover: CGPoint(x: 85, y: 60)), 1),
                                         (MascotInput(mood: .done, dot: true), 2.5)]   // la festa dura 2,4 s
    for (cut, seconds) in cuts {
        var life = MascotLife(kind: .mostro, seed: 1)
        var waited = 0.0
        while life.look.left.h < 10 && waited < 40 { live(&life, sleep, 1.0 / 60); waited += 1.0 / 60 }   // il primo risveglio è a 30 s
        #expect(life.look.left.h > 10, "\(cut): non sbircia")
        live(&life, cut, seconds)
        live(&life, sleep, 1.5)
        #expect(life.look.left.bend < -0.9 && life.look.left.h < 5, "\(cut): di nuovo occhi aperti (altezza \(life.look.left.h))")
    }
}

// Mostro e Mirtillo non respirano insieme (spec §2, fasi a caso): il primo respiro parte da un punto diverso per ogni vita,
// non sempre da zero (l'altezza all'avvio sarebbe la stessa per tutte).
@Test func eachLifeStartsBreathingAtItsOwnPoint() {
    let heights = Set((1...20).map { MascotLife(kind: .mostro, seed: $0).look.squash })
    #expect(heights.count > 10, "solo \(heights.count) altezze diverse su 20 vite")
}

@Test func readsWithEyesDownMovingRightThenBack() {
    var life = MascotLife(kind: .mirtillo, seed: 2)
    var xs: [Double] = [], hs: [Double] = []
    live(&life, MascotInput(mood: .work, dot: true), 12) { xs.append($0.gazeX); hs.append($0.left.h) }
    #expect(life.look.gazeY > 0.25 && hs.suffix(60).max()! > 12)   // occhi aperti (anche se l'ultimo istante cade in un battito)
    #expect(xs.max()! > 0.2 && xs.suffix(600).min()! < -0.4)   // va a destra e torna a capo
    #expect(life.look.dot > 0.95)
}

@Test func waitingLooksAtYouAndHops() {
    var life = MascotLife(kind: .mostro, seed: 3)
    var lifted = 0.0
    live(&life, MascotInput(mood: .wait, dot: true), 1) { lifted = max(lifted, $0.lift) }
    #expect(lifted > 3)   // il saltellino subito, per chiamarti
    #expect(life.look.gazeY < -0.1 && life.look.left.h > 12)
}

@Test func doneCheersOnceThenSleeps() {
    var life = MascotLife(kind: .mostro, seed: 4)
    let done = MascotInput(mood: .done, dot: true)
    var lifted = 0.0, sparkled = false
    live(&life, done, 1) { lifted = max(lifted, $0.lift); sparkled = sparkled || $0.sparkle != nil }
    #expect(lifted > 7 && sparkled && life.look.left.bend > 0.8)   // due saltelli, scintille, occhi felici
    live(&life, done, 3)
    #expect(life.look.left.bend < -0.9 && life.look.dot > 0.95)     // poi dorme, il pallino resta
    lifted = 0
    live(&life, done, 5) { lifted = max(lifted, $0.lift) }
    #expect(lifted == 0)                                            // stesso "ha finito": niente altri saltelli
    live(&life, MascotInput(mood: .sleep), 0.5)
    live(&life, done, 1) { lifted = max(lifted, $0.lift) }
    #expect(lifted > 7)                                             // un "ha finito" nuovo salta di nuovo
}

@Test func alarmWidensTheEyes() {
    var life = MascotLife(kind: .mirtillo, seed: 5)
    live(&life, MascotInput(mood: .alarm, dot: true), 1)
    #expect(life.look.left.h > 16.8 && life.look.right.w > 7.8)
}

@Test func hoverWakesAndLooksAtThePointerThenSleeps() {
    var life = MascotLife(kind: .mostro, seed: 6)
    live(&life, MascotInput(mood: .sleep), 2)
    live(&life, MascotInput(mood: .sleep, hover: CGPoint(x: 85, y: 60)), 1)
    #expect(life.look.left.h > 12 && life.look.gazeX > 0.8)
    live(&life, MascotInput(mood: .sleep), 1.5)
    #expect(life.look.left.bend < -0.9)
}

// Il puntatore all'altezza degli occhi non sposta lo sguardo in su né in giù, per ogni mascotte; più sotto, guarda giù.
@Test func hoverAimsFromTheEyeHeight() {
    for (kind, y) in [(MascotKind.mostro, 50.32), (.mirtillo, 62.72)] {
        var life = MascotLife(kind: kind, seed: 3)
        live(&life, MascotInput(mood: .sleep, hover: CGPoint(x: 50, y: y)), 2)
        #expect(abs(life.look.gazeY) < 0.02, "\(kind) \(life.look.gazeY)")
        live(&life, MascotInput(mood: .sleep, hover: CGPoint(x: 50, y: y + 12.5)), 2)
        #expect(abs(life.look.gazeY - 0.5) < 0.02, "\(kind) \(life.look.gazeY)")
    }
}

@Test func stopsMovingBetweenGestures() {
    var life = MascotLife(kind: .mostro, seed: 7)
    live(&life, MascotInput(mood: .sleep), 2.5)   // prima della prima "z" e del primo spostamento degli occhi chiusi (4–8 s)
    #expect(!life.moving && life.nextEventIn > 0 && life.nextEventIn < 6)
}

// Dopo ogni gesto la fisica si ferma: il displayLink resta acceso e `moving` (con `fastFrames`) sceglie solo fra 60 e 15
// immagini al secondo, ma se non tornasse falso la vista resterebbe a 60 per sempre. In ogni stato, 2 minuti a 60 Hz: il
// tratto più lungo di `moving` di fila sta sotto gli 8 s (misurato l'11/10: al massimo ~1,6 s al lavoro, il giro su se
// stessa col saltellino; ~0,9 s in allarme; se le molle non si assestassero mai sarebbero tutti i 120).
@Test func everyStateSettlesBetweenGestures() {
    for kind in [MascotKind.mostro, .mirtillo] {
        for mood in [MascotMood.sleep, .work, .wait, .done, .watch, .alarm] {
            var life = MascotLife(kind: kind, seed: 7)
            let input = MascotInput(mood: mood, dot: mood != .sleep)
            life.advance(5, input: input)   // passato l'ingresso nello stato
            var run = 0.0, longest = 0.0
            for _ in 0..<(120 * 60) {
                life.advance(1.0 / 60, input: input)
                run = life.moving ? run + 1.0 / 60 : 0
                longest = max(longest, run)
            }
            #expect(longest < 8, "\(kind) \(mood): in movimento \(longest) s di fila")
        }
    }
}

@Test func sameSeedSameLife() {
    func run(_ seed: UInt64) -> [MascotLook] {
        var life = MascotLife(kind: .mirtillo, seed: seed), out: [MascotLook] = []
        for mood in [MascotMood.sleep, .watch, .alarm, .sleep] {
            live(&life, MascotInput(mood: mood, dot: mood == .alarm), 15) { out.append($0) }
        }
        return out
    }
    #expect(run(9) == run(9) && run(9) != run(10))
}

// Review Focus 1: il Mac che si risveglia dopo un'ora.
@Test func longPausesSkipAheadWithoutPhysics() {
    var life = MascotLife(kind: .mostro, seed: 8)
    let start = Date()
    life.advance(3600, input: MascotInput(mood: .sleep))
    // largo: i test girano in parallelo e senza ottimizzazioni; un'ora di fisica piena a 120 Hz starebbe ben sopra
    #expect(Date().timeIntervalSince(start) < 5 && abs(life.time - 3600) < 0.01)
    #expect(life.look.left.bend < -0.9 || life.look.left.h > 10)   // un istante valido: dorme o sbircia
}

// Review Focus 2: stati che cambiano in due fotogrammi, a metà dell'accucciata del primo saltellino.
@Test func flappingMoodsLeaveNoTrace() {
    var life = MascotLife(kind: .mostro, seed: 11)
    live(&life, MascotInput(mood: .wait, dot: true), 0.35)
    var lifted = 0.0
    live(&life, MascotInput(mood: .work, dot: true), 1.0 / 60) { lifted = max(lifted, $0.lift) }
    live(&life, MascotInput(mood: .wait, dot: true), 1.0 / 60) { lifted = max(lifted, $0.lift) }
    live(&life, MascotInput(mood: .work, dot: true), 3) { lifted = max(lifted, $0.lift) }
    // niente accucciata rimasta (0,92) né saltello partito dopo; il respiro sposta l'altezza al più di 0,023
    #expect(abs(life.look.squash - 1) < 0.03 && lifted == 0 && life.look.dot > 0.95)
}

// Budget dei ridisegni (spec §5, rivisto il 10/10): ogni ridisegno della barra costa ~1 % al WindowServer; oggi 7 al
// secondo sempre. Dormendo (lo stato più frequente) meno di 5, da sveglia meno di 10: per ogni forma, col giro su se stessa
// e l'inchino del Monitor AI al lavoro (spec sezione Mascotte §10).
@Test func redrawBudget() {
    for kind in MascotKind.allCases {
        let sleep = redrawsPerSecond(kind, MascotInput(mood: .sleep))
        #expect(sleep < 5, "\(kind) dorme: \(sleep)")
        for mood in [MascotMood.work, .wait, .done, .watch, .alarm] {
            let r = redrawsPerSecond(kind, MascotInput(mood: mood, dot: true))
            #expect(r < 10, "\(kind) \(mood): \(r)")
        }
    }
}

// A riposo non sta mai ferma (spec §2, 10/10): dormendo, leggendo, aspettando e in allarme il disegno cambia di almeno un
// decimo di punto almeno ogni 3 s (la vista a 15 immagini al secondo). Dormendo è lo stato più calmo, e il caso non deve
// contare: vale per trenta semi diversi, da sveglia per dieci.
@Test func neverStillAtRest() {
    for kind in [MascotKind.mostro, .mirtillo] {
        for mood in [MascotMood.sleep, .work, .wait, .alarm] {
            for seed in 1...(mood == .sleep ? 30 : 10) {
                var life = MascotLife(kind: kind, seed: UInt64(seed))
                let input = MascotInput(mood: mood, dot: mood != .sleep)
                life.advance(5, input: input)
                var drawn = life.look, still = 0.0, longest = 0.0
                for _ in 0..<(120 * 15) {
                    life.advance(1.0 / 15, input: input)
                    still += 1.0 / 15
                    if visibleDistance(drawn, life.look, .of(kind)) >= visibleStep { drawn = life.look; still = 0 }
                    longest = max(longest, still)
                }
                #expect(longest < 3, "\(kind) \(mood) seme \(seed): ferma \(longest) s")
            }
        }
    }
}

// Un'asimmetria come Grok: leggendo (dove non fa occhiolini) ogni tanto il battito è di un occhio solo.
@Test func blinksSometimesWithOneEye() {
    var life = MascotLife(kind: .mostro, seed: 5)
    var one = false
    live(&life, MascotInput(mood: .work, dot: true), 180) {
        one = one || (min($0.left.h, $0.right.h) < 3 && max($0.left.h, $0.right.h) > 10)
    }
    #expect(one)
}

// Si addormenta ciondolando (spec §2): smette di leggere → occhi a metà e testa che cade, poi occhi chiusi.
@Test func nodsOffWhenFallingAsleep() {
    var life = MascotLife(kind: .mirtillo, seed: 6)
    live(&life, MascotInput(mood: .work), 3)
    var half = false, dropped = false
    live(&life, MascotInput(mood: .sleep), 0.6) { half = half || $0.left.lid > 0.3; dropped = dropped || $0.squash < 0.98 }
    #expect(half && dropped)
    live(&life, MascotInput(mood: .sleep), 1.5)
    #expect(life.look.left.bend < -0.9)
}

// Il respiro cambia: dormendo, in tre minuti, almeno un sospiro (profondo quasi il doppio di un respiro normale).
@Test func breathingVariesAndSighs() {
    var life = MascotLife(kind: .mostro, seed: 8)
    var peaks: [Double] = [], prev = life.look.squash, rising = false
    live(&life, MascotInput(mood: .sleep), 180) {
        if $0.squash < prev, rising { peaks.append(prev) }
        rising = $0.squash > prev; prev = $0.squash
    }
    #expect(peaks.count >= 12 && peaks.max()! > 1.039, "colmi \(peaks.count), il più alto \(peaks.max() ?? 0)")
}

// Dormendo ogni 40–80 s si risistema (spec §2): si piega un poco da una parte e ci resta fino al prossimo risveglio.
// L'ondeggio dormendo ha un'onda da 12,6 s che in una finestra intera si cancella e una da 37 s che ne lascia al più
// 0,0074 rad: una piega di 0,015 rad o più si vede come media dell'inclinazione su 12,6 s. In 15 minuti, su 300 semi,
// la piega più grande non scende mai sotto 0,02 rad (senza la risistemata resta a 0,0074).
@Test func settlesIntoALeanWhileAsleep() {
    var life = MascotLife(kind: .mostro, seed: 2)
    var tilts: [Double] = []
    live(&life, MascotInput(mood: .sleep), 900) { tilts.append($0.tilt) }
    let n = 756   // 12,6 s a 60 Hz
    var sum = tilts[..<n].reduce(0, +), best = abs(sum) / Double(n)
    for i in n..<tilts.count { sum += tilts[i] - tilts[i - n]; best = max(best, abs(sum) / Double(n)) }
    #expect(best > 0.015, "piega più grande \(best) rad")
}

// Il pallino cambia colore mentre è fuori (MascotNSView conta su questo): la sfumatura riparte da zero e finché dura tiene
// `moving` acceso (60 immagini al secondo), poi si assesta e la vista torna ai 15. Dormendo i primi 4 s sono senza gesti
// (la prima "shift" è fra 4 e 8 s): ferma prima, in movimento subito dopo il cambio, ferma a sfumatura finita.
@Test func dotColorChangeRestartsTheFadeAndSettles() {
    var life = MascotLife(kind: .mostro, seed: 7)
    let input = MascotInput(mood: .sleep, dot: true)
    live(&life, input, 1.5)   // il pallino è uscito e le molle sono ferme
    #expect(life.look.dot > 0.95 && life.look.dotFade > 0.99 && !life.moving)
    life.dotColorChanged()
    #expect(life.look.dotFade == 0 && life.moving)   // riparte dal colore di prima
    live(&life, input, 2)
    #expect(life.look.dotFade > 0.99 && !life.moving)   // a 3,5 s: sfumato, e nient'altro tiene acceso il movimento
}

// Premuta (spec pillole-mascotte §2): si schiaccia sotto l'85 % in 0,2 s, lasciata rimbalza oltre com'era e torna; non
// si sveglia. Due vite con lo stesso seme, una premuta e una no: la differenza è solo la molla del corpo.
@Test func pressingSquashesAndLettingGoBounces() {
    var pressed = MascotLife(kind: .mostro, seed: 1), still = MascotLife(kind: .mostro, seed: 1)
    let rest = MascotInput(mood: .sleep), down = MascotInput(mood: .sleep, pressed: true)
    for _ in 0..<12 { pressed.advance(1.0 / 60, input: down); still.advance(1.0 / 60, input: rest) }
    #expect(pressed.look.squash - still.look.squash < -0.15)
    #expect(pressed.look.left.h < 6 && pressed.look.right.h < 6)   // dorme ancora: occhi chiusi
    var bounce = 0.0
    for _ in 0..<30 {
        pressed.advance(1.0 / 60, input: rest); still.advance(1.0 / 60, input: rest)
        bounce = max(bounce, pressed.look.squash - still.look.squash)
    }
    #expect(bounce > 0.03)   // il rimbalzo
    for _ in 0..<30 { pressed.advance(1.0 / 60, input: rest); still.advance(1.0 / 60, input: rest) }
    #expect(abs(pressed.look.squash - still.look.squash) < 0.01)
}

// Review Focus 2: l'umore cambia mentre la tieni premuta (un agente parte): resta schiacciata.
@Test func staysSquashedWhenTheMoodChangesWhilePressed() {
    var life = MascotLife(kind: .mostro, seed: 2)
    live(&life, MascotInput(mood: .sleep, pressed: true), 0.3)
    live(&life, MascotInput(mood: .work, pressed: true), 0.5)
    #expect(life.look.squash < 0.85)
}

// Quattro clic veloci (ognuno entro mezzo secondo dal precedente) fanno partire una reazione; tre no, lenti no.
@Test func fourQuickClicksStartAReaction() {
    func reacts(every gap: Double, clicks: Int = 4) -> Bool {
        var life = MascotLife(kind: .squircle, seed: 3), seen = false
        live(&life, MascotInput(mood: .sleep), 1)
        for _ in 0..<clicks {
            live(&life, MascotInput(mood: .sleep, pressed: true), 0.1) { if $0.heart != nil || $0.dizzy != nil { seen = true } }
            live(&life, MascotInput(mood: .sleep), gap) { if $0.heart != nil || $0.dizzy != nil { seen = true } }
        }
        return seen
    }
    #expect(reacts(every: 0.3))
    #expect(!reacts(every: 0.3, clicks: 3))
    #expect(!reacts(every: 0.7))
}

// Cuore o spirale, 50 e 50 (prova G1): su 200 semi ciascuno fra il 35 e il 65 %.
@Test func heartAndSpiralComeHalfAndHalf() {
    var hearts = 0
    for seed in UInt64(0)..<200 {
        var life = MascotLife(kind: .mostro, seed: seed)
        for _ in 0..<4 { live(&life, MascotInput(mood: .work, pressed: true), 0.05); live(&life, MascotInput(mood: .work), 0.1) }
        #expect(life.look.heart != nil || life.look.dizzy != nil, "seme \(seed)")
        if life.look.heart != nil { hearts += 1 }
    }
    #expect((70...130).contains(hearts))
}

// Una reazione alla volta: durante una, altri 4 clic non ne fanno partire un'altra (e non contano dopo); finita, sparisce.
// Durante la reazione la vista va a 60 immagini al secondo.
@Test func oneReactionAtATimeThenItEnds() {
    var life = MascotLife(kind: .mostro, seed: 5)
    func clicks(_ n: Int) {
        for _ in 0..<n { live(&life, MascotInput(mood: .sleep, pressed: true), 0.05); live(&life, MascotInput(mood: .sleep), 0.1) }
    }
    clicks(4)
    let wasHeart = life.look.heart != nil, start = life.look.heart ?? life.look.dizzy!
    #expect(life.fastFrames)
    clicks(4)
    #expect((life.look.heart != nil) == wasHeart && (life.look.dizzy != nil) == !wasHeart)
    #expect((life.look.heart ?? life.look.dizzy!) > start)   // la stessa, andata avanti
    live(&life, MascotInput(mood: .sleep), 2)
    #expect(life.look.heart == nil && life.look.dizzy == nil)
    clicks(1)   // i clic fatti durante la reazione non contano: uno solo non basta
    #expect(life.look.heart == nil && life.look.dizzy == nil)
}

// Cuore e spirale che compaiono si disegnano sempre (come la "z").
@Test func reactionsAlwaysRedraw() {
    var a = MascotLook(); a.heart = 0.5
    #expect(visibleDistance(MascotLook(), a, .of(.mostro)) == .infinity)
    a = MascotLook(); a.dizzy = 0.5
    #expect(visibleDistance(MascotLook(), a, .of(.mostro)) == .infinity)
}

// Premuta resta a terra (spec pillole-mascotte §2): "ti aspetta" saltella dopo 0,3 s, ma tenuta premuta non si stacca.
@Test func heldMascotStaysOnTheGround() {
    var life = MascotLife(kind: .mostro, seed: 4), highest = 0.0
    live(&life, MascotInput(mood: .wait, pressed: true), 1.5) { highest = max(highest, $0.lift) }
    #expect(highest == 0)
    var free = MascotLife(kind: .mostro, seed: 4), freeHighest = 0.0
    live(&free, MascotInput(mood: .wait), 1.5) { freeHighest = max(freeHighest, $0.lift) }
    #expect(freeHighest > 3)   // senza premerla il saltello c'è
}
