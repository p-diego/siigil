import Foundation

// L'ultima quota letta (Claude e ChatGPT): si aggiorna all'avvio e al minuto quando è dovuta (Poller), mai a menu aperto.
@Observable @MainActor final class QuotaCache {
    static let shared = QuotaCache()
    private(set) var usage: Usage?
    private(set) var plan = ""
    private(set) var email: String?
    private(set) var status = String(localized: "Waiting for the first update…")
    private(set) var codex: CodexUsage?
    private(set) var codexStatus = String(localized: "Waiting for the first update…")

    // Titolo e finestre presenti, per i menu delle mascotte e Account AI (nil = mai letta).
    var claudeTitle: String { "Claude" + (plan.isEmpty ? "" : " · \(plan)") }
    var claudeRows: [(String, UsageWindow)]? { usage.map { $0.rows.map { ($0.label, $0.window) } } }
    var codexTitle: String { "ChatGPT" + ((codex?.plan).flatMap { $0.isEmpty ? nil : " · \($0)" } ?? "") }
    var codexRows: [(String, UsageWindow)]? { codex.map { $0.usage.rows.map { ($0.label, $0.window) } } }

    // Gli account (per agente: Claude, e Codex per ChatGPT) la cui finestra di 5 ore si è appena azzerata dopo essere finita:
    // le mascotte che guardano quell'agente lo dicono per 30 s, o finché non le clicchi o l'agente riparte (spec sezione
    // Mascotte §9, punto 7). Ogni account ha il suo orologio: due rinnovi insieme non si spengono a vicenda.
    private(set) var renewed: Set<Agent> = []
    private var renewTasks: [Agent: Task<Void, Never>] = [:]
    private var lastAttempt: [Agent: Date] = [:]

    func renew(_ a: Agent) {
        renewed.insert(a)
        renewTasks[a]?.cancel()
        renewTasks[a] = Task { guard (try? await Task.sleep(for: .seconds(30))) != nil else { return }; renewed.remove(a) }
    }

    func clearRenewed(_ agents: Set<Agent>) { renewed.subtract(agents) }

    // Al minuto dal Poller, e all'apertura della pagina Account AI: rete solo per gli account che servono e solo se sono
    // passati `quotaInterval` minuti dall'ultimo tentativo di quell'account (anche fallito: gli endpoint limitano le
    // richieste). Le due letture sono indipendenti: un errore su una non tocca l'altra.
    func refreshIfDue(accounts: Set<Agent>) async {
        let every = Double(Settings.shared.quotaInterval * 60)
        for a in Agent.allCases where accounts.contains(a) && Date().timeIntervalSince(lastAttempt[a] ?? .distantPast) >= every {
            lastAttempt[a] = Date()
            if a == .claude { await refreshClaude() } else { await refreshCodex() }
        }
    }

    private func updated() -> String { String(localized: "Updated \(clockString(Date(), format: "HH:mm"))") }

    // Il testo di una lettura fallita, uguale per i due account; `signIn` per 401 e 403 (ChatGPT: login da rifare).
    private func failure(_ error: Error, signIn: String? = nil) -> String {
        guard case UsageError.http(let code) = error else { return String(localized: "Unavailable") }
        if code == 429 { return String(localized: "Too many requests, retrying in \(Settings.shared.quotaInterval) min") }
        if let signIn, code == 401 || code == 403 { return signIn }
        return String(localized: "Unavailable (HTTP \(code))")
    }

    private func refreshClaude() async {
        do {
            guard let credentials = await Task.detached(operation: readCredentials).value else {
                status = String(localized: "Claude Code not signed in (claude login)"); return
            }
            if plan.isEmpty { plan = credentials.plan.capitalized }   // finché il profilo non risponde
            guard credentials.expiresAt > Date() else { status = String(localized: "Token expired, use Claude Code and retry"); return }
            guard let fresh = parseUsage(try await fetchOAuth("usage", token: credentials.accessToken)) else { throw UsageError.parse }
            // Il profilo è un di più: se non risponde restano piano e mail di prima, la quota si aggiorna lo stesso.
            if let data = try? await fetchOAuth("profile", token: credentials.accessToken) {
                if let p = parsePlan(data) { plan = p }
                if let e = parseEmail(data) { email = e }
            }
            if windowRenewed(from: usage?.fiveHour, to: fresh.fiveHour) { renew(.claude) }
            usage = fresh
            status = updated()
        } catch { status = failure(error) }
    }

    private func refreshCodex() async {
        do {
            guard let credentials = await Task.detached(operation: readCodexCredentials).value else {
                codexStatus = String(localized: "ChatGPT not signed in (open the app)"); return
            }
            guard let fresh = parseCodexUsage(try await fetchCodexUsage(credentials)) else { throw UsageError.parse }
            if windowRenewed(from: codex?.usage.fiveHour, to: fresh.usage.fiveHour) { renew(.codex) }
            codex = fresh
            codexStatus = updated()
        } catch { codexStatus = failure(error, signIn: String(localized: "Sign in to ChatGPT again")) }
    }
}

// Gli account di cui serve la quota (spec sezione Mascotte §7): quelli degli agenti delle mascotte accese che la mostrano
// nel menu o fanno il fumetto "Sessione rinnovata!" (che vuole i fumetti accesi); tutti con la pagina Account AI aperta
// (§9, punto 4).
func quotaAccounts(_ mascots: [Mascot], isOn: (Mascot) -> Bool, accountsPage: Bool) -> Set<Agent> {
    if accountsPage { return Set(Agent.allCases) }
    return mascots.filter { isOn($0) && ($0.quotaInMenu || ($0.renewedBadge && $0.captions)) }
        .reduce(into: []) { $0.formUnion($1.function.agents) }
}
