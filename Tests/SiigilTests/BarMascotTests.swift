import AppKit
import SwiftUI
import Testing
@testable import Siigil

func ai(_ agents: Set<Agent>, renewed: Bool = true) -> Mascot {   // serve anche a SoundsTests
    Mascot(shape: .mostro, body: 0, eyes: 0, voice: .bubble, function: .ai(agents: agents), renewedBadge: renewed)
}
// Le prove che passano da Settings.shared (qui il menu, che legge la mascotte da lì; AgentServer.apply) lo fanno scrivere nel
// dominio dello strumento dei test (alla prima lettura salva la migrazione): a fine prova le sue chiavi vanno via, così non
// restano da una corsa all'altra.
func forgetSharedSettings() {
    for key in ["siigil.mascots", "siigil.bar.left", "siigil.bar.right"] { UserDefaults.standard.removeObject(forKey: key) }
}

// "Sessione rinnovata!" con due account (spec §9, punto 7): sulle mascotte che guardano l'agente di quell'account e lo
// vogliono. Review Focus: un Monitor AI che guarda solo Codex non lo dice per Claude.
@Test func theRenewedBubbleIsForTheMascotsWatchingThatAccount() {
    #expect(renewedBubble(ai([.claude]), renewed: [.claude]))
    #expect(renewedBubble(ai([.claude, .codex]), renewed: [.codex]))
    #expect(!renewedBubble(ai([.codex]), renewed: [.claude]))
    #expect(!renewedBubble(ai([.claude], renewed: false), renewed: [.claude]))
    #expect(!renewedBubble(ai([.claude]), renewed: []))
}

// Un account c'è su questo Mac: Claude sempre, ChatGPT solo con la cartella di Codex (la regola di prima, M3).
@Test func chatGPTCountsOnlyWhereCodexIs() {
    #expect(accountAvailable(.claude, codexInstalled: false) && accountAvailable(.codex, codexInstalled: true))
    #expect(!accountAvailable(.codex, codexInstalled: false))
}

// Review Focus: il menu si fa per la mascotte com'è all'apertura. Solo le sessioni dei suoi agenti; cambiata la funzione
// dalle Impostazioni, il menu dopo è quello nuovo; eliminata, niente voci della funzione.
@MainActor @Test func theMenuIsBuiltForTheMascotAsItIsNow() {
    _ = NSApplication.shared
    let s = Settings.shared, saved = s.mascots
    defer { s.mascots = saved; forgetSharedSettings() }
    var m = ai([.codex]); m.quotaInMenu = false
    s.mascots.append(m)
    let bar = BarState()
    bar.sessions = ["k": session("k", .waiting, agent: .claude), "c": session("c", .working, agent: .codex)]
    let view = MascotMenuView(id: m.id, state: bar)
    func titles() -> [String] { view.menu().items.map(\.title) }
    #expect(titles().contains("Codex") && !titles().contains("Claude"))
    s.mascots[s.mascots.count - 1].function = .system(kinds: [.memory])
    #expect(titles().first == "All quiet")
    s.mascots.removeLast()
    #expect(!titles().contains("All quiet") && !titles().contains("Codex"))
}

// Nascondi e mostra dal tasto destro (spec §10; autore, 11/10: una voce sola "Mascotte" con le spunte): ogni mascotte col
// suo nome, il disegno fermo e la spunta se è nella barra; sceglierla la spegne o la riaccende, le altre restano come sono.
@MainActor @Test func theMenuHidesAndShowsMascots() throws {
    _ = NSApplication.shared
    let s = Settings.shared, saved = (s.mascots, s.left, s.right)
    defer { (s.mascots, s.left, s.right) = saved; forgetSharedSettings() }
    let a = s.addMascot(.ai(agents: [.claude])), b = s.addMascot(.system(kinds: [.heat]))
    let view = MascotMenuView(id: a, state: BarState())   // le voci tengono il loro bersaglio debole: la vista resta viva
    #expect(!view.menu().items.contains { $0.title == "Hide this mascot" || $0.title == "Show hidden mascots" })
    func row(_ id: UUID) throws -> NSMenuItem {
        let rows = view.menu().items.first { $0.title == "Mascots" }?.submenu?.items ?? []
        return try #require(rows.first { $0.representedObject as? UUID == id })
    }
    func choose(_ id: UUID) throws { let r = try row(id); _ = (r.target as? NSObject)?.perform(r.action, with: r) }
    #expect(try row(a).title == "AI monitor · Claude")
    #expect(try row(a).image?.size.height == 16)   // col disegno fermo, alto 16
    #expect(try row(a).state == .on)
    try choose(a)
    #expect(!s.isOn(.mascot(a)) && s.isOn(.mascot(b)))
    #expect(try row(a).state == .off)
    #expect(try row(b).state == .on)
    try choose(a)
    #expect(s.isOn(.mascot(a)) && s.isOn(.mascot(b)))
    #expect(try row(a).state == .on)
    // Le impostazioni staccate dal resto, come nei menu di prima.
    let items = view.menu().items, settings = try #require(items.firstIndex { $0.title == "Settings…" })
    #expect(settings > 0 && items[settings - 1].isSeparatorItem)
}

// Il menu "Mascotte" è sempre in ordine di aggiunta, come l'elenco delle Impostazioni, anche dopo uno spostamento nella
// barra e con una nascosta (autore, 11/10: «le righe devono stare sempre in ordine di aggiunta. Non serve fare
// riordinamenti»).
@MainActor @Test func theMascotsMenuKeepsTheAdditionOrder() throws {
    _ = NSApplication.shared
    let s = Settings.shared, saved = (s.mascots, s.left, s.right)
    defer { (s.mascots, s.left, s.right) = saved; forgetSharedSettings() }
    let a = s.addMascot(.ai(agents: [.claude])), b = s.addMascot(.system(kinds: [.heat])), c = s.addMascot(.ai(agents: [.codex]))
    s.move(.mascot(b), to: .left, index: 0)
    s.setMascot(a, on: false)
    let view = MascotMenuView(id: a, state: BarState())
    let rows = try #require(view.menu().items.first { $0.title == "Mascots" }?.submenu?.items).compactMap { $0.representedObject as? UUID }
    #expect(rows == s.mascots.map(\.id) && rows.suffix(3) == [a, b, c])
}

// Review Focus 3: il riquadro della quota (righe fatte con una vista) c'è se la mascotte lo vuole e, per ChatGPT, solo dove
// c'è la cartella di Codex (accountAvailable).
@MainActor @Test func theQuotaBlockFollowsTheOptionAndTheAccount() {
    _ = NSApplication.shared
    let s = Settings.shared, saved = s.mascots
    defer { s.mascots = saved; forgetSharedSettings() }
    func showsQuota(_ agents: Set<Agent>, quota: Bool) -> Bool {
        var m = ai(agents); m.quotaInMenu = quota
        s.mascots.append(m)
        defer { s.mascots.removeAll { $0.id == m.id } }
        let view = MascotMenuView(id: m.id, state: BarState())
        return view.menu().items.contains { $0.view != nil }   // menuViewItem: le righe della quota
    }
    #expect(showsQuota([.claude], quota: true) && !showsQuota([.claude], quota: false))
    #expect(showsQuota([.codex], quota: true) == FileManager.default.fileExists(atPath: codexDir.path))
    #expect(!showsQuota([.codex], quota: false))
}

// Una grandezza salvata fuori misura si legge dentro mascotSizes, come gli occhi: la pillola non esce dalla barra.
@MainActor @Test func aSavedSizeOutOfRangeStaysInTheBar() {
    func width(_ size: Double) -> CGFloat {
        var m = ai([.claude]); m.size = size; m.background = false; m.captions = false
        return NSHostingView(rootView: BarMascot(state: BarState(), mascot: m, mirrored: false)).fittingSize.width
    }
    #expect(width(3) == width(mascotSizes.upperBound) && width(0.1) == width(mascotSizes.lowerBound))
    #expect(width(mascotSizes.upperBound) > width(1))   // la grandezza conta
}

// La grandezza più grande entra nella barra (spec §10): la cima della tela non esce dai 38 pt, come la base.
@Test func theBiggestMascotFitsTheBar() {
    func top(_ size: Double) -> Double { (BarPanel.height - 26) / 2 + (26 - mascotBarSize.height * size) / 2 - 1.5 * size }
    #expect(top(mascotSizes.upperBound) >= 0 && top(mascotSizes.upperBound) + mascotBarSize.height * mascotSizes.upperBound <= BarPanel.height)
    #expect(top(1.3) < 0 && mascotSizes.lowerBound == 0.7)   // un passo oltre si taglierebbe
}
