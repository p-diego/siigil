import CoreGraphics
import Foundation
import Testing
@testable import Siigil

// Gli estremi dei tre cursori degli occhi di una forma (spec §10, EyeRanges), più il centro.
func extremes(_ shape: MascotKind) -> [EyeSettings] {
    let r = EyeRanges.of(shape)
    return [EyeSettings()] + r.sizes.bounds.flatMap { size in
        r.lifts.bounds.flatMap { lift in r.spreads.bounds.map { EyeSettings(size: size, lift: lift, spread: $0) } }
    }
}
private extension ClosedRange where Bound == Double { var bounds: [Double] { [lowerBound, upperBound] } }

// Gli angoli della scatola di ogni occhio stanno dentro la sagoma.
private func expectEyesInside(_ shape: MascotKind, _ g: MascotGeometry, _ look: MascotLook, _ why: String) {
    for eye in mascotFigure(g, look).eyes where !inside(shape.body, eye.boundingBoxOfPath) { Issue.record("\(why): occhio fuori") }
}

// Mostro e Mirtillo coi cursori al centro restano quelli di oggi: occhi alla stessa altezza e distanza, la faccia che scorre
// di 17,5 e 21,5 di lato e di 6 in su e in giù, il pallino allo stesso posto.
@Test func todaysTwoShapesKeepTodaysLook() {
    let mostro = MascotGeometry.of(.mostro), mirtillo = MascotGeometry.of(.mirtillo)
    #expect(abs(mostro.eyeY - 50.32) < 1e-9 && mostro.eyeGap == 12.6 && mostro.faceX == 17.5 && mostro.faceY == 6)
    #expect(abs(mirtillo.eyeY - 62.72) < 1e-9 && mirtillo.eyeGap == 11 && mirtillo.faceX == 21.5 && mirtillo.faceY == 6)
    #expect(abs(mostro.shape.dotCenter.x - 84.192) < 0.001 && abs(mostro.shape.dotCenter.y - 78.577) < 0.001, "\(mostro.shape.dotCenter)")
    #expect(abs(mirtillo.shape.dotCenter.x - 88.314) < 0.001 && abs(mirtillo.shape.dotCenter.y - 80.937) < 0.001, "\(mirtillo.shape.dotCenter)")
}

// Lo scorrimento della faccia di tutte e nove le forme coi cursori al centro, ricavato dalla sagoma: fissato, così un
// cambio alla regola degli occhi (eyePlace, dotNudge) non sposta niente senza che un test lo dica.
@Test func everyShapeKeepsItsFaceScroll() {
    let sideways: [MascotKind: Double] = [.mostro: 17.5, .mirtillo: 21.5, .ball: 10, .pebble: 14, .squircle: 13.5, .capsule: 24.5,
                                          .hexagon: 13, .cloud: 19, .drop: 20.5]
    for shape in MascotKind.allCases {
        let g = MascotGeometry.of(shape)
        #expect(g.faceX == sideways[shape] && g.faceY == 6, "\(shape): \(g.faceX) di lato, \(g.faceY) in su e in giù")
    }
}

// Review Focus: in ogni forma, a ogni estremo dei cursori, gli occhi restano dentro la sagoma con lo sguardo su tutta la
// griglia, in ogni posa e con la deriva piena; e anche quando fanno posto al pallino (come eyesMakeRoomForTheDot).
@Test func everyShapeKeepsItsEyesInsideAtEveryExtreme() {
    for shape in MascotKind.allCases {
        for eyes in extremes(shape) {
            let g = MascotGeometry.of(shape, eyes)
            for gx in stride(from: -1.0, through: 1, by: 0.25) {
                for gy in stride(from: -1.0, through: 1, by: 0.5) {
                    for pose in eyePoses {
                        // Senza pallino la deriva piena va dove guarda; col pallino fuori (anche dormendo e festeggiando lo
                        // è) l'occhio di destra è spinto verso il pallino e quello di sinistra dall'altra parte.
                        for dot in [0.0, 1] {
                            var look = MascotLook(); look.gazeX = gx; look.gazeY = gy; look.left = pose; look.right = pose; look.dot = dot
                            let drift = CGVector(dx: gx < 0 ? -1 : 1, dy: gy < 0 ? -0.5 : 0.5)
                            look.leftShift = dot == 0 ? drift : CGVector(dx: -1, dy: -0.5)
                            look.rightShift = dot == 0 ? drift : CGVector(dx: 1, dy: 0.5)
                            expectEyesInside(shape, g, look, "\(shape) \(eyes) sguardo \(gx) \(gy) \(pose) pallino \(dot)")
                        }
                    }
                }
            }
        }
    }
}

// Nel giro su se stessa (spec §10) gli occhi non escono mai dalla sagoma: ogni forma, ogni estremo dei cursori, lo sguardo
// agli estremi, la deriva piena, col pallino e senza, a ogni ventesimo di giro.
@Test func everyShapeKeepsItsEyesInsideWhileSpinning() {
    for shape in MascotKind.allCases {
        for eyes in extremes(shape) {
            let g = MascotGeometry.of(shape, eyes)
            for gx in [-1.0, 0, 1] {
                for gy in [-1.0, 1] {
                    for pose in [EyePose.open, .wide] {
                        for dot in [0.0, 1] {
                            var look = MascotLook(); look.gazeX = gx; look.gazeY = gy; look.left = pose; look.right = pose; look.dot = dot
                            let drift = CGVector(dx: gx < 0 ? -1 : 1, dy: gy < 0 ? -0.5 : 0.5)
                            look.leftShift = drift; look.rightShift = drift
                            for turn in stride(from: 0.05, to: 1, by: 0.05) {
                                look.turn = turn
                                expectEyesInside(shape, g, look, "\(shape) \(eyes) sguardo \(gx) \(gy) \(pose) pallino \(dot) giro \(turn)")
                            }
                        }
                    }
                }
            }
        }
    }
}

// Ogni forma sta nella tela come le due di oggi: poggia a terra (90), non esce dalla tela, il pallino (spec §3, 10/10) manca
// a 0 e a 1 sta sul bordo in basso verso il davanti (centro appena fuori, cerchio sul bordo, anche col rimbalzo dentro la
// tela, bordino compreso) e "z" e scintille si disegnano dentro la tela.
@Test func everyShapeSitsInTheCanvas() {
    for shape in MascotKind.allCases {
        let g = MascotGeometry.of(shape), b = shape.body.boundingBoxOfPath
        #expect(abs(b.maxY - 90) < 1e-6 && b.minY >= 15 && b.minX >= 4 && b.maxX <= 96, "\(shape) \(b)")   // a terra
        var look = MascotLook(); look.dot = 0
        #expect(mascotFigure(g, look).dot == nil, "\(shape) pallino a 0")   // sparito a 0
        look.dot = 1
        let dot = mascotFigure(g, look).dot!.boundingBoxOfPath
        #expect(!shape.body.contains(shape.dotCenter) && shape.body.contains(CGPoint(x: dot.minX + 2, y: dot.midY)), "\(shape) pallino")
        look.dot = 1.13
        let big = mascotFigure(g, look).dot!.boundingBoxOfPath.insetBy(dx: -3.7, dy: -3.7)
        #expect(big.maxX <= 108.3 && big.maxY <= 100, "\(shape) \(big)")
        look = MascotLook(); look.z = 1; look.sparkle = 0.5
        let fig = mascotFigure(g, look)
        for p in [fig.z!, fig.sparkles!] {
            let r = p.boundingBoxOfPath
            #expect(r.minX >= -8.3 && r.maxX <= 108.3 && r.minY >= 0 && r.maxY <= 100, "\(shape) \(r)")
        }
    }
}

// Gli intervalli dei cursori degli occhi di ogni forma (EyeRanges, autore 11/10): dentro i limiti, col centro; ogni
// combinazione tiene gli occhi dentro da fermi (anche dentro la scatola: ogni unità d'altezza, grandezza e distanza agli
// estremi e a metà); un passo oltre ogni lato, dove non è il limite, non sta più.
@Test func eyeRangesAreTheWidestThatFit() {
    func fits(_ s: Double, _ l: Double, _ p: Double, _ shape: MascotKind) -> Bool { eyesFitAtRest(shape, EyeSettings(size: s, lift: l, spread: p)) }
    for shape in MascotKind.allCases {
        let r = EyeRanges.of(shape)
        #expect(r.sizes.contains(1) && r.lifts.contains(0) && r.spreads.contains(1), "\(shape)")
        #expect(r.sizes.lowerBound >= 0.5 && r.sizes.upperBound <= 2 && r.lifts.lowerBound >= -15 && r.lifts.upperBound <= 15
                && r.spreads.lowerBound >= 0.4 && r.spreads.upperBound <= 2, "\(shape) \(r)")
        let sizes = [r.sizes.lowerBound, 1, r.sizes.upperBound], spreads = [r.spreads.lowerBound, 1, r.spreads.upperBound]
        for s in sizes {
            for p in spreads {
                for l in stride(from: r.lifts.lowerBound, through: r.lifts.upperBound, by: 1) where !fits(s, l, p, shape) {
                    Issue.record("\(shape): grandezza \(s), altezza \(l), distanza \(p) non sta")
                }
            }
        }
        // un passo oltre: qualche vertice della faccia nuova esce
        func face(_ s: [Double], _ l: [Double], _ p: [Double]) -> Bool { s.allSatisfy { s in l.allSatisfy { l in p.allSatisfy { fits(s, l, $0, shape) } } } }
        let S = [r.sizes.lowerBound, r.sizes.upperBound], L = [r.lifts.lowerBound, r.lifts.upperBound], P = [r.spreads.lowerBound, r.spreads.upperBound]
        if r.sizes.upperBound < 2 { #expect(!face([r.sizes.upperBound + 0.01], L, P), "\(shape) grandezza") }
        if r.sizes.lowerBound > 0.5 { #expect(!face([r.sizes.lowerBound - 0.01], L, P), "\(shape) grandezza in giù") }
        if r.spreads.upperBound < 2 { #expect(!face(S, L, [r.spreads.upperBound + 0.01]), "\(shape) distanza") }
        if r.spreads.lowerBound > 0.4 { #expect(!face(S, L, [r.spreads.lowerBound - 0.01]), "\(shape) distanza in giù") }
        if r.lifts.upperBound < 15 { #expect(!face(S, [r.lifts.upperBound + 1], P), "\(shape) altezza in su") }
        if r.lifts.lowerBound > -15 { #expect(!face(S, [r.lifts.lowerBound - 1], P), "\(shape) altezza in giù") }
    }
}

// Un oracolo diverso da quello dei cursori (eyesFitAtRest guarda le scatole degli occhi): i punti veri dei tracciati degli
// occhi, disegnati da fermi agli estremi degli intervalli di ogni forma, in ogni posa e con la deriva piena da tutte le
// parti, stanno ad almeno 0,9 unità dal bordo (il margine di 1 unità, meno la tolleranza dei tracciati). Se i cursori
// arrivassero fin sul bordo, senza margine, questa prova cadrebbe.
@Test func restingEyesKeepTheirMarginAtTheRangeCorners() {
    func points(_ path: CGPath) -> [CGPoint] {
        var out: [CGPoint] = []
        path.applyWithBlock { e in
            switch e.pointee.type {
            case .moveToPoint, .addLineToPoint: out.append(e.pointee.points[0])
            case .addQuadCurveToPoint: out.append(e.pointee.points[1])
            case .addCurveToPoint: out.append(e.pointee.points[2])
            default: break
            }
        }
        return out.enumerated().filter { $0.offset % 3 == 0 }.map(\.element)   // un punto ogni tre: i tratti sono lunghi 0,4
    }
    let ring = [CGVector(dx: 0.9, dy: 0), CGVector(dx: -0.9, dy: 0), CGVector(dx: 0, dy: 0.9), CGVector(dx: 0, dy: -0.9)]
    let drifts = [CGVector(dx: -1, dy: -0.5), CGVector(dx: -1, dy: 0.5), CGVector(dx: 1, dy: -0.5), CGVector(dx: 1, dy: 0.5)]
    for shape in MascotKind.allCases {
        for eyes in extremes(shape) {
            let g = MascotGeometry.of(shape, eyes)
            for pose in eyePoses {
                for drift in drifts {
                    var look = MascotLook(); look.left = pose; look.right = pose; look.leftShift = drift; look.rightShift = drift
                    let near = mascotFigure(g, look).eyes.flatMap(points).filter { p in
                        ring.contains { !shape.body.contains(CGPoint(x: p.x + $0.dx, y: p.y + $0.dy)) }
                    }
                    if !near.isEmpty { Issue.record("\(shape) \(eyes) \(pose) deriva \(drift): \(near.count) punti a meno di 0,9 dal bordo") }
                }
            }
        }
    }
}

// Cambiando forma gli occhi scelti restano, riportati dentro gli intervalli della forma nuova; il resto non cambia.
@Test func aNewShapeKeepsTheEyesInsideItsRanges() {
    var m = Mascot(shape: .mirtillo, body: 0xE8483F, eyes: 0x14141A, voice: .bottle, function: .system(kinds: [.cpu]))
    let r = EyeRanges.of(.mirtillo), to = EyeRanges.of(.mostro)
    m.eyeSize = r.sizes.upperBound; m.eyeLift = r.lifts.upperBound; m.eyeSpread = r.spreads.lowerBound
    var reshaped = m
    reshaped.reshape(.mostro)
    #expect(reshaped.shape == .mostro && reshaped.eyeSize == min(m.eyeSize, to.sizes.upperBound)
            && reshaped.eyeLift == min(m.eyeLift, to.lifts.upperBound) && reshaped.eyeSpread == max(m.eyeSpread, to.spreads.lowerBound))
    #expect(reshaped.eyeLift < m.eyeLift)   // Mostro ha gli occhi già in alto: in su arriva meno
    reshaped.shape = m.shape; reshaped.eyeSize = m.eyeSize; reshaped.eyeLift = m.eyeLift; reshaped.eyeSpread = m.eyeSpread
    #expect(reshaped == m)
}

// I valori degli occhi salvati fuori dagli intervalli (a mano, o da un'altra versione) tornano dentro.
@Test func savedEyeValuesAreClampedToTheRanges() {
    var m = Mascot(shape: .ball, body: 0, eyes: 0, voice: .bubble, function: .ai(agents: [.claude]))
    m.eyeSize = 5; m.eyeLift = -40; m.eyeSpread = 0.1
    let e = EyeSettings(m), r = EyeRanges.of(.ball)
    #expect(e.size == r.sizes.upperBound && e.lift == r.lifts.lowerBound && e.spread == r.spreads.lowerBound)
}

// I cursori fanno quello che dicono: più su, più distanti, più grandi.
@Test func eyeSlidersMoveTheEyes() {
    var look = MascotLook(); look.left = .open; look.right = .open
    func eyes(_ e: EyeSettings) -> [CGRect] { mascotFigure(.of(.mirtillo, e), look).eyes.map(\.boundingBoxOfPath) }
    let base = eyes(EyeSettings())
    #expect(abs(eyes(EyeSettings(lift: 4))[0].midY - (base[0].midY - 4)) < 1e-9)
    #expect(eyes(EyeSettings(spread: 1.2))[1].midX - eyes(EyeSettings(spread: 1.2))[0].midX > base[1].midX - base[0].midX + 4)
    #expect(eyes(EyeSettings(size: 1.2))[0].height > base[0].height * 1.15)
}
