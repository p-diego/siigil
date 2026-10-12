import CoreGraphics
import Foundation

// Dal JSON di pdf2svg.py (forme e buchi in coordinate SVG) all'SVG finale: forme unite, buchi tolti con le operazioni
// booleane di CoreGraphics (macOS 14+). Uso: boolsvg <in.json> <out.svg>
// Con --rune il logo Bluetooth, che SF Symbols non ha: la runa di BluetoothRune (Widgets.swift), col tratto trasformato in
// contorno pieno senza sovrapposizioni (Icon Composer colora i riempimenti), lato lungo 114,5 come i simboli.
// Uso: boolsvg --rune <out.svg>
struct Shape: Decodable { let d: String; let rule: String }
struct Layer: Decodable { let d: String; let rule: String; let holes: [Shape] }
struct Glyph: Decodable { let w: Double; let h: Double; let layers: [Layer] }

func path(_ d: String) -> CGPath {
    let p = CGMutablePath()
    let scanner = Scanner(string: d)
    scanner.charactersToBeSkipped = .whitespaces
    var cmd: Character = "M"
    func num() -> CGFloat { CGFloat(scanner.scanDouble() ?? 0) }
    while !scanner.isAtEnd {
        if let c = scanner.scanCharacter(), "MLCZ".contains(c) { cmd = c } else { break }
        switch cmd {
        case "M": p.move(to: CGPoint(x: num(), y: num()))
        case "L": p.addLine(to: CGPoint(x: num(), y: num()))
        case "C":
            let a = CGPoint(x: num(), y: num()), b = CGPoint(x: num(), y: num()), c = CGPoint(x: num(), y: num())
            p.addCurve(to: c, control1: a, control2: b)
        default: p.closeSubpath()
        }
    }
    return p
}

func union(_ shapes: [Shape]) -> CGPath? {
    shapes.reduce(nil as CGPath?) { acc, s in
        let next = path(s.d).normalized(using: s.rule == "evenodd" ? .evenOdd : .winding)
        return acc.map { $0.union(next) } ?? next
    }
}

func svgD(_ p: CGPath) -> String {
    var d = ""
    func f(_ pt: CGPoint) -> String { String(format: "%.3f %.3f", pt.x, pt.y) }
    p.applyWithBlock { e in
        let pts = e.pointee.points
        switch e.pointee.type {
        case .moveToPoint: d += "M\(f(pts[0]))"
        case .addLineToPoint: d += "L\(f(pts[0]))"
        case .addQuadCurveToPoint: d += "Q\(f(pts[0])) \(f(pts[1]))"
        case .addCurveToPoint: d += "C\(f(pts[0])) \(f(pts[1])) \(f(pts[2]))"
        case .closeSubpath: d += "Z"
        @unknown default: break
        }
    }
    return d
}

let shape: CGPath, w: Double, h: Double
if CommandLine.arguments[1] == "--rune" {
    let side = 114.5, line = side * 0.1, height = side - line, width = height * 0.55
    func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: line / 2 + x * width, y: line / 2 + y * height) }
    let rune = CGMutablePath()
    rune.addLines(between: [p(0, 0.25), p(1, 0.75), p(0.5, 1), p(0.5, 0), p(1, 0.25), p(0, 0.75)])
    shape = rune.copy(strokingWithWidth: line, lineCap: .round, lineJoin: .round, miterLimit: 10).normalized()
    w = width + line; h = side
} else {
    let g = try! JSONDecoder().decode(Glyph.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
    // Ogni riempimento meno i suoi buchi soltanto, poi tutto insieme.
    let pieces: [CGPath] = g.layers.map { l in
        let piece = path(l.d).normalized(using: l.rule == "evenodd" ? .evenOdd : .winding)
        return union(l.holes).map { piece.subtracting($0) } ?? piece
    }
    shape = pieces.dropFirst().reduce(pieces[0]) { $0.union($1) }
    w = g.w; h = g.h
}
let size = String(format: "%.3f %.3f", w, h)
let svg = """
<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 \(size)" width="\(String(format: "%.3f", w))" height="\(String(format: "%.3f", h))">
  <path fill-rule="nonzero" d="\(svgD(shape))"/>
</svg>

"""
try! svg.write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
print(CommandLine.arguments[2], "ok")
