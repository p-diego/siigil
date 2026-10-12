import AppKit
import SwiftUI

// Icona dal pid dell'app, non dal nome: più processi possono chiamarsi uguale (l'app Shortcuts e il servizio XPC
// ShortcutsViewService, con l'icona generica, che compariva per primo). Cache per bundle id, per nome se manca.
private var iconCache: [String: NSImage] = [:]

func appIcon(_ app: AppEntry) -> NSImage? {
    let key = app.bundle.isEmpty ? app.name : app.bundle
    if let cached = iconCache[key] { return cached }
    // in demo le app d'esempio non sono aperte: l'icona dal bundle installato (Demo.swift)
    guard let icon = NSRunningApplication(processIdentifier: app.pid)?.icon ?? (demo != nil ? appIcon(bundle: app.bundle) : nil) else { return nil }
    iconCache[key] = icon
    return icon
}

// Misure: numero con 12 px a sinistra e 6 a destra, icone 20 pt a 6 px, 12 px prima del bordo.
// Trascinare un'icona su un'altra pillola sposta la finestra (IconDrag.swift): il gesto sta qui, simultaneo, così la
// pillola riceve ancora il suo tap e il gruppo il suo ⌘-trascina; lo stato e il rilascio li gestisce BarView.
struct WorkspacePill: View {
    let report: SpaceReport
    let frontWindow: Int?
    let highlighted: Bool                // è la pillola su cui cadrebbe l'icona trascinata
    let dragging: Int?                   // windowID dell'icona che si sta trascinando: qui resta attenuata
    let onDrag: (AppEntry, DragGesture.Value) -> Void
    let onDrop: (DragGesture.Value) -> Void
    @Environment(\.palette) private var palette

    var body: some View {
        let focused = report.workspace.isFocused
        let reduced = report.workspace.name.isEmpty   // senza AeroSpace (reducedReport): click = attiva l'app, niente spazio né trascinamento
        // Dentro il blocco gli stessi margini della pillola separata (12 per lato): uno spazio vuoto è largo uguale
        // ovunque — i margini per posizione rendevano le larghezze "strane" (autore, 4/10).
        HStack(spacing: 6) {
            // La pillola ridotta si presenta: un simbolo al posto del nome dello spazio — e da vuota non è una capsula muta (autore, 3/10).
            if reduced {
                Image(systemName: "macwindow").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Text(report.workspace.name).barFont(size: 13).fixedSize()
            }
            ForEach(report.apps, id: \.windowID) { app in
                // Il nome accanto all'app a fuoco: gli id delle finestre sono unici, il confronto basta da solo
                // (prima c'era anche `focused &&`, ridondante con AeroSpace e falso in ridotto, dove id = pid).
                AppIconView(app: app, showName: app.windowID == frontWindow, dimmed: app.windowID == dragging,
                            action: { reduced ? showApp(app) : focusWindow(id: app.windowID) })
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 4, coordinateSpace: .named("bar"))
                            .onChanged { onDrag(app, $0) }
                            .onEnded { onDrop($0) }
                    )
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .modifier(WorkspaceBackground(focused: focused))   // vetro o tema; nel blocco unico un'evidenziazione interna
        .overlay {
            // Sull'attiva il bordo è già il colore dell'accento (lo sfondo): serve il testo sull'accento, per rimanere visibile.
            // In Monocromo il grigio del bordino (autore, 11/10): l'attivo ora è vicino al fondo e non si vedrebbe.
            if highlighted {
                RoundedRectangle(cornerRadius: Settings.shared.cornerRadius)
                    .strokeBorder(palette.map { $0.border ?? (focused ? $0.onAccent : $0.accent) } ?? .white.opacity(0.5), lineWidth: 1)
            }
        }
        .onTapGesture { if !reduced { switchTo(workspace: report.workspace.name) } }
        .animation(.smooth(duration: 0.3), value: focused)
    }
}

// Lo sfondo di uno spazio: la solita pillola, oppure — dentro il blocco unico (Aspetto) — niente vetro suo e lo
// spazio attivo evidenziato da una forma piatta interna, come la lente dei pannelli di macOS.
struct WorkspaceBackground: ViewModifier {
    let focused: Bool
    @Environment(\.mergedPill) private var merged
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        if merged {
            // Nei temi il testo segue l'accento; con Trasparente (anche chiaro, la cui tavolozza serve solo da
            // colori) il testo resta quello del blocco — l'accento di clearLight è un nero 0,5 da bordo, non da fondo.
            let themed = palette?.clear == false
            content
                .foregroundStyle(themed && focused ? palette!.onAccent : palette?.text ?? .white)
                .environment(\.onAccent, themed && focused)
                .contentShape(Rectangle())   // la superficie di click di tutto il segmento: nelle separate la dava PillBackground (fix 4/10: i click cadevano attraverso)
                .background { if focused { lens } }
        } else {
            content.modifier(PillBackground(active: focused))
        }
    }

    // La lente segue gli stessi quattro casi dello sfondo delle pillole (PillBackground), in scala da evidenziazione
    // interna: tema con vetro, tema piatto, Trasparente col vetro (scuro o chiaro), Trasparente piatto. Col vetro
    // scuro è vetro nel vetro del blocco, che scurisce già: velo leggero e tinta un filo blu, tarati sui rapporti
    // pixel fino a combaciare con la pillola separata (4/10).
    @ViewBuilder private var lens: some View {
        let shape = RoundedRectangle(cornerRadius: Settings.shared.cornerRadius)
        if let palette, !palette.clear, Settings.shared.themeGlass {
            shape.fill(palette.accent.opacity(themeGlassVeil))
                .glassEffect(.regular.tint(palette.accent.opacity(themeGlassTint)), in: shape)
        } else if let palette, !palette.clear {
            shape.fill(palette.accent)
        } else if Settings.shared.transparentGlass {
            let tones = ClearTones(palette)
            shape.fill(tones.lensVeil).glassEffect(.regular.tint(tones.lensTint), in: shape)
        } else {
            shape.fill(ClearTones(palette).flat(active: true))
        }
    }
}

// Le app senza finestre visibili (nascoste, minimizzate, chiuse): solo icone attenuate, click = mostra. Quella a
// tutto schermo in uno spazio nativo è piena: è parcheggiata altrove, non minimizzata (autore, 3/10).
struct HiddenPill: View {
    let apps: [AppEntry]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(apps, id: \.name) { app in
                AppIconView(app: app, showName: false, action: { showApp(app) })
                    .opacity(app.fullscreenElsewhere ? 1 : 0.6)   // nessuna pillola: solo le icone
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .animation(.smooth(duration: 0.3), value: apps)
    }
}

struct AppIconView: View {
    let app: AppEntry
    let showName: Bool    // è l'app in primo piano: nome accanto all'icona
    var dimmed = false      // la sua icona si sta trascinando altrove
    let action: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if let icon = appIcon(app) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2)
                    .overlay { AgentRing(state: app.agent) }
            }
            if showName {
                // Si apre dall'icona e vi si richiude: mai fuori dalla pillola mentre cambia larghezza.
                Text(app.name).barFont(size: 13).fixedSize()
                    .transition(.scale(scale: 0, anchor: .leading).combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .opacity(dimmed ? 0.3 : 1)
        // Simultaneo, non esclusivo: anche la pillola riceve il click (il glass anima la pressione);
        // il suo `workspace N` è un no-op se siamo già lì.
        .simultaneousGesture(TapGesture().onEnded(action))
        .overlay(AppMenu(app: app))   // sopra: riceve il click destro, inoltra i sinistri
        .animation(.smooth(duration: 0.3), value: showName)
    }
}

// I colori degli stati, gli stessi per il bordo delle icone e per i fumetti delle mascotte. Col vetro quelli di sempre: blu
// fisso (non l'accento di sistema: con accento verde o giallo si confonderebbe con finito e in attesa), il giallo
// #FFD34F, verde chiaro. Con un tema il suo blu, giallo e verde.
extension AgentState {
    func color(in palette: Palette?) -> Color {
        switch self {
        case .working: palette?.blue ?? Color(nsColor: .systemBlue)   // puro (autore, 12/10: schiarito al 35 % era spento)
        case .waiting: palette?.yellow ?? Color(red: 1, green: 0.83, blue: 0.31)   // #FFD34F
        case .done: palette?.green ?? Color(red: 0.6, green: 1, blue: 0.6)
        }
    }
}

// Stato dell'agente AI attorno all'icona (spec agenti §4, rivista il 2026-09-24 sera): un bordo fisso di 1 pt sul
// margine esterno dell'icona, blu = al lavoro, giallo = aspetta te, verde = finito. Nessuna
// animazione: ogni fotogramma in più nella finestra di vetro lo paga il compositore (~1 % di WindowServer per fps,
// spec prestazioni); il movimento lo fanno le mascotte. Compare e sparisce con il withAnimation del Poller.
struct AgentRing: View {
    let state: AgentState?
    @Environment(\.palette) private var palette
    @Environment(\.onAccent) private var onAccent   // sulla pillola dello spazio attivo

    var body: some View {
        if let state {
            // Sullo spazio attivo, pieno d'accento, ogni stato ha i colori di Trasparente (autore, 27/9: in Nord il blu
            // spariva sull'azzurro, in Gruvbox il giallo sul giallo); fuori, il colore del tema.
            RoundedRectangle(cornerRadius: 5).strokeBorder(state.color(in: onAccent ? nil : palette), lineWidth: 1)
                .padding(1)   // l'icona di macOS non riempie i suoi 20 pt: il bordo corre appena fuori dal suo margine
                .shadow(color: .black.opacity(0.6), radius: 0.5)   // stacco sulle icone chiare
                .transition(.opacity)
        }
    }
}
