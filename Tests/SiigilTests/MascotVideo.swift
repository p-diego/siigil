import AppKit
import Testing
@testable import Siigil

// Il video della mascotte viva (spec mascotte viva §7), solo a richiesta:
//   MASCOT_VIDEO=<cartella> [MASCOT_COLORS=14141A,F5F7FC,14141A,F5F7FC] swift test --filter mascotVideo
//   ffmpeg -framerate 60 -i <cartella>/%05d.png -c:v libx264 -pix_fmt yuv420p mascotte.mp4
// 40 s per Mostro e Mirtillo a 6×, barra scura sopra e chiara sotto, mostrati come nella barra (Shown). Colori: corpo e occhi
// del gatto, poi del cane.
@Test(.enabled(if: ProcessInfo.processInfo.environment["MASCOT_VIDEO"] != nil))
func mascotVideo() throws {
    let env = ProcessInfo.processInfo.environment
    let out = URL(fileURLWithPath: env["MASCOT_VIDEO"]!)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let hex = (env["MASCOT_COLORS"] ?? "F5F7FC,14141A,739EFA,14141A").split(separator: ",").compactMap { Int($0, radix: 16) }
    #expect(hex.count == 4, "MASCOT_COLORS: quattro colori esadecimali")
    let blue = CGColor(srgbRed: 0.45, green: 0.69, blue: 1, alpha: 1), yellow = CGColor(srgbRed: 1, green: 0.83, blue: 0.31, alpha: 1)
    let green = CGColor(srgbRed: 0.6, green: 1, blue: 0.6, alpha: 1), orange = CGColor(srgbRed: 1, green: 0.58, blue: 0, alpha: 1)
    let red = CGColor(srgbRed: 1, green: 0.23, blue: 0.19, alpha: 1)
    // secondi; gatto: umore e pallino; Watchdog: umore e pallino. Prima 26 s di sonno fuori dal video: la sbirciata dei
    // 30 s cade dentro la prima scena.
    let scene: [(Double, MascotMood, CGColor?, MascotMood, CGColor?)] = [
        (12, .sleep, nil, .sleep, nil), (10, .work, blue, .watch, nil), (10, .wait, yellow, .alarm, orange), (8, .done, green, .alarm, red)]
    let scale = 6.0, cell = CGSize(width: mascotBarSize.width * scale, height: mascotBarSize.height * scale), cols = 2
    let W = Int(cell.width) * cols, H = Int(cell.height) * 2
    var cat = Shown(.mostro, seed: 1), dog = Shown(.mirtillo, seed: 2)
    cat.warm(26); dog.warm(26)
    var frame = 0
    for (seconds, catMood, catDot, dogMood, dogDot) in scene {
        cat.color(catDot); dog.color(dogDot)
        for _ in 0..<Int(seconds * 60) {
            cat.frame(MascotInput(mood: catMood, dot: catDot != nil))
            dog.frame(MascotInput(mood: dogMood, dot: dogDot != nil))
            let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)   // y in giù
            let bars = [CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1), CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)]
            for (row, bar) in bars.enumerated() {
                let y = CGFloat(row) * cell.height
                ctx.setFillColor(bar); ctx.fill(CGRect(x: 0, y: y, width: CGFloat(W), height: cell.height))
                let who = [(cat, cat.colors(body: hex[0], eyes: hex[1])), (dog, dog.colors(body: hex[2], eyes: hex[3]))]
                for (col, (shown, colors)) in who.enumerated() {
                    ctx.saveGState()
                    ctx.translateBy(x: CGFloat(col) * cell.width, y: y); ctx.scaleBy(x: scale, y: scale)
                    drawMascot(shown.life.geometry, shown.drawn, colors, in: ctx, size: mascotBarSize, mirrored: false)
                    ctx.restoreGState()
                }
            }
            let url = out.appendingPathComponent(String(format: "%05d.png", frame))
            try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
            frame += 1
        }
    }
}

// Una mascotte nel video con le regole della vista (MascotNSView): un'immagine ogni 1/15 s col solo fondo, ogni 1/60 s
// nei gesti; si ridisegna solo con `shouldRedraw`; il pallino che cambia colore sfuma.
private struct Shown {
    var life: MascotLife
    var drawn: MascotLook
    var wait = 0.0                    // secondi alla prossima immagine della vista
    var dot: CGColor?, from: CGColor?
    init(_ kind: MascotKind, seed: UInt64) { life = MascotLife(kind: kind, seed: seed); drawn = life.look }
    mutating func warm(_ seconds: Double) { life.advance(seconds, input: MascotInput(mood: .sleep)); drawn = life.look }
    mutating func color(_ new: CGColor?) {
        if let new, let old = dot, new != old, life.look.dot > 0.01 {
            from = mixColor(from ?? old, old, life.look.dotFade); life.dotColorChanged()
        }
        if new != nil { dot = new }
    }
    mutating func frame(_ input: MascotInput) {   // 1/60 s di video
        life.advance(1.0 / 60, input: input)
        wait -= 1.0 / 60
        guard wait <= 1e-9 else { return }
        wait = 1 / (life.fastFrames ? MascotLife.fastFPS : MascotLife.calmFPS)
        if shouldRedraw(drawn, life) { drawn = life.look }
    }
    func colors(body: Int, eyes: Int) -> MascotColors {
        MascotColors(body: cgColor(hex: body), eyes: cgColor(hex: eyes),
                     dot: dot.map { d in from.map { mixColor($0, d, drawn.dotFade) } ?? d })
    }
}
