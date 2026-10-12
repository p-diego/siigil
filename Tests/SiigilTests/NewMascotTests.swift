import SwiftUI
import Testing
@testable import Siigil

// Lo stesso seme, la stessa mascotte: i test della creazione a caso girano sempre uguali.
@Test func aNewMascotIsRepeatableWithAFixedSeed() {
    var a = SplitMix(s: 42), b = SplitMix(s: 42)
    let x = newMascot(.ai(agents: [.claude]), existing: [], using: &a)
    let y = newMascot(.ai(agents: [.claude]), existing: [], using: &b)
    #expect(x.shape == y.shape && x.body == y.body && x.eyes == y.eyes)
}

// Colori fra i 12 pronti, occhi sempre leggibili sul corpo (3:1), voce secondo la funzione, mai una combinazione che c'è
// già finché ce n'è una libera (34 coppie corpo-occhi per forma, anche il viola); finite tutte, nasce lo stesso: un doppione
// di una che c'è, con gli occhi sempre leggibili.
@Test func newMascotsAreReadableAndNeverRepeat() {
    func legible(_ m: Mascot) -> Bool { contrast(Color(hex: m.eyes), Color(hex: m.body)) >= 3 }
    let pairs = mascotSwatches.reduce(0) { n, body in n + mascotSwatches.filter { contrast(Color(hex: $0), Color(hex: body)) >= 3 }.count }
    #expect(pairs == 34 && mascotEyeContrast == 3)
    var rng = SplitMix(s: 7)
    var all: [Mascot] = []
    for i in 0..<(MascotKind.allCases.count * pairs) {
        let m = newMascot(i.isMultiple(of: 2) ? .ai(agents: [.claude, .codex]) : .system(kinds: [.cpu]), existing: all, using: &rng)
        #expect(mascotSwatches.contains(m.body) && mascotSwatches.contains(m.eyes) && legible(m))
        #expect(m.voice == (m.function.isAI ? .bubble : .bottle))
        #expect(!all.contains { $0.shape == m.shape && $0.body == m.body && $0.eyes == m.eyes }, "doppione al giro \(i)")
        all.append(m)
    }
    #expect(all.contains { $0.body == 0x8B5CF6 })   // il viola nasce (a 4,5:1 non aveva occhi leggibili)
    let extra = newMascot(.system(kinds: [.heat]), existing: all, using: &rng)
    #expect(legible(extra) && all.contains { $0.shape == extra.shape && $0.body == extra.body && $0.eyes == extra.eyes })
}

// Le opzioni di partenza: effetti sonori al 35 %, fumetti, "Sessione rinnovata!", quota nel menu, sfondo; attaccata ai
// widget, così compare dopo le altre mascotte e prima dei widget (spec §9, punto 9).
@Test func aNewMascotStartsWithTheUsualOptions() {
    var rng = SplitMix(s: 1)
    let m = newMascot(.system(kinds: [.memory]), existing: [], using: &rng)
    #expect(m.function == .system(kinds: [.memory]))
    #expect(m.sounds && m.volume == 35 && m.captions && m.renewedBadge && m.quotaInMenu && m.background && !m.besideNotch)
    #expect(m.eyeSize == 1 && m.eyeLift == 0 && m.eyeSpread == 1 && m.size == 1)   // gli occhi della forma, grandezza di oggi
}
