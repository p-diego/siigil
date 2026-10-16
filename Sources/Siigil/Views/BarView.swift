import SwiftUI

struct BarView: View {
    let state: BarState
    let geometry: PanelGeometry
    private let settings = Settings.shared
    @State private var frames: [BarItem: CGRect] = [:]   // frame di widget e mascotte nella coordinate space "bar" (⌘-trascina)
    @State private var drag: Drag?
    @State private var abandoned: CGFloat?   // l'inizio di un ⌘-trascina interrotto (widget sparito): non ne riparte un altro
    @State private var pillFrames: [String: CGRect] = [:]   // colonne delle pillole spazio nello spazio "bar" (trascina icone)
    @State private var iconDrag: IconDrag?
    @State private var sides: [Side: CGRect] = [:]   // l'area di ogni lato del notch nello spazio "bar" (mascotte: nearNotch)
    @Environment(\.colorScheme) private var scheme   // chiaro/scuro del Mac: il pannello non forza l'aspetto

    var body: some View {
        let leftWidth = geometry.leftWidth, rightWidth = geometry.rightWidth   // di default: pillole a sinistra del notch, mascotte e widget a destra
        let a = arranged   // i due lati: quelli salvati o, mentre trascini, l'anteprima
        let leftDragging = drag.map { a.left.contains($0.id) } ?? false
        // La tavolozza di adesso (nil = Trasparente scuro, Theme.swift): chiaro/scuro dal Mac, il pannello non forza l'aspetto.
        let palette = Siigil.palette(settings.barStyle, dark: isDark(settings.barAppearance, system: scheme))
        HStack(spacing: 6) {
            // ponytail: oltre il notch i widget vengono tagliati; comprimerli se capita davvero
            HStack(spacing: 6) {
                // Con il blocco unico solo mascotte e nascoste restano fuori, ciascuna col suo aspetto (autore, 4/10).
                if settings.mergedLeft { mergedBlock(a.left) }
                ForEach(settings.mergedLeft ? a.left.filter(outsideBlock) : a.left, id: \.self) { id in
                    // Le mascotte attaccate al notch da sinistra (notchGap, Rearrange.swift): il vuoto prima di loro.
                    if leftWidth != nil, id == notchGap(.left, list: a.left, besideNotch: a.besideNotch) { Spacer() }
                    if shows(id) { widget(id).modifier(rearrangeable(id)).transition(.blurReplace) }
                }
            }
            .frame(maxWidth: leftWidth.map { $0 - settings.edgeMargin - settings.notchMargin }, maxHeight: .infinity, alignment: .leading)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("bar")) } action: { sides[.left] = $0 }
            // Il clip lascia 4 pt ai due lati: il bordo del glass (e la pressione) sporge dal frame, anche verso il notch (la
            // mascotte attaccata al notch da sinistra perdeva 1 pt, 27/9). Durante il ⌘-trascina di un widget di sinistra si
            // allarga: altrimenti il widget spariva appena usciva dal suo lato.
            .padding(.horizontal, 4).clipShape(Rectangle().inset(by: leftDragging ? -10_000 : 0)).padding(.horizontal, -4)
            Spacer()
            HStack(spacing: 6) {
                ForEach(settings.mergedRight ? a.right.filter(outsideBlock) : a.right, id: \.self) { id in
                    if shows(id) { widget(id).modifier(rearrangeable(id)).transition(.blurReplace) }
                    // Le mascotte attaccate al notch da destra: il vuoto dopo di loro. Senza notch, attaccate ai widget.
                    if rightWidth != nil, id == notchGap(.right, list: a.right, besideNotch: a.besideNotch) { Spacer() }
                }
                if settings.mergedRight { mergedBlock(a.right) }
            }
            .frame(maxWidth: rightWidth.map { $0 - settings.edgeMargin - settings.notchMargin }, alignment: .trailing)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("bar")) } action: { sides[.right] = $0 }
        }
        .animation(.smooth(duration: 0.3), value: state.reports)
        .animation(.smooth(duration: 0.3), value: state.hidden)
        .animation(.smooth(duration: 0.3), value: state.focus)
        // I fumetti delle mascotte, che allargano la loro pillola: sessioni degli agenti, "Sessione rinnovata!", allarmi (ogni
        // mascotte di sistema vede il più grave dei suoi tipi: contano tutti).
        .animation(.smooth(duration: 0.3), value: state.sessions)
        .animation(.smooth(duration: 0.3), value: QuotaCache.shared.renewed)
        .animation(.smooth(duration: 0.3), value: state.watchdog.alarms.map(\.caption))
        .animation(.smooth(duration: 0.3), value: a.left)   // anche l'anteprima: gli altri si spostano per fare posto
        .animation(.smooth(duration: 0.3), value: a.right)
        .animation(.smooth(duration: 0.3), value: settings.mergedLeft)
        .animation(.smooth(duration: 0.3), value: settings.mergedRight)
        // Il widget trascinato è sparito a metà (l'ultima app nascosta si è chiusa, Wi-Fi spento): il suo gesto non finirà
        // mai, e senza questo tornava spostato e sopra gli altri fino al trascinamento dopo (27/9).
        .onChange(of: drag.map { shows($0.id) }) { _, shown in if shown == false { abandoned = drag?.start; drag = nil } }
        // La finestra si è chiusa o ha lasciato la sua pillola a metà trascinamento: la view del gesto non c'è più, quindi nemmeno la copia.
        .onChange(of: state.reports) { _, reports in
            if let d = iconDrag, !reports.contains(where: { $0.workspace.name == d.from && $0.apps.contains { $0.windowID == d.app.windowID } }) { iconDrag = nil }
        }
        .foregroundStyle(palette?.text ?? .white)
        // Il vetro chiaro o scuro come la barra, anche quando l'aspetto scelto è l'opposto di quello del Mac (27/9).
        .environment(\.colorScheme, isDark(settings.barAppearance, system: scheme) ? .dark : .light)
        // Margine dai bordi dello schermo (Aspetto); tra i lati e il notch il margine dal notch, nelle larghezze sopra.
        .padding(.horizontal, settings.edgeMargin)
        .frame(height: BarPanel.height)
        // ⌘-trascina (Rearrange.swift): un gesto solo per la barra, che all'inizio prende l'elemento sotto il puntatore e
        // sopravvive all'anteprima che lo sposta di fila. Simultaneo: il gesto delle icone delle pillole precede sia
        // `.gesture` sia `.highPriorityGesture` (misurato il 26/9); così girano entrambi, e con ⌘ quello dell'icona si ignora.
        .simultaneousGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named("bar")).modifiers(.command)
                .onChanged { v in
                    if drag != nil { drag?.x = v.location.x; return }
                    guard v.startLocation.x != abandoned,
                          let id = frames.first(where: { settings.isOn($0.key) && shows($0.key)
                              && ($0.value.minX...$0.value.maxX).contains(v.startLocation.x) })?.key
                    else { return }
                    drag = Drag(id: id, start: v.startLocation.x, x: v.location.x, frames: frames, sides: sides)
                }
                .onEnded { v in
                    guard var d = drag else { return }
                    d.x = v.location.x
                    // Il rilascio salva l'anteprima (lo stesso place, e Settings.move fa lo stesso moved); lo scostamento si
                    // azzera nella stessa animazione: l'elemento scivola dal puntatore al suo posto, che è già quello.
                    withAnimation(.smooth(duration: 0.3)) {
                        drag = nil
                        let p = place(d)
                        if let beside = p.besideNotch { settings.setBesideNotch(d.id, beside) }
                        settings.move(d.id, to: p.side, index: p.index)
                    }
                }
        )
        .coordinateSpace(name: "bar")
        // La copia dell'icona trascinata: sopra tutta la barra, fuori dal gruppo ritagliato delle pillole; non riceve click.
        .overlay(alignment: .topLeading) {
            if let d = iconDrag, let icon = appIcon(d.app) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
                    .position(d.location)
                    .allowsHitTesting(false)
            }
        }
        // La tavolozza a tutta la barra (pillole, widget, anelli degli agenti); il cambio di stile o d'aspetto sfuma.
        .environment(\.palette, palette)
        .animation(.smooth(duration: 0.3), value: palette)
    }

    // Mascotte e nascoste (che possono stare su entrambi i lati col ⌘-trascina) restano fuori dal blocco unico.
    private func outsideBlock(_ id: BarItem) -> Bool { id.isMascot || id == .widget(.hidden) }

    // Il blocco unico di un lato (Aspetto): un solo sfondo-pillola attorno alla fila; dentro, i widget senza il loro
    // (mergedPill) ma coi loro margini. Vuoto se non c'è niente da mostrare: nessuna capsula nuda.
    @ViewBuilder private func mergedBlock(_ all: [BarItem]) -> some View {
        let ids = all.filter { !outsideBlock($0) }
        if ids.contains(where: shows) {
            HStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    if shows(id) { widget(id).modifier(rearrangeable(id)).transition(.blurReplace) }
                }
            }
            .environment(\.mergedPill, true)
            .frame(height: 26)   // niente aria interna: la lente dello spazio attivo arriva ai bordi (autore, 4/10)
            .modifier(PillBackground())
        }
    }

    // Un elemento della barra: una mascotte (la sua scheda, letta adesso) o un widget.
    @ViewBuilder private func widget(_ id: BarItem) -> some View {
        switch id {
        case .mascot(let m):
            if let mascot = settings.mascot(m) {
                // guarda verso lo spazio vuoto del suo lato (mirroredMascot)
                let a = arranged   // anche nell'anteprima guarda verso il vuoto del posto in cui finirà
                BarMascot(state: state, mascot: mascot, mirrored: mirroredMascot(id, notch: geometry.rightWidth != nil, left: a.left,
                                                                                  right: a.right, besideNotch: a.besideNotch(id)))
            }
        case .widget(let w): widget(w)
        }
    }

    // Un widget per id (impostazioni: Barra). Le pillole degli spazi sono un widget solo.
    @ViewBuilder private func widget(_ id: WidgetID) -> some View {
        switch id {
        case .workspaces:
            WorkspacesRow {
                ForEach(state.reports, id: \.workspace.name) { r in
                    let name = r.workspace.name
                    let reduced = name.isEmpty   // la pillola ridotta non riceve trascinamenti (spec senza-aerospace §3)
                    WorkspacePill(report: r, frontWindow: settings.showFrontAppName ? state.frontWindow : nil,
                                  highlighted: iconTarget == name, dragging: iconDrag?.app.windowID,
                                  onDrag: reduced ? { _, _ in } : { app, v in dragIcon(app, from: name, v) },
                                  onDrop: reduced ? { _ in } : dropIcon)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("bar")) } action: { pillFrames[name] = $0 }
                        .transition(.blurReplace)
                }
            }
        case .hidden: HiddenPill(apps: state.hidden)   // solo se ci sono app nascoste (shows)
        case .focus: if let f = state.focus { FocusView(focus: f) }
        case .wifi: if let w = state.wifi { WiFiView(wifi: w) }
        case .bluetooth: if let on = state.bluetooth { BluetoothView(on: on) }
        case .nowPlaying: if let t = state.track { NowPlayingView(track: t, artwork: state.artwork) }
        case .volume: if let v = state.volume { VolumeView(volume: v, muted: state.muted) }
        case .battery: if let b = state.battery { BatteryView(battery: b) }
        case .clock: ClockView()
        }
    }

    // Se un widget ha qualcosa da mostrare adesso. Uno vuoto resta fuori dalla riga: con i modificatori del ⌘-trascina
    // prenderebbe comunque un posto e la sua spaziatura, 6 pt in più accanto (misurato il 2026-09-26).
    // Una mascotte eliminata nelle Impostazioni sparisce anche da qui, frame compreso (place).
    private func shows(_ id: BarItem) -> Bool {
        switch id {
        case .mascot(let m): settings.mascot(m) != nil
        case .widget(.hidden): !state.hidden.isEmpty
        case .widget(.nowPlaying): state.track != nil
        case .widget(.focus): state.focus != nil
        case .widget(.wifi): state.wifi != nil
        case .widget(.bluetooth): state.bluetooth != nil
        case .widget(.volume): state.volume != nil
        case .widget(.battery): state.battery != nil
        case .widget(.workspaces), .widget(.clock): true
        }
    }

    private func rearrangeable(_ id: BarItem) -> Rearrangeable { Rearrangeable(id: id, frames: $frames, drag: drag) }

    // Dove finirebbe quello che trascini (dropPlace), sulle posizioni di quando hai cominciato. Il frame di un widget
    // sparito nel frattempo (Wi-Fi spento, nessuna app nascosta) non conta: confonderebbe il rilascio.
    private func place(_ d: Drag) -> (side: Side, index: Int, besideNotch: Bool?) {
        dropPlace(of: d.id, at: d.x, left: settings.left, right: settings.right, leftWidth: geometry.leftWidth,
                  frames: d.frames.filter { shows($0.key) }, sides: d.sides, besideNotch: settings.besideNotch)
    }

    // I due lati come si vedono: quelli salvati o, mentre trascini, come saranno al rilascio (gli altri fanno posto, la
    // mascotte trascinata attaccata dove si attaccherà).
    private var arranged: (left: [BarItem], right: [BarItem], besideNotch: (BarItem) -> Bool) {
        guard let d = drag else { return (settings.left, settings.right, settings.besideNotch) }
        let p = place(d)
        let beside = { (i: BarItem) in i == d.id ? p.besideNotch ?? settings.besideNotch(i) : settings.besideNotch(i) }
        let l = moved(d.id, to: p.side, index: p.index, left: settings.left, right: settings.right, besideNotch: beside)
        return (l.left, l.right, beside)
    }

    // Le cornici degli spazi che ci sono adesso. Mai azzerate a onDisappear: nel passaggio allo sfondo unito (e ritorno) la
    // fila vecchia e quella nuova convivono per la transizione con le stesse chiavi, e l'onDisappear della vecchia cancellava
    // le misure della nuova — il primo spazio, che nessuno rimisura, non riceveva più niente (16/10). Lo stesso modello delle
    // cornici dei widget (place): filtrate al momento dell'uso, così uno spazio sparito non cattura rilasci.
    private var livePillFrames: [String: CGRect] { pillFrames.filter { f in state.reports.contains { $0.workspace.name == f.key } } }

    // La pillola su cui cadrebbe l'icona trascinata (bordo bianco), nil se nessuna.
    private var iconTarget: String? { iconDrag.flatMap { iconDropTarget(at: $0.location, from: $0.from, pills: livePillFrames) } }

    // Il gesto dell'icona parte qui al primo movimento oltre i 4 pt. Con ⌘ premuto è il ⌘-trascina del gruppo: niente.
    // Un gesto di un'altra finestra riparte da capo (la precedente può essere ancora appesa nel ritorno a vuoto).
    private func dragIcon(_ app: AppEntry, from: String, _ v: DragGesture.Value) {
        if iconDrag?.app.windowID != app.windowID {
            guard !NSEvent.modifierFlags.contains(.command) else { return }
            iconDrag = IconDrag(app: app, from: from, start: v.startLocation, location: v.location)
        } else {
            iconDrag?.location = v.location
        }
    }

    // Su un'altra pillola: AeroSpace sposta la finestra (lo spazio la segue se era quella a fuoco) e la barra si aggiorna
    // come dopo ogni azione. Altrove: la copia torna al punto di presa e sparisce.
    private func dropIcon(_ v: DragGesture.Value) {
        guard let d = iconDrag else { return }
        if let to = iconDropTarget(at: v.location, from: d.from, pills: livePillFrames) {
            iconDrag = nil
            moveWindow(id: d.app.windowID, to: to, follow: d.app.windowID == state.frontWindow)
        } else {
            // Solo se nel frattempo non è partito un altro trascinamento.
            withAnimation(.smooth(duration: 0.2)) { iconDrag?.location = d.start } completion: { if iconDrag?.location == d.start { iconDrag = nil } }
        }
    }
}

// Il fondo delle pillole di Trasparente (widget e spazi), scuro come sempre o chiaro (27/9).
// Col vetro, scuro: il vetro scuro con un velo nero sotto e un tint nero. Il tint non cambia la luminosità (misurato il
// 2026-09-26: da 0,25 a 0,32 l'interno resta a 140/255): scurisce solo il velo, un filo per il contrasto (autore,
// 2026-09-26); lo spazio attivo = lo stesso velo più lo scarto di sempre (0,15). Chiaro: il vetro chiaro di macOS e basta
// (autore, 27/9), col velo bianco solo sullo spazio attivo, che senza era identico agli altri (179 contro 178 su 255).
// Senza vetro la pillola è piena: col vetro è luminosa quanto la scrivania (109 contro 106, misurato il 27/9) e si vede
// per il bordo, quindi da piatta le serve un grigio suo, nero o bianco, con lo stesso scarto per lo spazio attivo.
struct ClearTones {
    let light: Bool   // Trasparente chiaro: la sua tavolozza (clearLight, Theme.swift); scuro: nessuna
    init(_ palette: Palette?) { light = palette != nil }
    private var base: Color { light ? .white : .black }
    func veil(active: Bool) -> Color { light ? (active ? base.opacity(0.23) : .clear) : base.opacity(active ? 0.23 : 0.08) }
    var tint: Color? { light ? nil : base.opacity(0.25) }
    var scheme: ColorScheme { light ? .light : .dark }   // il vetro chiaro o scuro, qualunque sia l'aspetto del Mac
    func flat(active: Bool) -> Color { base.opacity(active ? 0.40 : 0.25) }
    // La lente dello spazio attivo nel blocco unico (WorkspaceBackground). Scuro: velo più leggero del 0,23 e tinta
    // un filo blu — il vetro del blocco scurisce già, e scurisce il rosso più del blu: una tinta neutra non basta
    // (tarata sui rapporti pixel con la pillola separata, 4/10). Chiaro: il velo bianco dell'attiva, nessuna tinta.
    var lensVeil: Color { light ? veil(active: true) : base.opacity(0.18) }
    var lensTint: Color? { light ? nil : Color(red: 0.02, green: 0.07, blue: 0.18).opacity(0.22) }
}
// Vetro sopra un tema (27/9): un velo del colore del tema sotto il glass e lo stesso colore, più leggero, nel tint.
let themeGlassVeil = 0.6
let themeGlassTint = 0.35

extension View {
    // Pillola alta 26 dei widget: margini interni e lo sfondo di ogni pillola (PillBackground). Senza sfondo (solo le
    // mascotte, se lo si spegne) resta l'altezza, senza margini ai lati: più stretta, trasparente (autore, 27/9).
    func pill(background: Bool = true) -> some View { modifier(Pill(background: background)) }
}

// Dentro un blocco unico (Aspetto: "Una pillola sola") lo sfondo lo disegna il blocco: la pillola tiene solo i
// suoi margini — e la superficie di click intera, che nelle separate dava PillBackground (senza, i click nei
// margini cadevano attraverso: lo stesso difetto già corretto negli spazi, 4/10).
struct Pill: ViewModifier {
    var background = true
    @Environment(\.mergedPill) private var merged

    func body(content: Content) -> some View {
        let shaped = content.padding(.horizontal, background ? 8 : 0).frame(height: 26)
        if background, !merged { shaped.modifier(PillBackground()) }
        else if background { shaped.contentShape(Rectangle()) }
        else { shaped }
    }
}

// La fila delle pillole degli spazi: 6 pt di distacco tra pillole separate, zero nel blocco unico — lì il distacco
// lo fanno già i margini interni dei segmenti (autore, 4/10).
struct WorkspacesRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.mergedPill) private var merged

    var body: some View {
        HStack(spacing: merged ? 0 : 6, content: content)
    }
}

// Lo sfondo di ogni pillola, widget e spazi. Trasparente (nessuna tavolozza, o quella chiara): il vetro scuro o chiaro
// (ClearTones), o senza vetro una forma piena di grigio. Tema con Vetro: il vetro sopra un velo del colore
// del tema. Tema piatto: una forma piena, la superficie o l'accento se è lo spazio attivo. Senza vetro la pillola si
// schiarisce finché la si preme. Nei temi il testo è quello del tema (sull'accento nello spazio attivo). Il raggio viene
// dalle impostazioni (13 = capsula: le pillole sono alte 26).
struct PillBackground: ViewModifier {
    var active = false
    var height: CGFloat = 26   // le mini barre di Aspetto: la stessa pillola in scala, senza pressione
    @Environment(\.palette) private var palette
    @State private var pressed = false

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Settings.shared.cornerRadius * height / 26)
        let live = height == 26
        if let palette, !palette.clear {
            let color = active ? palette.accent : palette.surface
            let themed = content.foregroundStyle(active ? palette.onAccent : palette.text).environment(\.onAccent, active)
            if Settings.shared.themeGlass {
                // Vetro sopra il tema: la pressione la fa il vetro, niente chiarore.
                themed
                    .background(shape.fill(color.opacity(themeGlassVeil)))
                    .glassEffect(.regular.tint(color.opacity(themeGlassTint)).interactive(live), in: shape)
                    .contentShape(shape)
            } else {
                // In Monocromo col bordino delle mascotte, 1 pt fuori: un tratto da 2 sotto il riempimento, in scala nelle mini
                // barre (spec pillole-mascotte §1). Col vetro acceso (ramo sopra) niente bordino: il bordo lo fa il vetro.
                pressable(themed.background {
                    shape.fill(color)
                        .background { if let border = palette.border { shape.stroke(border, lineWidth: 2 * height / 26) } }
                }, shape)
            }
        } else if Settings.shared.transparentGlass {
            let tones = ClearTones(palette)
            content
                .background(shape.fill(tones.veil(active: active)))
                .glassEffect(.regular.tint(tones.tint).interactive(live), in: shape)
                .environment(\.colorScheme, tones.scheme)
                .contentShape(shape)
        } else {
            pressable(content.background(shape.fill(ClearTones(palette).flat(active: active))), shape)   // Trasparente senza vetro (27/9)
        }
    }

    // Le pillole senza vetro schiariscono finché le si preme (col vetro la pressione la fa il vetro). Pressione che non
    // completa mai: al rilascio il click va al tap della pillola, e il trascina icona e il ⌘-trascina restano quelli di
    // prima (misurato con una sonda, 27/9).
    @ViewBuilder private func pressable(_ view: some View, _ shape: RoundedRectangle) -> some View {
        if height == 26 {
            view
                .brightness(pressed ? 0.08 : 0)
                .animation(.smooth(duration: 0.15), value: pressed)
                .contentShape(shape)
                .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, perform: {}, onPressingChanged: { pressed = $0 })
        } else {
            view   // un'anteprima: il click è del suo riquadro
        }
    }
}
