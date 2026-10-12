import CoreGraphics
import Foundation

// Il puntatore vero per i video della modalità demo (scripts/demo-video.sh): una lista di passi, in punti dello schermo
// (origine in alto a sinistra), eseguiti in fila. Movimenti morbidi a 60 passi al secondo, come una mano.
//   demo-pointer move 400 19 wait 1.2 click 420 19 drag 470 19 100 19 1.2 wait 1
var args = Array(CommandLine.arguments.dropFirst())
func next() -> Double { Double(args.removeFirst())! }
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
var at = CGEvent(source: nil)?.location ?? .zero
func glide(to p: CGPoint, seconds: Double, as type: CGEventType) {
    let steps = max(1, Int(seconds * 60))
    let from = at
    for i in 1...steps {
        let t = Double(i) / Double(steps), e = t * t * (3 - 2 * t)   // smoothstep: parte e arriva piano
        post(type, CGPoint(x: from.x + (p.x - from.x) * e, y: from.y + (p.y - from.y) * e))
        usleep(16_667)
    }
    at = p
}
while !args.isEmpty {
    switch args.removeFirst() {
    case "move": let p = CGPoint(x: next(), y: next()); glide(to: p, seconds: 0.5, as: .mouseMoved)
    case "click":
        let p = CGPoint(x: next(), y: next())
        glide(to: p, seconds: 0.5, as: .mouseMoved); usleep(120_000)
        post(.leftMouseDown, p); usleep(80_000); post(.leftMouseUp, p)
    case "drag":
        let a = CGPoint(x: next(), y: next()), b = CGPoint(x: next(), y: next()), seconds = next()
        glide(to: a, seconds: 0.5, as: .mouseMoved); usleep(150_000)
        post(.leftMouseDown, a); usleep(150_000)
        glide(to: b, seconds: seconds, as: .leftMouseDragged); usleep(150_000)
        post(.leftMouseUp, b)
    case "wait": usleep(useconds_t(next() * 1_000_000))
    case let other: FileHandle.standardError.write("passo sconosciuto: \(other)\n".data(using: .utf8)!); exit(2)
    }
}
