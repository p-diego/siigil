import Foundation
import Testing
@testable import Siigil

// I test su QuotaCache.shared uno alla volta: il primo aspetta (Task.yield) e un altro non deve cambiare i rinnovi in mezzo.
@MainActor @Suite(.serialized) struct RenewedAccounts {
    // Claude e ChatGPT possono rinnovarsi nello stesso aggiornamento: ognuno ha il suo orologio di 30 s, e un secondo rinnovo
    // dello stesso account lo fa ripartire senza spegnere niente. Cliccare una mascotte, o un agente che riparte, spegne solo
    // gli account dei suoi agenti.
    @Test func renewedIsPerAccount() async {
        let q = QuotaCache.shared
        q.renew(.claude); q.renew(.codex); q.renew(.claude)
        await Task.yield(); await Task.yield()
        #expect(q.renewed == [.claude, .codex])
        q.clearRenewed([.claude])
        #expect(q.renewed == [.codex])
        q.clearRenewed(Set(Agent.allCases))
        #expect(q.renewed.isEmpty)
    }

    // Una sessione Codex che riparte (AgentServer.apply) spegne "Sessione rinnovata!" solo per l'account ChatGPT.
    @Test func aCodexSessionAtWorkClearsOnlyItsAccount() {
        let q = QuotaCache.shared
        defer { q.clearRenewed(Set(Agent.allCases)); forgetSharedSettings() }   // apply legge le mascotte da Settings.shared
        q.renew(.claude); q.renew(.codex)
        let server = AgentServer(state: BarState(), path: "/tmp/siigil-test-apply-\(getpid()).sock") {}   // niente socket: start() non parte
        server.apply(Data(#"{"agent":"codex","state":"working","bundle":"","payload":{"session_id":"q1"}}"#.utf8))
        #expect(q.renewed == [.claude])
    }
}

// La quota di un account si scarica se una mascotte accesa la mostra nel menu o fa il fumetto "Sessione rinnovata!" per
// quell'account (spec §7); spenta, di sistema, o senza nessuna delle due: niente.
@Test func quotaIsFetchedOnlyForAccountsSomeoneUses() {
    func ai(_ agents: Set<Agent>, quota: Bool = false, renewed: Bool = false, captions: Bool = true) -> Mascot {
        Mascot(shape: .mostro, body: 0, eyes: 0, voice: .bubble, function: .ai(agents: agents), captions: captions,
               renewedBadge: renewed, quotaInMenu: quota)
    }
    let system = Mascot(shape: .mirtillo, body: 0, eyes: 0, voice: .bottle, function: .system(kinds: [.cpu]))
    func accounts(_ m: [Mascot], on: Bool = true, page: Bool = false) -> Set<Agent> { quotaAccounts(m, isOn: { _ in on }, accountsPage: page) }
    #expect(accounts([ai([.claude], quota: true)]) == [.claude])
    #expect(accounts([ai([.codex], renewed: true)]) == [.codex])
    #expect(accounts([ai([.codex], renewed: true, captions: false)]).isEmpty)
    #expect(accounts([ai([.claude], quota: true, captions: false)]) == [.claude])   // la quota nel menu non vuole i fumetti
    #expect(accounts([ai([.claude, .codex], quota: true)], on: false).isEmpty)
    #expect(accounts([system, ai([.claude])]).isEmpty)
    #expect(accounts([ai([.claude], quota: true), ai([.codex], quota: true)]) == [.claude, .codex])
    // La pagina Account AI aperta aggiorna i due account anche senza mascotte che li usano (spec §9, punto 4).
    #expect(accounts([], page: true) == [.claude, .codex])
}
