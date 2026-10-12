import CoreGraphics

// Il disegno della mascotte viva (spec mascotte viva §1 e §3): i tracciati di un istante nella tela 100 (y in giù) e il
// loro disegno in un CGContext, lo stesso nella barra, nelle Impostazioni, nei test e nel video. Piatta, col bordino
// grigio da 1 pt attorno al corpo; il pallino davanti, col suo bordino.

struct MascotColors { var body, eyes: CGColor; var dot: CGColor? }

// I pezzi di un istante.
struct MascotFigure {
    var body: CGPath
    var eyes: [CGPath]
    var dot: CGPath?    // il pallino di stato, davanti al corpo
    var z: CGPath?
    var zAlpha = 0.0
    var sparkles: CGPath?
    var heart: CGPath?  // il cuoricino (spec pillole-mascotte §2), anche sopra la tela (y negativa)
    var heartAlpha = 0.0
}

// headroom: le unità sopra la tela dove il cuoricino può salire (la vista è alta 100 + headroom).
func mascotFigure(_ g: MascotGeometry, _ look: MascotLook, headroom: Double = 0) -> MascotFigure {
    // il corpo: schiacciato o allungato dalla base (che resta a terra), inclinato attorno alla base, sollevato
    let sx = 1 + (1 - look.squash) * 0.6
    let t = CGAffineTransform(translationX: 0, y: -look.lift).translatedBy(x: 50, y: 90)
        .rotated(by: look.tilt).scaledBy(x: sx, y: look.squash).translatedBy(x: -50, y: -90)
    // "z" e scintille seguono saltello e inclinazione, non lo schiacciamento (spec pillole-mascotte §2).
    let td = CGAffineTransform(translationX: 0, y: -look.lift).translatedBy(x: 50, y: 90)
        .rotated(by: look.tilt).translatedBy(x: -50, y: -90)
    let body = moved(g.shape.body, t)
    // la faccia scorre con lo sguardo (eyePlace)
    let gx = look.gazeX, p = min(max(look.dot, 0), 1.2)
    var face = CGPoint(x: 50 + gx * g.faceX, y: g.eyeY + look.gazeY * g.faceY)
    let k = g.eyes.size   // il cursore della grandezza (spec §10)
    func sized(_ pose: EyePose) -> EyePose { EyePose(w: pose.w * k, h: pose.h * k, bend: pose.bend, lid: pose.lid) }
    func eye(_ s: Double, _ pose: EyePose, _ d: CGVector) -> CGPath {
        let at = eyePlace(side: s, gaze: gx, face: face, gap: g.eyeGap, drift: d)
        return eyePath(sized(pose), center: at.center, widthScale: at.squeeze)
    }
    if p > 0.01 {   // gli occhi fanno posto al pallino (dotNudge)
        let n = dotNudge(eyeBox: eye(1, look.right, look.rightShift).boundingBoxOfPath, dot: g.shape.dotCenter, p: p)
        face.x += n.dx; face.y += n.dy
    }
    let sides = [(-1.0, look.left, look.leftShift), (1.0, look.right, look.rightShift)]
    var eyes: [CGPath]
    if look.turn > 0, look.turn < 1 {
        // il giro su se stessa (spec sezione Mascotte §10, come Grok): la sagoma resta ferma e gli occhi fanno il giro della
        // testa, attorno al cilindro largo quanto lei all'altezza degli occhi (head, spunEye)
        let places = sides.map { (eyePlace(side: $0.0, gaze: gx, face: face, gap: g.eyeGap, drift: $0.2), sized($0.1)) }
        let reach = places.map { $0.1.h / 2 + 1.3 }.max()!, ys = places.map(\.0.center.y)   // mezza altezza più la curva degli archetti
        let head = g.shape.head(ys.min()! - reach, ys.max()! + reach)
        eyes = places.compactMap { at, pose in
            let w = max(pose.w * at.squeeze, 0.6), x = at.center.x
            guard let (l, r) = spunEye(left: x - w / 2, right: x + w / 2, axis: head.axis, radius: head.radius, angle: 2 * .pi * look.turn)
            else { return nil }
            return moved(eyePath(pose, center: CGPoint(x: (l + r) / 2, y: at.center.y), widthScale: (r - l) / pose.w), t)
        }
    } else {
        eyes = sides.map { moved(eye($0, $1, $2), t) }
    }
    if let d = look.dizzy {   // confusa (spec pillole-mascotte §2): al posto degli occhi due spirali che girano in versi opposti
        eyes = eyes.enumerated().map { i, e in
            let b = e.boundingBoxOfPath
            return spiral(CGPoint(x: b.midX, y: b.midY), d, direction: i == 0 ? 1 : -1, size: k)
        }
    }
    var fig = MascotFigure(body: body, eyes: eyes)
    if p > 0.01 {   // il pallino davanti al corpo, fermo anche nel giro: cresce da niente con un piccolo rimbalzo (la molla del modello)
        let c = g.shape.dotCenter, r = MascotKind.dotRadius * p
        fig.dot = moved(CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil), t)
    }
    if let q = look.z {   // la "z" sale dall'angolo in alto del corpo, verso il davanti, e sfuma
        let size = 11 + 4 * q
        fig.z = moved(zGlyph, CGAffineTransform(translationX: 84 + 4 * q, y: 30 - 8 * q).scaledBy(x: size, y: size).concatenating(td))
        fig.zAlpha = sin(.pi * min(max(q, 0), 1))
    }
    if let q = look.sparkle {   // quattro scintille attorno al corpo, una dopo l'altra (come il prototipo)
        let b = g.shape.body.boundingBoxOfPath, out = CGMutablePath()
        let spots = [CGPoint(x: b.minX - 4, y: b.minY + 4), CGPoint(x: b.maxX + 2, y: b.minY - 2),
                     CGPoint(x: b.maxX + 5, y: b.midY + 8), CGPoint(x: b.minX - 6, y: b.midY + 12)]
        for (k, s) in spots.enumerated() {
            let qq = min(1, max(0, q * 1.3 - Double(k) * 0.1))
            if qq > 0 { out.addPath(star(CGPoint(x: min(max(s.x, 5), 95), y: min(max(s.y, 5), 92)), 6 * sin(.pi * qq))) }
        }
        fig.sparkles = moved(out, td)
    }
    if let h = look.heart {   // il cuoricino: centrato sopra la testa, con la punta appoggiata; spunta con un rimbalzo, sale appena, sfuma
        let top = g.shape.body.boundingBoxOfPath
        let pop = h < 0.18 ? 0.3 + 0.95 * h / 0.18 : 1.25 - 0.25 * min(1, (h - 0.18) / 0.12)
        let half = CGSize(width: 14.8 * pop, height: 12.95 * pop)   // 8 × 7 pt alla grandezza 100 %
        // sale di 1,5 pt (autore, 11/10, nella barra: "centrato e più in basso"), ma col suo bordino (1 pt) non esce mai dallo
        // spazio sopra la tela: con le mascotte grandi sale meno
        let y = max(top.minY - 12.5 - 5.5 * h - look.lift, -headroom + half.height + 1 / 0.27)
        fig.heart = heartPath(CGRect(x: top.midX - half.width, y: y - half.height, width: 2 * half.width, height: 2 * half.height))
        fig.heartAlpha = h < 0.6 ? 1 : 1 - (h - 0.6) / 0.4
    }
    return fig
}

// Dove sta un occhio (side -1 il sinistro, 1 il destro) e quanto si stringe: la faccia scorre con lo sguardo, l'occhio dal
// lato dove guarda si stringe come su una superficie curva e i due si avvicinano un poco. La stessa regola per il disegno
// (mascotFigure) e per lo scorrimento che tiene gli occhi dentro la sagoma (MascotGeometry).
func eyePlace(side: Double, gaze gx: Double, face: CGPoint, gap: Double, drift: CGVector) -> (center: CGPoint, squeeze: Double) {
    (CGPoint(x: face.x + side * gap * (1 - 0.1 * abs(gx)) + drift.dx, y: face.y + drift.dy), 1 - (side * gx > 0 ? 0.25 : 0.06) * abs(gx))
}

// Un occhio nel giro su se stessa: i suoi due bordi (left, right) sono punti di un cilindro verticale (asse e raggio della
// testa, head) che gira di `angle` verso il davanti (destra, prima di girare la mascotte). Si vede la parte davanti: verso
// il bordo si stringe, poi va dietro (nil) e torna stretto dal bordo opposto; a un giro intero è di nuovo dov'era. Un bordo
// che da fermo sta già oltre il cilindro (occhi grandi, agli estremi dei cursori) tiene il suo scarto: così il primo e
// l'ultimo istante sono la figura ferma, e il bordo non va mai oltre il punto dove sta da fermo, dentro la sagoma. Gli
// altri non escono dal cilindro, quindi nemmeno loro dalla sagoma.
func spunEye(left: Double, right: Double, axis cx: Double, radius r: Double, angle: Double) -> (left: Double, right: Double)? {
    guard r > 0 else { return nil }
    func edge(_ x: Double) -> (angle: Double, offset: Double) {
        let a = asin(min(max((x - cx) / r, -1), 1))
        return (a + angle, x - cx - r * sin(a))   // lo scarto è zero se il bordo sta sul cilindro
    }
    let lo = edge(left), hi = edge(right)
    for front in [0.0, 2 * .pi] {   // il davanti, prima e dopo il giro intero
        let l = max(lo.angle, front - .pi / 2), h = min(hi.angle, front + .pi / 2)
        if l < h { return (cx + r * sin(l) + lo.offset, cx + r * sin(h) + hi.offset) }
    }
    return nil
}

// Gli occhi fanno posto al pallino grande `p`, come in Grok: se la scatola dell'occhio di destra arriva al cerchio o al suo
// anello di 1 pt (più mezza unità di respiro), tutta la faccia si scosta, lungo la retta dal centro del pallino, di quanto
// manca. Il rimbalzo del pallino quando compare (`p` fin verso 1,13) non spinge più in là: i cursori degli occhi sono
// provati col pallino a 1 (eyesFitWithDot), oltre gli occhi potrebbero uscire dalla sagoma.
func dotNudge(eyeBox b: CGRect, dot c: CGPoint, p: Double) -> CGVector {
    let q = CGPoint(x: min(max(c.x, b.minX), b.maxX), y: min(max(c.y, b.minY), b.maxY))   // il punto della scatola più vicino
    let d = hypot(q.x - c.x, q.y - c.y), room = MascotKind.dotRadius * min(p, 1) + 1 / 0.27 + 0.5
    guard d > 0 && d < room else { return .zero }
    return CGVector(dx: (q.x - c.x) / d * (room - d), dy: (q.y - c.y) / d * (room - d))
}

// Il grigio del bordino delle mascotte (il `bordered` di base.swift, tolto il 10/10): generico, ≈ 0,68 in sRGB; si disegna
// al 60 %. Lo usano anche le pillole di Monocromo (mascotBorder, Theme.swift).
let mascotBorderGray = CGColor(gray: 0.62, alpha: 1)

// Disegna un istante in un contesto con y in giù, in punti: la tela di 100 è alta quanto `size`, centrata in larghezza.
// Girata, il davanti va a sinistra. Con headroom la vista è più alta: la tela di 100 resta alta quanto prima e scende di
// headroom unità (sopra sale il cuoricino).
func drawMascot(_ g: MascotGeometry, _ look: MascotLook, _ colors: MascotColors, in ctx: CGContext, size: CGSize, mirrored: Bool, headroom: Double = 0) {
    let fig = mascotFigure(g, look, headroom: headroom), s = size.height / (100 + headroom)
    ctx.saveGState()
    if mirrored { ctx.translateBy(x: size.width, y: 0); ctx.scaleBy(x: -1, y: 1) }
    ctx.translateBy(x: (size.width - 100 * s) / 2, y: headroom * s)
    ctx.scaleBy(x: s, y: s)
    func fill(_ paths: [CGPath], _ color: CGColor) { ctx.setFillColor(color); for p in paths { ctx.addPath(p); ctx.fillPath() } }
    // il bordino: un tracciato riempito e ripassato con una linea larga 2 / 0,27 unità della tela (2 pt alla taglia della
    // barra, 27 pt di altezza: ne resta fuori 1), grigio al 60 % in un solo strato, così riempimento e linea non si
    // sommano. Ogni tracciato ha il suo; quello del pallino sta in un anello bucato nel corpo, così si vede come quello
    // del corpo
    let gray = mascotBorderGray
    func border(_ path: CGPath) {
        ctx.setAlpha(0.6)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        ctx.setFillColor(gray); ctx.setStrokeColor(gray); ctx.setLineWidth(2 / 0.27); ctx.setLineJoin(.round)
        ctx.addPath(path); ctx.drawPath(using: .fillStroke)
        ctx.endTransparencyLayer()
        ctx.setAlpha(1)
    }
    // Tutta la mascotte in uno strato: così il taglio attorno al pallino buca solo lei, non quello che c'è sotto.
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    border(fig.body)
    fill([fig.body], colors.body)
    fill(fig.eyes, colors.eyes)
    if let dot = fig.dot, let color = colors.dot {
        // il pallino davanti, staccato dal corpo da un anello di 1 pt dove si vede la barra col grigio sopra: lo stesso
        // bordo del corpo (autore, 10/10: sopra il nero il grigio da solo sembrava più scuro)
        ctx.setBlendMode(.clear)
        ctx.addPath(dot); ctx.setLineWidth(2 / 0.27); ctx.drawPath(using: .fillStroke)
        ctx.setBlendMode(.normal)
        border(dot)
        fill([dot], color)
    }
    if let z = fig.z { fill([z], CGColor(srgbRed: 0.7, green: 0.8, blue: 1, alpha: fig.zAlpha)) }
    if let sp = fig.sparkles { fill([sp], CGColor(srgbRed: 1, green: 0.85, blue: 0.35, alpha: 1)) }
    if let heart = fig.heart {   // il cuoricino rosa col bordino, che sfuma tutto insieme
        ctx.saveGState()
        ctx.setAlpha(fig.heartAlpha)
        ctx.beginTransparencyLayer(auxiliaryInfo: nil)
        border(heart)
        fill([heart], CGColor(srgbRed: 1, green: 0.42, blue: 0.55, alpha: 1))
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }
    ctx.endTransparencyLayer()
    ctx.restoreGState()
}

// Un punto della vista (y in giù) nella tela, col davanti a destra anche quando la mascotte è girata; con headroom la tela
// sta sotto lo spazio in più (drawMascot).
func canvasPoint(_ p: CGPoint, size: CGSize, mirrored: Bool, headroom: Double = 0) -> CGPoint {
    let s = size.height / (100 + headroom), ox = (size.width - 100 * s) / 2
    return CGPoint(x: ((mirrored ? size.width - p.x : p.x) - ox) / s, y: p.y / s - headroom)
}

// Un occhio: la barretta (rettangolo arrotondato) con la palpebra che ne taglia la cima e la curva che la piega ad
// archetto. Si deformano i punti del tracciato, così ogni forma passa nell'altra senza scatti.
func eyePath(_ p: EyePose, center c: CGPoint, widthScale k: Double) -> CGPath {
    let w = max(p.w * k, 0.6), h = max(p.h, 0.6), r = min(w, h) / 2 - 0.001
    let box = CGPath(roundedRect: CGRect(x: -w / 2, y: -h / 2, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil)
    let top = -h / 2 + p.lid * h
    func deform(_ q: CGPoint) -> CGPoint {
        let u = q.x / (w / 2)
        return CGPoint(x: c.x + q.x, y: c.y + max(q.y, top) - 1.3 * p.bend * (1 - u * u))
    }
    let out = CGMutablePath()
    var last = CGPoint.zero
    box.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: out.move(to: deform(pts[0])); last = pts[0]
        case .addLineToPoint:   // un lato lungo in pezzi corti, così si piega con gli altri punti
            let n = max(1, Int((hypot(pts[0].x - last.x, pts[0].y - last.y) / 0.4).rounded(.up)))
            for i in 1...n {
                let t = Double(i) / Double(n)
                out.addLine(to: deform(CGPoint(x: last.x + (pts[0].x - last.x) * t, y: last.y + (pts[0].y - last.y) * t)))
            }
            last = pts[0]
        case .addCurveToPoint: out.addCurve(to: deform(pts[2]), control1: deform(pts[0]), control2: deform(pts[1])); last = pts[2]
        case .closeSubpath: out.closeSubpath()
        default: break   // un rettangolo arrotondato ha solo punti, lati, curve cubiche e chiusura
        }
    }
    return out
}

func cgColor(hex v: Int) -> CGColor {
    CGColor(srgbRed: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255, alpha: 1)
}

// Fra due colori in sRGB (il pallino che cambia stato sfuma).
func mixColor(_ a: CGColor, _ b: CGColor, _ t: Double) -> CGColor {
    let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let x = a.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
          let y = b.converted(to: srgb, intent: .defaultIntent, options: nil)?.components, x.count == 4, y.count == 4 else { return b }
    let k = min(max(t, 0), 1)
    return CGColor(srgbRed: x[0] + (y[0] - x[0]) * k, green: x[1] + (y[1] - x[1]) * k, blue: x[2] + (y[2] - x[2]) * k, alpha: 1)
}

func moved(_ p: CGPath, _ t: CGAffineTransform) -> CGPath {
    var t = t
    return p.copy(using: &t)!
}

// La "z" del sonno in un quadrato di lato 1 centrato: due barre e la diagonale, squadrata come il font dei fumetti.
private let zGlyph: CGPath = {
    let p = CGMutablePath()
    p.addLines(between: [(0, 0), (1, 0), (1, 0.22), (0.36, 0.78), (1, 0.78), (1, 1), (0, 1), (0, 0.78), (0.64, 0.22), (0, 0.22)]
        .map { CGPoint(x: $0.0 - 0.5, y: $0.1 - 0.5) })
    p.closeSubpath()
    return p
}()

// La scintilla del prototipo (star): quattro punte morbide.
private func star(_ c: CGPoint, _ r: Double) -> CGPath {
    let k = r * 0.24, p = CGMutablePath()
    p.move(to: CGPoint(x: c.x, y: c.y - r))
    p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
    p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - k, y: c.y - k))
    p.closeSubpath()
    return p
}

// Una spirale al posto di un occhio (confusa): 2,2 giri, raggio 6,6 per la grandezza degli occhi, tratto 2,2, 1,6 giri al
// secondo nel verso `direction`; compare e sparisce nel primo e nell'ultimo 12 % della reazione. Un tracciato pieno, come
// gli occhi, così drawMascot la riempie col colore degli occhi.
private func spiral(_ c: CGPoint, _ d: Double, direction: Double, size k: Double) -> CGPath {
    let grow = min(1, d / 0.12) * min(1, (1 - d) / 0.12), turns = 2.2, r = 6.6 * k * grow
    let spin = d * MascotLife.dizzyTime * 1.6 * 2 * .pi * direction
    let p = CGMutablePath()
    for i in 0...60 {
        let th = Double(i) / 60 * turns * 2 * .pi, q = r * Double(i) / 60
        let pt = CGPoint(x: c.x + q * cos(th + spin), y: c.y + q * sin(th + spin))
        if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
    }
    return p.copy(strokingWithWidth: max(2.2 * k * grow, 0.01), lineCap: .round, lineJoin: .round, miterLimit: 10)
}

// Il cuoricino nel riquadro r (y in giù): due lobi tondi in alto e la punta in basso (la prova di prototipi-pillole).
private func heartPath(_ r: CGRect) -> CGPath {
    let p = CGMutablePath(), w = r.width, h = r.height, x = r.minX, y = r.minY
    p.move(to: CGPoint(x: x + w / 2, y: y + h))
    p.addCurve(to: CGPoint(x: x, y: y + h * 0.32), control1: CGPoint(x: x + w * 0.2, y: y + h * 0.78), control2: CGPoint(x: x, y: y + h * 0.58))
    p.addArc(center: CGPoint(x: x + w * 0.25, y: y + h * 0.3), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: false)
    p.addArc(center: CGPoint(x: x + w * 0.75, y: y + h * 0.3), radius: w * 0.25, startAngle: .pi, endAngle: 0, clockwise: false)
    p.addCurve(to: CGPoint(x: x + w / 2, y: y + h), control1: CGPoint(x: x + w, y: y + h * 0.58), control2: CGPoint(x: x + w * 0.8, y: y + h * 0.78))
    p.closeSubpath()
    return p
}
