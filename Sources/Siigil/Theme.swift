import AppKit
import SwiftUI

// Stili della barra (spec 2026-09-26-siigil-temi-design): il vetro di oggi, o quattro temi piatti classici. Ogni tema ha
// una variante chiara e una scura; quale vale lo decidono l'aspetto scelto e, in Automatico, il Mac. Tavolozze dalle
// fonti ufficiali (verificate il 26/9), tutte MIT: Catppuccin, Nord, Dracula, Gruvbox.

// `glass` è lo stile Transparent (27/9): il nome salvato resta quello di prima.
enum BarStyle: String, CaseIterable { case glass, catppuccin, nord, dracula, gruvbox, monochrome }
enum BarAppearance: String, CaseIterable { case automatic, light, dark }

// I ruoli di colore della barra piatta: superficie delle pillole, testo, accento (spazio attivo) e testo sull'accento,
// i colori degli stati (agenti al lavoro, in attesa, finiti; batteria scarica).
struct Palette: Equatable {
    let surface, text, accent, onAccent, blue, yellow, green, red: Color
    var clear = false   // Trasparente chiaro: si disegna col vetro e un velo bianco, non piena (PillBackground)
    var border: Color? = nil   // il bordino delle mascotte attorno alle pillole piene (Monocromo, spec pillole-mascotte §1)
}

extension Color {
    // 0xRRGGBB, come nelle tavolozze ufficiali; i canali li divide cgColor(hex:) (MascotDrawing.swift).
    init(hex: Int) { self.init(cgColor: Siigil.cgColor(hex: hex)) }   // qualificata: Color ha la sua proprietà cgColor
}

private func tones(_ surface: Int, _ text: Int, _ accent: Int, _ onAccent: Int,
                   _ blue: Int, _ yellow: Int, _ green: Int, _ red: Int) -> Palette {
    Palette(surface: Color(hex: surface), text: Color(hex: text), accent: Color(hex: accent), onAccent: Color(hex: onAccent),
            blue: Color(hex: blue), yellow: Color(hex: yellow), green: Color(hex: green), red: Color(hex: red))
}

// Nell'ordine: superficie, testo, accento, sull'accento, blu, giallo, verde, rosso (spec, tabella Tavolozze). Dracula non
// ha un blu: il suo ciano. In Gruvbox l'accento è il giallo.
private let palettes: [BarStyle: (light: Palette, dark: Palette)] = [
    .catppuccin: (tones(0xCCD0DA, 0x4C4F69, 0x8839EF, 0xEFF1F5, 0x1E66F5, 0xDF8E1D, 0x40A02B, 0xD20F39),   // Latte
                  tones(0x313244, 0xCDD6F4, 0xCBA6F7, 0x1E1E2E, 0x89B4FA, 0xF9E2AF, 0xA6E3A1, 0xF38BA8)),  // Mocha
    .nord:       (tones(0xE5E9F0, 0x2E3440, 0x5E81AC, 0xECEFF4, 0x81A1C1, 0xEBCB8B, 0xA3BE8C, 0xBF616A),   // Snow Storm
                  tones(0x3B4252, 0xECEFF4, 0x88C0D0, 0x2E3440, 0x81A1C1, 0xEBCB8B, 0xA3BE8C, 0xBF616A)),  // Polar Night
    .dracula:    (tones(0xCFCFDE, 0x1F1F1F, 0x644AC9, 0xFFFBEB, 0x036A96, 0x846E15, 0x14710A, 0xCB3A2A),   // Alucard
                  tones(0x44475A, 0xF8F8F2, 0xBD93F9, 0x282A36, 0x8BE9FD, 0xF1FA8C, 0x50FA7B, 0xFF5555)),  // Dracula
    .gruvbox:    (tones(0xEBDBB2, 0x3C3836, 0xB57614, 0xFBF1C7, 0x076678, 0xB57614, 0x79740E, 0x9D0006),   // chiaro
                  tones(0x3C3836, 0xEBDBB2, 0xFABD2F, 0x282828, 0x83A598, 0xFABD2F, 0xB8BB26, 0xFB4934)),  // scuro
    .monochrome: (mono(dark: false), mono(dark: true)),
]

// Monocromo (autore, 11/10, prove A1 e A2 di siigil-docs/prototipi-pillole; spec pillole-mascotte §1): il nero e il bianco
// delle mascotte, il bordino grigio del loro corpo attorno alle pillole piene, lo spazio attivo appena più chiaro (scuro)
// o più scuro (chiaro) col testo di sempre, non più invertito; gli stati coi colori del vetro, che in grigio non si
// distinguerebbero.
private func mono(dark: Bool) -> Palette {
    let ink = Color(hex: dark ? 0xF5F7FC : 0x14141A)
    return Palette(surface: Color(hex: dark ? 0x14141A : 0xF1EFE9), text: ink, accent: Color(hex: dark ? 0x34343E : 0xD6D2C7),
                   onAccent: ink, blue: AgentState.working.color(in: nil), yellow: AgentState.waiting.color(in: nil),
                   green: AgentState.done.color(in: nil), red: .red, border: mascotBorder)
}

// Il bordino delle mascotte come colore delle pillole: lo stesso grigio, al 60 % come in drawMascot.
let mascotBorder = Color(cgColor: mascotBorderGray).opacity(0.6)

// Il font di orologio e spazi (autore, 27/9); la batteria resta di sistema. JetBrains Mono tolto il 4/10 (autore): chi
// l'aveva scelto torna a SF Pro, come per ogni nome sconosciuto (Settings).
enum BarFont: String, CaseIterable {
    case system, mono, rounded, serif
    func font(size: CGFloat) -> Font {
        switch self {
        case .system: .system(size: size)
        case .mono: .system(size: size, design: .monospaced)
        case .rounded: .system(size: size, design: .rounded)
        case .serif: .system(size: size, design: .serif)
        }
    }
}

extension View {
    // Il font della barra (orologio, spazi, app a fuoco, titolo della canzone). New York, nella stessa riga, disegna più
    // in alto degli altri tre: 1 pt a 13 pt, mezzo a 12 (misurato sul disegno il 4/10, anche a 16×; le misure del font
    // promettevano 0,3, ma SwiftUI gli dà una riga sua). Lo si abbassa di tanto: centrato come SF Pro.
    func barFont(size: CGFloat) -> some View {
        let f = Settings.shared.barFont
        return font(f.font(size: size)).offset(y: f == .serif ? (size >= 13 ? 1 : 0.5) : 0)
    }
}

// Trasparente chiaro (autore, 27/9): velo bianco (ClearTones), testi scuri come la barra di macOS in chiaro, gli stati
// coi colori di sistema di macOS in chiaro (blu, arancio, verde, rosso), che su fondo chiaro reggono meglio di quelli del
// vetro scuro (il fumetto passa comunque da readable). Fissi, non NSColor di sistema: quelli cambiano con l'aspetto e,
// risolti fuori dal main (i test), bloccavano il processo. Il bordo di trascinamento: nero a metà, come il bianco a metà
// dello scuro.
let clearLight = Palette(surface: .white, text: Color(hex: 0x1C1C1C), accent: .black.opacity(0.5), onAccent: .black.opacity(0.5),
                         blue: Color(hex: 0x007AFF), yellow: Color(hex: 0xFF9500), green: Color(hex: 0x34C759), red: Color(hex: 0xFF3B30),
                         clear: true)

// La tavolozza di uno stile: Trasparente scuro nessuna (i bianchi di sempre), chiaro clearLight.
func palette(_ style: BarStyle, dark: Bool) -> Palette? {
    if style == .glass { return dark ? nil : clearLight }
    return palettes[style].map { dark ? $0.dark : $0.light }
}

// Scuro o chiaro: Automatico segue il Mac, Chiaro e Scuro restano fissi.
func isDark(_ appearance: BarAppearance, system: ColorScheme) -> Bool { appearance == .automatic ? system == .dark : appearance == .dark }

// La barra è scura? L'aspetto scelto in Aspetto; in Automatico quello del Mac, letto dall'app (non dalle finestre di
// Siigil: il Benvenuto è sempre scuro). Per le mini barre di Aspetto e per le tendine.
@MainActor func barIsDark() -> Bool {
    let macDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    return isDark(Settings.shared.barAppearance, system: macDark ? .dark : .light)
}

extension EnvironmentValues {
    // La tavolozza della barra e delle pillole delle mascotte (BarView); nil = vetro.
    @Entry var palette: Palette? = nil
    // Dentro la pillola dello spazio attivo, piena d'accento (PillBackground): l'anello degli agenti ne tiene conto.
    @Entry var onAccent = false
    @Entry var mergedPill = false   // dentro un blocco unico: la pillola non disegna il suo sfondo (Aspetto)
}

// Un colore di stato scritto sulla pillola di un tema: il suo se si legge (contrasto WCAG ≥ 4,5:1, testo piccolo),
// altrimenti il testo della pillola. Giallo e verde sulle varianti chiare scendono a 1,0–4,0:1 (misurato il 27/9 per il
// fumetto della mascotte). Col vetro (nil) i colori di sempre.
func readable(_ color: Color, on palette: Palette?) -> Color {
    guard let palette else { return color }
    return contrast(color, palette.surface) >= 4.5 ? color : palette.text
}

// Contrasto WCAG tra due colori, da 1 a 21.
func contrast(_ a: Color, _ b: Color) -> Double {
    func luminance(_ c: Color) -> Double {
        let r = c.resolve(in: EnvironmentValues())
        return 0.2126 * Double(r.linearRed) + 0.7152 * Double(r.linearGreen) + 0.0722 * Double(r.linearBlue)
    }
    let (x, y) = (luminance(a), luminance(b))
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)
}

extension Optional where Wrapped == Palette {
    var ink: Color { self?.text ?? .white.opacity(0.9) }       // testo e simboli dei widget
    var dim: Color { (self?.text ?? .white).opacity(0.45) }    // fondo della batteria e sua punta
    var alert: Color { self?.red ?? .red }                     // batteria scarica
}
