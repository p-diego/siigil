import AppKit
import SwiftUI

// Una mascotte nella barra (spec sezione Mascotte §3–4): una pillola come le altre, o senza sfondo, che guarda verso lo
// spazio vuoto (mirroredMascot): layoutDirection inverte mascotte e fumetto, il testo resta dritto, la mascotte si gira da
// sé. Senza sfondo resta la pillola trasparente senza margini ai lati (autore, 27/9) e il fumetto tiene il suo riquadro
// nero per leggersi sopra la scrivania. La grandezza (§10) allarga la pillola; in altezza la mascotte esce dalla pillola,
// come già oggi di un punto, ma non dalla barra (mascotSizes). L'aspetto viene dalla sua scheda; umore, pallino, fumetto,
// clic e menu dalla funzione, guardando solo quello che dice il filtro. Forma, occhi e grandezza si cambiano senza
// ricreare la mascotte viva, che continua a vivere (MascotNSView.geometry). I suoni non partono da qui (una vista per
// schermo): li decidono AgentServer e Poller (Settings.whoSounds).
struct BarMascot: View {
    let state: BarState
    let mascot: Mascot
    let mirrored: Bool
    @Environment(\.palette) private var palette

    var body: some View {
        content(boxed: !mascot.background).pill(background: mascot.background).contentShape(Rectangle())
            .onTapGesture(perform: click)
            // Tasto destro: il menu della funzione; ai click sinistri è trasparente. Sempre sinistra→destra: con la mascotte
            // riflessa il menu si apriva alla sua sinistra (27/9).
            .overlay(MenuAnchor { MascotMenuView(id: mascot.id, state: state) }.environment(\.layoutDirection, .leftToRight))
    }

    // La grandezza salvata dentro mascotSizes, come gli occhi (EyeSettings): un valore fuori misura (scritto a mano, o da una
    // versione con un intervallo più largo) non fa uscire la mascotte dalla barra.
    private var scale: Double { clamped(mascot.size, to: mascotSizes, default: 1) }
    private var room: Double { barHeadroom(scale) * 0.27 * scale }   // i punti sopra la tela fino alla cima della barra

    private func content(boxed: Bool) -> some View {
        let (mood, dot) = look
        return HStack(spacing: 4) {
            LiveMascot(geometry: .of(mascot), bodyHex: mascot.body, eyesHex: mascot.eyes, mood: mood, dot: dot, mirrored: mirrored,
                       headroom: barHeadroom(scale))
                .frame(width: mascotBarSize.width * scale, height: mascotBarSize.height * scale + room)
                // la tela di 27 pt sta al centro della pillola alta 26 e qui sale di 1,5 pt: il corpo (7,6–24,3 pt della tela) va da
                // 5,6 a 22,3 pt dalla cima della pillola, circa 1 pt sotto il centro; sopra restano 5,6 pt, dove salgono saltelli e
                // "z". Con la grandezza crescono insieme. La vista è più alta di `room` verso l'alto, fino alla cima della barra,
                // dove sale il cuoricino (spec pillole-mascotte §2): si alza di metà, così la tela resta dov'era.
                .offset(y: -1.5 * scale - room / 2)
                .zIndex(1)   // quando si gira, il fumetto che cambia lato gli passa dietro, non sopra (27/9)
            if let caption = caption(boxed: boxed) {
                let text = Text(caption.text).font(.system(size: 9, design: .monospaced)).foregroundStyle(caption.color).fixedSize()
                Group {
                    if boxed { text.padding(.horizontal, 4).padding(.vertical, 3).background(Color.black) } else { text }
                }
                // Cresce dal personaggio, come il nome dell'app nella pillola dello spazio (in dissolvenza e basta,
                // il riquadro scivolava sopra la mascotte mentre il posto si apriva).
                .transition(.scale(scale: 0, anchor: mirrored ? .trailing : .leading).combined(with: .opacity))
            }
        }
        .environment(\.layoutDirection, mirrored ? .rightToLeft : .leftToRight)
    }

    private var mine: [String: AgentSession] { sessions(state.sessions, watchedBy: mascot.function.agents) }   // Monitor AI
    private var report: WatchdogReport { state.watchdog.seen(by: mascot.function.kinds) }                     // Monitor di sistema

    // Monitor AI: dalla sessione più urgente fra le sue, col pallino nei colori dell'anello delle icone (spec mascotte viva
    // §3). Monitor di sistema: dall'allarme più grave fra i suoi tipi, col pallino arancione o rosso.
    private var look: (MascotMood, Color?) {
        guard mascot.function.isAI else { return (report.mood, watchdogDot(report.alarm, palette: palette)) }
        let top = topSession(mine)?.state
        return (aiMood(top), top.map { $0.color(in: palette) })
    }

    // Il fumetto: "Task in attesa!" nel giallo dell'attesa finché un suo agente aspetta, "Task completato!" in verde finché la
    // sessione done resta, se no "Sessione rinnovata!"; per il Monitor di sistema l'allarme che vede, arancione o rosso. Nel
    // riquadro nero la variante scura del tema; sulla pillola il colore solo dove si legge (readable).
    private func caption(boxed: Bool) -> (text: String, color: Color)? {
        guard mascot.captions else { return nil }
        let dark = Siigil.palette(Settings.shared.barStyle, dark: true)
        guard mascot.function.isAI else {
            guard let alarm = report.alarm, let color = watchdogDot(alarm, palette: boxed ? dark : palette) else { return nil }
            return (alarm.caption, boxed ? color : readable(color, on: palette))
        }
        func color(_ s: AgentState) -> Color { boxed ? s.color(in: dark) : readable(s.color(in: palette), on: palette) }
        return switch topSession(mine)?.state {
        case .waiting: (String(localized: "Task waiting!"), color(.waiting))   // stessi colori del bordo delle icone
        case .done: (String(localized: "Task done!"), color(.done))
        default: renewedBubble(mascot, renewed: QuotaCache.shared.renewed) ? (String(localized: "Session renewed!"), boxed ? .white : palette.ink) : nil
        }
    }

    // Monitor AI: la finestra della sessione più urgente fra le sue (se aspettava, l'attesa è vista: showSession) e via il
    // "Sessione rinnovata!" dei suoi account. Monitor di sistema: niente, come prima.
    private func click() {
        guard mascot.function.isAI else { return }
        QuotaCache.shared.clearRenewed(mascot.function.agents)
        if let s = topSession(mine) { showSession(s) }
    }
}

// L'umore di un Monitor AI dall'agente più urgente fra i suoi (spec mascotte viva §2): dorme senza agenti, legge quando
// uno lavora, ti chiama quando uno aspetta te, festeggia quando uno ha finito.
func aiMood(_ agent: AgentState?) -> MascotMood {
    switch agent {
    case .working: .work
    case .waiting: .wait
    case .done: .done
    case nil: .sleep
    }
}

// "Sessione rinnovata!" (spec sezione Mascotte §9, punto 7): sulle mascotte che lo vogliono e guardano l'agente
// dell'account che si è rinnovato.
func renewedBubble(_ m: Mascot, renewed: Set<Agent>) -> Bool { m.renewedBadge && !renewed.isDisjoint(with: m.function.agents) }

// Un account c'è su questo Mac: Claude sempre, come il predefinito di prima; ChatGPT se c'è la cartella di Codex, la regola
// di prima per accendere la sua quota (M3): chi usa solo Claude non trova un riquadro ChatGPT "non collegato". Vale per il
// menu e per "Sessione rinnovata!" nelle Impostazioni.
func accountAvailable(_ a: Agent, codexInstalled: Bool = FileManager.default.fileExists(atPath: codexDir.path)) -> Bool {
    a == .claude || codexInstalled
}

// Tasto destro su una mascotte (spec sezione Mascotte §3): in cima l'aggiornamento (§9, punto 1); poi, secondo la funzione,
// le sessioni dei suoi agenti e le quote dei loro account, o l'allarme che vede e le app più pesanti; in fondo "Mascotte",
// tutte con le spunte (§10), e, staccate come nei menu di prima, le impostazioni. La mascotte si legge per id a
// ogni apertura: funzione, filtro e opzioni possono essere cambiati, o lei eliminata. Il menu è la fotografia di quando si
// apre: cambiare le voci a menu aperto lo impagina male (testo bianco, niente aria in fondo), quindi la rete non tocca mai
// un menu aperto.
final class MascotMenuView: RightClickMenuView {
    let id: UUID
    let state: BarState
    private var culprit: Owner?
    private var ignoreKey: String?

    init(id: UUID, state: BarState) {
        self.id = id
        self.state = state
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { nil }

    override func menu() -> NSMenu {
        let menu = NSMenu()
        addUpdate(to: menu)
        guard let m = Settings.shared.mascot(id) else { return menu }   // eliminata mentre la vista spariva
        switch m.function {
        case .ai(let agents): addSessions(agents, quota: m.quotaInMenu, to: menu)
        case .system(let kinds): addWatchdog(kinds, to: menu)
        }
        separate(menu)
        addMascots(to: menu)
        separate(menu)
        menu.addItem(SettingsMenuItem(mascot: id))   // la sua pagina (spec §9, punto 2)
        return menu
    }

    // Una voce sola, "Mascotte": tutte, con la spunta su quelle nella barra; sceglierne una la nasconde o la mostra (autore,
    // 11/10: come i menu con le spunte, al posto di "Nascondi questa" e "Mostra le nascoste"). In ordine di aggiunta, come
    // l'elenco delle Impostazioni. Col disegno fermo (spec §10): si riconoscono a colpo d'occhio, come nella barra.
    private func addMascots(to menu: NSMenu) {
        let s = Settings.shared, item = NSMenuItem(title: String(localized: "Mascots"), action: nil, keyEquivalent: ""), sub = NSMenu()
        for m in s.mascots {
            let row = NSMenuItem(m.title, #selector(toggle(_:)), target: self)
            row.image = mascotThumbnail(m, height: 16)
            row.representedObject = m.id
            row.state = s.isOn(.mascot(m.id)) ? .on : .off
            sub.addItem(row)
        }
        item.submenu = sub
        menu.addItem(item)
    }

    // Spenta come dall'interruttore; riaccesa a destra, dopo le altre mascotte (spec §4).
    @objc private func toggle(_ item: NSMenuItem) {
        guard let id = item.representedObject as? UUID else { return }
        Settings.shared.setMascot(id, on: !Settings.shared.isOn(.mascot(id)))
    }

    // Una riga di separazione, se sopra c'è qualcosa da separare.
    private func separate(_ menu: NSMenu) { if let last = menu.items.last, !last.isSeparatorItem { menu.addItem(.separator()) } }

    // L'aggiornamento (Updater.swift), in ogni mascotte: lo stato di adesso, perché il menu non cambia da aperto.
    private func addUpdate(to menu: NSMenu) {
        switch Updater.shared.state {
        case .available(let r):
            menu.addItem(NSMenuItem(String(localized: "Update to \(r.version)"), #selector(updateItem), target: self))
        case .downloading(let r):
            menu.addItem(NSMenuItem(title: String(localized: "Downloading \(r.version)…"), action: nil, keyEquivalent: ""))   // senza azione: grigia
        case .failed:
            menu.addItem(NSMenuItem(String(localized: "Update failed · download the DMG"), #selector(openReleasePage), target: self))
        case .idle, .upToDate:
            return
        }
        menu.addItem(.separator())
    }

    // Le sessioni dei suoi agenti dalla più urgente (spec sessioni §2) e, se la vuole, la quota degli account dei suoi agenti
    // presenti su questo Mac (Claude → account Claude, Codex → account ChatGPT): intestazione come le reti del menu Wi-Fi,
    // poi una riga con la barra sottile per finestra.
    // ponytail: nessun tetto al numero di voci; da mettere se un elenco lungo capita davvero (spec sessioni, Fuori scopo)
    private func addSessions(_ agents: Set<Agent>, quota: Bool, to menu: NSMenu) {
        for session in sessionsByUrgency(sessions(state.sessions, watchedBy: agents)) { menu.addItem(sessionItem(session)) }
        guard quota else { return }
        let q = QuotaCache.shared
        for agent in Agent.allCases where agents.contains(agent) && accountAvailable(agent) {
            separate(menu)
            let claude = agent == .claude
            let title = claude ? q.claudeTitle + " · " + q.status : q.codexTitle + " · " + q.codexStatus
            let row = AccountRow(icon: appIcon(bundle: claude ? "com.anthropic.claudefordesktop" : "com.openai.codex"),
                                 title: title, subtitle: claude ? q.email : q.codex?.email)
            menu.addItem(menuViewItem(NSHostingView(rootView: row), height: 40))
            let rows = claude ? q.claudeRows : q.codexRows
            for (label, w) in rows ?? [] { menu.addItem(menuViewItem(NSHostingView(rootView: QuotaRow(label: label, window: w)), height: 34)) }
            if rows == nil { menu.addItem(NSMenuItem(title: "—", action: nil, keyEquivalent: "")) }
        }
    }

    // L'allarme che vede (il più grave fra i suoi tipi): il perché, le 5 app più pesanti dell'ultimo minuto, per il colpevole
    // Esci e Forza uscita, Ignora finché non smette (vale per tutte le mascotte: l'app è una sola), Monitoraggio Attività.
    private func addWatchdog(_ kinds: Set<AlarmKind>, to menu: NSMenu) {
        let report = state.watchdog.seen(by: kinds)
        menu.addItem(NSMenuItem(title: report.headline(now: Date()), action: nil, keyEquivalent: ""))
        if !report.top.isEmpty { menu.addItem(.separator()) }
        for load in report.top { menu.addItem(menuViewItem(NSHostingView(rootView: LoadRow(load: load)), height: 24)) }
        culprit = report.culprit
        if let culprit {
            menu.addItem(.separator())
            menu.addItem(NSMenuItem(String(localized: "Quit \(culprit.name)"), #selector(quit), target: self))
            menu.addItem(NSMenuItem(String(localized: "Force Quit \(culprit.name)"), #selector(forceQuit), target: self))
        }
        ignoreKey = nil
        if case .cpu(let l)? = report.alarm {
            ignoreKey = l.owner.key
            menu.addItem(NSMenuItem(String(localized: "Ignore until it stops"), #selector(ignore), target: self))
        }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(String(localized: "Open Activity Monitor"), #selector(activityMonitor), target: self))
    }

    @objc private func updateItem() { Task { await Updater.shared.install() } }
    @objc private func openReleasePage() { DispatchQueue.main.async { NSWorkspace.shared.open(latestReleasePage) } }
    @objc private func quit() { culprit?.bundle.map { runningApps(bundle: $0).forEach { $0.terminate() } } }
    @objc private func forceQuit() { culprit?.bundle.map { runningApps(bundle: $0).forEach { $0.forceTerminate() } } }
    @objc private func ignore() { ignoreKey.map { poller.ignoreWatchdog($0) } }
    @objc private func activityMonitor() { open("-b", "com.apple.ActivityMonitor") }

    // Voce standard di macOS con sottotitolo e sottomenu: Mostra finestra, Reimposta l'agente (scelta dell'autore, 27/9).
    private func sessionItem(_ s: AgentSession) -> NSMenuItem {
        let app = s.bundle.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first?.localizedName }
        let row = NSMenuItem(title: sessionTitle(s, app: app), action: nil, keyEquivalent: "")
        row.subtitle = sessionSubtitle(s)
        row.image = sessionIcon(s)
        let sub = NSMenu()
        for (title, action) in [(String(localized: "Show window"), #selector(showSessionItem(_:))),
                                (String(localized: "Reset agent"), #selector(resetSessionItem(_:)))] {
            let item = NSMenuItem(title, action, target: self)
            item.representedObject = s.id
            sub.addItem(item)
        }
        row.submenu = sub
        return row
    }

    // Si rilegge la sessione al clic: fra l'apertura e il clic può essere finita, scaduta o reimpostata.
    @objc private func showSessionItem(_ item: NSMenuItem) {
        if let id = item.representedObject as? String, let s = state.sessions[id] { showSession(s) }
    }
    @objc private func resetSessionItem(_ item: NSMenuItem) {
        if let id = item.representedObject as? String { resetSessions([id]) }
    }
}

// L'icona dell'app, se installata (tonda nella riga, come i cerchi del menu Wi-Fi); altrimenti un simbolo.
func appIcon(bundle: String) -> NSImage? {
    NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map { NSWorkspace.shared.icon(forFile: $0.path) }
}

// Voce di una sessione nel menu di una mascotte (spec sessioni §2): "Claude · Terminale", sotto "In attesa · 2 min". Il
// nome dell'app è quello che macOS dà all'app in esecuzione, lo stesso della barra; senza app nota solo l'agente.
func sessionTitle(_ s: AgentSession, app: String?) -> String { app.map { "\(s.agent.rawValue) · \($0)" } ?? s.agent.rawValue }

func sessionSubtitle(_ s: AgentSession, now: Date = Date()) -> String {
    let state = switch s.state {
    case .waiting: String(localized: "Waiting")
    case .working: String(localized: "Working")
    case .done: String(localized: "Finished")
    }
    let secs = max(0, Int(now.timeIntervalSince(s.since)))   // orologio spostato indietro: "adesso", mai un'età negativa
    let age = secs < 60 ? String(localized: "now")
        : secs < 3600 ? String(localized: "\(secs / 60) min") : String(localized: "\(secs / 3600) h")
    return "\(state) · \(age)"
}

// L'icona della voce: l'app della sessione con l'anello del suo stato, come nella barra; senza app nota il cerchio grigio
// col simbolo bianco delle intestazioni delle quote (un simbolo nudo usciva nero, invisibile nel menu scuro).
@MainActor func sessionIcon(_ s: AgentSession) -> NSImage? {
    let icon = s.bundle.flatMap(appIcon(bundle:))
    let r = ImageRenderer(content: Group {
        if let icon { Image(nsImage: icon).resizable() } else { MenuRowIcon(symbol: "sparkles", active: false, size: 20) }
    }.frame(width: 20, height: 20).overlay { AgentRing(state: s.state) })
    r.scale = NSScreen.main?.backingScaleFactor ?? 2
    return r.nsImage
}

// Il pallino del Monitor di sistema (spec mascotte viva §3), come il suo fumetto: arancione (il giallo del tema), rosso se
// grave; nessuno senza allarme.
func watchdogDot(_ alarm: Alarm?, palette: Palette?) -> Color? {
    alarm.map { $0.severe ? palette.alert : (palette?.yellow ?? .orange) }
}

// Riga con icona, titolo e sottotitolo grigio, come le reti nel menu Wi-Fi di macOS.
private struct AccountRow: View {
    let icon: NSImage?
    let title: String
    let subtitle: String?
    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon { Image(nsImage: icon).resizable().interpolation(.high) }
                else { MenuRowIcon(symbol: "sparkles", active: false) }
            }
            .frame(width: 26, height: 26).clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
                if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.horizontal, menuInset)
    }
}

// Una finestra di quota nel menu: "Last 5 hours  12 % · Resets in 4 h" e sotto la barra (rossa da esaurita).
private struct QuotaRow: View {
    let label: String
    let window: UsageWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(quotaLine(label, window)).font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
            UsageBar(window: window).frame(height: 5)
        }
        .padding(.horizontal, menuInset)
    }
}

// La barra di una finestra di quota: blu, rossa da esaurita.
struct UsageBar: View {
    let window: UsageWindow
    var body: some View {
        GeometryReader { g in
            Capsule().fill(.primary.opacity(0.28))
                .overlay(alignment: .leading) {
                    Capsule().fill(window.utilization >= 95 ? Color.red : Color.accentColor)
                        .frame(width: g.size.width * min(1, window.utilization / 100))
                }
        }
    }
}

// Una riga del menu del Monitor di sistema: icona dell'app (un ingranaggio per i processi di sistema), nome, CPU a destra.
private struct LoadRow: View {
    let load: Load
    var body: some View {
        HStack(spacing: 8) {
            if let bundle = load.owner.bundle, let icon = appIcon(bundle: bundle) {
                Image(nsImage: icon).resizable().frame(width: 16, height: 16)
            } else {
                Image(systemName: "gearshape.fill").foregroundStyle(.secondary).frame(width: 16, height: 16)
            }
            Text(load.owner.name).lineLimit(1)
            Spacer()
            Text(verbatim: "\(Int(load.percent.rounded())) %").monospacedDigit().foregroundStyle(.secondary)
        }
        .font(.system(size: NSFont.menuFont(ofSize: 0).pointSize))
        .padding(.horizontal, menuInset)
    }
}
