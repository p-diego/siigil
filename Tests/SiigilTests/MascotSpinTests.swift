import CoreGraphics
import Foundation
import Testing
@testable import Siigil

// Il Monitor AI al lavoro fa un giro su se stesso ogni 25–45 s (spec §10): in 5 minuti fra 6 e 11 (un giro dura 1 s),
// con gli occhi che a metà sono dietro la testa e un saltellino alla fine; guardando un lavoro pesante (Monitor di
// sistema) mai.
@Test func spinsOnlyWhileWorking() {
    var life = MascotLife(kind: .mostro, seed: 3)
    let g = life.geometry
    var spins = 0, back = false, hopAfter = false, spinning = false, ended: Double?
    var t = 0.0
    live(&life, MascotInput(mood: .work, dot: true), 300) { look in
        t += 1.0 / 60
        back = back || (look.turn > 0 && mascotFigure(g, look).eyes.isEmpty)
        if spinning && look.turn == 0 { ended = t }
        if !spinning && look.turn > 0 { spins += 1 }
        spinning = look.turn > 0
        if let e = ended, t - e < 0.5, look.lift > 1 { hopAfter = true }
    }
    #expect(back && ended != nil && hopAfter && (6...11).contains(spins), "\(spins) giri")
    var watching = MascotLife(kind: .mostro, seed: 3), turned = false
    live(&watching, MascotInput(mood: .watch), 90) { turned = turned || $0.turn > 0 }
    #expect(!turned)
}

// Dal lavoro a guardare senza cambiare attività (la funzione diventa Monitor di sistema mentre legge): finito il giro in
// corso, niente più giri.
@Test func noSpinsOnceTheMoodIsNoLongerWork() {
    var life = MascotLife(kind: .mostro, seed: 3)
    let work = MascotInput(mood: .work, dot: true)
    #expect(live(&life, work, until: { $0.turn > 0 }) != nil && live(&life, work, until: { $0.turn == 0 }) != nil)
    live(&life, MascotInput(mood: .watch), 120) { #expect($0.turn == 0) }
}

// A ogni a capo della lettura un piccolo inchino in avanti (spec §10), solo al Monitor AI al lavoro: la mascotte si piega
// ben oltre l'ondeggio (al più 0,045 rad da sveglia), che è tutto quello che fa leggendo come Monitor di sistema.
@Test func bowsAtLineReturnsOnlyWhileWorking() {
    func tilt(_ mood: MascotMood) -> Double {
        var life = MascotLife(kind: .mirtillo, seed: 2), most = 0.0
        live(&life, MascotInput(mood: mood, dot: true), 40) { most = max(most, $0.tilt) }
        return most
    }
    #expect(tilt(.work) > 0.08 && tilt(.watch) < 0.06, "al lavoro \(tilt(.work)), a guardare \(tilt(.watch))")
}

// Il giro si fa con gli occhi (spec §10, come Grok), con ogni forma: sagoma e pallino restano quelli di sempre; gli occhi
// partono verso il davanti, a metà giro sono dietro tutti e due e a giro finito la figura è quella di sempre, senza
// scatti né all'inizio né alla fine.
@Test func theSpinIsMadeWithTheEyes() {
    for shape in MascotKind.allCases {
        let g = MascotGeometry.of(shape)
        var still = MascotLook(); still.left = .open; still.right = .open; still.dot = 1; still.gazeX = -0.45; still.gazeY = 0.35
        let plain = mascotFigure(g, still), boxes = plain.eyes.map(\.boundingBoxOfPath)
        func spun(_ turn: Double) -> MascotFigure { var look = still; look.turn = turn; return mascotFigure(g, look) }
        for turn in stride(from: 0.05, to: 1, by: 0.05) {
            #expect(spun(turn).body == plain.body && spun(turn).dot == plain.dot, "\(shape) a \(turn): la sagoma e il pallino non girano")
        }
        #expect(spun(0.5).eyes.isEmpty, "\(shape) a metà giro")
        #expect(spun(1).eyes == plain.eyes, "\(shape) a giro finito")
        let early = spun(0.08).eyes.map(\.boundingBoxOfPath)
        #expect(early.count == 2 && zip(early, boxes).allSatisfy { $0.midX > $1.midX + 1 }, "\(shape) verso il davanti")
        for turn in [0.0005, 0.9995] {   // vicino all'inizio e alla fine: dove erano
            let near = spun(turn).eyes.map(\.boundingBoxOfPath)
            #expect(near.count == 2 && zip(near, boxes).allSatisfy { abs($0.minX - $1.minX) < 0.2 && abs($0.maxX - $1.maxX) < 0.2 }, "\(shape) a \(turn)")
        }
    }
}

// Anche agli estremi dei cursori di ogni forma, con occhi grandi che da fermi stanno oltre il cilindro della testa, il giro
// parte e finisce dalla figura ferma: al primo e all'ultimo istante gli occhi sono dove erano, senza scatti.
@Test func theSpinStartsAndEndsFromTheStillFigureAtEveryExtreme() {
    for shape in MascotKind.allCases {
        for eyes in extremes(shape) {
            let g = MascotGeometry.of(shape, eyes)
            for gx in [-1.0, 0, 1] {
                var still = MascotLook(); still.left = .open; still.right = .open; still.dot = 1; still.gazeX = gx
                still.leftShift = CGVector(dx: -1, dy: -0.5); still.rightShift = CGVector(dx: 1, dy: 0.5)
                let boxes = mascotFigure(g, still).eyes.map(\.boundingBoxOfPath)
                for turn in [0.0005, 0.9995] {
                    var look = still; look.turn = turn
                    let near = mascotFigure(g, look).eyes.map(\.boundingBoxOfPath)
                    let jump = near.count == 2 ? zip(near, boxes).map { max(abs($0.minX - $1.minX), abs($0.maxX - $1.maxX)) }.max()! : .infinity
                    #expect(jump < 0.2, "\(shape) \(eyes) sguardo \(gx) a \(turn): gli occhi saltano di \(jump)")
                }
            }
        }
    }
}

// Review Focus: l'agente che ti aspetta (o finisce) a metà giro non lascia la mascotte senza occhi: il giro si interrompe
// e gli occhi tornano davanti.
@Test func aMoodChangeInTheMiddleOfASpinEndsIt() throws {
    var life = MascotLife(kind: .drop, seed: 3)
    try #require(live(&life, MascotInput(mood: .work, dot: true), until: { $0.turn >= 0.3 }) != nil)
    live(&life, MascotInput(mood: .wait, dot: true), 1)
    #expect(life.look.turn == 0 && mascotFigure(life.geometry, life.look).eyes.count == 2)
    live(&life, MascotInput(mood: .wait, dot: true), 60) { #expect($0.turn == 0) }   // e aspettando non gira
}
