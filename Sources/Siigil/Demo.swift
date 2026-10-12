import AppKit
import SwiftUI

// La modalità demo (spec README marketing, 11/10): `--demo <workspaces|mascots|widgets>` mostra la barra vera con dati in
// memoria e un copione a tempo, per i video del README (scripts/demo-video.sh). Non tocca niente fuori: impostazioni in una
// cartella a parte, niente AeroSpace, rete, permessi né socket degli agenti (main.swift salta tutto questo); le azioni
// sulle pillole cambiano solo i dati qui (Aerospace.swift).
enum DemoScene: String { case workspaces, mascots, widgets }

let demo: DemoScene? = {
    let a = CommandLine.arguments
    guard let i = a.firstIndex(of: "--demo"), i + 1 < a.count else { return nil }
    return DemoScene(rawValue: a[i + 1])
}()

// Le impostazioni della demo (Settings.shared): una cartella a parte, svuotata a ogni avvio; quelle vere non si leggono.
func demoDefaults() -> UserDefaults {
    let name = "com.siigil.demo", d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

// Gli spazi della demo: app d'esempio con pid fuori dai numeri possibili (macOS arriva a 99999), così nessuna azione
// tocca un processo vero; l'icona viene dal bundle installato (appIcon). Spostare una finestra la mette in ordine di
// nome, come fa report() con le finestre di AeroSpace (Model.swift).
struct DemoSpaces {
    var spaces: [(name: String, apps: [AppEntry])]
    var focused: String
    var front: [String: Int]   // la finestra davanti in ogni spazio

    static func app(_ name: String, _ bundle: String, _ n: Int, agent: AgentState? = nil) -> AppEntry {
        AppEntry(name: name, pid: pid_t(100_000 + n), windowID: n, bundle: bundle, agent: agent)
    }

    static let start = DemoSpaces(spaces: [
        ("1", [app("Mail", "com.apple.mail", 2), app("Safari", "com.apple.Safari", 1)]),
        ("2", [app("Notes", "com.apple.Notes", 3)]),
        ("3", [app("Music", "com.apple.Music", 4)]),
        ("4", [app("Terminal", "com.apple.Terminal", 5, agent: .working)]),
    ], focused: "1", front: ["1": 1])

    var reports: [SpaceReport] { spaces.map { SpaceReport(workspace: Workspace(name: $0.name, isFocused: $0.name == focused), apps: $0.apps) } }
    var frontWindow: Int? { front[focused] ?? spaces.first { $0.name == focused }?.apps.first?.windowID }

    mutating func switchTo(_ name: String) { if spaces.contains(where: { $0.name == name }) { focused = name } }

    mutating func focus(window id: Int) {
        guard let s = spaces.first(where: { $0.apps.contains { $0.windowID == id } }) else { return }
        focused = s.name; front[s.name] = id
    }

    mutating func move(window id: Int, to target: String, follow: Bool) {
        guard let from = spaces.firstIndex(where: { $0.apps.contains { $0.windowID == id } }),
              let to = spaces.firstIndex(where: { $0.name == target }), from != to,
              let app = spaces[from].apps.first(where: { $0.windowID == id }) else { return }
        spaces[from].apps.removeAll { $0.windowID == id }
        spaces[to].apps.append(app)
        spaces[to].apps.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        if front[spaces[from].name] == id { front[spaces[from].name] = nil }
        if follow { focused = target; front[target] = id }
    }
}

@MainActor enum Demo {
    static var spaces = DemoSpaces.start

    // Impostazioni e dati della scena, prima di showPanels(); poi il copione.
    static func start(_ scene: DemoScene) {
        let s = Settings.shared
        s.clockApp = ""   // il clic sull'orologio non apre niente
        switch scene {
        case .workspaces:
            s.left = [.widget(.workspaces)]; s.right = []
            publish()
        case .mascots:
            MascotLife.spinGap = 4...8   // il giro con gli occhi spesso, per vederlo nel video
            let mascots = [
                Mascot(shape: .mostro, body: 0xF5F7FC, eyes: 0x14141A, voice: .bubble, function: .ai(agents: [.claude])),
                Mascot(shape: .pebble, body: 0xF0B429, eyes: 0x14141A, voice: .bubble, function: .ai(agents: [.codex])),
                Mascot(shape: .squircle, body: 0x14141A, eyes: 0xF1EFE9, voice: .bottle, function: .system(kinds: [.cpu, .heat, .memory])),
            ].map { m in var m = m; m.sounds = false; m.background = false; m.besideNotch = true; return m }
            s.mascots = mascots
            s.left = []; s.right = mascots.map { .mascot($0.id) }
            let now = Date()
            state.sessions = [
                "demo-claude": AgentSession(id: "demo-claude", agent: .claude, state: .working, cwd: "/demo", bundle: nil, since: now, updatedAt: now),
                "demo-codex": AgentSession(id: "demo-codex", agent: .codex, state: .waiting, cwd: "/demo", bundle: nil, since: now, updatedAt: now),
            ]
            state.watchdog = WatchdogReport(alarms: [.cpu(Load(owner: Owner(key: "xcode", name: "Xcode", bundle: "com.apple.dt.Xcode"), percent: 412, memory: 0))],
                                            since: now)
        case .widgets:
            // a sinistra del notch: in alto a destra macOS mette la spia della registrazione dello schermo, sopra l'orologio
            s.left = [WidgetID.focus, .nowPlaying, .bluetooth, .volume, .wifi, .battery, .clock].map { .widget($0) }
            s.right = []
            widgetsStart()
            play(widgetSteps)
        }
    }

    static func publish() { state.reports = spaces.reports; state.frontWindow = spaces.frontWindow }

    // Le azioni sulle pillole in demo (Aerospace.swift): solo i dati qui, con l'animazione di sempre.
    static func change(_ f: (inout DemoSpaces) -> Void) { withAnimation(.smooth(duration: 0.3)) { f(&spaces); publish() } }

    // I widget: lo stato di partenza e un cambio ogni 1,3 s (le icone che si barrano finiscono in circa 0,55 s, e un cambio
    // a metà annullerebbe il passo prima), con l'animazione con cui compaiono e spariscono le pillole.
    static let clockStart = Calendar.current.date(bySettingHour: 9, minute: 41, second: 0, of: Date())!
    static func widgetsStart() {
        state.volume = 60; state.muted = false
        state.wifi = WiFi(on: true, bars: 3, vpn: false)
        state.bluetooth = false
        state.battery = Battery(percent: 74, charging: false)
        state.focus = nil; state.track = nil; state.artwork = nil
        state.clockOverride = clockStart
    }
    static let widgetSteps: [() -> Void] = [
        { state.muted = true },
        { state.muted = false },
        { state.wifi = WiFi(on: false, bars: 0, vpn: false) },
        { state.wifi = WiFi(on: true, bars: 3, vpn: false) },
        { state.bluetooth = true },
        { state.battery = Battery(percent: 74, charging: true) },
        { state.focus = Focus(mode: dndMode, symbol: "moon.fill") },
        { state.artwork = cover(); state.track = Track(player: .music, title: "Glass Morning", artist: "Siigil", playing: true) },
        { state.clockOverride = clockStart.addingTimeInterval(60) },
    ]

    // Un passo ogni 1,3 s dopo 2 s di quiete (la barra appena aperta si assesta).
    static func play(_ steps: [() -> Void]) {
        for (i, step) in steps.enumerated() {
            let t = Timer(timeInterval: 2 + 1.3 * Double(i), repeats: false) { _ in
                MainActor.assumeIsolated { withAnimation(.smooth(duration: 0.3)) { step() } }
            }
            RunLoop.main.add(t, forMode: .common)
        }
    }

    // La copertina della canzone d'esempio: un quadrato coi colori delle mascotte, disegnato qui (niente file né rete).
    static func cover() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { r in
            NSGradient(colors: [NSColor(srgbRed: 0.45, green: 0.62, blue: 0.98, alpha: 1), NSColor(srgbRed: 0.55, green: 0.36, blue: 0.96, alpha: 1)])!
                .draw(in: r, angle: -45)
            return true
        }
    }
}
