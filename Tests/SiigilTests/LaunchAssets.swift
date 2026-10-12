import AppKit
import SwiftUI
import Testing
@testable import Siigil

// I pezzi del video di lancio (~/Git/siigil-video, scripts/assets.sh), solo a richiesta: le tre mascotte del video come
// sequenze di PNG trasparenti a 12×, 30 al secondo, nei momenti della storia, e i suoni dell'app come WAV. Stesso motore
// della barra, un'immagine per ogni trentesimo di secondo (nel video niente ridisegni risparmiati).
//   LAUNCH_ASSETS=<cartella> swift test --filter launchAssets
@MainActor @Test(.enabled(if: ProcessInfo.processInfo.environment["LAUNCH_ASSETS"] != nil))   // i colori di SwiftUI sul main
func launchAssets() throws {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["LAUNCH_ASSETS"]!)
    let resolved = { (c: Color) in c.resolve(in: EnvironmentValues()).cgColor }
    let mascots: [(name: String, kind: MascotKind, body: Int, eyes: Int)] = [
        ("mostro", .mostro, 0xF5F7FC, 0x14141A), ("pebble", .pebble, 0xF0B429, 0x14141A), ("squircle", .squircle, 0x14141A, 0xF1EFE9),
    ]
    let moments: [(name: String, mood: MascotMood, seconds: Double, dot: CGColor?)] = [
        ("work", .work, 8, resolved(AgentState.working.color(in: nil))), ("wait", .wait, 6, resolved(AgentState.waiting.color(in: nil))),
        ("alarm", .alarm, 6, resolved(.orange)), ("done", .done, 3, resolved(AgentState.done.color(in: nil))), ("sleep", .sleep, 4, nil),
        ("hello", .wait, 8, nil), ("party", .done, 6, nil),   // il saluto dell'inizio e la festa della fine, senza pallino
    ]
    let saved = MascotLife.spinGap
    MascotLife.spinGap = 2...3   // nel video il giro con gli occhi arriva presto
    defer { MascotLife.spinGap = saved }
    // La tela della barra a 12×, con un margine per saltelli e scintille.
    let scale = 12.0, pad = 40.0
    let W = Int((mascotBarSize.width * scale + pad * 2).rounded(.up)), H = Int((mascotBarSize.height * scale + pad * 2).rounded(.up))
    for (i, m) in mascots.enumerated() {
        for moment in moments {
            let dir = out.appendingPathComponent("\(m.name)/\(moment.name)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            var life = MascotLife(kind: m.kind, seed: UInt64(i + 1))
            life.advance(1, input: MascotInput(mood: .sleep))   // si parte da quieti: il momento comincia col suo ingresso
            let colors = MascotColors(body: cgColor(hex: m.body), eyes: cgColor(hex: m.eyes), dot: moment.dot)
            for frame in 0..<Int(moment.seconds * 30) {
                // la festa ricomincia ogni 2,3 s (finisce dopo 2,4): un fotogramma d'altro e si riparte coi saltelli
                let again = moment.name == "party" && frame > 0 && frame % 69 == 0
                life.advance(1.0 / 30, input: MascotInput(mood: again ? .work : moment.mood, dot: moment.dot != nil))
                let ctx = try #require(CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                ctx.translateBy(x: 0, y: CGFloat(H)); ctx.scaleBy(x: 1, y: -1)   // y in giù
                ctx.translateBy(x: pad, y: pad); ctx.scaleBy(x: scale, y: scale)
                drawMascot(life.geometry, life.look, colors, in: ctx, size: mascotBarSize, mirrored: false)
                let url = dir.appendingPathComponent(String(format: "%05d.png", frame))
                try #require(NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])).write(to: url)
            }
        }
    }
    // I suoni, gli stessi che l'app crea la prima volta che servono (Sounds.swift).
    let sounds = out.appendingPathComponent("sounds")
    try FileManager.default.createDirectory(at: sounds, withIntermediateDirectories: true)
    for effect in Effect.allCases {
        for voice in MascotVoice.allCases {
            try wav(render(effect, voice)).write(to: sounds.appendingPathComponent("\(effect)-\(voice.rawValue).wav"))
        }
    }
}
