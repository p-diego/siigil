import CoreGraphics
import Foundation
import Testing
@testable import Siigil

// Lo sguardo verso il davanti sposta la faccia a destra e stringe l'occhio di destra; gli archetti chiusi scendono nel
// mezzo dormendo e salgono da felici (z e scintille dentro la tela: everyShapeSitsInTheCanvas).
@Test func gazeAndArchesGoTheRightWay() {
    var look = MascotLook(); look.left = .open; look.right = .open
    let rest = mascotFigure(.of(.mirtillo), look).eyes.map(\.boundingBoxOfPath)
    look.gazeX = 1
    let right = mascotFigure(.of(.mirtillo), look).eyes.map(\.boundingBoxOfPath)
    #expect(right[0].midX > rest[0].midX && right[1].midX > rest[1].midX)
    #expect(right[1].width < right[0].width)
    func middleBelowTips(_ p: EyePose) -> Bool {
        let path = eyePath(p, center: .zero, widthScale: 1), b = path.boundingBoxOfPath
        return path.contains(CGPoint(x: 0, y: b.maxY - 0.5)) && !path.contains(CGPoint(x: b.minX + 0.5, y: b.maxY - 0.5))
    }
    #expect(middleBelowTips(.asleep) && !middleBelowTips(.happy))
}

// z e scintille seguono il saltello, come nel prototipo: con il corpo sollevato di 10 salgono di 10 anche loro.
@Test func decorationsRideTheHop() {
    var look = MascotLook(); look.z = 0.5; look.sparkle = 0.5
    let ground = mascotFigure(.of(.mostro), look)
    look.lift = 10
    let hop = mascotFigure(.of(.mostro), look)
    #expect(abs(ground.z!.boundingBoxOfPath.minY - hop.z!.boundingBoxOfPath.minY - 10) < 1e-6)
    #expect(abs(ground.sparkles!.boundingBoxOfPath.minY - hop.sparkles!.boundingBoxOfPath.minY - 10) < 1e-6)
}

// Ogni occhio vaga per conto suo (spec §2): lo spostamento di uno non muove l'altro.
@Test func eachEyeDriftsOnItsOwn() {
    var look = MascotLook(); look.left = .open; look.right = .open
    let a = mascotFigure(.of(.mostro), look).eyes.map(\.boundingBoxOfPath)
    look.leftShift = CGVector(dx: 1, dy: 0.5)
    let b = mascotFigure(.of(.mostro), look).eyes.map(\.boundingBoxOfPath)
    #expect(abs(b[0].midX - a[0].midX - 1) < 1e-6 && abs(b[0].midY - a[0].midY - 0.5) < 1e-6 && b[1] == a[1])
}

// Review Focus 3: girata, il davanti (lo sguardo, il pallino) è a sinistra.
@Test func pointerPositionInTheCanvasFollowsTheMirror() {
    let size = mascotBarSize
    let p = canvasPoint(CGPoint(x: 2.25 + size.height * 0.8, y: size.height * 0.6), size: size, mirrored: false)
    #expect(abs(p.x - 80) < 1e-9 && abs(p.y - 60) < 1e-9)
    let m = canvasPoint(CGPoint(x: size.width - 2.25 - size.height * 0.8, y: size.height * 0.6), size: size, mirrored: true)
    #expect(abs(m.x - 80) < 1e-9)
}

// La mascotte su una tela di 126×108 pixel (31,5×27 pt a 4×; y in giù, in punti), su `background` se c'è.
private let w = 126, h = 108
private func canvas(_ geometry: MascotGeometry, _ look: MascotLook, _ colors: MascotColors, mirrored: Bool = false,
                    background: CGColor? = nil) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    if let background { ctx.setFillColor(background); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h)) }
    ctx.translateBy(x: 0, y: CGFloat(h)); ctx.scaleBy(x: 4, y: -4)
    drawMascot(geometry, look, colors, in: ctx, size: mascotBarSize, mirrored: mirrored)
    return ctx
}

@Test func drawsBodyEyesAndDotWithTheirColors() {
    func pixels(_ look: MascotLook, mirrored: Bool) -> (Int, Int) -> (r: UInt8, g: UInt8, b: UInt8) {
        let colors = MascotColors(body: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), eyes: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                  dot: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
        let ctx = canvas(.of(.mirtillo), look, colors, mirrored: mirrored)
        return { x, y in   // la chiusura tiene vivo il contesto (e la sua memoria); y dall'alto
            let data = ctx.data!.assumingMemoryBound(to: UInt8.self), i = (y * w + x) * 4
            return (data[i], data[i + 1], data[i + 2])
        }
    }
    var look = MascotLook(); look.left = .open; look.right = .open; look.gazeX = 0; look.gazeY = 0; look.dot = 1
    let px = pixels(look, mirrored: false)
    // tela → pixel: x = (2,25 + 0,27 u) × 4, y = 0,27 v × 4
    func at(_ u: Double, _ v: Double, mirrored: Bool = false) -> (Int, Int) {
        let x = 2.25 + 0.27 * u
        return (Int(((mirrored ? mascotBarSize.width - x : x) * 4).rounded()), Int((0.27 * v * 4).rounded()))
    }
    let body = at(50, 45), eye = at(50 - MascotGeometry.of(.mirtillo).eyeGap, MascotGeometry.of(.mirtillo).eyeY)
    let c = MascotKind.mirtillo.dotCenter
    let dot = at(c.x, c.y), over = at(c.x - 8, c.y)   // `over` sta sul corpo e dentro il pallino
    #expect(px(body.0, body.1).b > 200 && px(body.0, body.1).r < 50)   // corpo blu
    #expect(px(eye.0, eye.1).r > 200 && px(eye.0, eye.1).b < 50)       // occhio rosso
    #expect(px(dot.0, dot.1).g > 200 && px(dot.0, dot.1).r < 50)       // pallino verde, in basso a destra
    #expect(px(over.0, over.1).g > 200 && px(over.0, over.1).b < 50)   // davanti al corpo, non dietro
    let mirrored = pixels(look, mirrored: true), md = at(c.x, c.y, mirrored: true)
    #expect(mirrored(md.0, md.1).g > 200)                               // girata: in basso a sinistra
}

// L'archetto si vede davvero (oggi la curva è ~1,4 unità): chiuso nel sonno il mezzo dell'occhio sta sotto le punte, felice sopra.
// Con i soli punti di un rettangolo i lati lunghi restano dritti: l'occhio resta alto 4,4; piegato (asleep e happy) è alto 5,15,
// e la soglia (4,8) sta a metà.
@Test func closedEyesAreVisiblyArched() {
    for pose in [EyePose.asleep, .happy] {
        let b = eyePath(pose, center: .zero, widthScale: 1).boundingBoxOfPath
        #expect(b.height > 4.8, "\(pose) alto \(b.height)")
    }
}

// Gli occhi stanno all'altezza di oggi per ogni sagoma (fitEyes del prototipo: 28 + 62 × 0,36 per il "monster", × 0,56 per il quadrato morbido).
@Test func eyesSitAtTheHeightOfTheirShape() {
    for (kind, y) in [(MascotKind.mostro, 50.32), (.mirtillo, 62.72)] {
        var look = MascotLook(); look.left = .open; look.right = .open; look.gazeX = 0; look.gazeY = 0
        for eye in mascotFigure(.of(kind), look).eyes { #expect(abs(eye.boundingBoxOfPath.midY - y) < 1e-6, "\(kind) \(eye.boundingBoxOfPath.midY)") }
    }
}

// Il bordino (spec §1, "come i fotogrammi di oggi"): il grigio generico 0,62 del `bordered` di base.swift, tolto il 10/10
// (≈ 0,68 in sRGB), al 60 %, 1 pt fuori dal corpo (4 pixel a 4×) e non oltre. Misurato sui pixel di un fondo
// trasparente: l'alfa e il grigio senza premoltiplicare.
@Test func theBorderIsGreyAtSixtyPercentOnePointOutside() {
    let colors = MascotColors(body: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), eyes: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), dot: nil)
    let ctx = canvas(.of(.mostro), MascotLook(), colors)   // a riposo, occhi chiusi
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    // a v = 50 il bordo sinistro del corpo sta a u = 11: colonna (2,25 + 0,27 × 11) × 4 ≈ 21, riga 0,27 × 50 × 4 ≈ 54
    let row = Int((0.27 * 50 * 4).rounded()), edge = Int(((2.25 + 0.27 * 11) * 4).rounded())
    func pixel(_ x: Int) -> (alpha: Double, grey: Double) {
        let i = (row * w + x) * 4, a = Double(data[i + 3]) / 255
        return (a, a > 0 ? Double(data[i]) / 255 / a : 0)
    }
    let near = pixel(edge - 3), far = pixel(edge - 6)   // 3 pixel (0,75 pt) e 6 pixel (1,5 pt) fuori dal corpo
    #expect(abs(near.alpha - 0.6) < 0.03, "a 3 pixel dal corpo: alfa \(near.alpha)")
    #expect(abs(near.grey - 0.68) < 0.01, "a 3 pixel dal corpo: grigio \(near.grey)")
    #expect(far.alpha == 0, "a 6 pixel dal corpo: alfa \(far.alpha)")
}

// Il bordo del pallino è come quello del corpo (autore, 10/10): anche dove il pallino copre il corpo, nell'anello di 1 pt
// attorno si vede quello che c'è sotto la mascotte (qui niente: il contesto è trasparente) col grigio al 60 % sopra, non
// il grigio mescolato al nero del corpo.
@Test func theDotRingLooksLikeTheBodyBorder() {
    var look = MascotLook(); look.left = .open; look.right = .open; look.dot = 1
    let ctx = canvas(.of(.mostro), look, MascotColors(body: cgColor(hex: 0x14141A), eyes: cgColor(hex: 0xF5F7FC), dot: cgColor(hex: 0x739EFA)))
    // mezzo punto fuori dal pallino, verso l'interno del corpo: cade nell'anello, sopra il corpo
    let c = MascotKind.mostro.dotCenter, k = MascotKind.dotRadius + 0.5 / 0.27
    let u = 2.25 + 0.27 * (c.x - cos(0.52) * k), v = 0.27 * (c.y - sin(0.52) * k)
    #expect(MascotKind.mostro.body.contains(CGPoint(x: c.x - cos(0.52) * k, y: c.y - sin(0.52) * k)))
    let x = Int((u * 4).rounded()), y = Int((v * 4).rounded())
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self), i = (y * w + x) * 4
    let alpha = Double(data[i + 3]) / 255, grey = alpha > 0 ? Double(data[i]) / 255 / alpha : 0
    #expect(abs(alpha - 0.6) < 0.05 && abs(grey - 0.68) < 0.02, "anello del pallino: opacità \(alpha), grigio \(grey)")
}

// Il taglio attorno al pallino buca solo la mascotte, non quello che c'è sotto (la barra, il fondo del video): su uno sfondo
// opaco l'anello resta opaco e ha lo stesso colore del bordo del corpo (grigio al 60 % sulla barra).
@Test func theDotRingDoesNotPunchWhatIsUnderTheMascot() {
    var look = MascotLook(); look.left = .open; look.right = .open; look.dot = 1
    let ctx = canvas(.of(.mostro), look, MascotColors(body: cgColor(hex: 0x14141A), eyes: cgColor(hex: 0xF5F7FC), dot: cgColor(hex: 0x739EFA)),
                     background: cgColor(hex: 0xEDEDF2))
    let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
    func pixel(_ u: Double, _ v: Double) -> [Int] {   // un punto della tela 100
        let i = (Int((0.27 * v * 4).rounded()) * w + Int(((2.25 + 0.27 * u) * 4).rounded())) * 4
        return (0..<4).map { Int(data[i + $0]) }
    }
    let c = MascotKind.mostro.dotCenter, k = MascotKind.dotRadius + 0.5 / 0.27
    let ring = pixel(c.x - cos(0.52) * k, c.y - sin(0.52) * k)   // mezzo punto fuori dal pallino, sopra il corpo
    let border = pixel(11 - 0.5 / 0.27, 55)                      // mezzo punto fuori dal corpo, a sinistra
    #expect(ring[3] == 255 && zip(ring, border).allSatisfy { abs($0 - $1) <= 2 }, "anello \(ring), bordo del corpo \(border)")
}

// Con il pallino fuori gli occhi gli fanno posto, come in Grok: anche con lo sguardo agli estremi, occhi aperti o spalancati
// e deriva piena verso di lui, la scatola dell'occhio di destra sta fuori dal cerchio e dal suo anello di 1 pt (distanza dal
// centro del pallino); si scosta tutta la faccia, gli occhi restano dentro il corpo e a riposo il pallino non li sposta.
@Test func eyesMakeRoomForTheDot() {
    let ring = 1 / 0.27
    for kind in [MascotKind.mostro, .mirtillo] {
        let c = kind.dotCenter
        for (gx, gy) in [(1.0, 1.0), (1.0, 0.3), (0.7, 0.3)] {
            for pose in [EyePose.open, .wide] {
                var look = MascotLook(); look.gazeX = gx; look.gazeY = gy; look.left = pose; look.right = pose; look.dot = 1
                look.rightShift = CGVector(dx: 1, dy: 0.5)
                let eyes = mascotFigure(.of(kind), look).eyes.map(\.boundingBoxOfPath), b = eyes[1]
                let near = hypot(min(max(c.x, b.minX), b.maxX) - c.x, min(max(c.y, b.minY), b.maxY) - c.y)
                #expect(near >= MascotKind.dotRadius + ring, "\(kind) sguardo \(gx) \(gy) \(pose): a \(near) dal centro del pallino")
                for e in eyes { #expect(inside(kind.body, e), "\(kind) sguardo \(gx) \(gy) \(pose): occhio fuori dal corpo") }
                look.dot = 0   // lo stesso sguardo senza pallino: si scosta tutta la faccia, i due occhi restano alla stessa distanza
                let plain = mascotFigure(.of(kind), look).eyes.map(\.boundingBoxOfPath)
                #expect(abs((eyes[1].midX - eyes[0].midX) - (plain[1].midX - plain[0].midX)) < 1e-9
                        && abs((eyes[1].midY - eyes[0].midY) - (plain[1].midY - plain[0].midY)) < 1e-9,
                        "\(kind) sguardo \(gx) \(gy) \(pose): si è scostato un occhio solo")
            }
        }
        var rest = MascotLook(); rest.left = .open; rest.right = .open
        let without = mascotFigure(.of(kind), rest).eyes.map(\.boundingBoxOfPath)
        rest.dot = 1
        #expect(mascotFigure(.of(kind), rest).eyes.map(\.boundingBoxOfPath) == without, "\(kind): a riposo il pallino non sposta gli occhi")
    }
}

// Il rimbalzo del pallino (fin verso 1,13 quando compare) non scosta la faccia più del pallino a 1, quello che provano i
// cursori degli occhi (eyesFitWithDot): oltre, agli estremi gli occhi uscivano dalla sagoma fino a 1,35 unità (ripasso
// dell'11/10).
@Test func theDotBounceDoesNotPushTheEyesFurther() {
    let box = CGRect(x: 60, y: 50, width: 7, height: 7), dot = CGPoint(x: 70, y: 60)
    let full = dotNudge(eyeBox: box, dot: dot, p: 1)
    #expect(full != .zero)
    #expect(dotNudge(eyeBox: box, dot: dot, p: 1.13) == full)
}

// Confusa (spec pillole-mascotte §2): al posto delle barrette due spirali, larghe come una spirale da 6,6, dove stavano gli
// occhi; girano.
@Test func dizzyEyesBecomeSpinningSpirals() {
    var look = MascotLook(); look.left = .open; look.right = .open
    let eyes = mascotFigure(.of(.mirtillo), look).eyes.map(\.boundingBoxOfPath)
    look.dizzy = 0.5
    let spirals = mascotFigure(.of(.mirtillo), look).eyes
    #expect(spirals.count == 2)
    for (e, s) in zip(eyes, spirals.map(\.boundingBoxOfPath)) {
        #expect(abs(s.midX - e.midX) < 3 && abs(s.midY - e.midY) < 3 && s.width > 10 && s.height > 10, "\(s) \(e)")
    }
    look.dizzy = 0.55
    #expect(mascotFigure(.of(.mirtillo), look).eyes[0] != spirals[0])
}

// Il cuoricino (spec pillole-mascotte §2; autore, 11/10: centrato e più in basso): sopra la testa, sale, pieno a metà e quasi sparito alla
// fine; non esce mai dallo spazio sopra la tela, bordino compreso (1 pt), per ogni forma e grandezza (Review Focus 4).
@Test func theHeartRisesAboveTheHeadAndStaysInTheBar() {
    for shape in MascotKind.allCases {
        let g = MascotGeometry.of(shape), top = shape.body.boundingBoxOfPath
        var look = MascotLook(); look.heart = 0.1
        let early = mascotFigure(g, look, headroom: barHeadroom(1)).heart!.boundingBoxOfPath
        #expect(abs(early.midX - top.midX) < 1e-6 && early.midY < top.minY, "\(shape)")   // centrato sopra la testa
        look.heart = 0.5
        let later = mascotFigure(g, look, headroom: barHeadroom(1))
        #expect(later.heart!.boundingBoxOfPath.midY < early.midY && later.heartAlpha == 1, "\(shape)")
        look.heart = 0.95
        #expect(mascotFigure(g, look, headroom: barHeadroom(1)).heartAlpha < 0.2, "\(shape)")
        for size in stride(from: 0.7, through: 1.25, by: 0.05) {
            for h in stride(from: 0.0, through: 1, by: 0.05) {
                look.heart = h
                let b = mascotFigure(g, look, headroom: barHeadroom(size)).heart!.boundingBoxOfPath
                #expect(b.minY - 1 / 0.27 >= -barHeadroom(size) - 1e-6, "\(shape) grandezza \(size) cuore \(h)")
            }
        }
    }
}

// Lo spazio sopra la tela nella barra: 4 pt alla grandezza 100 % (14,8 unità), quasi niente al 125 %.
@Test func barHeadroomIsTheRoomAboveTheCanvas() {
    #expect(abs(barHeadroom(1) - 4 / 0.27) < 1e-9)
    #expect(barHeadroom(1.25) >= 0 && barHeadroom(1.25) < 1)
}

// Con lo spazio sopra la tela (headroom) la tela scende di tanto e resta della stessa misura: il puntatore si legge uguale.
@Test func headroomMovesTheCanvasDown() {
    let size = CGSize(width: mascotBarSize.width, height: mascotBarSize.height + 4)
    let p = canvasPoint(CGPoint(x: 2.25 + 27 * 0.8, y: 4 + 27 * 0.6), size: size, mirrored: false, headroom: 4 / 0.27)
    #expect(abs(p.x - 80) < 1e-6 && abs(p.y - 60) < 1e-6)
}

// "z" e scintille non si schiacciano col corpo (spec pillole-mascotte §2): premuta (altezza 0,8) restano dove sono.
@Test func decorationsDoNotSquash() {
    var look = MascotLook(); look.z = 0.5; look.sparkle = 0.5
    let rest = mascotFigure(.of(.mostro), look)
    look.squash = 0.8
    let pressed = mascotFigure(.of(.mostro), look)
    #expect(pressed.z!.boundingBoxOfPath == rest.z!.boundingBoxOfPath)
    #expect(pressed.sparkles!.boundingBoxOfPath == rest.sparkles!.boundingBoxOfPath)
    #expect(pressed.body.boundingBoxOfPath != rest.body.boundingBoxOfPath)   // il corpo invece sì
}
