import AppKit
import SwiftUI

// Prova: ImageRenderer di SwiftUI disegna un simbolo in un PDF vettoriale? Uso: symrender <simbolo> <out.pdf>
let name = CommandLine.arguments[1], out = CommandLine.arguments[2]
@MainActor func run() {
    let renderer = ImageRenderer(content: Image(systemName: name).font(.system(size: 100)).foregroundStyle(.black))
    renderer.render { size, draw in
        var box = CGRect(origin: .zero, size: size)
        let ctx = CGContext(URL(fileURLWithPath: out) as CFURL, mediaBox: &box, nil)!
        ctx.beginPDFPage(nil)
        draw(ctx)
        ctx.endPDFPage()
        ctx.closePDF()
        print(name, size)
    }
}
MainActor.assumeIsolated { run() }
