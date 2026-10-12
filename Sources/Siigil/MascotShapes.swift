import CoreGraphics
import Foundation
import SwiftUI   // Path(roundedRect:style: .continuous): gli angoli morbidi del quadrato e della capsula, come il prototipo

// Le forme delle mascotte (spec sezione Mascotte §10): le sagome del prototipo del 4/10 (siigil-docs/prototipi-mascotte/base.swift,
// bodyPath) nella tela 100 (y in giù), nel riquadro 8…92 × 28…90, tutte appoggiate a terra (90) come le due di prima
// (respiro, salti e accucciate partono dalla base). Dall'11/10, come le forme di Grok (riferimento dell'autore): niente
// triangolo rovesciato, lo squircle nuovo e il sasso rifatto; l'esagono è un poligono arrotondato. Per ognuna dove stanno
// gli occhi (fitEyes) e il pallino.
extension MascotKind {
    var body: CGPath { Self.bodies[self]! }
    static let dotRadius = 12.0
    var dotCenter: CGPoint { Self.dots[self]! }

    // Gli occhi della forma prima dei cursori: l'altezza del centro (fitEyes del prototipo, 28 + 62 × la frazione: 0,36 per
    // Mostro, 0,56 per le altre) e metà della distanza (Mostro 12,6 e Mirtillo 11,0 come oggi, scelte dell'autore il 10/10;
    // le altre come Mirtillo, così gli archetti chiusi restano staccati).
    var eyeSpot: (y: Double, gap: Double) {
        switch self {
        case .mostro: (28 + 62 * 0.36, 12.6)
        default: (28 + 62 * 0.56, 11.0)
        }
    }

    private static let bodies = Dictionary(uniqueKeysWithValues: allCases.map { ($0, grounded(shapePath($0))) })
    private static let dots = Dictionary(uniqueKeysWithValues: allCases.map { ($0, dotSpot(bodies[$0]!)) })

    private static func shapePath(_ k: MascotKind) -> CGPath {
        switch k {
        case .mostro:   // il "monster" allungato fino a terra
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 22, y: 31))
            p.addQuadCurve(to: CGPoint(x: 78, y: 31), control: CGPoint(x: 50, y: 25))
            p.addQuadCurve(to: CGPoint(x: 89, y: 44), control: CGPoint(x: 89, y: 32))
            p.addCurve(to: CGPoint(x: 68, y: 80), control1: CGPoint(x: 89, y: 62), control2: CGPoint(x: 82, y: 78))
            p.addQuadCurve(to: CGPoint(x: 32, y: 80), control: CGPoint(x: 50, y: 84))
            p.addCurve(to: CGPoint(x: 11, y: 44), control1: CGPoint(x: 18, y: 78), control2: CGPoint(x: 11, y: 62))
            p.addQuadCurve(to: CGPoint(x: 22, y: 31), control: CGPoint(x: 11, y: 32))
            p.closeSubpath()
            return moved(p, CGAffineTransform(translationX: 0, y: 25).scaledBy(x: 1, y: 65.0 / 57).translatedBy(x: 0, y: -25))
        case .mirtillo:   // quadrato morbido, rotondità 0,88
            return Path(roundedRect: CGRect(x: 8, y: 28, width: 84, height: 62), cornerRadius: 0.88 * 62 / 2, style: .continuous).cgPath
        case .ball:
            return CGPath(ellipseIn: CGRect(x: 16, y: 22, width: 68, height: 68), transform: nil)
        case .pebble:   // un ovale irregolare come il sasso di Grok: più largo che alto, pieno in alto a sinistra, più piatto
            // sotto, inclinato di 10° (la destra più in basso)
            // 24 punti uniti da curve morbide (Catmull-Rom): pochi tratti, così controllare se un punto è dentro costa poco
            let tilt = 10 * Double.pi / 180, n = 24
            let pts = (0..<n).map { i -> CGPoint in
                let th = Double(i) / Double(n) * 2 * .pi, c = cos(th), s = sin(th)
                let k = 1 + 0.07 * cos(th + 2.3) + 0.025 * cos(2 * th - 0.6)   // il bozzo in alto a sinistra
                let x = 38 * k * c, y = 31 * k * s * (s > 0 ? 1 - 0.16 * s * s : 1)   // y in giù: s > 0 è sotto, schiacciato
                return CGPoint(x: 50 + x * cos(tilt) - y * sin(tilt), y: 59 + x * sin(tilt) + y * cos(tilt))
            }
            let p = CGMutablePath()
            p.move(to: pts[0])
            for i in 0..<n {
                let a = pts[(i + n - 1) % n], b = pts[i], c = pts[(i + 1) % n], d = pts[(i + 2) % n]
                p.addCurve(to: c, control1: CGPoint(x: b.x + (c.x - a.x) / 6, y: b.y + (c.y - a.y) / 6),
                           control2: CGPoint(x: c.x - (d.x - b.x) / 6, y: c.y - (d.y - b.y) / 6))
            }
            p.closeSubpath()
            return moved(p, CGAffineTransform(translationX: 50 - p.boundingBoxOfPath.midX, y: 0))   // al centro come le altre
        case .squircle:   // un quadrato con gli angoli continui, come lo squircle di Grok: largo come la pallina
            return Path(roundedRect: CGRect(x: 18, y: 26, width: 64, height: 64), cornerRadius: 20, style: .continuous).cgPath
        case .capsule:
            return Path(roundedRect: CGRect(x: 5, y: 35, width: 90, height: 55), cornerRadius: 27.5, style: .continuous).cgPath
        case .hexagon:   // un poligono con gli angoli arrotondati (roundedPoly del prototipo), dal mezzo del lato in alto a sinistra
            let pts = [CGPoint(x: 29, y: 28), CGPoint(x: 71, y: 28), CGPoint(x: 92, y: 59), CGPoint(x: 71, y: 90),
                       CGPoint(x: 29, y: 90), CGPoint(x: 8, y: 59)], p = CGMutablePath()
            p.move(to: CGPoint(x: 18.5, y: 43.5))
            for i in pts.indices { p.addArc(tangent1End: pts[i], tangent2End: pts[(i + 1) % pts.count], radius: 12) }
            p.closeSubpath()
            return p
        case .cloud:   // tre bozzi tondi sopra una base piatta
            var p = CGPath(roundedRect: CGRect(x: 10, y: 54, width: 80, height: 36), cornerWidth: 18, cornerHeight: 18, transform: nil)
            for (x, y, r) in [(31.0, 56.0, 19.0), (53.0, 45.0, 23.0), (73.0, 57.0, 17.0)] {
                p = p.union(CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r), transform: nil))
            }
            return p
        case .drop:   // la punta in alto
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 50, y: 20))
            p.addCurve(to: CGPoint(x: 92, y: 67.68), control1: CGPoint(x: 66.8, y: 26.2), control2: CGPoint(x: 92, y: 41.08))
            p.addCurve(to: CGPoint(x: 50, y: 90), control1: CGPoint(x: 92, y: 87.52), control2: CGPoint(x: 78.56, y: 90))
            p.addCurve(to: CGPoint(x: 8, y: 67.68), control1: CGPoint(x: 21.44, y: 90), control2: CGPoint(x: 8, y: 87.52))
            p.addCurve(to: CGPoint(x: 50, y: 20), control1: CGPoint(x: 8, y: 41.08), control2: CGPoint(x: 33.2, y: 26.2))
            p.closeSubpath()
            return p
        }
    }

    // Lo spazio della testa fra le altezze y0…y1, dove è larga abbastanza a ogni riga: l'asse e metà della larghezza, meno 1
    // unità di margine (come eyesFit). Il cilindro attorno a cui girano gli occhi nel giro su se stessa (spunEye).
    func head(_ y0: Double, _ y1: Double) -> (axis: Double, radius: Double) {
        let band = Self.rows[self]![max(Int(y0.rounded(.down)), 0)...min(Int(y1.rounded(.up)), 100)]
        guard band.allSatisfy({ $0 != nil }) else { return (50, 0) }
        let l = band.map { $0!.lowerBound }.max()!, r = band.map { $0!.upperBound }.min()!
        return ((l + r) / 2, (r - l) / 2 - 1)
    }

    // La sagoma riga per riga, a ogni unità della tela dall'alto: da dove a dove è dentro attorno al centro (x 50); nil dove
    // il centro è fuori. Calcolata una volta per tutte le forme, al primo giro (~5 ms).
    private static let rows = Dictionary(uniqueKeysWithValues: allCases.map { k in (k, (0...100).map { span(bodies[k]!, Double($0)) }) })

    private static func span(_ body: CGPath, _ y: Double) -> ClosedRange<Double>? {
        guard body.contains(CGPoint(x: 50, y: y)) else { return nil }
        func edge(_ dir: Double) -> Double {   // a passi di 2 finché è dentro, poi sei volte a metà: al trentaduesimo di unità
            var inside = 50.0, outside = 50 + 2 * dir
            while (0...100).contains(outside), body.contains(CGPoint(x: outside, y: y)) { inside = outside; outside += 2 * dir }
            for _ in 0..<6 { let mid = (inside + outside) / 2; if body.contains(CGPoint(x: mid, y: y)) { inside = mid } else { outside = mid } }
            return inside
        }
        return edge(-1)...edge(1)
    }

    // A terra: il punto più basso a 90.
    private static func grounded(_ p: CGPath) -> CGPath { moved(p, CGAffineTransform(translationX: 0, y: 90 - p.boundingBoxOfPath.maxY)) }

    // Dove sta il pallino: sul bordo del corpo, sulla diagonale in basso verso il davanti (30° sotto l'orizzontale), col
    // centro appena fuori: copre l'angolo senza arrivare agli occhi.
    private static func dotSpot(_ body: CGPath) -> CGPoint {
        let c = CGPoint(x: 50, y: 59), dir = CGVector(dx: cos(0.52), dy: sin(0.52))
        var t = 0.0
        while body.contains(CGPoint(x: c.x + dir.dx * t, y: c.y + dir.dy * t)) { t += 0.25 }
        t += 0.2 * dotRadius
        return CGPoint(x: c.x + dir.dx * t, y: c.y + dir.dy * t)
    }
}

// I tre cursori degli occhi (spec §10): grandezza e distanza come fattori, altezza in unità della tela (in su se positiva).
// Fin dove arrivano lo decide la forma (EyeRanges).
struct EyeSettings: Hashable {
    var size = 1.0, lift = 0.0, spread = 1.0
}

extension EyeSettings {
    // I valori salvati riportati negli intervalli della forma (scritti a mano, da un'altra versione o con un'altra forma):
    // gli occhi restano dentro la sagoma.
    init(_ m: Mascot) {
        let r = EyeRanges.of(m.shape)
        self.init(size: clamped(m.eyeSize, to: r.sizes, default: 1), lift: clamped(m.eyeLift, to: r.lifts, default: 0),
                  spread: clamped(m.eyeSpread, to: r.spreads, default: 1))
    }
}

// Fin dove arrivano i cursori degli occhi di una forma (spec §10; autore, 11/10: "una modifica maggiore"): la scatola più
// larga di grandezza × altezza × distanza, dentro i limiti 50–200 %, ±15 unità e 40–200 %, in cui ogni combinazione tiene
// gli occhi dentro la sagoma da fermi (eyesFitAtRest); lo scorrimento della faccia si ricava poi da forma e occhi, e agli
// estremi può essere zero. La scatola cresce prima in proporzione ai limiti, poi ogni lato fin dove può (grandezza, distanza,
// altezza), a passi dei cursori: 1 % e 1 unità. Si guardano i vertici: occhi più grandi, più distanti o più lontani dal
// centro della sagoma stanno peggio (un test prova anche dentro). Calcolata una volta per forma.
struct EyeRanges: Equatable {
    let sizes: ClosedRange<Double>, lifts: ClosedRange<Double>, spreads: ClosedRange<Double>

    static func of(_ shape: MascotKind) -> EyeRanges {
        lock.lock(); defer { lock.unlock() }
        if let r = cache[shape] { return r }
        let r = EyeRanges(shape)
        cache[shape] = r
        return r
    }
    private static var cache: [MascotKind: EyeRanges] = [:]
    private static let lock = NSLock()

    private init(_ shape: MascotKind) {
        // la scatola in passi dei cursori: grandezza e distanza in %, altezza in unità
        let caps = [50...200, 40...200, -15...15], start = [100, 100, 0]
        func fits(_ b: [ClosedRange<Int>]) -> Bool {
            for s in [b[0].lowerBound, b[0].upperBound] {
                for p in [b[1].lowerBound, b[1].upperBound] {
                    for l in [b[2].lowerBound, b[2].upperBound]
                    where !eyesFitAtRest(shape, EyeSettings(size: Double(s) / 100, lift: Double(l), spread: Double(p) / 100)) { return false }
                }
            }
            return true
        }
        var b = start.map { $0...$0 }
        if fits(b) {
            // in proporzione ai limiti: il passo più lungo, in centesimi della strada fino ai limiti, che sta dentro
            func scaled(_ n: Int) -> [ClosedRange<Int>] {
                (0..<3).map { (start[$0] - (start[$0] - caps[$0].lowerBound) * n / 100)...(start[$0] + (caps[$0].upperBound - start[$0]) * n / 100) }
            }
            var good = 0, bad = 101
            while bad - good > 1 { let mid = (good + bad) / 2; if fits(scaled(mid)) { good = mid } else { bad = mid } }
            b = scaled(good)
            // poi un lato alla volta, fin dove può
            for i in 0..<3 {
                for up in [false, true] {
                    func with(_ v: Int) -> [ClosedRange<Int>] { var c = b; c[i] = up ? c[i].lowerBound...v : v...c[i].upperBound; return c }
                    var good = up ? b[i].upperBound : b[i].lowerBound, bad = up ? caps[i].upperBound + 1 : caps[i].lowerBound - 1
                    while abs(bad - good) > 1 { let mid = (good + bad) / 2; if fits(with(mid)) { good = mid } else { bad = mid } }
                    b = with(good)
                }
            }
        }
        sizes = Double(b[0].lowerBound) / 100...Double(b[0].upperBound) / 100
        spreads = Double(b[1].lowerBound) / 100...Double(b[1].upperBound) / 100
        lifts = Double(b[2].lowerBound)...Double(b[2].upperBound)
    }
}

// Una forma coi suoi occhi: dove stanno, quanto scorre la faccia con lo sguardo e dove sta il pallino. Lo scorrimento è il
// massimo che tiene gli occhi dentro la sagoma con 1 unità di margine, in tutte le pose, con la deriva piena e lo sguardo
// agli estremi, e anche quando la faccia si scosta per fare posto al pallino (in su e in giù al più 6, come oggi), a mezze
// unità: così Mostro e Mirtillo coi cursori al centro escono come prima (17,5 e 21,5). Si calcola una volta per forma e
// cursori (`of`).
struct MascotGeometry: Equatable {
    let shape: MascotKind
    let eyes: EyeSettings
    let eyeY, eyeGap, faceX, faceY: Double

    static func of(_ m: Mascot) -> MascotGeometry { of(m.shape, EyeSettings(m)) }

    // ponytail: una cache che cresce con ogni valore dei cursori visto (pochi: i cursori vanno a passi); svuotarla se
    // diventassero continui.
    static func of(_ shape: MascotKind, _ eyes: EyeSettings = EyeSettings()) -> MascotGeometry {
        let key = Key(shape: shape, eyes: eyes)
        lock.lock(); defer { lock.unlock() }
        if let g = cache[key] { return g }
        let g = MascotGeometry(shape: shape, eyes: eyes)
        cache[key] = g
        return g
    }
    private struct Key: Hashable { let shape: MascotKind; let eyes: EyeSettings }
    private static var cache: [Key: MascotGeometry] = [:]
    private static let lock = NSLock()

    private init(shape: MascotKind, eyes: EyeSettings) {
        self.shape = shape
        self.eyes = eyes
        let spot = shape.eyeSpot, y = spot.y - eyes.lift, gap = spot.gap * eyes.spread
        func fits(_ fx: Double, _ fy: Double) -> Bool {
            eyesFit(shape.body, dot: shape.dotCenter, eyeY: y, gap: gap, scale: eyes.size, faceX: fx, faceY: fy)
        }
        let fy = stride(from: 6.0, through: 0, by: -0.5).first { fits(0, $0) } ?? 0
        var fit = 0, miss = 80   // in mezze unità: 0 sta dentro (gli intervalli dei cursori lo garantiscono), 40 no
        while miss - fit > 1 { let mid = (fit + miss) / 2; if fits(Double(mid) / 2, fy) { fit = mid } else { miss = mid } }
        eyeY = y; eyeGap = gap; faceY = fy; faceX = Double(fit) / 2
    }
}

// Gli occhi stanno dentro la sagoma: con 1 unità di margine con lo sguardo su tutta la griglia, in ogni posa e con la deriva
// piena; senza margine quando la faccia fa posto al pallino (eyesFitWithDot, ogni posa). Le scatole
// degli occhi come le mette mascotFigure: esatte per occhi aperti e spalancati, un po' abbondanti per gli archetti piegati.
private func eyesFit(_ body: CGPath, dot: CGPoint, eyeY: Double, gap: Double, scale: Double, faceX: Double, faceY: Double) -> Bool {
    for gx in stride(from: -1.0, through: 1, by: 0.25) {
        for gy in stride(from: -1.0, through: 1, by: 0.5) {
            let face = CGPoint(x: 50 + gx * faceX, y: eyeY + gy * faceY)
            let drift = CGVector(dx: gx < 0 ? -1 : 1, dy: gy < 0 ? -0.5 : 0.5)
            for pose in eyePoses {
                for side in [-1.0, 1.0]
                where !inside(body, eyeBox(pose, side, gx, face, drift, gap: gap, scale: scale).insetBy(dx: -1, dy: -1)) { return false }
            }
            // il pallino fuori, sulla stessa griglia dello sguardo (eyesFitWithDot)
            if !eyesFitWithDot(body, dot: dot, face: face, gaze: gx, gap: gap, scale: scale) { return false }
        }
    }
    return true
}

// Le pose di tutti gli stati: gli archetti chiusi sono i più larghi.
let eyePoses = [EyePose.open, .wide, .half, .asleep, .happy, .wink]

// La scatola di un occhio come la mette mascotFigure (eyePlace): esatta per occhi aperti e spalancati, un po' abbondante
// per gli archetti piegati.
private func eyeBox(_ pose: EyePose, _ side: Double, _ gx: Double, _ face: CGPoint, _ drift: CGVector, gap: Double, scale: Double) -> CGRect {
    let at = eyePlace(side: side, gaze: gx, face: face, gap: gap, drift: drift), c = at.center
    let w = max(pose.w * scale * at.squeeze, 0.6), h = max(pose.h * scale, 0.6), top = -h / 2 + pose.lid * h
    return CGRect(x: c.x - w / 2, y: c.y + top - max(0, 1.3 * pose.bend), width: w, height: h / 2 - top + abs(1.3 * pose.bend))
}

// I quattro angoli della scatola stanno tutti dentro la sagoma.
func inside(_ body: CGPath, _ r: CGRect) -> Bool {
    [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
        .allSatisfy { body.contains($0) }
}

// Col pallino fuori la faccia si scosta lungo la retta dal suo centro, come in mascotFigure (dotNudge), di quanto le chiede
// l'occhio di destra nella sua posa. In ogni posa (anche dormendo e festeggiando il pallino può essere fuori), con l'occhio
// di destra spinto dalla deriva verso il pallino e quello di sinistra dall'altra parte, tutti e due restano dentro: senza
// margine, sono già scostati. La stessa prova per lo scorrimento della faccia (eyesFit) e per i cursori (eyesFitAtRest).
private func eyesFitWithDot(_ body: CGPath, dot: CGPoint, face: CGPoint, gaze gx: Double, gap: Double, scale: Double) -> Bool {
    let toward = CGVector(dx: 1, dy: 0.5), away = CGVector(dx: -1, dy: -0.5)
    for pose in eyePoses {
        let n = dotNudge(eyeBox: eyeBox(pose, 1, gx, face, toward, gap: gap, scale: scale), dot: dot, p: 1)
        let moved = CGPoint(x: face.x + n.dx, y: face.y + n.dy)
        for (side, drift) in [(-1.0, away), (1.0, toward)]
        where !inside(body, eyeBox(pose, side, gx, moved, drift, gap: gap, scale: scale)) { return false }
    }
    return true
}

// Gli occhi dentro la sagoma da fermi (EyeRanges): faccia ferma e sguardo dritto, la deriva piena da tutte le parti (a
// faccia ferma gli sguardi di lato stringono e avvicinano gli occhi: stanno dentro questi), ogni posa, con 1 unità di
// margine; e col pallino fuori la faccia che si scosta per lui (eyesFitWithDot), come eyesFit.
func eyesFitAtRest(_ shape: MascotKind, _ e: EyeSettings) -> Bool {
    let body = shape.body, spot = shape.eyeSpot, gap = spot.gap * e.spread, face = CGPoint(x: 50, y: spot.y - e.lift)
    for dx in [-1.0, 1] {
        for dy in [-0.5, 0.5] {
            for pose in eyePoses {
                for side in [-1.0, 1.0]
                where !inside(body, eyeBox(pose, side, 0, face, CGVector(dx: dx, dy: dy), gap: gap, scale: e.size).insetBy(dx: -1, dy: -1)) { return false }
            }
        }
    }
    for gx in stride(from: -1.0, through: 1, by: 0.5)
    where !eyesFitWithDot(body, dot: shape.dotCenter, face: face, gaze: gx, gap: gap, scale: e.size) { return false }
    return true
}
