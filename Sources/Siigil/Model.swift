import Foundation

struct Workspace: Equatable {
    let name: String       // AeroSpace: stringa, non per forza numerica
    let isFocused: Bool
}

struct Window: Equatable {
    let workspace: String
    let app: String
    let id: Int
    let pid: pid_t
    let bundle: String     // app-bundle-id: lega le sessioni degli agenti all'app
    let title: String      // disambigua tra più finestre della stessa app
}

// Una finestra su un workspace (un'icona per finestra); nella pillola delle nascoste è un'app, windowID 0.
struct AppEntry: Equatable {
    let name: String
    let pid: pid_t
    let windowID: Int
    let bundle: String
    var agent: AgentState? = nil   // stato più alto tra le sessioni di agenti su questa finestra
    var sessionIDs: [String] = []  // quelle sessioni, ordinate (un ordine che cambia ridisegnerebbe): "Azzera agente" toglie queste
    var fullscreenElsewhere = false   // a tutto schermo in uno spazio nativo: tra le nascoste, ma piena (scelta del 3/10)
}

// Stato di una sessione di agente AI (protocollo in DEVELOPMENT.md, «Agents»).
// L'ordine è la priorità quando più sessioni stanno sulla stessa icona.
enum AgentState: Comparable {   // l'ordine dei casi è l'ordine del confronto
    case done, working, waiting
}

struct AgentSession: Equatable {
    let id: String
    let agent: Agent       // Claude o Codex (campo `agent` di siigil-hook): il nome nel menu delle mascotte e il loro filtro
    let state: AgentState
    let cwd: String
    var bundle: String?    // app che ospita il terminale ($__CFBundleIdentifier nel hook, o hostBundle); nil = non sappiamo dove
    var since: Date        // inizio dello stato: resta finché i messaggi portano lo stesso stato (continuing)
    let updatedAt: Date
}

struct SpaceReport: Equatable {
    let workspace: Workspace
    let apps: [AppEntry]   // una per finestra, in ordine alfabetico per app, poi titolo (report)
}

// App che non hanno mai un'icona, col nome che riporta `aerospace list-windows`.
private let ignoredApps: Set<String> = ["Comnyang"]
func rows(_ text: String) -> [[Substring]] {   // righe `a|b|…` delle risposte di AeroSpace
    text.split(separator: "\n").map { $0.split(separator: "|", omittingEmptySubsequences: false) }
}

// Righe `workspace|is-focused` (formato in Aerospace.swift).
func parseWorkspaces(_ text: String) -> [Workspace] {
    rows(text).compactMap { f in
        f.count == 2 ? Workspace(name: String(f[0]), isFocused: f[1] == "true") : nil
    }
}

// Righe `workspace|app|window-id|pid|bundle|title`; il titolo è ultimo perché contiene `|` spesso.
// ponytail: un `|` negli altri campi fa scartare la riga; passare a --json se succede davvero
func parseWindows(_ text: String) -> [Window] {
    rows(text).compactMap { f in
        guard f.count >= 6, let id = Int(f[2]), let pid = pid_t(f[3]) else { return nil }
        return Window(workspace: String(f[0]), app: String(f[1]), id: id, pid: pid,
                      bundle: String(f[4]), title: f[5...].joined(separator: "|"))
    }
}

// La finestra di una sessione: l'unica visibile della sua app, o l'unica col nome della cartella di lavoro nel
// titolo (VS Code, Ghostty con shell integration). Altrimenti nil: la sessione si posa sull'app, non sulla finestra.
private func window(of s: AgentSession, in windows: [Window]) -> Window? {
    guard let bundle = s.bundle else { return nil }
    let candidates = windows.filter { $0.bundle == bundle }   // già solo quelle visibili (visibleWindows)
    if candidates.count == 1 { return candidates[0] }
    let dir = (s.cwd as NSString).lastPathComponent
    // ponytail: nome cartella corto (src) combacia con più finestre → degrada ad app; la via per tab/pane è in ANALISI.md
    let byTitle = candidates.filter { !dir.isEmpty && $0.title.contains(dir) }
    return byTitle.count == 1 ? byTitle[0] : nil
}

// Sessioni finite o abbandonate (spec agenti §3): done resta verde finché l'app che la ospita non torna in primo
// piano (`front` = bundle id dell'app a fuoco), e comunque almeno 5 s; senza bundle noto, 5 s e basta. Working
// scade dopo 10 min (agente chiuso senza SessionEnd); waiting resta finché non cambia, è il motivo della feature.
// In ogni stato: se l'app che ospitava la sessione non gira più (`running` = bundle id in esecuzione), la sessione
// è morta con lei — Cmd-Q sul terminale non manda SessionEnd.
func expired(_ s: AgentSession, now: Date, front: String? = nil, running: Set<String>? = nil) -> Bool {
    if let running, let bundle = s.bundle, !running.contains(bundle) { return true }
    let age = now.timeIntervalSince(s.updatedAt)
    return switch s.state {
    case .done: age > 5 && (s.bundle == nil || s.bundle == front)
    case .working: age > 600
    case .waiting: false
    }
}

// App aperte (quelle del Dock) senza icona su nessun workspace: nascoste, minimizzate o senza finestre.
// `running` viene da NSWorkspace (Poller); windowID 0 = nessuna finestra nota. Le sessioni si legano per bundle.
func hiddenApps(running: [AppEntry], reports: [SpaceReport], sessions: [AgentSession],
                fullscreen: Set<pid_t> = []) -> [AppEntry] {
    var seen = Set(reports.flatMap { $0.apps.map(\.name) }).union(ignoredApps).union(["Finder"])
    return running.filter { seen.insert($0.name).inserted }   // una per nome: ForEach usa il nome come id
        .map { app in
            var e = app
            let mine = sessions.filter { $0.bundle == app.bundle }
            e.agent = mine.map(\.state).max()
            e.sessionIDs = mine.map(\.id).sorted()
            e.fullscreenElsewhere = fullscreen.contains(app.pid)
            return e
        }
}

// Senza AeroSpace (spec senza-aerospace §2): la barra mostra una pillola sola con le app del Dock che hanno finestre
// a schermo. Workspace senza nome e mai a fuoco — l'invariante che la distingue (AeroSpace non ha workspace senza
// nome): la pillola non mostra numero, il click attiva l'app, niente trascinamento. windowID = -pid: unico per app
// (due omonime restano due icone) e regge la regola del nome a fuoco (frontWindow = -pid in ridotto); il segno
// negativo dice "non è una finestra di AeroSpace, solo un'icona attivabile" (showApp). Le sessioni si
// posano sull'app per bundle, come sulle nascoste.
func reducedReport(running: [AppEntry], visible: Set<pid_t>, sessions: [AgentSession]) -> SpaceReport {
    let apps = running.filter { visible.contains($0.pid) }
        .sorted(using: [KeyPathComparator(\.name, comparator: .localizedStandard), KeyPathComparator(\.pid)])
        .map { app -> AppEntry in
            let mine = sessions.filter { $0.bundle == app.bundle }
            return AppEntry(name: app.name, pid: app.pid, windowID: -Int(app.pid), bundle: app.bundle,
                            agent: mine.map(\.state).max(), sessionIDs: mine.map(\.id).sorted())
        }
    return SpaceReport(workspace: Workspace(name: "", isFocused: false), apps: apps)
}

// Le finestre che hanno un'icona. Quali esistono e in che spazio lo dice AeroSpace; se si vedono lo dice macOS
// (`offscreen`: minimizzate e app nascoste, qualunque layout dia AeroSpace), e per 1,5 s dopo un avviso di SkyLight
// (`recent`, WindowEvents.swift) vale l'avviso, perché l'elenco di macOS arriva fino a 0,1 s dopo. Una finestra
// riaperta che AeroSpace ha tolto dalla lista (⌘M) la rimette 0,9 s dopo e nello spazio a fuoco: intanto torna
// dall'ultima riga nota, in quello spazio. Dopo ⌘H invece AeroSpace la tiene in lista col suo spazio (misurato il
// 2026-09-26).
func visibleWindows(_ listed: [Window], offscreen: Set<Int>, recent: [Int: Bool], lastKnown: [Int: Window],
                    focusedWorkspace: String?) -> [Window] {
    let ids = Set(listed.map(\.id))
    let back = recent.filter { $0.value && !ids.contains($0.key) }.keys.sorted().compactMap { lastKnown[$0] }.map { w in
        Window(workspace: focusedWorkspace ?? w.workspace, app: w.app, id: w.id, pid: w.pid, bundle: w.bundle, title: w.title)
    }
    return (listed + back).filter { recent[$0.id] ?? !offscreen.contains($0.id) }
}

// Un rapporto per spazio, con le finestre già visibili (visibleWindows). L'ordine lo decide Siigil: alfabetico per app
// come nel Finder, poi titolo (deciso il 23/9, prima lo dava AeroSpace).
func report(workspaces: [Workspace], windows: [Window], sessions: [AgentSession]) -> [SpaceReport] {
    let bound = sessions.map { ($0, window(of: $0, in: windows)) }   // sessione → finestra, o nil
    return workspaces.map { ws in
        let apps = windows
            .filter { $0.workspace == ws.name && !ignoredApps.contains($0.app) }
            .sorted(using: [KeyPathComparator(\.app, comparator: .localizedStandard),
                            KeyPathComparator(\.title, comparator: String.StandardComparator.lexical), KeyPathComparator(\.id)])
            .map { win -> AppEntry in
                // Sessioni di questa finestra: legate proprio a lei, oppure senza finestra (su tutte le finestre della loro app).
                let mine = bound.filter { s, w in w.map { $0.id == win.id } ?? (s.bundle == win.bundle) }
                return AppEntry(name: win.app, pid: win.pid, windowID: win.id, bundle: win.bundle, agent: mine.map(\.0.state).max(),
                                sessionIDs: mine.map(\.0.id).sorted())
            }
        return SpaceReport(workspace: ws, apps: apps)
    }
}

// Dove sta una sessione (spec sessioni §3): la prima icona che la mostra, nella barra o tra le app nascoste. Le icone
// sanno già le loro sessioni (report, hiddenApps): la stessa regola per il clic su una mascotte e per il suo menu.
func place(of id: String, in apps: [AppEntry]) -> AppEntry? { apps.first { $0.sessionIDs.contains(id) } }

// Le sessioni dalla più urgente (spec sessioni §2): stato più alto, a parità la più recente. La prima è quella che una
// mascotte mostra (stesso criterio delle pillole); il suo menu le mostra tutte in quest'ordine.
func sessionsByUrgency(_ sessions: [String: AgentSession]) -> [AgentSession] {
    sessions.values.sorted { ($0.state, $0.updatedAt) > ($1.state, $1.updatedAt) }
}

func topSession(_ sessions: [String: AgentSession]) -> AgentSession? { sessionsByUrgency(sessions).first }

// Le sessioni che una mascotte guarda (spec sezione Mascotte §3): solo quelle dei suoi agenti. Si filtra prima di
// topSession e sessionsByUrgency: umore, pallino, fumetto, clic e menu vengono da queste.
func sessions(_ all: [String: AgentSession], watchedBy agents: Set<Agent>) -> [String: AgentSession] {
    all.filter { agents.contains($0.value.agent) }
}

// La sessione dopo un messaggio (AgentServer): se lo stato continua tiene il suo inizio, il "da quanto" del menu delle
// mascotte; se cambia, o la sessione è nuova, lo stato inizia adesso (lo porta già il messaggio). Tiene anche l'app
// trovata al primo messaggio (hostBundle), che i messaggi dopo non portano.
func continuing(_ new: AgentSession, from old: AgentSession?) -> AgentSession {
    var s = new
    if s.bundle == nil { s.bundle = old?.bundle }
    if let old, old.state == new.state { s.since = old.since }
    return s
}
