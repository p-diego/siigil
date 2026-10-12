import AppKit
import Testing
@testable import Siigil

// I suoni li crea l'app (Sounds.swift): qui si misurano i campioni e il WAV, senza mai suonare.

private func seconds(_ x: [Double]) -> Double { Double(x.count) / sampleRate }
private func energy(_ x: [Double]) -> Double { x.reduce(0) { $0 + $1 * $1 } }
private func rmsDB(_ x: [Double], first t: Double = 0.6) -> Double {
    let n = min(x.count, Int(t * sampleRate))
    return 20 * log10(sqrt(energy(Array(x.prefix(n))) / Double(n)))
}

// I sei suoni: tre momenti per due voci (spec sezione Mascotte §5).
private let tones = Effect.allCases.flatMap { e in MascotVoice.allCases.map { (e, $0) } }

// Uguali a ogni creazione, anche il soffio della bottiglia (il rumore parte da un seme fisso).
@Test func soundsAreIdenticalEveryTime() {
    for (e, v) in tones { #expect(render(e, v) == render(e, v), "\(e) \(v)") }
}

// Le durate della prova scelta dall'autore, con le voci di allora (1,29 s, 1,34 s, 2,14 s).
@Test func soundsLastAsLongAsThePrototype() {
    #expect(abs(seconds(render(.waits, .bubble)) - 1.29) < 0.25)
    #expect(abs(seconds(render(.done, .bubble)) - 1.34) < 0.25)
    #expect(abs(seconds(render(.alarm, .bottle)) - 2.14) < 0.25)
}

// Volume medio -18 dB (RMS dei primi 0,6 s), mai sopra 0,95, con tutte e due le voci.
@Test func soundsAreAtMinus18dBAndNeverClip() {
    for (e, v) in tones {
        let x = render(e, v)
        #expect(abs(rmsDB(x) + 18) < 0.5, "\(e) \(v)")
        #expect((x.map(abs).max() ?? 1) <= 0.95, "\(e) \(v)")
    }
}

// La stessa nota con le due voci: le onde non si somigliano (correlazione normalizzata ben sotto 1). La voce è della
// mascotte: lo stesso momento con l'altra voce è un altro suono.
@Test func theTwoVoicesSoundDifferent() {
    let note = [Note(start: 0, f0: 440, f1: 440)]
    let a = synth(note, MascotVoice.bubble.timbre), b = synth(note, MascotVoice.bottle.timbre)
    let corr = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 } / (energy(a) * energy(b)).squareRoot()
    #expect(corr < 0.9, "correlazione \(corr)")
    #expect(render(.waits, .bubble) != render(.waits, .bottle) && render(.alarm, .bubble) != render(.alarm, .bottle))
    // La bollicina è la voce di Mostro, la bottiglia quella di Mirtillo: i suoni di prima, uguali.
    #expect(a == synth(note, .mostro) && b == synth(note, .mirtillo))
}

// Il WAV in memoria è un WAV vero: NSSound lo accetta (senza suonarlo) e ne conosce la durata, che il tasto Prova usa
// per far partire "ha finito" dopo "ti aspetta".
@Test func wavIsAcceptedByNSSound() throws {
    for (e, v) in tones {
        let x = render(e, v), data = wav(x)
        #expect(data.count == 44 + x.count * 2, "\(e) \(v)")
        let sound = try #require(NSSound(data: data), "\(e) \(v)")
        #expect(abs(sound.duration - seconds(x)) < 0.01, "\(e) \(v)")
    }
}

// Un suono per "ti aspetta" e uno diverso per "ha finito"; lavorando niente.
@Test func agentStatesHaveOneSoundEach() {
    #expect(Effect(.waiting) == .waits && Effect(.done) == .done && Effect(.working) == nil)
    #expect(render(.waits, .bubble) != render(.done, .bubble))
}

// Il limite è del fatto: uno per i due momenti degli agenti (al più uno ogni 5 s), un altro per gli allarmi (uno al
// minuto), qualunque mascotte suoni.
@Test func limitsAreForTheFactNotTheMascot() {
    #expect(Effect.waits.limit === Effect.done.limit && Effect.waits.limit.every == 5)
    #expect(Effect.alarm.limit !== Effect.waits.limit && Effect.alarm.limit.every == 60)
}

// Un fatto, un suono (spec §8): con due mascotte che vedono lo stesso fatto suona solo la prima, in ordine di aggiunta,
// accesa e con gli effetti sonori accesi (Settings.whoSounds); con la prima spenta o muta suona la seconda; chi non guarda
// quell'agente non suona mai (Review Focus: un Monitor AI che guarda solo Codex resta zitto per Claude).
@Test func oneFactOneSound() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d)
    let first = ai([.claude, .codex]), codexOnly = ai([.codex]), second = ai([.claude])
    let claude: (Mascot) -> Bool = { $0.function.agents.contains(.claude) }
    for m in s.mascots { s.deleteMascot(m.id) }   // le due di chi aggiorna: qui contano solo queste
    s.mascots = [first, codexOnly, second]
    for m in s.mascots { s.setMascot(m.id, on: true) }
    #expect(s.whoSounds(claude)?.id == first.id)
    s.setMascot(first.id, on: false)              // la prima è spenta: salta chi non guarda Claude
    #expect(s.whoSounds(claude)?.id == second.id)
    s.setMascot(first.id, on: true)
    s.mascots[0].sounds = false                   // la prima è muta
    #expect(s.whoSounds(claude)?.id == second.id)
    s.setMascot(second.id, on: false)             // resta solo chi guarda Codex
    #expect(s.whoSounds(claude) == nil)
}

// Dopo "ti aspetta", "ha finito" entro 5 s non suona se non è forzato (il tasto Prova); il forzato fa ripartire l'attesa.
@Test func limitLetsOneSoundThroughEveryFewSeconds() {
    let limit = Limit(every: 5), t = Date(timeIntervalSince1970: 1_000_000)
    #expect(limit.allow(at: t))                                     // "ti aspetta"
    #expect(!limit.allow(at: t + 2))                                // "ha finito" due secondi dopo: no
    #expect(!limit.allow(at: t + 5))                                // esattamente 5 s: ancora no
    #expect(limit.allow(force: true, at: t + 5))                    // forzato: sì
    #expect(!limit.allow(at: t + 9))                                // 4 s dal forzato
    #expect(limit.allow(at: t + 11))                                // 6 s dal forzato
}
