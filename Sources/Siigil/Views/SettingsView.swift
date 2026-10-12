import AppKit
import CoreLocation
import SwiftUI
import UniformTypeIdentifiers

// Le impostazioni con la barra laterale, come Impostazioni di Sistema (autore, 27/9), secondo le linee guida Apple
// ("Sidebars", "Split views", "Settings": siigil-docs/apple-settings-specs.md). Barra laterale nativa: List in stile sidebar con
// la selezione di sistema e le icone col colore d'accento (quelle dell'autore, se ci sono). A destra un form raggruppato
// per pagina; Pillole apre la schermata di ogni widget come Notifiche, Mascotte la pagina di ogni mascotte. Indietro e avanti
// nella toolbar, con la cronologia tra pagine e schermate, come Impostazioni di Sistema. Il titolo della finestra è la pagina
// visibile; alla riapertura, anche dopo un riavvio, l'ultima vista.
enum Page: String, CaseIterable {
    case general, pills, appearance, mascots, ai
    var name: String {
        switch self {
        case .general: String(localized: "General"); case .pills: String(localized: "Pills"); case .appearance: String(localized: "Appearance")
        case .mascots: String(localized: "Mascots")
        case .ai: String(localized: "AI accounts")   // era Monitor AI: il valore salvato resta `ai`, chi l'aveva aperta la ritrova
        }
    }
}

// Lo sfondo delle pagine, quasi nero, anche nel Benvenuto (autore, 4/10). Il Benvenuto è sempre scuro; le
// impostazioni seguono il Mac, e in chiaro resta lo sfondo di sistema. I contenitori restano quelli di sistema: un
// fondo nostro sotto le righe è stato provato e bocciato (autore, 4/10).
// Un ramo solo: con due (if/else) cambiare chiaro/scuro a finestra aperta rifaceva la pagina da capo (scorrimento e
// stato persi; review 4/10).
struct PageBackground: ViewModifier {
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        let dark = scheme == .dark
        content.scrollContentBackground(dark ? .hidden : .automatic)
            .background { if dark { Color(white: 0.07).ignoresSafeArea() } }
    }
}

// Dove si è nella finestra: una pagina e, in Pillole, la schermata di un widget; in Mascotte, la pagina di una mascotte.
struct SettingsPlace: Equatable {
    var page: Page
    var widget: WidgetID? = nil
    var mascot: UUID? = nil
}

struct SettingsRoot: View {
    @AppStorage("siigil.settingsPane") private var page = Page.general   // HIG: "Restore the most recently viewed pane"
    // La cronologia, come Impostazioni di Sistema: indietro e avanti nella toolbar valgono tra le pagine e le schermate.
    @State private var back: [SettingsPlace] = []
    @State private var forward: [SettingsPlace] = []
    @State private var widget: WidgetID?   // la schermata aperta in Pillole
    @State private var mascot: UUID?       // la pagina aperta in Mascotte
    private let settings = Settings.shared

    private var here: SettingsPlace { SettingsPlace(page: page, widget: widget, mascot: mascot) }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { page }, set: { if let p = $0 { go(SettingsPlace(page: p)) } })) {
                ForEach(Page.allCases, id: \.self) { p in
                    Label {
                        Text(p.name)
                    } icon: {
                        // Le icone dell'autore a 24 pt (autore, 27/9: 4 pt più di quelle di Impostazioni di Sistema).
                        SettingsIcon(name: "pane-\(p.rawValue)", size: 24)
                    }
                }
            }
            .listStyle(.sidebar)
            // navigationSplitViewColumnWidth da sola lascia la colonna a ~145 pt (misurato il 27/9, come nel 24/9): serve il frame.
            .frame(width: 220)
            .navigationSplitViewColumnWidth(220)
            .toolbar(removing: .sidebarToggle)   // finestra a misura fissa, come Impostazioni di Sistema: la barra resta
        } detail: {
            Group {
                if let id = mascot {
                    MascotScreen(id: id)
                } else if let w = widget {
                    WidgetScreen(w: w)
                } else {
                    Form {
                        switch here.page {
                        case .general: GeneralPage()
                        case .pills: BarPage(open: { go(SettingsPlace(page: .pills, widget: $0)) })
                        case .appearance: AppearancePage()
                        case .mascots: MascotsPage(open: { go(SettingsPlace(page: .mascots, mascot: $0)) })
                        case .ai: AIPage()
                        }
                    }
                    .formStyle(.grouped)
                }
            }
            .modifier(PageBackground())
            .navigationTitle(mascot.flatMap(settings.mascot).map { Text($0.title) } ?? widget.map { Text($0.title) } ?? Text(here.page.name))
            // Indietro e avanti in una capsula prima del titolo, sempre presenti e spenti quando non c'è dove andare, come in
            // Impostazioni di Sistema (screenshot dell'autore, 27/9); ⌘[ e ⌘] come lì.
            .toolbar {
                ToolbarItemGroup(placement: .navigation) {
                    Button { step(from: &back, to: &forward) } label: { Image(systemName: "chevron.left") }
                        .disabled(back.isEmpty).keyboardShortcut("[", modifiers: .command).help(String(localized: "Back"))
                    Button { step(from: &forward, to: &back) } label: { Image(systemName: "chevron.right") }
                        .disabled(forward.isEmpty).keyboardShortcut("]", modifiers: .command).help(String(localized: "Forward"))
                }
            }
        }
        // La finestra non viene mai distrutta: chiusa, si riapre sulla pagina (non sulla schermata) e senza cronologia.
        .onChange(of: SettingsShown.shared.open) { _, open in if !open { widget = nil; mascot = nil; back = []; forward = [] } }
        // Una mascotte eliminata: si torna all'elenco, e indietro e avanti non riportano alla sua pagina.
        .onChange(of: settings.mascots.map(\.id)) { _, ids in
            let alive = Set(ids)
            if let m = mascot, !alive.contains(m) { mascot = nil }   // prima: `here` diventa l'elenco
            back = pruned(back, alive: alive, here: here); forward = pruned(forward, alive: alive, here: here)
        }
        // "Impostazioni…" nel menu di una mascotte: la sua pagina (spec sezione Mascotte §9, punto 2).
        .onChange(of: SettingsShown.shared.goTo, initial: true) { _, place in arrive(place) }
    }

    private func arrive(_ place: SettingsPlace?) {
        guard let place else { return }
        SettingsShown.shared.goTo = nil
        go(place)
    }

    private func go(_ place: SettingsPlace) {
        guard place != here else { return }
        back.append(here)
        forward = []
        show(place)
    }

    private func step(from: inout [SettingsPlace], to: inout [SettingsPlace]) {
        guard let place = from.popLast() else { return }
        to.append(here)
        show(place)
    }

    private func show(_ place: SettingsPlace) {
        page = place.page
        widget = place.widget
        mascot = place.mascot
    }
}

extension WidgetID {
    var title: LocalizedStringKey {
        switch self {
        case .workspaces: "Workspaces"; case .hidden: "Hidden apps"
        case .focus: "Focus"; case .wifi: "Wi-Fi"; case .bluetooth: "Bluetooth"; case .nowPlaying: "Now Playing"
        case .volume: "Volume"; case .battery: "Battery"; case .clock: "Clock"
        }
    }
    // Sotto il nome, nella card in cima alla schermata del widget.
    var about: LocalizedStringKey {
        switch self {
        case .workspaces: "AeroSpace workspaces, with the icons of their windows."
        case .hidden: "Apps that are running without a visible window."
        case .focus: "The active Focus mode, as in the macOS menu bar."
        case .wifi: "Signal and VPN; right-click for the networks menu."
        case .bluetooth: "Right-click for your devices: click one to connect it."
        case .nowPlaying: "What's playing in Spotify or Music. Click = play/pause; needs Automation on first use."
        case .volume: "Output volume, as in the macOS menu bar."
        case .battery: "Battery level and charging, as in the macOS menu bar."
        case .clock: "Date and time. ⌥-click turns Do Not Disturb on or off."
        }
    }
}

// Titolo e, sotto, la descrizione in grigio: la parte sinistra di una riga.
struct RowLabel: View {
    let title: LocalizedStringKey
    let description: LocalizedStringKey?   // nil se manca solo a volte; una riga che non l'ha mai usa Text o Toggle("…", isOn:)
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let description { Text(description).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

private struct GeneralPage: View {
    @Bindable var settings = Settings.shared
    var body: some View {
        Section { AboutCard() }
        Section {
            Toggle("Launch at login", isOn: Binding(get: { settings.launchAtLogin }, set: { settings.setLaunchAtLogin($0) }))
            if let e = settings.launchAtLoginError { Text(e).font(.callout).foregroundStyle(.red) }
            Toggle(isOn: $settings.menuBarHidden) {
                RowLabel(title: "Hide the macOS menu bar", description: settings.didHideMenuBar ? "Siigil turned this on when it was installed; the bar takes its place." : nil)
            }
            Toggle(isOn: $settings.edgeTiling) {
                RowLabel(title: "Snap windows to screen edges (macOS)", description: settings.didDisableTiling ? "Siigil turned this off when it was installed: AeroSpace arranges the windows." : nil)
            }
        }
        .modifier(Watching { settings.refreshLaunchAtLogin(); settings.refreshMenuBar(); settings.refreshEdgeTiling() })
        // Il Benvenuto del primo avvio, riaperto da qui (prima era la voce Setup… nel menu della mascotte: autore, 27/9).
        Section {
            HStack {
                RowLabel(title: "Setup", description: "The first-launch checklist: basic settings, permissions and AI agents.")
                Spacer()
                Button("Open…") { WelcomeWindow.shared.open() }
            }
        }
    }
}

// In cima a Generali (autore, 27/9): icona, nome, una riga su cos'è, e sotto versione e aggiornamento (Updater.swift,
// spec aggiornamento §1): lo stato accanto al numero, "Check now" sempre, "What's new" e "Update" quando c'è una
// versione nuova, "Download the DMG" dopo un'installazione fallita.
private struct AboutCard: View {
    let updater = Updater.shared
    var body: some View {
        // L'icona a sinistra, in pari col bordo delle righe sotto; a destra nome, descrizione, versione e aggiornamento
        // (autore, 27/9).
        HStack(spacing: 12) {
            // Stesso vuoto a sinistra e a destra del disegno (autore, 27/9): le righe del Form rientrano già di 10 pt, e il
            // margine trasparente dell'icona (100 su 1024 per lato) c'è da tutte e due le parti; ne mancano 2.
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 80, height: 80).padding(.leading, 12 - 10)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "Siigil").font(.system(size: 22, weight: .bold))
                Text("The bar for AeroSpace: workspaces, widgets and mascots that keep an eye on your AI agents and your Mac.")
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Text([String(localized: "Version \(updater.current)"), status].compactMap { $0 }.joined(separator: " · "))
                        .font(.callout).foregroundStyle(.secondary)
                    buttons
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 6)
    }

    @ViewBuilder private var buttons: some View {
        switch updater.state {
        case .available(let r):
            Link("What's new", destination: r.page)
            Button("Update") { Task { await updater.install() } }
        case .failed:
            Link("Download the DMG", destination: latestReleasePage)
        default:
            EmptyView()
        }
        Button("Check now") { Task { await updater.check() } }
    }

    // Scaricamento ed errore d'installazione prima di tutto; poi un controllo fallito; poi l'esito dell'ultimo controllo.
    private var status: String? {
        switch (updater.state, updater.checkError) {
        case (.downloading(let r), _): String(localized: "Downloading \(r.version)…")
        case (.failed(let reason), _): String(localized: "Update failed: \(reason)")
        case (_, let e?): String(localized: "Couldn't check: \(e)")
        case (.upToDate, _): String(localized: "Up to date")
        case (.available(let r), _): String(localized: "\(r.version) is out")
        default: nil
        }
    }
}

// Le pillole della barra (pagina Pillole): un elenco come Notifiche di Impostazioni di Sistema (autore, 27/9) — icona,
// nome, un riassunto in grigio, la freccetta — che apre la schermata del widget (WidgetScreen); chi è solo acceso/spento
// ha l'interruttore nella riga.
private struct BarPage: View {
    let open: (WidgetID) -> Void
    @Bindable var settings = Settings.shared
    @State private var missing: Set<Missing> = []

    var body: some View {
        Section {
            ForEach(WidgetID.allCases, id: \.self) { w in
                if hasOptions(w) {
                    Button { open(w) } label: {
                        HStack(spacing: 12) {
                            SettingsIcon(name: w.rawValue, size: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(w.title)
                                Text(summary(w)).font(.callout).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())   // il click vale su tutta la riga
                    }
                    .buttonStyle(.plain)
                } else {
                    // Solo acceso/spento (autore, 27/9): l'interruttore nella riga, sotto il nome la descrizione.
                    HStack(spacing: 12) {
                        SettingsIcon(name: w.rawValue, size: 28)
                        RowLabel(title: w.title, description: w.about)
                        Spacer()
                        Toggle(w.title, isOn: Binding(get: { settings.isOn(w) }, set: { switchWidget(w, on: $0) })).labelsHidden()   // il nome per VoiceOver
                    }
                }
            }
        } footer: { Text("⌘-drag a widget in the bar to move it.") }
        .modifier(Watching(refresh: refresh))
    }

    // Ha una schermata chi ha opzioni: spazi, orologio, In riproduzione; gli altri solo quando gli manca un permesso o
    // una scorciatoia (Missing: la schermata ha il pulsante che lo sistema), altrimenti acceso/spento. Le mascotte hanno
    // la loro sezione (Mascotte).
    private func hasOptions(_ w: WidgetID) -> Bool {
        switch w {
        case .workspaces, .clock, .nowPlaying: true
        default: missing.contains { $0.widget == w }
        }
    }

    // Il riassunto grigio sotto il nome, come in Notifiche: "Spento", oppure cosa è acceso o cosa manca.
    private func summary(_ w: WidgetID) -> String {
        guard settings.isOn(w) else { return String(localized: "Off") }
        switch w {
        case .workspaces: return settings.showFrontAppName ? String(localized: "Front app name") : String(localized: "On")
        case .clock: return appName(bundle: settings.clockApp).map { String(localized: "Opens \($0)") } ?? String(localized: "On")
        default: return Missing.allCases.first { $0.widget == w && missing.contains($0) }?.text ?? String(localized: "On")
        }
    }

    private func refresh() { readMissingAsync { missing = $0 } }
}

// La schermata di un widget, aperta da Pillole: in cima la card con icona grande, descrizione e interruttore, sotto le sue
// opzioni, solo da acceso. Il titolo della finestra è il nome del widget; indietro e avanti sono nella toolbar.
private struct WidgetScreen: View {
    let w: WidgetID
    @Bindable var settings = Settings.shared
    @State private var missing: Set<Missing> = []

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    SettingsIcon(name: w.rawValue, size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(w.title).font(.title3.weight(.semibold))
                        Text(w.about).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    // Il lato del notch si sceglie solo col ⌘-trascina nella barra (il menu Sinistra/Destra, tolto il 27/9,
                    // metteva il widget in fondo al lato e non sapeva delle regole delle mascotte).
                    Toggle(w.title, isOn: Binding(get: { settings.isOn(w) }, set: { switchWidget(w, on: $0) })).labelsHidden()   // il nome per VoiceOver
                }
                .padding(.vertical, 4)
            }
            .modifier(Watching(refresh: refresh))
            if settings.isOn(w) { options }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var options: some View {
        switch w {
        case .workspaces:
            Section { Toggle("Front app name on the active workspace", isOn: $settings.showFrontAppName) }
        case .nowPlaying:
            Section { Toggle(isOn: $settings.bigArtwork) { RowLabel(title: "Large artwork in the menu", description: "Off: a compact row with a small cover.") } }
        case .clock:
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        RowLabel(title: "Format", description: "Unicode date pattern, e.g. EEE d MMM HH:mm.")
                        Text(verbatim: clockString(Date(), format: settings.clockFormat)).font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    TextField("Format", text: $settings.clockFormat).labelsHidden().frame(width: 170).multilineTextAlignment(.trailing)
                    Button("Reset") { settings.clockFormat = clockDefaultFormat }
                }
                HStack {
                    RowLabel(title: "Click opens", description: "The app comes to the front; a second click hides it.")
                    Spacer()
                    if let icon = appIcon(bundle: settings.clockApp) { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 20, height: 20) }
                    Text(appName(bundle: settings.clockApp) ?? String(localized: "None")).foregroundStyle(.secondary)
                    Button("Choose…") { chooseClockApp() }
                    if !settings.clockApp.isEmpty { Button("None") { settings.clockApp = "" } }
                }
            }
        // Gli altri: cosa manca (permessi, scorciatoie), ognuno col pulsante che lo sistema.
        default:
            let rows = Missing.allCases.filter { $0.widget == w && missing.contains($0) }
            if !rows.isEmpty {
                Section {
                    ForEach(rows, id: \.self) { m in
                        HStack {
                            Text(m.text)
                            Spacer()
                            Button(m.button) { m.fix(); refresh() }
                        }
                    }
                }
            }
        }
    }

    private func refresh() { readMissingAsync { missing = $0 } }
}

// La lettura dei permessi fuori dal main (l'Accesso completo al disco tocca il disco), il risultato sul main:
// la stessa per Pillole e per la schermata di un widget.
func readMissingAsync(_ done: @MainActor @escaping (Set<Missing>) -> Void) {
    let noLocation = locationMissing()
    DispatchQueue.global().async {
        let now = readMissing(noLocation: noLocation)
        DispatchQueue.main.async { done(now) }
    }
}

// Quello che si legge dal sistema (permessi e scorciatoie che mancano, hook, login, barra dei menu, aggancio) si rilegge
// quando la pagina compare e quando la finestra torna key, apertura compresa (dopo un cambio fatto altrove: la finestra non
// viene mai distrutta). Attaccato una volta sola per pagina.
private struct Watching: ViewModifier {
    let refresh: () -> Void
    func body(content: Content) -> some View {
        content
            .onAppear(perform: refresh)
            // Il tipo, non SettingsWindow.shared: la pagina riaperta può comparire mentre shared è ancora in costruzione, e
            // leggerlo lì fa cadere l'app (27/9, come per il titolo della finestra).
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { if $0.object is SettingsWindow { refresh() } }
    }
}

// Le icone di pagine e widget: Resources/settings-icons/<nome>.png, generate nel build dai file di Icon Composer
// dell'autore (Makefile; la lista dei simboli vive in scripts/settings-icons/make.sh). Col Mac in scuro la versione
// scura, <nome>-dark.png (il build la ricava dalle impostazioni "dark" dei file: simbolo chiaro su vetro scuro).
struct SettingsIcon: View {
    let name: String
    let size: CGFloat
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        if let image = (scheme == .dark ? load("\(name)-dark") : nil) ?? load(name) {
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        }
    }
    private func load(_ file: String) -> NSImage? { Bundle.main.resourceURL.flatMap { NSImage(contentsOf: $0.appendingPathComponent("settings-icons/\(file).png")) } }
}

// Il nome dell'app come lo mostra il Finder, dal bundle id; nil se non è installata o il bundle id è vuoto.
func appName(bundle: String) -> String? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { FileManager.default.displayName(atPath: $0.path) }
}

// Il pannello "Apri" di macOS limitato alle app, come foglio sulla finestra delle impostazioni: nessun elenco nostro.
private func chooseClockApp() {
    let panel = NSOpenPanel()
    panel.allowedContentTypes = [.applicationBundle]
    panel.directoryURL = URL(fileURLWithPath: "/Applications")
    panel.prompt = String(localized: "Choose")
    panel.beginSheetModal(for: SettingsWindow.shared) { response in
        guard response == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        Settings.shared.clockApp = id
    }
}

// Cosa manca ai widget per funzionare del tutto: una riga sotto il loro interruttore, col pulsante che lo sistema.
enum Missing: CaseIterable {
    case location, fullDiskAccess, dndShortcut, lowPowerShortcut, bluetooth, bluetoothShortcut

    var widget: WidgetID {
        switch self {
        case .location: .wifi
        case .lowPowerShortcut: .battery
        case .bluetooth, .bluetoothShortcut: .bluetooth
        default: .focus
        }
    }
    var text: String {   // la frase: la riga della schermata del widget e il riassunto grigio di Pillole
        switch self {
        case .location: String(localized: "Network name needs Location")
        case .fullDiskAccess: String(localized: "Needs Full Disk Access")
        case .dndShortcut: String(localized: "Needs the “Siigil DND” shortcut")
        case .lowPowerShortcut: String(localized: "Needs the “Siigil Low Power” shortcut")
        case .bluetooth: String(localized: "Needs Bluetooth permission")
        case .bluetoothShortcut: String(localized: "Needs the “Siigil Bluetooth” shortcut")
        }
    }
    var button: LocalizedStringKey {
        switch self {
        case .location, .bluetooth: "Allow…"
        case .fullDiskAccess: "Open Settings…"
        case .dndShortcut, .lowPowerShortcut, .bluetoothShortcut: "Install…"
        }
    }

    func fix() {
        switch self {
        case .location: requestLocation()
        case .fullDiskAccess: open("x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        case .dndShortcut: installShortcut(Siigil.dndShortcut)   // qualificati: i casi dell'enum oscurano le costanti
        case .lowPowerShortcut: installShortcut(Siigil.lowPowerShortcut)
        case .bluetooth: requestBluetooth()
        case .bluetoothShortcut: installShortcut(Siigil.bluetoothShortcut)
        }
    }
}

// Accendere o spegnere un widget dalle Impostazioni (elenco e schermata). All'accensione la prima lettura parte subito,
// con la richiesta del suo permesso: Automazione per In riproduzione, Bluetooth per il Bluetooth.
@MainActor func switchWidget(_ w: WidgetID, on: Bool) {
    Settings.shared.set(w, on: on)
    guard on else { return }
    if w == .nowPlaying { NowPlaying.readNow() }
    if w == .bluetooth { poller.bluetoothWatcher.start() }
}

// La Posizione si legge sul main (CLLocationManager). Vale "manca" anche se negata: la riga resta e il pulsante porta
// alle Impostazioni (requestLocation distingue i due casi).
func locationMissing() -> Bool {
    ([.notDetermined, .denied, .restricted] as [CLAuthorizationStatus]).contains(locationManager.authorizationStatus)
}

// Cosa manca adesso, per le righe in Generali › Widget e per il Benvenuto. Bloccante (Assertions.json, `shortcuts list`
// ~1 s): fuori dal main. `shortcut: false` salta `shortcuts list` quando la scorciatoia non interessa (la fotografia).
func readMissing(noLocation: Bool, shortcut: Bool = true) -> Set<Missing> {
    var now: Set<Missing> = noLocation ? [.location] : []
    if !focusReadable() { now.insert(.fullDiskAccess) }
    if bluetoothMissing() { now.insert(.bluetooth) }
    if shortcut {
        let names = shortcutNames()   // una lettura per tutte
        if !names.contains(dndShortcut) { now.insert(.dndShortcut) }
        if !names.contains(lowPowerShortcut) { now.insert(.lowPowerShortcut) }
        if !names.contains(bluetoothShortcut) { now.insert(.bluetoothShortcut) }
    }
    return now
}

// Una riga di colori (corpo e occhi delle mascotte, spec mascotte viva §4): i dodici tondini (Button: in un Form i tocchi
// sulle forme li prende la riga) e il selettore libero.
struct SwatchRow: View {
    let title: LocalizedStringKey
    @Binding var value: Int

    var body: some View {
        HStack(spacing: 2) {
            Text(title)
            Spacer()
            ForEach(Array(zip(mascotSwatches, mascotSwatchNames)), id: \.0) { hex, name in
                Button { value = hex } label: {
                    Circle().fill(Color(hex: hex)).frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(.primary.opacity(0.25)))   // segue il chiaro/scuro del Mac: il bianco su bianco sparirebbe
                        .padding(2)
                        .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2).opacity(value == hex ? 1 : 0))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(LocalizedStringKey(name))   // il nome del colore per VoiceOver
                .accessibilityAddTraits(value == hex ? .isSelected : [])
            }
            ColorPicker(title, selection: Binding(get: { Color(hex: value) }, set: { value = hexValue($0) }), supportsOpacity: false)
                .labelsHidden()   // il titolo (Corpo, Occhi) lo legge VoiceOver; la riga lo mostra già
        }
    }
}

// Account AI (era Monitor AI): per Claude e ChatGPT l'account (icona, piano, mail) e gli hook dell'agente (spec impostazioni
// native §4, spec Codex §2); in fondo ogni quanto si aggiorna la quota. La quota nel menu è un'opzione di ogni mascotte.
// Lo stato degli hook si rilegge a ogni comparsa e dopo ogni azione; la logica sta in Integrations.swift.
private struct AIPage: View {
    @Bindable var settings = Settings.shared
    @State private var statuses: [String: IntegrationStatus] = [:]

    var body: some View {
        let q = QuotaCache.shared
        Section {
            AccountHeader(bundle: "com.anthropic.claudefordesktop", title: q.claudeTitle, subtitle: q.email ?? q.status)
            agent("claude-code")
        } footer: { Text("Hooks apply to new sessions.") }
        Section {
            AccountHeader(bundle: "com.openai.codex", title: q.codexTitle, subtitle: q.codex?.email ?? q.codexStatus)
            agent("codex")
        }
        Section {
            Picker("Refresh every", selection: $settings.quotaInterval) {
                ForEach([5, 10, 15, 30], id: \.self) { Text("\($0) min").tag($0) }
            }
        }
        // La finestra non viene mai distrutta: lo stato degli hook si rilegge alla comparsa e quando la finestra
        // torna key (Watching), come i permessi delle altre pagine. In vista, la pagina tiene aggiornati i due account
        // anche se nessuna mascotte mostra la quota (spec sezione Mascotte §9, punto 4): con refresh se è passato
        // l'intervallo, poi al minuto col Poller.
        .modifier(Watching(refresh: refresh))
        .onAppear { SettingsShown.shared.accountsShown = true }
        .onDisappear { SettingsShown.shared.accountsShown = false }
    }

    @ViewBuilder private func agent(_ id: String) -> some View {
        if let i = integrations.first(where: { $0.id == id }) { IntegrationRow(integration: i, status: statuses[id], refresh: refresh) }
    }

    private func refresh() {
        for i in integrations { statuses[i.id] = i.status() }
        Task { await QuotaCache.shared.refreshIfDue(accounts: Set(Agent.allCases)) }
    }
}

// La riga di un'integrazione, in Account AI e nel Benvenuto: nome, stato sotto, a destra il pulsante per lo stato
// (o il segno verde da installata, nel Benvenuto); sotto, in rosso, l'errore dell'ultima azione; per Codex con
// `.needsApproval` i due pulsanti dell'approvazione. Dopo ogni azione chiama `refresh`: chi la usa rilegge.
struct IntegrationRow: View {
    let integration: Integration
    let status: IntegrationStatus?
    var inWelcome = false   // Benvenuto: il simbolo a sinistra come le altre righe, niente stato grigio, il segno verde al posto di Remove
    let refresh: () -> Void
    @State private var error: String?
    @State private var restartPending = false   // "Open Terminal" premuto: il riavvio serve anche dopo l'approvazione

    var body: some View {
        HStack(spacing: 10) {
            if inWelcome { Image(systemName: "sparkles").frame(width: 20).foregroundStyle(.secondary) }
            VStack(alignment: .leading, spacing: 2) {
                Text(integration.name)
                if !inWelcome { Text(statusText).font(.callout).foregroundStyle(.secondary) }
            }
            Spacer()
            switch status {
            case .installed? where inWelcome: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
            case .installed?, .needsApproval?: if !inWelcome { Button("Remove") { run(integration.remove) } }
            case .outdated?: Button("Update") { run(integration.install) }
            case .notInstalled?: Button("Install") { run(integration.install) }
            default: EmptyView()
            }
        }
        if let error { Text(error).font(.callout).foregroundStyle(.red) }
        if integration.id == "codex", status == .needsApproval || restartPending {
            HStack {
                Button("Open Terminal") { openCodexTerminal(); restartPending = true }
                Button("Restart ChatGPT") { restartChatGPT(); restartPending = false }
            }
            .controlSize(.small)
        }
    }

    private var statusText: String {
        switch status {
        case .installed?: String(localized: "Installed")
        case .outdated?: String(localized: "Installed, old path — update")
        case .notInstalled?: String(localized: "Not installed")
        case .needsApproval?: String(localized: "Installed — approve once: open Terminal, type /hooks, choose Trust, then restart ChatGPT.")
        case .missing(let m)?: m
        case nil: ""
        }
    }

    private func run(_ action: () throws -> Void) {
        do { try action(); error = nil } catch { self.error = error.localizedDescription }
        // Scelta dell'utente, non una regressione: Remove/Install/Update da qui non deve far ricomparire il Benvenuto
        // al prossimo avvio solo perché la fotografia diceva ancora "a posto".
        if inApplications(Bundle.main.bundlePath) { Settings.shared.setupSnapshot[integration.id] = integration.status() == .installed }
        refresh()
    }
}

// Icona dell'app, titolo (nome e piano) e sotto la mail, o lo stato finché la quota non risponde.
private struct AccountHeader: View {
    let bundle: String
    let title: String
    let subtitle: String
    var body: some View {
        HStack(spacing: 10) {
            if let icon = appIcon(bundle: bundle) { Image(nsImage: icon).resizable().interpolation(.high).frame(width: 32, height: 32) }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
