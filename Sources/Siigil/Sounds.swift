import AppKit

// I suoni delle mascotte, creati dall'app la prima volta che servono: niente file audio, niente licenze. Sono la prova
// "Tra 2 · Più delicata" scelta dall'autore (10/10). La melodia viene dal momento (Effect), il timbro dalla voce della
// mascotte (MascotVoice: bollicina o bottiglia); ogni suono è fatto di note, ognuna con la sua armonica e un "bwip"
// all'attacco (la bottiglia ha anche un soffio), e un filo di riverbero. Volume dalla mascotte; `force` salta il limite
// (i tasti "Prova" e della voce). Tutto sul main.

let sampleRate = 44100.0   // Hz, mono, 16 bit

// Una nota: quando parte (s), la frequenza di partenza e quella d'arrivo (Hz) e in quanto tempo ci scivola (s).
struct Note { var start, f0, f1: Double; var glide = 0.06 }

// Un'armonica: multiplo della frequenza, ampiezza e quanto dura rispetto alla nota.
struct Partial { var ratio, amp, decay: Double }

// Una voce: le armoniche; l'attacco (s); il "bwip" (di quanti semitoni la nota parte più bassa e in quanto tempo sale, s);
// quanto dura una nota a 440 Hz (tau, s); il soffio all'attacco (0 = niente); il filtro che smussa gli acuti (1 = nessuno).
struct Voice {
    var partials: [Partial]
    var attack, scoop, scoopTime, tau: Double
    var breath = 0.0, lowpass = 1.0

    static let mostro = Voice(partials: [Partial(ratio: 1, amp: 1, decay: 1), Partial(ratio: 8, amp: 0.04, decay: 1.1)],
                              attack: 0.008, scoop: 3, scoopTime: 0.015, tau: 0.24, lowpass: 0.4)
    static let mirtillo = Voice(partials: [Partial(ratio: 1, amp: 1, decay: 1), Partial(ratio: 3, amp: 0.06, decay: 0.6)],
                                attack: 0.015, scoop: 3, scoopTime: 0.04, tau: 0.26, breath: 0.06, lowpass: 0.3)
}

// Le voci delle mascotte: la bollicina era di Mostro, la bottiglia di Mirtillo.
extension MascotVoice {
    var timbre: Voice { self == .bubble ? .mostro : .mirtillo }
}

// I tre momenti: "ti aspetta" e "ha finito" (Monitor AI), l'allarme (Monitor di sistema).
enum Effect: CaseIterable {
    case waits, done, alarm

    init?(_ state: AgentState) {
        switch state { case .waiting: self = .waits; case .done: self = .done; case .working: return nil }
    }

    var notes: [Note] {
        switch self {
        case .waits: [Note(start: 0, f0: 622, f1: 587), Note(start: 0.16, f0: 523, f1: 880, glide: 0.07)]
        case .done: [Note(start: 0, f0: 523, f1: 523), Note(start: 0.1, f0: 659, f1: 659), Note(start: 0.2, f0: 784, f1: 784)]
        case .alarm: [Note(start: 0, f0: 494, f1: 494), Note(start: 0.14, f0: 370, f1: 370),
                      Note(start: 0.3, f0: 494, f1: 494), Note(start: 0.44, f0: 370, f1: 370)]
        }
    }
    // Il limite è del fatto, non della mascotte né della voce: i due degli agenti se lo dividono.
    var limit: Limit { self == .alarm ? alarmLimit : agentLimit }
}

// Al più un suono ogni `every` secondi; `force` salta l'attesa ma la fa ripartire.
final class Limit {
    let every: TimeInterval
    private var last = Date.distantPast
    init(every: TimeInterval) { self.every = every }

    func allow(force: Bool = false, at now: Date = Date()) -> Bool {
        guard force || now.timeIntervalSince(last) > every else { return false }
        last = now
        return true
    }
}

// Agenti: al più uno ogni 5 s, idle_prompt e i turni brevi altrimenti farebbero suonare a raffica. Allarmi: al più uno al
// minuto (spec Watchdog §2).
private let agentLimit = Limit(every: 5), alarmLimit = Limit(every: 60)

// Sintesi additiva: ogni nota è la somma delle sue armoniche, ognuna col suo decadimento; la frequenza parte `scoop`
// semitoni sotto e sale in fretta (il "bwip"); il soffio è rumore filtrato alla frequenza della nota, solo all'attacco.
// Più acuta è la nota, più breve dura.
func synth(_ notes: [Note], _ v: Voice) -> [Double] {
    var out = [Double](repeating: 0, count: Int(3 * sampleRate))
    var rng = SplitMix(s: 1)   // il soffio ha un seme fisso: il suono è identico a ogni avvio
    for nt in notes {
        var phase = [Double](repeating: 0, count: v.partials.count)
        var y1 = 0.0, y2 = 0.0
        let o = Int(nt.start * sampleRate), tau = v.tau * pow(440 / nt.f1, 0.5)
        for i in 0..<Int(tau * 6 * sampleRate) where o + i < out.count {
            let t = Double(i) / sampleRate
            var f = nt.f0 * pow(nt.f1 / nt.f0, min(1, t / nt.glide))
            f *= pow(2, -v.scoop * exp(-t / v.scoopTime) / 12)
            var x = 0.0
            for (k, p) in v.partials.enumerated() where f * p.ratio < 18000 {
                x += p.amp * exp(-t / (tau * p.decay)) * sin(phase[k])
                phase[k] += 2 * .pi * f * p.ratio / sampleRate
            }
            if v.breath > 0 {
                let r = 0.985, w = 2 * .pi * f / sampleRate
                let y = Double.random(in: -1...1, using: &rng) * (1 - r) + 2 * r * cos(w) * y1 - r * r * y2
                y2 = y1; y1 = y
                x += v.breath * 40 * y * exp(-t / 0.035)
            }
            out[o + i] += x * min(1, t / v.attack)
        }
    }
    if v.lowpass < 1 { var y = 0.0; for i in out.indices { y += v.lowpass * (out[i] - y); out[i] = y } }
    return out
}

// Un filo di riverbero (quattro echi in parallelo e due filtri in serie che li sfumano, con le misure di Freeverb) con
// 0,7 s di coda; poi si taglia il silenzio in fondo e si sfuma l'ultimo 0,08 s.
func reverb(_ x: [Double]) -> [Double] {
    let input = x + [Double](repeating: 0, count: Int(0.7 * sampleRate))
    var acc = [Double](repeating: 0, count: input.count)
    for d in [1116, 1188, 1277, 1356] {   // gli echi: ognuno rimanda il suono con gli acuti un po' smorzati
        var buf = [Double](repeating: 0, count: d), idx = 0, store = 0.0
        for i in input.indices { let y = buf[idx]; store = y * 0.65 + store * 0.35; buf[idx] = input[i] + store * 0.72; idx = (idx + 1) % d; acc[i] += y }
    }
    for d in [556, 441] {   // i filtri che sfumano gli echi
        var buf = [Double](repeating: 0, count: d), idx = 0
        for i in acc.indices { let b = buf[idx], y = -acc[i] + b; buf[idx] = acc[i] + b * 0.5; idx = (idx + 1) % d; acc[i] = y }
    }
    var out = input.indices.map { input[$0] + 0.15 * acc[$0] / 4 }
    let peak = out.map(abs).max() ?? 1
    var end = out.count; while end > 1 && abs(out[end - 1]) < peak * 1e-3 { end -= 1 }
    out = Array(out[0..<end])
    let fade = min(out.count, Int(0.08 * sampleRate))
    for k in 0..<fade { out[out.count - 1 - k] *= Double(k) / Double(fade) }
    return out
}

// Il suono finito: volume medio di -18 dB (RMS dei primi 0,6 s), senza mai saturare (autore, 11/10: a -27 si sentiva poco anche col volume al 90 %).
func render(_ e: Effect, _ v: MascotVoice) -> [Double] {
    let x = reverb(synth(e.notes, v.timbre))
    let n = min(x.count, Int(0.6 * sampleRate)), rms = sqrt(x.prefix(n).reduce(0) { $0 + $1 * $1 } / Double(n))
    let peak = x.map(abs).max() ?? 1, gain = min(pow(10, -18.0 / 20) / rms, 0.95 / peak)
    return x.map { $0 * gain }
}

// Un WAV a 16 bit, mono, tutto in memoria.
func wav(_ x: [Double]) -> Data {
    var d = Data()
    func u32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    func u16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
    let n = UInt32(x.count * 2), rate = UInt32(sampleRate)
    d += Data("RIFF".utf8); u32(36 + n); d += Data("WAVE".utf8)
    d += Data("fmt ".utf8); u32(16); u16(1); u16(1); u32(rate); u32(rate * 2); u16(2); u16(16)
    d += Data("data".utf8); u32(n)
    d += x.map { Int16((max(-1, min(1, $0)) * 32767).rounded()).littleEndian }.withUnsafeBytes { Data($0) }
    return d
}

// Un suono: la melodia di un momento con una voce (3 × 2), creato la prima volta che serve e tenuto in memoria.
struct Tone: Hashable {
    let effect: Effect
    let voice: MascotVoice

    // ponytail: si crea sul main, 5-9 ms a suono in release (0,2-0,3 s in debug); se si sentisse, prepararli in background.
    var sound: NSSound? {
        if let s = made[self] { return s }
        let s = NSSound(data: wav(render(effect, voice)))
        made[self] = s
        return s
    }
}

private var made: [Tone: NSSound] = [:]   // i suoni già creati

private func play(_ t: Tone, volume: Int, force: Bool) {
    // Fuori dall'app (nei test) i suoni tacciono sempre: una regola sola per tutti i percorsi. Il suono prima del limite:
    // se non si crea, non si consuma l'attesa di 5 s o di un minuto.
    guard Bundle.main.bundleIdentifier == "com.siigil.app", let sound = t.sound, t.effect.limit.allow(force: force) else { return }
    sound.stop()
    sound.volume = Float(volume) / 100   // 1 = volume di sistema pieno
    sound.play()
}

// "Ti aspetta" o "ha finito" (mentre lavora niente) con la voce e il volume della mascotte.
func agentSound(_ state: AgentState, by m: Mascot, force: Bool = false) {
    guard let e = Effect(state) else { return }
    play(Tone(effect: e, voice: m.voice), volume: m.volume, force: force)
}

// L'allarme del Watchdog con la voce e il volume della mascotte.
func alarmSound(by m: Mascot, force: Bool = false) {
    play(Tone(effect: .alarm, voice: m.voice), volume: m.volume, force: force)
}

// Il tasto "Prova" di una mascotte, senza limite: Monitor AI "ti aspetta" e, quando è finito, "ha finito"; Monitor di
// sistema l'allarme.
// ponytail: "ha finito" parte allo scadere della durata del primo, non dal delegato di NSSound; se l'uscita audio si
// sveglia piano (Bluetooth) può sovrapporsi alla fine del primo; la strada è didFinishPlaying del delegato.
private var tryNext: DispatchWorkItem?
func trySounds(_ m: Mascot) {
    // Una prova ancora in corso, di qualunque mascotte e voce, si ferma: non suona sotto questa.
    tryNext?.cancel()
    made.values.forEach { $0.stop() }
    guard m.function.isAI else { return alarmSound(by: m, force: true) }
    agentSound(.waiting, by: m, force: true)
    debounce(&tryNext, after: Tone(effect: .waits, voice: m.voice).sound?.duration ?? 0) { agentSound(.done, by: m, force: true) }
}

// Il tasto della voce (Impostazioni › la mascotte › Aspetto): il primo suono della sua funzione con quella voce, anche
// a effetti sonori spenti.
func playVoice(_ m: Mascot) {
    play(Tone(effect: m.function.isAI ? .waits : .alarm, voice: m.voice), volume: m.volume, force: true)
}
