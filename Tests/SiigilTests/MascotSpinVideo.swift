import AppKit
import Testing
@testable import Siigil

// Il giro su se stessa in PNG, solo a richiesta (spec sezione Mascotte §10): le nove forme al lavoro, sopra dritte e sotto
// girate (mirrored), dal mezzo secondo prima del primo giro per due secondi e mezzo, a 60 immagini al secondo e 4×.
//   SPIN_VIDEO=<cartella> swift test --filter spinVideo
//   ffmpeg -framerate 60 -i <cartella>/%04d.png -c:v libx264 -pix_fmt yuv420p giro.mp4
@Test(.enabled(if: ProcessInfo.processInfo.environment["SPIN_VIDEO"] != nil))
func spinVideo() throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SPIN_VIDEO"]!)
    try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
    let input = MascotInput(mood: .work, dot: true), scale = 4.0, cell = CGSize(width: mascotBarSize.width * scale, height: mascotBarSize.height * scale)
    // Lo stesso seme: tutte girano nello stesso istante. Si cerca il primo giro e si parte mezzo secondo prima.
    var probe = MascotLife(kind: .mostro, seed: 3)
    let start = try #require(live(&probe, input, until: { $0.turn > 0 }))
    var lives = MascotKind.allCases.map { MascotLife(kind: $0, seed: 3) }
    for i in lives.indices { lives[i].advance(start - 0.5, input: input) }
    for frames in 0..<150 {
        let W = Int(cell.width) * lives.count, H = Int(cell.height) * 2
        let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)
        for (i, life) in lives.enumerated() {
            for row in 0..<2 {
                ctx.saveGState()
                ctx.translateBy(x: CGFloat(i) * cell.width, y: CGFloat(row) * cell.height); ctx.scaleBy(x: scale, y: scale)
                drawMascot(life.geometry, life.look, MascotColors(body: cgColor(hex: 0xF5F7FC), eyes: cgColor(hex: 0x14141A), dot: cgColor(hex: 0x739EFA)),
                           in: ctx, size: mascotBarSize, mirrored: row == 1)
                ctx.restoreGState()
            }
        }
        let url = out.appendingPathComponent(String(format: "%04d.png", frames))
        try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
        for i in lives.indices { lives[i].advance(1.0 / 60, input: input) }
    }
}
