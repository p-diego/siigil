import Foundation
import Network
import Testing
@testable import Siigil

private let now = Date(timeIntervalSince1970: 1_000_000)
private func msg(_ s: String) -> Data { Data(s.utf8) }

@Test func parsesAMessageIntoASession() {
    let m = parseAgentMessage(msg(#"{"agent":"claude","state":"waiting","bundle":"com.microsoft.VSCode","payload":{"session_id":"abc","cwd":"/Users/me/Git/siigil","hook_event_name":"Notification"}}"# + "\n"), now: now)
    #expect(m?.id == "abc")
    #expect(m?.session == AgentSession(id: "abc", agent: .claude, state: .waiting, cwd: "/Users/me/Git/siigil", bundle: "com.microsoft.VSCode", since: now, updatedAt: now))
}

@Test func endYieldsNoSessionAndEmptyBundleIsNil() {
    let m = parseAgentMessage(msg(#"{"agent":"claude","state":"end","bundle":"","payload":{"session_id":"abc"}}"#), now: now)
    #expect(m?.id == "abc")
    #expect(m?.session == nil)
    let w = parseAgentMessage(msg(#"{"state":"working","bundle":"","payload":{"session_id":"abc"}}"#), now: now)
    #expect(w?.session == AgentSession(id: "abc", agent: .claude, state: .working, cwd: "", bundle: nil, since: now, updatedAt: now))
}

@Test func rejectsMissingSessionUnknownStateAndGarbage() {
    #expect(parseAgentMessage(msg(#"{"state":"working","payload":{"cwd":"/x"}}"#), now: now) == nil)
    #expect(parseAgentMessage(msg(#"{"state":"dancing","payload":{"session_id":"abc"}}"#), now: now) == nil)
    #expect(parseAgentMessage(msg("not json"), now: now) == nil)
}

@Test func readsTheAgentClaudeByDefault() {
    func agent(_ field: String) -> Agent? {
        parseAgentMessage(msg(#"{\#(field)"state":"working","payload":{"session_id":"abc"}}"#), now: now)?.session?.agent
    }
    #expect(agent(#""agent":"codex","#) == .codex)
    #expect(agent(#""agent":"claude","#) == .claude)
    #expect(agent("") == .claude)                       // campo assente: il default dello script
    #expect(agent(#""agent":"gemini","#) == .claude)    // sconosciuto: come lo script
}

// Il hook manda il pid di chi lo chiama (l'agente): serve a trovare l'app quando manca il bundle.
@Test func readsTheCallerPid() {
    #expect(parseAgentMessage(msg(#"{"state":"working","bundle":"","pid":32773,"payload":{"session_id":"abc"}}"#), now: now)?.pid == 32773)
    #expect(parseAgentMessage(msg(#"{"state":"working","payload":{"session_id":"abc"}}"#), now: now)?.pid == nil)
}

// Gravity (autore, 12/10): i suoi bot girano nel servizio di sfondo in.mikolajczuk.gravityd, l'app è in.mikolajczuk.gravity.
@Test func aBackgroundServiceBelongsToTheAppItsLabelStartsWith() {
    let list = "PID\tStatus\tLabel\n32759\t0\tapplication.in.mikolajczuk.gravity.33323510.33323518\n32773\t0\tin.mikolajczuk.gravityd\n-\t0\tcom.apple.x\n"
    #expect(launchdLabel(pid: 32773, list: list) == "in.mikolajczuk.gravityd")
    #expect(launchdLabel(pid: 1, list: list) == nil)
    let running = ["com.microsoft.VSCode", "in.mikolajczuk", "in.mikolajczuk.gravity"]
    #expect(appForLabel("in.mikolajczuk.gravityd", running: running) == "in.mikolajczuk.gravity")   // la più lunga
    #expect(appForLabel("com.other.daemon", running: running) == nil)
}

// L'app trovata al primo messaggio resta alla sessione: i messaggi dopo non la portano.
@Test func aSessionKeepsItsAppWhenLaterMessagesHaveNone() {
    let first = AgentSession(id: "abc", agent: .claude, state: .working, cwd: "", bundle: "in.mikolajczuk.gravity", since: now, updatedAt: now)
    let later = AgentSession(id: "abc", agent: .claude, state: .done, cwd: "", bundle: nil, since: now + 5, updatedAt: now + 5)
    #expect(continuing(later, from: first).bundle == "in.mikolajczuk.gravity")
    #expect(continuing(later, from: first).since == now + 5)   // lo stato è cambiato: inizia adesso
}

// End-to-end: server su un socket temporaneo, client Network, riga JSON → BarState.sessions sul main.
@Test @MainActor func serverReceivesAMessageOverTheSocket() async throws {
    let path = "/tmp/siigil-test-\(getpid()).sock"
    defer { forgetSharedSettings() }   // apply legge le mascotte da Settings.shared
    let state = BarState()
    var ticks = 0
    let server = AgentServer(state: state, path: path) { ticks += 1 }
    server.start()
    try await Task.sleep(for: .milliseconds(200))   // il listener si lega in modo asincrono

    let client = NWConnection(to: .unix(path: path), using: NWParameters(tls: nil))
    client.start(queue: .main)
    let line = #"{"agent":"claude","state":"waiting","bundle":"com.test","payload":{"session_id":"e2e","cwd":"/x"}}"# + "\n"
    client.send(content: Data(line.utf8), completion: .contentProcessed { _ in })

    for _ in 0..<40 where state.sessions["e2e"] == nil { try await Task.sleep(for: .milliseconds(50)) }
    #expect(state.sessions["e2e"]?.state == .waiting)
    #expect(state.sessions["e2e"]?.bundle == "com.test")
    #expect(ticks == 1)
    client.cancel()
    unlink(path)
}
