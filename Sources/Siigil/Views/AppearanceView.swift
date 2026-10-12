import AppKit
import SwiftUI

// Impostazioni › Aspetto (spec temi §1), fatta come il pannello Aspetto di macOS: stile e aspetto sono riquadri con una
// mini barra disegnata con la tavolozza vera; sotto, i cursori di margini e arrotondamento, che cambiano la barra dal vivo.
struct AppearancePage: View {
    @Bindable var settings = Settings.shared

    var body: some View {
        Section {
            TileRow(title: "Style", items: BarStyle.allCases) { style in
                Tile(title: style.title, selected: settings.barStyle == style, action: { settings.barStyle = style }) {
                    MiniBar(palette: palette(style, dark: barIsDark()))
                }
            }
            // Chiaro e scuro anche per Trasparente (27/9).
            TileRow(title: "Appearance", items: BarAppearance.allCases) { appearance in
                Tile(title: appearance.title, selected: settings.barAppearance == appearance,
                     action: { settings.barAppearance = appearance }) { preview(appearance) }
            }
            // Il vetro, una scelta per Trasparente e una per i temi (27/9): su Trasparente spento resta il velo scuro, su un
            // tema acceso mette i suoi colori sotto il Liquid Glass (PillBackground).
            if settings.barStyle == .glass {
                Toggle(isOn: $settings.transparentGlass) { RowLabel(title: "Glass", description: "Liquid Glass on the pills. Off, just their dark tint.") }
            } else {
                Toggle(isOn: $settings.themeGlass) { RowLabel(title: "Glass", description: "Theme colours under Liquid Glass.") }
            }
            TileRow(title: "Font", items: BarFont.allCases) { font in
                Tile(title: font.title, selected: settings.barFont == font, action: { settings.barFont = font }) {
                    // l'anteprima: l'ora com'è nella barra, bianca su un fondo scuro
                    ZStack { Color(white: 0.16); Text("12:34").font(font.font(size: 19)).foregroundStyle(.white) }
                }
            }
        }
        Section {
            SliderRow(title: "Screen edge margin", value: $settings.edgeMargin, range: 0...24, icon: "arrow.left.and.right")
            // Solo con un notch: senza, i due lati si toccano e il margine dal notch non c'è.
            if NSScreen.screens.contains(where: { $0.auxiliaryTopLeftArea != nil }) {
                SliderRow(title: "Notch margin", value: $settings.notchMargin, range: 0...40, icon: "arrow.right.and.line.vertical.and.arrow.left")
            }
            SliderRow(title: "Corner rounding", value: $settings.cornerRadius, range: 0...13, icon: "capsule")
        }
        Section {
            // Fusione in un blocco per lato (autore, 4/10): la pressione del vetro diventa del blocco intero.
            Toggle("Merge left pills", isOn: $settings.mergedLeft)
            Toggle("Merge right pills", isOn: $settings.mergedRight)
        }
        Section {
            // Tutto l'aspetto com'era al primo avvio (Settings.resetAppearance).
            Button("Reset style") { withAnimation(.smooth(duration: 0.3)) { settings.resetAppearance() } }
        }
    }

    @ViewBuilder private func preview(_ appearance: BarAppearance) -> some View {
        let style = settings.barStyle
        switch appearance {
        case .light: MiniBar(palette: palette(style, dark: false))
        case .dark: MiniBar(palette: palette(style, dark: true))
        case .automatic:   // metà chiara e metà scura, come il riquadro Auto di macOS
            MiniBar(palette: palette(style, dark: false))
                .overlay { MiniBar(palette: palette(style, dark: true)).mask(HStack(spacing: 0) { Color.clear; Color.black }) }
        }
    }
}

extension BarStyle {
    var title: LocalizedStringKey {
        switch self {
        case .glass: "Transparent"; case .catppuccin: "Catppuccin"; case .nord: "Nord"; case .dracula: "Dracula"
        case .gruvbox: "Gruvbox"; case .monochrome: "Monochrome"
        }
    }
}

extension BarFont {
    var title: LocalizedStringKey {
        switch self { case .system: "SF Pro"; case .mono: "SF Mono"; case .rounded: "SF Rounded"; case .serif: "New York" }
    }
}

extension BarAppearance {
    var title: LocalizedStringKey {
        switch self { case .automatic: "Automatic"; case .light: "Light"; case .dark: "Dark" }
    }
}

// Un riquadro come quelli di macOS: l'anteprima con gli angoli arrotondati, il bordo nell'accento di sistema se è la
// scelta attuale, il nome sotto.
// È un pulsante: in un Form i testi (il nome, "12:34" nei riquadri dei font) si prendevano i click e il tap non
// arrivava (misurato il 27/9 con una sonda: rispondevano solo i bordi). Il pulsante prende il click su tutto il riquadro,
// e funziona anche da tastiera e con VoiceOver.
// Sei stili in una riga di circa 580 pt: 6 × 84 + 5 × 12 (27/9).
let tileSize = CGSize(width: 84, height: 56)

struct Tile<Preview: View>: View {
    let title: LocalizedStringKey
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let preview: Preview

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(width: tileSize.width, height: tileSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .white.opacity(0.15), lineWidth: selected ? 3 : 1))
                // Un nome più largo del riquadro sborda un poco invece di allargarlo: le distanze restano uguali.
                Text(title).font(.callout).foregroundStyle(selected ? .primary : .secondary).fixedSize()
            }
            .frame(width: tileSize.width)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// Una riga di riquadri sotto la sua etichetta (autore, 27/9): da sinistra, sempre alla stessa distanza tra loro. La usano
// stile, aspetto e font.
struct TileRow<Items: RandomAccessCollection, Content: View>: View where Items.Element: Hashable {
    let title: LocalizedStringKey
    let items: Items
    @ViewBuilder let tile: (Items.Element) -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
            HStack(spacing: 12) {
                ForEach(items, id: \.self) { tile($0) }
            }
        }
    }
}

// Una barra in miniatura su uno sfondo sfumato che fa da desktop: tre pillole, quella in mezzo attiva, con il raggio
// delle impostazioni in scala. Senza tavolozza, il vetro; con Vetro acceso, il vetro sopra i colori del tema, in ogni
// riquadro (stile e aspetto), come la barra.
private struct MiniBar: View {
    let palette: Palette?

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(hex: 0x5B7FBF), Color(hex: 0xC78CB2)], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Le pillole vere in scala (PillBackground): una regola sola per la barra e per le sue anteprime.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { i in   // quella in mezzo attiva
                    Color.clear.frame(width: 21, height: 12).modifier(PillBackground(active: i == 1, height: 12))
                }
            }
            .padding(.top, 8)
        }
        .environment(\.palette, palette)
    }
}

// Un cursore come quello del Liquid Glass di macOS: il valore in numeri a sinistra, un simbolo a destra, numeri interi.
// Lo usano Aspetto (margini, arrotondamento, in pt) e Mascotte (volume, in %, col pulsante Prova davanti).
struct SliderRow: View {
    let title: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let icon: String
    var unit = "pt"
    var action: (title: LocalizedStringKey, run: () -> Void)? = nil

    var body: some View {
        LabeledContent(title) {
            // Il valore e il simbolo in una riga: le etichette di Slider devono essere dello stesso tipo.
            HStack(spacing: 8) {
                if let action { Button(action.title, action: action.run) }   // a sinistra del valore (autore, 27/9)
                Text(verbatim: "\(Int(value)) \(unit)").monospacedDigit().foregroundStyle(.secondary).frame(width: 44, alignment: .trailing)
                // Numeri interi arrotondati qui, non con `step`: con lo step macOS disegna una tacca per valore, e sul volume
                // (0–100) diventavano una fila di puntini sotto il cursore (27/9).
                Slider(value: Binding(get: { value }, set: { value = $0.rounded() }), in: range)
                // Tutti nello stesso riquadro: i simboli hanno larghezze diverse e i cursori finivano in punti diversi (27/9).
                Image(systemName: icon).font(.system(size: 13)).foregroundStyle(.secondary).frame(width: 24)
            }
            .frame(width: action == nil ? 300 : 360)
        }
    }
}
