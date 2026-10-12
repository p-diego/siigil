import AppKit
import Network
import os

// Messaggio di `siigil-hook` (spec agenti §1): {"agent","state","bundle","pid","payload":{"session_id","cwd",…}}; `pid` è
// chi chiama il hook, l'agente.
// `end` non è uno stato: torna (id, nil) e la sessione va rimossa. nil = messaggio da scartare.
private let agentStates: [String: AgentState] = ["working": .working, "waiting": .waiting, "done": .done]

func parseAgentMessage(_ data: Data, now: Date = Date()) -> (id: String, session: AgentSession?, pid: pid_t?)? {
    guard let m = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let payload = m["payload"] as? [String: Any],
          let id = payload["session_id"] as? String, !id.isEmpty,
          let state = m["state"] as? String else { return nil }
    let pid = (m["pid"] as? Int).map { pid_t($0) }
    if state == "end" { return (id, nil, pid) }
    guard let s = agentStates[state] else { return nil }
    let bundle = (m["bundle"] as? String).flatMap { $0.isEmpty ? nil : $0 }
    let agent: Agent = m["agent"] as? String == "codex" ? .codex : .claude   // assente o sconosciuto: il default dello script
    return (id, AgentSession(id: id, agent: agent, state: s, cwd: payload["cwd"] as? String ?? "", bundle: bundle,
                             since: now, updatedAt: now), pid)
}

// L'app di un agente che non la dice da sé: il hook manda $__CFBundleIdentifier, che manca a chi gira in un servizio di
// sfondo avviato da launchd, come i bot di Gravity nel suo in.mikolajczuk.gravityd (autore, 12/10). È l'app che macOS
// ritiene responsabile del processo, o, se il responsabile è un servizio, l'app aperta il cui identificativo è l'inizio
// della sua etichetta.
func hostBundle(pid: pid_t) -> String? {
    guard let r = responsiblePid(pid) else { return nil }
    if let bundle = NSRunningApplication(processIdentifier: r)?.bundleIdentifier { return bundle }
    guard let label = launchdLabel(pid: r, list: shell("/bin/launchctl", ["list"]) ?? "") else { return nil }
    return appForLabel(label, running: NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
}

// L'etichetta del servizio col pid dato, dalle righe "pid  stato  etichetta" di `launchctl list`.
func launchdLabel(pid: pid_t, list: String) -> String? {
    for line in list.split(separator: "\n") {
        let f = line.split(separator: "\t")
        if f.count == 3, f[0] == "\(pid)" { return String(f[2]) }
    }
    return nil
}

// ponytail: basta l'inizio del nome (in.mikolajczuk.gravityd → in.mikolajczuk.gravity), quindi com.foo prenderebbe anche
// com.foobar.servizio; se capita, chiedere un punto o la fine dopo l'identificativo. Fra più app, la più lunga.
func appForLabel(_ label: String, running: [String]) -> String? {
    running.filter { label.hasPrefix($0) }.max { $0.count < $1.count }
}

// Socket Unix per-utente su cui gli hook degli agenti scrivono una riga JSON e chiudono (spec agenti §3).
// ponytail: nessuna autenticazione, il socket è locale e per-utente; il contenuto al massimo colora un anello
final class AgentServer {
    static let path = "/tmp/siigil-\(getuid()).sock"
    let state: BarState
    private var listener: NWListener?
    private let path: String
    private let changed: () -> Void   // una sessione è cambiata in modo visibile: il Poller rifà i report

    init(state: BarState, path: String = AgentServer.path, changed: @escaping () -> Void) {
        self.state = state; self.path = path; self.changed = changed
    }

    func start() {
        unlink(path)   // residuo di un crash: bind fallirebbe
        let params = NWParameters(tls: nil)
        params.requiredLocalEndpoint = NWEndpoint.unix(path: path)
        do { listener = try NWListener(using: params) } catch { logger.error("agents: \(String(describing: error), privacy: .public)"); return }
        listener?.newConnectionHandler = { [self] c in
            c.start(queue: .main)
            read(c, Data())
        }
        // Un bind fallito dopo lo start (es. path già occupato) arriva solo qui, non altrove.
        listener?.stateUpdateHandler = { if case .failed(let e) = $0 { logger.error("agents: \(String(describing: e), privacy: .public)") } }
        listener?.start(queue: .main)
    }

    // Un messaggio per connessione, chiuso da newline; chiudiamo noi appena letto così `nc` esce subito. Fino ad allora
    // la connessione la trattiene il receive in sospeso (la sua closure): non serve tenerle da parte.
    // oltre 1 MB il JSON è troncato e scartato: la sessione resta com'era fino al prossimo evento
    private func read(_ c: NWConnection, _ buf: Data) {
        c.receive(minimumIncompleteLength: 1, maximumLength: 1_048_576) { [self] data, _, complete, error in
            var buf = buf
            if let data { buf.append(data) }
            if complete || error != nil || buf.last == UInt8(ascii: "\n") || buf.count >= 1_048_576 {
                c.cancel()
                apply(buf)
            } else {
                read(c, buf)
            }
        }
    }

    func apply(_ data: Data) {   // non privata: i test la chiamano senza socket
        guard let m = parseAgentMessage(data) else { logger.error("agents: messaggio scartato"); return }
        // Un tick solo, e solo se cambia qualcosa di visibile: PreToolUse arriva a ogni tool call.
        let old = state.sessions[m.id]
        var new = m.session.map { continuing($0, from: old) }
        // L'app si cerca una volta, al primo messaggio della sessione: dopo la tiene continuing.
        if old == nil, new?.bundle == nil, let pid = m.pid { new?.bundle = hostBundle(pid: pid) }
        let visible = old?.state != new?.state || old?.bundle != new?.bundle
        state.sessions[m.id] = new   // nil (end) rimuove; i fumetti delle mascotte la osservano (animazione in BarView)
        if visible { changed() }
        // Un fatto, un suono (spec sezione Mascotte §5): la mascotte accesa, con gli effetti sonori, che guarda
        // quell'agente (whoSounds); al più uno ogni 5 s (agentSound).
        if visible, let s = m.session, s.state == .waiting || s.state == .done,
           let who = Settings.shared.whoSounds({ $0.function.agents.contains(s.agent) }) {
            agentSound(s.state, by: who)
        }
        // Sei ripartito con un agente: il "Sessione rinnovata!" del suo account ha fatto il suo (apply gira sul main: le
        // connessioni usano la coda main).
        if let s = m.session, s.state == .working {
            MainActor.assumeIsolated { QuotaCache.shared.clearRenewed([s.agent]) }
        }
    }
}
