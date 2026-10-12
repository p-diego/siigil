import SwiftUI
import Testing
@testable import Siigil

// Trasparente scuro resta senza tavolozza (i bianchi di sempre); il chiaro ha la sua, col vetro.
@Test func transparentHasAPaletteOnlyWhenLight() {
    #expect(palette(.glass, dark: true) == nil)
    #expect(palette(.glass, dark: false) == clearLight && clearLight.clear)
    #expect(BarStyle.allCases.filter { $0 != .glass }.allSatisfy { palette($0, dark: false)?.clear == false })
    #expect(readable(clearLight.yellow, on: clearLight) == clearLight.text)   // l'arancio su bianco non basta al fumetto
}

// Ogni tema ha una variante chiara e una scura, diverse tra loro: un refuso che le copiasse o le scambiasse si vede qui.
@Test func everyThemeHasALightAndADarkPalette() {
    for style in BarStyle.allCases where style != .glass {
        let light = palette(style, dark: false), dark = palette(style, dark: true)
        #expect(light != nil && dark != nil && light != dark)
    }
}

// Controlli puntuali sulla tabella della spec (fonti ufficiali).
@Test func palettesUseTheOfficialColors() {
    #expect(palette(.catppuccin, dark: false)?.surface == Color(hex: 0xCCD0DA))
    #expect(palette(.catppuccin, dark: false)?.accent == Color(hex: 0x8839EF))
    #expect(palette(.gruvbox, dark: true)?.surface == Color(hex: 0x3C3836))
    #expect(palette(.gruvbox, dark: true)?.accent == Color(hex: 0xFABD2F))
}

@Test func automaticFollowsTheMacWhileLightAndDarkStayFixed() {
    #expect(isDark(.automatic, system: .dark) && !isDark(.automatic, system: .light))
    #expect(!isDark(.light, system: .dark) && isDark(.dark, system: .light))
}

@Test func hexColorsSplitIntoChannels() {
    #expect(cgColor(hex: 0xFF8000) == CGColor(srgbRed: 1, green: 128.0 / 255, blue: 0, alpha: 1))
}

// Con il vetro valgono i colori di oggi, con un tema quelli della tavolozza.
@Test func glassKeepsTodaysWhitesThemesUseTheirColors() {
    let none: Palette? = nil, nord = palette(.nord, dark: true)
    #expect(none.ink == .white.opacity(0.9) && none.dim == .white.opacity(0.45) && none.alert == .red)
    #expect(nord.ink == Color(hex: 0xECEFF4) && nord.alert == Color(hex: 0xBF616A))
}

// Monocromo coi colori delle mascotte (autore, 11/10; spec pillole-mascotte §1): il nero dello squircle e il bianco del
// sasso, lo spazio attivo appena più chiaro o più scuro e non più invertito (il testo resta quello), il bordino delle
// mascotte; gli stati restano quelli del vetro, che in grigio non si distinguerebbero. Il bordino è solo suo.
@Test func monochromeUsesTheMascotColorsAndBorder() {
    let dark = palette(.monochrome, dark: true)!, light = palette(.monochrome, dark: false)!
    #expect(dark.surface == Color(hex: 0x14141A) && dark.text == Color(hex: 0xF5F7FC) && dark.accent == Color(hex: 0x34343E))
    #expect(light.surface == Color(hex: 0xF1EFE9) && light.text == Color(hex: 0x14141A) && light.accent == Color(hex: 0xD6D2C7))
    for m in [dark, light] {
        #expect(m.onAccent == m.text && m.border == mascotBorder)
        #expect(m.yellow == AgentState.waiting.color(in: nil) && m.green == AgentState.done.color(in: nil))
    }
    for style in BarStyle.allCases where style != .monochrome {
        #expect(palette(style, dark: true)?.border == nil && palette(style, dark: false)?.border == nil, "\(style)")
    }
}

// Sulla pillola dello spazio attivo ogni stato ha i colori di Trasparente (AgentRing passa nil); fuori, quelli del tema.
@Test func ringOnTheActiveSpaceUsesTheTransparentColors() {
    let nord = palette(.nord, dark: true)
    #expect(AgentState.working.color(in: nord) == nord?.blue)
    for state in [AgentState.working, .waiting, .done] {
        #expect(state.color(in: nil) != state.color(in: nord))
    }
}

// Il fumetto sulla pillola del gatto: giallo e verde sulle varianti chiare non si leggono (1,0–4,0:1), lì il testo del tema.
@Test func stateColorsFallBackToTheTextWhereTheyAreUnreadable() {
    let latte = palette(.catppuccin, dark: false)!, mocha = palette(.catppuccin, dark: true)!
    #expect(readable(latte.yellow, on: latte) == latte.text)
    #expect(readable(mocha.yellow, on: mocha) == mocha.yellow)
    for style in BarStyle.allCases {
        guard let light = palette(style, dark: false), let dark = palette(style, dark: true) else { continue }
        #expect(readable(light.green, on: light) == light.text)
        #expect(readable(dark.green, on: dark) == dark.green)
    }
    #expect(readable(.yellow, on: nil) == .yellow)   // vetro: i colori di sempre
    #expect(contrast(.white, .black) > 20.9 && contrast(.white, .black) < 21.1)
}
