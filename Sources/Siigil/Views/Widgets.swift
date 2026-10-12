import SwiftUI
import AppKit

// Si aggiorna allo scoccare del minuto (il primo render è subito, con l'ora corrente). Formato: impostazioni Orologio.
struct ClockView: View {
    @Environment(\.palette) private var palette
    var body: some View {
        TimelineView(.everyMinute) { context in
            let text = clockString(state.clockOverride ?? context.date, format: Settings.shared.clockFormat)
            // Come l'orologio della menu bar: peso regular, bianco al 90% (misurato il 2026-09-26 su una cattura della menu bar:
            // tratto 3,2 px come il regular di AppKit, il medium ne fa 3,7; il testo nativo arriva al 91% tra fondo e bianco).
            Text(text).barFont(size: 13).foregroundStyle(palette.ink)   // font: Aspetto
                .contentTransition(.numericText()).padding(.horizontal, 2).pill()
                // Click: attiva l'app scelta nelle impostazioni, un altro click la nasconde (ClockApp.swift).
                // ⌥-clic: Non disturbare, come l'orologio della menu bar di macOS; un altro ⌥-clic la spegne (Alterna).
                .onTapGesture { NSEvent.modifierFlags.contains(.option) ? toggleDND() : toggleApp(bundle: Settings.shared.clockApp) }
                .animation(.smooth(duration: 0.3), value: text)   // serve al glass interattivo per animare la pressione
        }
    }
}

// Come la batteria della menu bar di macOS 27: capsula traslucida, carica come riempimento
// da sinistra, percentuale (e fulmine in carica) ritagliate nel corpo, nub a destra.
// Menu della batteria al tasto destro (regola unica dei menu: autore, 4/10): la fonte (coi watt alla corrente),
// quando c'è, Risparmio energetico (stato vero; per alternarlo serve la scorciatoia "Siigil Low Power" — macOS non dà
// una via pubblica, stesso schema di Non disturbare; senza, il click apre le Impostazioni), "Battery Settings…".
final class BatteryMenuView: RightClickMenuView {
    override func menu() -> NSMenu {
        let menu = NSMenu()
        let watts = adapterWatts()
        // Come il pannello originale (screenshot dell'autore, 4/10): titolo, la fonte in grigio (da noi anche carica e
        // tempo: scelta dell'autore), "Modalità energetica" con la riga a cerchio del Risparmio. Le "app energivore"
        // dell'originale no: le conosce solo un servizio interno di macOS, e l'autore le ha escluse.
        menu.addItem(menuTitle(String(localized: "Battery")))
        // Una riga sola, come l'originale: la fonte, coi watt quando è alla corrente (autore, 4/10; niente carica e
        // tempo: la carica la dice già la pillola).
        let source = watts.map { String(localized: "Power Source: Power Adapter (\($0) W)") } ?? String(localized: "Power Source: Battery")
        menu.addItem(menuLabel(source))
        menu.addItem(.separator())
        menu.addItem(menuHeader(String(localized: "Energy Mode")))
        let low = MenuIconRow(symbol: "battery.50percent", name: String(localized: "Low Power"),
                              active: ProcessInfo.processInfo.isLowPowerModeEnabled) { [weak menu] in
            toggleLowPower()
            menu?.cancelTracking()
        }
        menu.addItem(menuViewItem(NSHostingView(rootView: low), height: 36))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(String(localized: "Battery Settings…"), #selector(openBatterySettings), target: self))
        return menu
    }

    @objc private func openBatterySettings() { open("x-apple.systempreferences:com.apple.Battery-Settings.extension") }
}

struct BatteryView: View {
    let battery: Battery
    private let bodyWidth: CGFloat = 23
    @Environment(\.palette) private var palette

    // ponytail: rosso a 10% o meno è una stima; misurare sul sistema quando capita. Giallo in Risparmio
    // energetico, come su iOS (autore, 4/10): lo stesso dell'attesa degli agenti.
    private var fill: Color {
        battery.lowPower ? AgentState.waiting.color(in: palette)
            : battery.percent <= 10 ? palette.alert : palette?.text ?? .white.opacity(0.95)
    }

    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                palette.dim
                fill.frame(width: bodyWidth * CGFloat(battery.percent) / 100)
                HStack(spacing: -1) {
                    // "100" col fulmine sfora i 23 pt di poco: il numero si stringe invece di diventare "1…".
                    Text("\(battery.percent)").font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.7)   // regular, come la menu bar
                        .contentTransition(.numericText())
                    if battery.charging {
                        // Il mezzo punto in giù sotto serve alle cifre, non al fulmine, che sta già basso di suo: senza
                        // questo stava 1 pt sotto il centro del corpo, nella menu bar è al centro (misurato il 12/10).
                        Image(systemName: "bolt.fill").font(.system(size: 7, weight: .medium)).offset(y: -1)
                    }
                }
                .frame(width: bodyWidth)
                // Mezzo punto più in basso: centrate sulla riga di testo le cifre (senza discendenti) stanno alte. Misurato sulla
                // menu bar: 4 px sopra e 5 sotto nel corpo di 24; senza offset erano 3 e 6.
                .offset(y: 0.5)
                // Le cifre sono ritagliate nella capsula e mostrano lo sfondo.
                .blendMode(.destinationOut)
            }
            .compositingGroup()
            .frame(width: bodyWidth, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            UnevenRoundedRectangle(bottomTrailingRadius: 2, topTrailingRadius: 2)
                .fill(palette.dim)
                .frame(width: 1.5, height: 4)
        }
        .padding(2)
        .pill()
        .overlay(MenuAnchor { BatteryMenuView() })   // tasto destro: il menu della batteria
        .animation(.smooth(duration: 0.3), value: battery)
    }
}

// L'altoparlante della menu bar di macOS 27: tre onde accese fino al livello; muto = niente onde e la barra
// (`slash` 0...1, quanto è disegnata). Coordinate nel box 19x14 del simbolo.
struct Speaker: View {
    let waves: Int        // onde accese, -1 le nasconde tutte
    var slash: Double
    @Environment(\.palette) private var palette

    var body: some View {
        let value = [0, 0.33, 0.66, 1][max(waves, 0)]
        // Niente .contentTransition(.symbolEffect) qui: spegne l'effetto di pressione del glass interattivo.
        Image(systemName: "speaker.wave.3.fill", variableValue: value)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(palette.ink)
            .mask(alignment: .leading) { Rectangle().frame(width: waves < 0 ? 11 : 40) }
            .modifier(Slashed(progress: slash, from: CGPoint(x: 1.7, y: 2.8), to: CGPoint(x: 13.7, y: 14.8)))
            // Muto: altoparlante e barra al centro del box; stesso box in ogni stato, la larghezza non cambia.
            .offset(x: waves < 0 ? 3.9 : 0)
            .frame(width: 19)
            .padding(2)
    }
}

// La barra dei simboli spenti, come quella di macOS (altoparlante muto, Wi-Fi e Bluetooth spenti): un solco
// trasparente largo 2,5 che stacca il simbolo e sopra il tratto da 1,1. `progress` 0...1 è quanto è disegnata,
// dall'alto; Path non interpola, si anima il numero. Punti nel box del simbolo (per il Wi-Fi misurati su wifi.slash di
// sistema il 4/10).
struct Slashed: ViewModifier, Animatable {
    var progress: Double
    let from: CGPoint, to: CGPoint
    var animatableData: Double { get { progress } set { progress = newValue } }
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        let line = Path { $0.move(to: from); $0.addLine(to: to) }
        let y = from.y + (to.y - from.y) * progress + 1.75
        let clip = Rectangle().path(in: CGRect(x: -10, y: -10, width: 50, height: 10 + y))
        content
            .overlay {
                if progress > 0 {
                    line.stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).fill(.black).blendMode(.destinationOut).clipShape(clip)
                    line.stroke(style: StrokeStyle(lineWidth: 1.1, lineCap: .round)).fill(palette.ink).clipShape(clip)
                }
            }
            .compositingGroup()
    }
}

// Scambio d'icona (muto ↔ volume, Wi-Fi spento ↔ acceso): quella che esce si rimpicciolisce e sfuma, quella che entra
// fa il contrario, dopo.
private let iconZoom = AnyTransition.scale(scale: 0.5).combined(with: .opacity)
private let iconSwap = AnyTransition.asymmetric(insertion: iconZoom.animation(.smooth(duration: 0.2).delay(0.2)),
                                                removal: iconZoom.animation(.smooth(duration: 0.2)))

// Spegnere un simbolo come l'altoparlante muto di macOS, la stessa animazione per volume, Wi-Fi e Bluetooth (autore,
// 4/10). Spegnendo: l'icona esce e rientra quella spenta (anche se è la stessa, come la runa del Bluetooth), poi la
// barra si disegna dall'alto. Riaccendendo l'inverso: la barra si ritira, poi torna l'icona. `icon` riceve quale icona
// disegnare e quanta barra. Si parte già dallo stato giusto (27/9: all'avvio da muto si vedeva lo scambio animato).
// Un cambio nel frattempo annulla i passi ritardati del precedente.
struct SwitchOffIcon<Icon: View>: View {
    let off: Bool
    let icon: (_ off: Bool, _ slash: Double) -> Icon
    @State private var shownOff: Bool   // quale icona è disegnata: segue `off` attraverso l'animazione
    @State private var slash: Double
    @State private var step: DispatchWorkItem?   // il passo ritardato: un cambio nel frattempo annulla quello del precedente

    init(off: Bool, @ViewBuilder icon: @escaping (_ off: Bool, _ slash: Double) -> Icon) {
        self.off = off
        self.icon = icon
        _shownOff = State(initialValue: off)
        _slash = State(initialValue: off ? 1 : 0)
    }

    var body: some View {
        ZStack { icon(shownOff, slash).id(shownOff).transition(iconSwap) }
            .onChange(of: off) { _, now in animate(toOff: now) }
    }

    private func animate(toOff: Bool) {
        if toOff {
            slash = 0
            withAnimation { shownOff = true }
            debounce(&step, after: 0.35) { withAnimation(.easeOut(duration: 0.2)) { slash = 1 } }
        } else {
            withAnimation(.easeIn(duration: 0.15)) { slash = 0 }
            debounce(&step, after: 0.15) { withAnimation { shownOff = false } }
        }
    }
}

// Menu del volume al tasto destro (regola unica dei menu: autore, 4/10): il regolatore, le uscite e gli ingressi con
// la spunta sull'attivo (click = cambia), "Sound Settings…". Il muto sta sull'altoparlante a sinistra del regolatore
// (la voce Silenzia tolta: autore, 4/10). Costruito all'apertura, mai cambiato da aperto.
final class VolumeMenuView: RightClickMenuView {
    override func menu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(menuTitle(String(localized: "Sound")))
        menu.addItem(menuViewItem(NSHostingView(rootView: VolumeSliderRow()), height: 34))
        menu.addItem(.separator())
        // Le uscite e gli ingressi come nel pannello originale: cerchio tondo col simbolo bianco (blu = attivo,
        // grigio = gli altri, MenuRowIcon come il menu Wi-Fi), niente spunte né simboli-modello (che su 27.2 beta
        // negli NSMenuItem non compaiono, provato il 4/10). Un click cambia e chiude.
        func devices(_ title: String, input: Bool) {
            menu.addItem(menuHeader(title))
            let active = defaultDevice(input: input)
            for device in audioDevices(input: input) {
                let symbol = audioDeviceSymbol(transport: device.transport, name: device.name, input: input)
                let row = MenuIconRow(symbol: symbol, name: device.name, active: device.id == active) { [weak menu] in
                    setDefaultDevice(device.id, input: input)
                    menu?.cancelTracking()
                }
                menu.addItem(menuViewItem(NSHostingView(rootView: row), height: 36))
            }
        }
        devices(String(localized: "Output"), input: false)
        devices(String(localized: "Input"), input: true)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(String(localized: "Sound Settings…"), #selector(openSoundSettings), target: self))
        return menu
    }

    @objc private func openSoundSettings() { open("x-apple.systempreferences:com.apple.Sound-Settings.extension") }
}

// L'evidenziazione al passaggio del mouse delle righe cliccabili nostre, come nel pannello del Suono di macOS
// (screenshot dell'autore, 4/10): rettangolo arrotondato chiaro, un filo dentro i bordi del menu.
struct MenuHover: ViewModifier {
    @State private var hovering = false
    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(hovering ? 0.1 : 0)).padding(.horizontal, 5)   // raggio come l'originale (autore, 4/10)
            }
            .onHover { hovering = $0 }
    }
}

// Una riga come nei pannelli di macOS (Suono, Batteria, Bluetooth): cerchio col simbolo bianco (blu da attiva) e nome;
// `loading` (si sta collegando) mette la rotellina nel cerchio al posto del simbolo (autore, 4/10). Il click fa `pick`
// (cambia uscita, alterna il risparmio, collega…), chi la crea chiude il menu se serve.
struct MenuIconRow: View {
    let symbol: String
    let name: String
    let active: Bool
    var loading = false
    let pick: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            MenuRowIcon(symbol: symbol, active: active, size: 28, loading: loading)   // come i cerchi del pannello originale (autore, 4/10)
            Text(name).font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
            Spacer()
        }
        .padding(.horizontal, menuInset)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .modifier(MenuHover())
        .onTapGesture(perform: pick)
    }
}

// Il regolatore dentro il menu, come quello di macOS: muove il volume dell'uscita attiva mentre lo trascini.
// Muto = regolatore a zero, nei due sensi (autore, 4/10): portarlo a zero mette il muto, trascinarlo da muto smuta
// (come il pannello nativo, review 4/10), e il muto da fuori (l'altoparlante a sinistra, la pillola, i tasti) lo porta a
// zero; smutando torna al livello. A zero il livello non si tocca: smutando si ritrova quello di prima. Un'uscita senza
// muto a zero va a volume zero. Il livello si scrive solo se il regolatore se ne scosta: quando si riallinea da solo
// (smutando) riscriverebbe il livello arrotondato al punto percentuale (review 4/10).
struct VolumeSliderRow: View {
    @State private var value = Self.position()

    private static func position() -> Double { state.muted ? 0 : Double(state.volume ?? 0) / 100 }

    var body: some View {
        HStack(spacing: 8) {
            // Come l'originale: altoparlanti grandi e bianchi, non grigi (autore, 4/10). Quello a sinistra: click = muto.
            Image(systemName: "speaker.fill").font(.system(size: 13)).foregroundStyle(.primary)
                .contentShape(Rectangle())
                .onTapGesture { toggleMute() }
            Slider(value: $value, in: 0...1)
                .onChange(of: value) { _, v in
                    if v > 0, abs(v * 100 - Double(state.volume ?? -1)) >= 0.5 { setVolume(Float(v)) }
                    if let device = defaultOutputDevice(), isMuted(device) != (v == 0), !setMuted(v == 0), v == 0 { setVolume(0) }
                }
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 13)).foregroundStyle(.primary)
        }
        .padding(.horizontal, menuInset)
        .onChange(of: state.muted) { value = Self.position() }
    }
}

struct VolumeView: View {
    let volume: Int
    let muted: Bool

    var body: some View {
        // Muto: sparisce il volume, compare il corpo senza onde, si disegna la barra (SwitchOffIcon).
        SwitchOffIcon(off: muted) { off, slash in Speaker(waves: off ? -1 : waves(volume), slash: slash) }
            .pill()
            .overlay(MenuAnchor { VolumeMenuView() })   // tasto destro: il menu del volume
            .onTapGesture { toggleMute() }
            // Il glass interattivo anima la pressione solo dentro un contesto di animazione a valle.
            .animation(.smooth(duration: 0.2), value: volume)
    }
}

// "In riproduzione" (NowPlaying.swift): copertina arrotondata (o la nota, finché non arriva) e titolo troncato —
// niente scorrimento: le animazioni continue nel vetro sono bandite (regola ferma). Click = pausa/riprendi; tasto
// destro = menu con copertina grande, brano, artista, comandi e "Apri <lettore>".
struct NowPlayingView: View {
    let track: Track
    let artwork: NSImage?
    @State private var shown = false            // il titolo: compare al play o al cambio canzone, resta 5 s
    @State private var hide: DispatchWorkItem?
    @Environment(\.palette) private var palette

    var body: some View {
        // Il titolo sta sempre a destra della copertina (autore, 4/10).
        HStack(spacing: 5) {
            if let artwork {
                Image(nsImage: artwork).resizable().interpolation(.high)
                    .frame(width: 16, height: 16).clipShape(RoundedRectangle(cornerRadius: 3))
            } else {
                Image(systemName: "music.note").font(.system(size: 12, weight: .medium)).foregroundStyle(palette.ink)
            }
            title
        }
        .padding(.horizontal, 2)
        .pill()
        .overlay(MenuAnchor { NowPlayingMenuView() })   // tasto destro, regola unica dei menu
        .onTapGesture { NowPlaying.command("playpause") }
        .onAppear { reveal() }
        .onChange(of: track) { old, new in
            if new.title != old.title || (new.playing && !old.playing) { reveal() }
        }
    }

    // Il titolo non sta sempre: 5 s al play o al cambio canzone, poi sparisce. Niente mouseover: faceva rincorrere
    // comparsa e sparizione in un ciclo di ridisegno continuo (rotella, misurato il 4/10: 53% di CPU da fermo).
    @ViewBuilder private var title: some View {
        if shown {
            Text(track.title).barFont(size: 12).foregroundStyle(palette.ink)
                .lineLimit(1).truncationMode(.tail).frame(maxWidth: 110)
                .fixedSize(horizontal: true, vertical: false)
                .transition(.opacity)
        }
    }

    // Mostra il titolo e programma la sparizione; un nuovo motivo di mostra azzera il conto alla rovescia.
    // withAnimation, non .animation sulla vista: l'animazione dichiarata dentro la pillola non muove la fila attorno —
    // la pillola saltava di colpo al posto finale e il testo sfumava nel buco (misurato a raffica di scatti, 4/10).
    private func reveal() {
        withAnimation(.smooth(duration: 0.25)) { shown = true }
        debounce(&hide, after: 5) { withAnimation(.smooth(duration: 0.25)) { shown = false } }
    }
}

// Menu del brano: copertina grande con titolo e artista, i tre comandi, "Apri …".
final class NowPlayingMenuView: RightClickMenuView {
    override func menu() -> NSMenu {
        let menu = NSMenu()
        guard let track = state.track else { return menu }
        // Copertina grande con titolo e artista sotto (default); compatta dalle impostazioni del widget (autore, 4/10).
        // Menu più stretto dei nostri (240 contro 280), con la copertina che lo riempie (autore, 4/10).
        // Le righe leggono lo stato da sole: il menu resta aperto sui comandi (autore, 4/10) e brano, copertina e
        // pausa/riprendi si aggiornano mentre è aperto — cambiano le viste dentro le righe, mai il menu stesso.
        if Settings.shared.bigArtwork {
            menu.addItem(menuViewItem(NSHostingView(rootView: BigTrackRow()), height: 258, width: 240))
        } else {
            menu.addItem(menuViewItem(NSHostingView(rootView: TrackRow()), height: 56, width: 240))
        }
        menu.addItem(.separator())
        menu.addItem(menuViewItem(NSHostingView(rootView: PlayerControlsRow()), height: 36, width: 240))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(String(localized: "Open \(track.player.rawValue)"), #selector(openPlayerItem), target: self))
        return menu
    }

    @objc private func openPlayerItem() {
        if let bundle = state.track?.player.bundle { open("-b", bundle) }
    }
}

// Copertina grande con titolo e artista sotto, come il mini-player di Music: la testata di default del menu.
// Legge lo stato da sola (niente istantanee): col menu aperto brano e copertina restano aggiornati.
struct BigTrackRow: View {
    var body: some View {
        // Copertina a tutta larghezza del menu, testi a sinistra, menu un filo più stretto (autore, 4/10).
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if let artwork = state.artwork { Image(nsImage: artwork).resizable().interpolation(.high) }
                else {
                    RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.08))
                        .overlay { Image(systemName: "music.note").font(.system(size: 42)).foregroundStyle(.secondary) }
                }
            }
            .frame(width: 212, height: 212).clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.track?.title ?? "").font(.system(size: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)).lineLimit(1)
                Text(state.track?.artist ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(width: 212, alignment: .leading)
        .padding(.horizontal, menuInset)   // gli stessi margini degli altri nostri menu (autore, 4/10)
        .padding(.top, 6)
    }
}

// Copertina 48 pt, titolo e artista: la testata compatta del menu del brano. Anche lei legge lo stato da sola.
struct TrackRow: View {
    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let artwork = state.artwork { Image(nsImage: artwork).resizable().interpolation(.high) }
                else { Image(systemName: "music.note").font(.system(size: 20)).foregroundStyle(.secondary) }
            }
            .frame(width: 48, height: 48).clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(state.track?.title ?? "").font(.system(size: NSFont.menuFont(ofSize: 0).pointSize, weight: .semibold)).lineLimit(1)
                Text(state.track?.artist ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, menuInset)
    }
}

// Indietro, pausa/riprendi, avanti: come il mini-player di macOS — pausa/riprendi più grande al centro, salti più
// piccoli, cerchio chiaro al passaggio (autore, 4/10: "i comandi non sembrano molto Apple"). Il menu NON si chiude
// sui comandi, come negli altri nostri menu (autore, 4/10): l'icona pausa/riprendi si aggiorna leggendo lo stato.
struct PlayerControlsRow: View {
    var body: some View {
        HStack(spacing: 22) {
            CircleHoverControl(symbol: "backward.fill", size: 13) { NowPlaying.command("previous track") }
            CircleHoverControl(symbol: state.track?.playing == true ? "pause.fill" : "play.fill", size: 19) { NowPlaying.command("playpause") }
            CircleHoverControl(symbol: "forward.fill", size: 13) { NowPlaying.command("next track") }
        }
        .frame(maxWidth: .infinity)
    }
}

// Un simbolo con il cerchio chiaro al passaggio, come i controlli nativi.
struct CircleHoverControl: View {
    let symbol: String
    let size: CGFloat
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Image(systemName: symbol).font(.system(size: size, weight: .medium))
            .frame(width: 34, height: 34)
            .background { Circle().fill(Color.primary.opacity(hovering ? 0.1 : 0)) }
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
    }
}

// Il Wi-Fi della menu bar di macOS 27: tre tacche accese fino al segnale; spento = il ventaglio pieno con la barra, come
// wifi.slash, con l'animazione del muto (SwitchOffIcon, autore 4/10); acceso ma non collegato = tacche tutte spente;
// lucchetto nell'angolo con una VPN attiva. Stesso box e colore dell'altoparlante.
struct WiFiView: View {
    let wifi: WiFi
    @Environment(\.palette) private var palette
    @Environment(\.mergedPill) private var merged

    var body: some View {
        // Niente .contentTransition(.symbolEffect): spegne l'effetto di pressione del glass interattivo (vedi Speaker).
        SwitchOffIcon(off: !wifi.on) { off, slash in
            Image(systemName: "wifi", variableValue: off ? 1 : Double(wifi.bars) / 3)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
                .modifier(Slashed(progress: slash, from: CGPoint(x: 3.4, y: 0.8), to: CGPoint(x: 15.3, y: 12.7)))
        }
        // Il ventaglio lascia vuoto l'angolo in basso a destra: lì sta il lucchetto, attaccato al ventaglio (largo 18), dove
        // stava nel box di 19. Nel blocco unito niente box, come il Bluetooth, e il lucchetto conta nella larghezza: tra le
        // icone restano solo i margini (11/10).
        .overlay(alignment: .bottomTrailing) {
            if wifi.vpn {
                Image(systemName: "lock.fill").font(.system(size: 7, weight: .bold))
                    .foregroundStyle(palette.ink).offset(x: 2.5, y: 1)
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
            }
        }
        .padding(.trailing, merged && wifi.vpn ? 2 : 0)
        .frame(width: merged ? nil : 19)
        .padding(2)
        .pill()
        .overlay(MenuAnchor { WiFiMenuView() })   // solo tasto destro (regola unica dei menu: autore, 4/10)
        .animation(.smooth(duration: 0.3), value: wifi)   // serve anche al glass interattivo per animare la pressione
    }
}

// Menu del Wi-Fi al tasto destro (regola unica dei menu: autore, 4/10), sul modello di quello di macOS: "Wi-Fi" con
// l'interruttore, la rete (cerchio blu, nome, lucchetto se protetta, traffico sotto il nome), gli IP, la VPN,
// "Wi-Fi Settings…". RightClickMenuView: àncora in basso a sinistra, trasparente ai click sinistri.
final class WiFiMenuView: RightClickMenuView {
    override func pop() {
        // Prima locationManager: crea il CLLocationManager nel processo, altrimenti ssid() dà nil anche con
        // Posizione autorizzata (nessun CLLocationManager esisteva ancora per dare il nome alla rete).
        let status = locationManager.authorizationStatus
        let model = WiFiMenuModel()
        model.refresh()
        let vpn = vpnActive(interfaces())

        let menu = NSMenu()
        var wifiOnly: [NSMenuItem] = []   // spariscono a Wi-Fi spento, come nel menu di macOS
        let separator = NSMenuItem.separator()
        let toggle = MenuSwitchRow(title: String(localized: "Wi-Fi"), on: model.on) { _, on in
            setWiFiPower(on)
            wifiOnly.forEach { $0.isHidden = !on }
            separator.isHidden = !on && !vpn
        }
        menu.addItem(menuViewItem(toggle, height: 32))
        menu.addItem(.separator())
        // Niente intestazione "Known Network": mostriamo una rete sola, il titolo di sezione era rumore (autore, 4/10).
        wifiOnly.append(menuViewItem(NSHostingView(rootView: NetworkRow(model: model)), height: 40))
        // Gli IP, un click li copia (autore, 4/10). Quello pubblico arriva dalla rete: la riga si riempie da sola.
        // Solo a Wi-Fi acceso (le righe altrimenti sono nascoste), con l'IP locale a far da chiave di rete del memo.
        if model.on { Siigil.publicIP(key: model.localIP) { model.publicIP = $0 ?? "—" } }
        wifiOnly.append(.separator())
        wifiOnly.append(menuViewItem(NSHostingView(rootView: IPRow(label: String(localized: "Internal IP"), value: { model.localIP })), height: 28))
        wifiOnly.append(menuViewItem(NSHostingView(rootView: IPRow(label: String(localized: "Public IP"), value: { model.publicIP })), height: 28))
        // Senza Posizione il nome della rete non c'è: la voce che la chiede, sotto la riga della rete.
        if model.connected, model.name == nil {
            let title = status == .notDetermined ? String(localized: "Show network name…") : String(localized: "Allow Location in System Settings…")
            wifiOnly.append(NSMenuItem(title, #selector(askLocation), target: self))
        }
        wifiOnly.forEach { menu.addItem($0); $0.isHidden = !model.on }
        // Anche a Wi-Fi spento (VPN su Ethernet): il lucchetto sull'icona deve trovare la sua spiegazione qui.
        if vpn { menu.addItem(menuViewItem(NSHostingView(rootView: VPNRow()), height: 40)) }
        separator.isHidden = !model.on && !vpn
        menu.addItem(separator)
        menu.addItem(NSMenuItem(String(localized: "Wi-Fi Settings…"), #selector(openWiFiSettings), target: self))
        popUpFromBar(menu, in: self, refresh: model.refresh)
    }

    @objc private func askLocation() { requestLocation() }
    @objc private func openWiFiSettings() { open("x-apple.systempreferences:com.apple.wifi-settings-extension") }
}

// Il logo Bluetooth (SF Symbols non ce l'ha): la runa a tratto continuo, punte a un quarto e a tre quarti
// dell'altezza, incrocio al centro. Lo stesso tracciato fa l'icona delle impostazioni (scripts/settings-icons/boolsvg.swift --rune).
struct BluetoothRune: Shape {
    func path(in r: CGRect) -> Path {
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: r.minX + x * r.width, y: r.minY + y * r.height) }
        var path = Path()
        path.addLines([p(0, 0.25), p(1, 0.75), p(0.5, 1), p(0.5, 0), p(1, 0.25), p(0, 0.75)])
        return path
    }
}

// Il Bluetooth della menu bar di macOS: il logo; spento, barrato con l'animazione del muto. Stesso box e colore del Wi-Fi:
// da solo largo come le altre icone; nel blocco unito senza box, perché tra le icone restino solo i margini, uguali per
// tutti (il box di 19 lasciava 5 pt vuoti per lato attorno al logo, 11/10).
struct BluetoothView: View {
    let on: Bool
    @Environment(\.palette) private var palette
    @Environment(\.mergedPill) private var merged

    var body: some View {
        SwitchOffIcon(off: !on) { _, slash in
            BluetoothRune()
                .stroke(palette.ink, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 7, height: 13)
                .modifier(Slashed(progress: slash, from: CGPoint(x: -2, y: 0.3), to: CGPoint(x: 9.6, y: 11.9)))
        }
        .frame(width: merged ? nil : 19)
        .padding(2)
        .pill()
        .overlay(MenuAnchor { BluetoothMenuView() })   // tasto destro, regola unica dei menu
        .animation(.smooth(duration: 0.3), value: on)   // serve anche al glass interattivo per animare la pressione
    }
}

// Menu del Bluetooth al tasto destro (regola unica dei menu), sul modello di quello di macOS: "Bluetooth" con
// l'interruttore (la scorciatoia "Siigil Bluetooth": macOS non lo dà alle app), i dispositivi abbinati (cerchio blu =
// collegato; click = collega o scollega, il menu resta aperto e la riga si aggiorna da sola), "Bluetooth Settings…".
final class BluetoothMenuView: RightClickMenuView {
    override func pop() {
        let model = BluetoothMenuModel()
        model.refresh()
        let menu = NSMenu()
        var onlyOn: [NSMenuItem] = []   // spariscono a Bluetooth spento, come nel menu di macOS
        let on = state.bluetooth == true
        let showDevices = { (on: Bool) in onlyOn.forEach { $0.isHidden = !on } }
        // La scorciatoia alterna, non imposta: l'interruttore resta fermo finché non ha finito (una seconda pressione ne
        // farebbe partire un'altra), e se non c'è o fallisce torna com'era insieme ai dispositivi (review 4/10).
        menu.addItem(menuViewItem(MenuSwitchRow(title: String(localized: "Bluetooth"), on: on) { row, on in
            row.isEnabled = false
            showDevices(on)
            runShortcut(bluetoothShortcut) { ok in
                row.isEnabled = true
                if !ok { row.isOn = !on; showDevices(!on) }
            }
        }, height: 32))
        menu.addItem(.separator())
        for device in model.devices {
            onlyOn.append(menuViewItem(NSHostingView(rootView: BluetoothDeviceRow(device: device, model: model)), height: 36))
        }
        if model.devices.isEmpty {
            onlyOn.append(menuLabel(String(localized: "No paired devices")))
        }
        onlyOn.append(.separator())
        onlyOn.forEach { menu.addItem($0); $0.isHidden = !on }
        menu.addItem(NSMenuItem(String(localized: "Bluetooth Settings…"), #selector(openBluetoothSettings), target: self))
        popUpFromBar(menu, in: self, refresh: model.refresh)
    }

    @objc private func openBluetoothSettings() { open("x-apple.systempreferences:com.apple.BluetoothSettings") }
}

// I dispositivi abbinati per il menu aperto, riletti ogni secondo: il cerchio si accende quando il collegamento riesce.
@Observable final class BluetoothMenuModel {
    var devices: [PairedDevice] = []
    func refresh() { devices = pairedDevices() }
}

// Un dispositivo: la riga dei pannelli di macOS, collegato = cerchio blu, la rotellina mentre si collega (non più appena
// risulta collegato: la risposta di IOBluetooth può arrivare dopo la rilettura del secondo).
private struct BluetoothDeviceRow: View {
    let device: PairedDevice   // com'era all'apertura: nome e simbolo restano, lo stato si rilegge dal modello
    let model: BluetoothMenuModel

    var body: some View {
        let connected = (model.devices.first { $0.address == device.address } ?? device).connected
        MenuIconRow(symbol: device.symbol, name: device.name, active: connected,
                    loading: bluetoothLinks.pending[device.address] != nil && !connected) {
            bluetoothLinks.toggle(device)
        }
    }
}

// Righe del menu Wi-Fi fatte a mano (NSMenuItem.view): testo allineato alle voci normali (14 pt dal bordo), larghezza
// del menu di macOS. Le righe hanno altezza fissa e cambiano solo dentro: un menu che cambia misura mentre è aperto si
// impagina male (nascondere o mostrare voci intere invece lo rifà bene, provato il 2026-09-23).
let menuInset: CGFloat = 14
let menuRowWidth: CGFloat = 280

// Una riga di menu fatta con una vista (SwiftUI via NSHostingView): stessa larghezza per tutti i menu di Siigil.
// Voce di menu con l'azione e il suo bersaglio in un colpo solo: senza target la voce resta grigia, e i cinque menu
// lo impostavano a mano (audit 3/10).
extension NSMenuItem {
    convenience init(_ title: String, _ action: Selector, target: AnyObject) {
        self.init(title: title, action: action, keyEquivalent: "")
        self.target = target
    }
}

func menuViewItem(_ view: NSView, height: CGFloat, width: CGFloat = menuRowWidth) -> NSMenuItem {
    view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    view.autoresizingMask = .width
    let i = NSMenuItem()
    i.view = view
    return i
}

// Una riga di solo testo nei nostri menu (titoli, intestazioni, righe grigie): la stessa forma, cambiano corpo, peso,
// colore e altezza (review 4/10: era scritta tre volte); di serie la riga grigia. Colori espliciti: il "secondario" di
// SwiftUI nei menu viene spento dalla vibrancy.
func menuLabel(_ text: String, size: CGFloat = NSFont.menuFont(ofSize: 0).pointSize, weight: Font.Weight = .regular,
               opacity: Double = 0.55, height: CGFloat = 22) -> NSMenuItem {
    menuViewItem(NSHostingView(rootView:
        HStack {
            Text(text).font(.system(size: size, weight: weight)).foregroundStyle(Color.primary.opacity(opacity))
            Spacer()
        }.padding(.horizontal, menuInset)
    ), height: height)
}

// Il titolo in grassetto dei pannelli (Suono, Batteria) e l'intestazione di sezione (Uscita, Ingresso…): misure dagli
// screenshot a confronto con l'originale (4/10) — titolo 14 semibold; intestazione ~17 px @2x ≈ 11,5 pt, grigio al
// 55 % (quella di serie, sectionHeader, era quasi della taglia giusta ma troppo scura).
func menuTitle(_ text: String) -> NSMenuItem { menuLabel(text, size: 14, weight: .semibold, opacity: 1, height: 28) }
func menuHeader(_ title: String) -> NSMenuItem { menuLabel(title, size: 11.5, weight: .semibold, opacity: 0.55, height: 20) }

// Un IP col suo nome; un click lo copia negli appunti e la riga risponde "Copiato" per un momento. `value` è una
// chiusura: letta a ogni ridisegno, si riempie quando l'IP pubblico arriva (il menu non si tocca da aperto).
struct IPRow: View {
    let label: String
    let value: () -> String?   // nil = in arrivo ("…"); "—" = lettura fallita, non copiabile (review 4/10)
    @State private var copied = false

    var body: some View {
        let ip = value()
        HStack {
            Text(label).font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
            Spacer()
            Text(copied ? String(localized: "Copied") : (ip ?? "…"))
                .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize, design: copied ? .default : .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, menuInset)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .modifier(MenuHover())
        .onTapGesture {
            guard let ip, ip != "—", !copied else { return }   // il tratto del fallimento non si copia
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(ip, forType: .string)
            copied = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { copied = false }
        }
    }
}

// "Wi-Fi" o "Bluetooth" in grassetto e l'interruttore a grandezza normale, allineato al margine destro come nel menu di
// macOS. Resta grigio: diventa blu solo se Siigil è l'app attiva, e prendersi il primo piano toglierebbe il focus
// all'app in cui si sta lavorando (provato e scartato il 2026-09-23). Cambiarlo non chiude il menu.
// `changed` riceve anche la riga, per rimetterla com'era o fermarla mentre l'azione è in corso (Bluetooth).
final class MenuSwitchRow: NSView {
    private let toggle = NSSwitch()
    private let changed: (MenuSwitchRow, Bool) -> Void

    var isOn: Bool {
        get { toggle.state == .on }
        set { toggle.state = newValue ? .on : .off }
    }
    var isEnabled: Bool {
        get { toggle.isEnabled }
        set { toggle.isEnabled = newValue }
    }

    init(title: String, on: Bool, changed: @escaping (MenuSwitchRow, Bool) -> Void) {
        self.changed = changed
        super.init(frame: NSRect(x: 0, y: 0, width: menuRowWidth, height: 32))
        let label = NSTextField(labelWithString: title)
        label.font = .boldSystemFont(ofSize: NSFont.menuFont(ofSize: 0).pointSize)
        label.sizeToFit()
        label.frame.origin = NSPoint(x: menuInset, y: (frame.height - label.frame.height) / 2)
        toggle.state = on ? .on : .off
        toggle.target = self
        toggle.action = #selector(toggled)
        toggle.sizeToFit()
        toggle.frame.origin = NSPoint(x: frame.width - menuInset - toggle.frame.width, y: (frame.height - toggle.frame.height) / 2)
        toggle.autoresizingMask = .minXMargin
        addSubview(label)
        addSubview(toggle)
    }
    required init?(coder: NSCoder) { nil }

    @objc private func toggled() { changed(self, isOn) }
}

// Il cerchio colorato col simbolo bianco delle righe del menu Wi-Fi di macOS; `loading`: la rotellina, chiara, dentro
// il cerchio al posto del simbolo.
struct MenuRowIcon: View {
    let symbol: String
    let active: Bool
    var size: CGFloat = 26   // 20 nelle voci delle sessioni del menu delle mascotte, grandi come le icone della barra
    var loading = false
    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.small).environment(\.colorScheme, .dark)
            } else {
                Image(systemName: symbol).font(.system(size: size * 12 / 26, weight: .semibold)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .background(Circle().fill(active ? Color(nsColor: .controlAccentColor) : Color.gray.opacity(0.5)))
    }
}

// La rete: cerchio blu da collegata, nome (o "Connected" senza Posizione), traffico sotto, lucchetto se protetta.
private struct NetworkRow: View {
    let model: WiFiMenuModel
    var body: some View {
        HStack(spacing: 8) {
            MenuRowIcon(symbol: "wifi", active: model.connected)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.connected ? model.name ?? String(localized: "Connected") : String(localized: "Not connected"))
                    .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                if let traffic = model.traffic {
                    Text(traffic).font(.system(size: 11).monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if model.connected, model.secure {
                Image(systemName: "lock.fill").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, menuInset)
    }
}

private struct VPNRow: View {
    var body: some View {
        HStack(spacing: 8) {
            MenuRowIcon(symbol: "lock.fill", active: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("VPN").font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                Text("Connected").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, menuInset)
    }
}

// L'àncora di un menu in overlay: `make` la crea una volta sola, e SwiftUI la tiene viva quanto la vista (come AppMenu).
struct MenuAnchor: NSViewRepresentable {
    let make: () -> NSView
    func makeNSView(context: Context) -> NSView { make() }
    func updateNSView(_ view: NSView, context: Context) {}
}

// Full immersione attiva: il simbolo della modalità (luna, letto…), come l'icona della menu bar di macOS. Si vede solo
// da accesa (BarView).
struct FocusView: View {
    let focus: Focus
    @Environment(\.palette) private var palette

    var body: some View {
        Image(systemName: focus.symbol)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 2)
            .pill()
            // Si spegne da qui solo Non disturbare: le altre modalità vorrebbero una scorciatoia ciascuna (spec §3).
            .onTapGesture { if focus.mode == dndMode { toggleDND() } }
            .animation(.smooth(duration: 0.3), value: focus)   // serve anche al glass interattivo per animare la pressione
    }
}
