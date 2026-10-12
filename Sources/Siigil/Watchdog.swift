import Foundation

// Il Watchdog (spec 2026-09-27-siigil-watchdog-design): chi si sta mangiando il Mac. Qui la parte pura — lettura di ps,
// a chi appartiene un processo, carico per app nell'ultimo minuto, filtro del carico totale, allarmi —; le letture vere
// stanno in WatchdogReader.swift, il ritmo nel Poller.

// Una riga di `ps -axco pid=,time=,rss=,comm=`: tempo di CPU accumulato in secondi (sempre `m:ss.cc`, anche oltre
// l'ora: WindowServer a `828:30.17`, 27/9), memoria residente in KB, nome corto (può avere spazi).
struct ProcSample: Equatable {
    let pid: pid_t
    let cpu: Double
    let rss: Int
    let name: String
}

func parsePS(_ text: String) -> [ProcSample] {
    text.split(separator: "\n").compactMap { line in
        let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard f.count == 4, let pid = pid_t(f[0]), let rss = Int(f[2]) else { return nil }
        let t = f[1].split(separator: ":")
        guard t.count == 2, let minutes = Double(t[0]), let seconds = Double(t[1]) else { return nil }
        return ProcSample(pid: pid, cpu: minutes * 60 + seconds, rss: rss, name: String(f[3]))
    }
}

// Un'app del Dock com'era alla lettura.
struct AppInfo: Equatable {
    let name: String
    let bundle: String
}

// A chi si somma la CPU di un processo: un'app (chiave il bundle id) o il processo da solo (chiave "pid:N").
struct Owner: Hashable {
    let key: String
    let name: String
    let bundle: String?   // nil = processo di sistema o app senza bundle id: niente Esci né icona dell'app
}

// Come i gruppi di Monitoraggio Attività: l'app responsabile del processo (`responsible`, dalla funzione privata di
// macOS; nil se la funzione manca). Un processo che non porta a un'app sta da solo.
func owner(of s: ProcSample, responsible: pid_t?, apps: [pid_t: AppInfo]) -> Owner {
    if let responsible, let info = apps[responsible] {
        return Owner(key: info.bundle.isEmpty ? info.name : info.bundle, name: info.name, bundle: info.bundle.isEmpty ? nil : info.bundle)
    }
    return Owner(key: "pid:\(s.pid)", name: s.name, bundle: nil)
}

// Il carico di un'app (o di un processo di sistema) nell'ultimo minuto: CPU come Monitoraggio Attività (100 = un core
// intero) e memoria residente (KB) dei suoi processi.
struct Load: Equatable {
    let owner: Owner
    let percent: Double
    let memory: Int
}

// Le letture di ps con il loro istante. Il tempo di CPU è cumulativo: la media di un periodo è la differenza tra due
// letture divisa per il tempo passato, anche se in mezzo ne sono saltate (filtro del carico totale).
struct CPUHistory {
    private var readings: [(at: Date, cpu: [pid_t: Double])] = []

    // Dopo `loads`: la lettura di adesso fa da base alle prossime. Oltre i 150 s non serve più.
    mutating func add(_ samples: [ProcSample], at now: Date) {
        // ps fallito (niente pipe o spawn, proprio quando il Mac è pieno): non è una lettura. Vuota, come base farebbe
        // contare a ogni processo tutto il suo tempo di CPU (Safari con 2 h: 12000 %).
        guard !samples.isEmpty else { return }
        readings.append((now, Dictionary(samples.map { ($0.pid, $0.cpu) }, uniquingKeysWith: { a, _ in a })))
        readings.removeAll { now.timeIntervalSince($0.at) > 150 }
    }

    // Il carico per app nell'ultimo minuto: la base è la lettura più recente tra quelle di 55–150 s prima; nil senza (il
    // primo minuto: prima non c'è allarme). Un processo che nella base non c'era è nato dopo e conta tutto il suo tempo
    // (più preciso di "dal primo tempo letto" della spec: sta tutto nel periodo); un tempo più basso della base (pid
    // riusato) conta zero; uno sparito non conta.
    func loads(_ samples: [ProcSample], at now: Date, owner: (ProcSample) -> Owner) -> [Load]? {
        guard let base = readings.last(where: { (55...150).contains(now.timeIntervalSince($0.at)) }) else { return nil }
        let span = now.timeIntervalSince(base.at)
        var cpu: [Owner: Double] = [:], memory: [Owner: Int] = [:]
        for s in samples {
            let o = owner(s)
            cpu[o, default: 0] += max(0, s.cpu - (base.cpu[s.pid] ?? 0))
            memory[o, default: 0] += s.rss
        }
        return cpu.map { Load(owner: $0.key, percent: $0.value / span * 100, memory: memory[$0.key] ?? 0) }
    }
}

// I tick di tutti i core insieme dal kernel (host_processor_info): occupati (utente, sistema, nice) e totali.
struct HostTicks: Equatable {
    let busy: UInt64
    let total: UInt64
    let cores: Int
}

// Quanti core ha usato il Mac in media tra due letture (1 = un core intero). Il filtro gratuito (0,004 ms, 27/9): sotto 1
// nessuna app può essere sopra il 100 %, e ps non serve.
func busyCores(from a: HostTicks, to b: HostTicks) -> Double {
    guard b.total > a.total, b.busy >= a.busy else { return 0 }
    return Double(b.busy - a.busy) / Double(b.total - a.total) * Double(b.cores)
}

// Un allarme (spec §1): rosso col Mac "serio" o peggio o la memoria critica; arancione un'app sopra il 100 % da un
// minuto, il Mac "discreto", la memoria in attenzione. Al più uno per tipo, in quest'ordine di gravità.
enum Alarm: Equatable {
    case cpu(Load)
    case heat(severe: Bool)
    case memory(critical: Bool)

    var severe: Bool {
        switch self {
        case .cpu: false
        case .heat(let severe): severe
        case .memory(let critical): critical
        }
    }

    // Lo stesso per lo stesso allarme che cambia solo di valore: si suona a un allarme nuovo, non a ogni lettura (fresh).
    var kind: String {
        switch self {
        case .cpu(let l): "cpu:\(l.owner.key)"
        case .heat: "heat"
        case .memory: "memory"
        }
    }

    // Il tipo, per il filtro delle mascotte (spec sezione Mascotte §3).
    var type: AlarmKind {
        switch self {
        case .cpu: .cpu
        case .heat: .heat
        case .memory: .memory
        }
    }

    // Il fumetto di un Monitor di sistema.
    var caption: String {
        switch self {
        case .cpu(let l): "\(l.owner.name) \(Int(l.percent.rounded())) %"
        case .heat: String(localized: "Mac hot!")
        case .memory: String(localized: "Memory full!")
        }
    }
}

// Quello che vedono la barra e il menu.
struct WatchdogReport: Equatable {
    var alarms: [Alarm] = []   // gli allarmi in corso, dal più grave (sezione Mascotte §7)
    var since: Date?        // da quando dura l'allarme CPU (menu: "da 3 min")
    var top: [Load] = []    // le 5 più pesanti dell'ultima lettura
    var memoryTop: Load?    // chi usa più memoria all'ultima lettura
    var ignored: String?    // chiave dell'app ignorata finché non smette

    var alarm: Alarm? { alarms.first }   // il più grave
    // L'umore di un Monitor di sistema (spec mascotte viva §2): dorme, allarme (occhi spalancati, trema), guarda (legge il
    // lavoro pesante che hai ignorato, nessun altro allarme).
    var mood: MascotMood { alarm != nil ? .alarm : ignored != nil ? .watch : .sleep }

    // Quello che vede una mascotte che guarda solo `kinds` (spec sezione Mascotte §3): gli allarmi di quei tipi, e il
    // lavoro pesante ignorato solo se guarda la CPU. L'app ignorata è una sola per tutte.
    func seen(by kinds: Set<AlarmKind>) -> WatchdogReport {
        var r = self
        r.alarms = alarms.filter { kinds.contains($0.type) }
        if !kinds.contains(.cpu) { r.ignored = nil }
        return r
    }

    // Chi si può chiudere dal menu: l'app dell'allarme CPU; con la memoria quella che ne usa di più; col calore la più
    // pesante solo se è sopra il 100 %. Solo app dell'utente (bundle): un processo di sistema non si chiude senza password.
    var culprit: Owner? {
        let o: Owner? = switch alarm {
        case .cpu(let l)?: l.owner
        case .memory?: memoryTop?.owner
        case .heat?: top.first.flatMap { $0.percent > 100 ? $0.owner : nil }
        case nil: nil
        }
        return o?.bundle == nil ? nil : o
    }

    // La prima riga del menu.
    func headline(now: Date) -> String {
        switch alarm {
        case .cpu(let l)?:
            let minutes = max(1, Int(now.timeIntervalSince(since ?? now) / 60))
            return "\(l.owner.name) \(Int(l.percent.rounded())) % " + String(localized: "for \(minutes) min")
        case .heat(let severe)?: return severe ? String(localized: "Mac very hot") : String(localized: "Mac hot")
        case .memory(let critical)?: return critical ? String(localized: "Memory almost full") : String(localized: "Memory under pressure")
        case nil: return String(localized: "All quiet")
        }
    }
}

// L'automa degli allarmi, una chiamata a lettura (ogni 10 s). Solo una lettura per app (`loads`: ps con una base di un
// minuto) cambia colpevole, letture sotto, app ignorata e classifica: le soglie sono sulla media dell'ultimo minuto, e
// una pausa di pochi secondi (una build ignorata che aspetta il disco) non dice niente su quella media. Senza (`loads`
// nil: niente ps in questo giro perché il Mac era sotto un core, ps senza base dopo l'avvio o lo sleep, ps fallito)
// cambiano solo calore e memoria. `thermal` e `memory` come li dà macOS (memoria: 1 normale, 2 attenzione, 4 critica).
struct Watchdog {
    private(set) var report = WatchdogReport()
    private(set) var fresh: Set<AlarmKind> = []   // i tipi con un allarme nuovo all'ultimo aggiornamento
    private var culprit: Load?   // l'app sopra il 100 %, o l'ultima finché non passano 3 letture sotto
    private var below = 0
    private var thermal = ProcessInfo.ThermalState.nominal
    private var memory: Int32 = 1

    var hasCulprit: Bool { culprit != nil }   // il Poller legge ps finché c'è

    // Le condizioni in corso, anche quelle coperte da una più grave (le soglie stanno solo in alarms()): un allarme che torna
    // in vista non è nuovo.
    private var active: Set<String> { Set(alarms().map(\.kind)) }

    mutating func update(loads: [Load]?, thermal: ProcessInfo.ThermalState, memory: Int32, now: Date) {
        let before = active
        self.thermal = thermal
        self.memory = memory
        if let loads {
            report.top = Array(loads.sorted { $0.percent > $1.percent }.prefix(5))
            report.memoryTop = loads.max { $0.memory < $1.memory }
            // L'app ignorata torna normale quando la sua media del minuto scende sotto il 100 % (o si è chiusa).
            if let key = report.ignored, (loads.first(where: { $0.owner.key == key })?.percent ?? 0) <= 100 { report.ignored = nil }
            let hot = loads.filter { $0.percent > 100 && $0.owner.key != report.ignored }.max { $0.percent < $1.percent }
            if let hot {
                if culprit?.owner.key != hot.owner.key { report.since = now }
                culprit = hot
                below = 0
            } else if culprit != nil {
                below += 1
                if below >= 3 { culprit = nil; report.since = nil }
            }
        }
        settle(since: before)
    }

    // "Ignora finché non smette" (menu) per l'app che il menu mostrava: se nel frattempo il colpevole è cambiato, niente.
    mutating func ignore(_ key: String) {
        guard let culprit, culprit.owner.key == key else { return }
        report.ignored = culprit.owner.key
        self.culprit = nil
        below = 0
        report.since = nil
        report.alarms = alarms()
        fresh = []
    }

    // Suona chi vede un allarme nuovo: il più grave fra i tipi che guarda, se alla lettura prima non c'era (spec §2,
    // sezione Mascotte §5). Con tutti i tipi è la regola di sempre: un allarme coperto da uno più grave non suona.
    func barks(_ kinds: Set<AlarmKind>) -> Bool { report.seen(by: kinds).alarm.map { fresh.contains($0.type) } ?? false }

    // Gli allarmi del momento e quali sono nuovi: quelli che alla lettura prima non c'erano, per tipo.
    private mutating func settle(since before: Set<String>) {
        report.alarms = alarms()
        fresh = Set(report.alarms.filter { !before.contains($0.kind) }.map(\.type))
    }

    private func alarms() -> [Alarm] {
        var out: [Alarm] = []
        if thermal.rawValue >= ProcessInfo.ThermalState.serious.rawValue { out.append(.heat(severe: true)) }
        if memory >= 4 { out.append(.memory(critical: true)) }
        if let culprit { out.append(.cpu(culprit)) }
        if thermal == .fair { out.append(.heat(severe: false)) }
        if (2..<4).contains(memory) { out.append(.memory(critical: false)) }
        return out
    }
}
