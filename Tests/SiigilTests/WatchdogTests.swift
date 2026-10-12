import Foundation
import Testing
@testable import Siigil

// t0, load e all servono anche a MascotFiltersTests.
let t0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
private func sample(_ pid: pid_t, cpu: Double, rss: Int = 1000, name: String = "p") -> ProcSample {
    ProcSample(pid: pid, cpu: cpu, rss: rss, name: name)
}
private func app(_ name: String) -> Owner { Owner(key: "com.\(name)", name: name, bundle: "com.\(name)") }
func load(_ name: String, _ percent: Double, memory: Int = 0) -> Load { Load(owner: app(name), percent: percent, memory: memory) }
let all = Set(AlarmKind.allCases)   // chi guarda tutto: la regola di prima

@Test func parsesPSOutput() {
    let text = """
      406 828:30.17 143984 WindowServer
    89076   0:12.50  51200 Code Helper (Renderer)
    rotta
       77   x:12.00    100 guasto

    """
    #expect(parsePS(text) == [
        ProcSample(pid: 406, cpu: 828 * 60 + 30.17, rss: 143984, name: "WindowServer"),
        ProcSample(pid: 89076, cpu: 12.5, rss: 51200, name: "Code Helper (Renderer)"),
    ])
}

@Test func ownerIsTheResponsibleApp() {
    let apps = [pid_t(10): AppInfo(name: "Code", bundle: "com.microsoft.VSCode")]
    let helper = sample(20, cpu: 0, name: "Code Helper")
    #expect(owner(of: helper, responsible: 10, apps: apps) == Owner(key: "com.microsoft.VSCode", name: "Code", bundle: "com.microsoft.VSCode"))
    // Processo di sistema: la funzione risponde -1 o il processo stesso, nessuna app: sta da solo.
    let daemon = sample(30, cpu: 0, name: "mds_stores")
    #expect(owner(of: daemon, responsible: -1, apps: apps) == Owner(key: "pid:30", name: "mds_stores", bundle: nil))
    // Un'app senza bundle id: chiave il nome, niente bundle (niente Esci dal menu).
    let odd = [pid_t(50): AppInfo(name: "Strana", bundle: "")]
    #expect(owner(of: sample(50, cpu: 0), responsible: 50, apps: odd) == Owner(key: "Strana", name: "Strana", bundle: nil))
}

@Test func noLoadsWithoutAMinuteOfHistory() {
    var h = CPUHistory()
    h.add([sample(1, cpu: 10)], at: t0)
    #expect(h.loads([sample(1, cpu: 30)], at: t0 + 30) { _ in app("A") } == nil)
}

@Test func loadIsThePerAppAverageOverTheLastMinute() {
    var h = CPUHistory()
    h.add([sample(1, cpu: 10, rss: 100), sample(2, cpu: 5, rss: 50), sample(3, cpu: 0)], at: t0)
    h.add([sample(1, cpu: 20), sample(2, cpu: 15), sample(3, cpu: 0)], at: t0 + 30)   // troppo recente per fare da base
    let now = t0 + 60
    // pid 1 e 2 sono di A (helper sommati), 3 di sistema; il 4 è nato dopo la base e conta tutto il suo tempo.
    let loads = h.loads([sample(1, cpu: 70, rss: 100), sample(2, cpu: 65, rss: 50), sample(3, cpu: 6), sample(4, cpu: 12)], at: now) {
        $0.pid == 3 ? Owner(key: "pid:3", name: "mds", bundle: nil) : app("A")
    }!
    let a = loads.first { $0.owner.key == "com.A" }!, mds = loads.first { $0.owner.key == "pid:3" }!
    #expect(abs(a.percent - (60 + 60 + 12) / 60 * 100) < 0.001)   // 220 %
    #expect(a.memory == 100 + 50 + 1000)
    #expect(abs(mds.percent - 10) < 0.001)
}

@Test func reusedPidCountsZero() {
    var h = CPUHistory()
    h.add([sample(1, cpu: 500)], at: t0)
    #expect(h.loads([sample(1, cpu: 3)], at: t0 + 60) { _ in app("A") }!.first!.percent == 0)
}

@Test func baseOlderThan150sIsIgnored() {
    var h = CPUHistory()
    h.add([sample(1, cpu: 0)], at: t0)
    #expect(h.loads([sample(1, cpu: 600)], at: t0 + 200) { _ in app("A") } == nil)
}

@Test func busyCoresFromKernelTicks() {
    let a = HostTicks(busy: 1000, total: 10_000, cores: 10), b = HostTicks(busy: 2000, total: 20_000, cores: 10)
    #expect(busyCores(from: a, to: b) == 1)   // un decimo di 10 core = un core intero
    #expect(busyCores(from: b, to: b) == 0)
    #expect(busyCores(from: b, to: a) == 0)   // contatori ripartiti: niente di negativo
}

@Test func cpuAlarmNeedsMoreThanOneFullCore() {
    var w = Watchdog()
    w.update(loads: [load("A", 100)], thermal: .nominal, memory: 1, now: t0)
    #expect(w.report.alarm == nil)
    w.update(loads: [load("A", 412), load("B", 150)], thermal: .nominal, memory: 1, now: t0 + 10)
    #expect(w.report.alarm == .cpu(load("A", 412)) && w.report.since == t0 + 10 && w.report.mood == .alarm)
    #expect(w.report.alarm?.caption == "A 412 %" && w.report.alarm?.kind == "cpu:com.A")
    #expect(w.report.top.map(\.owner.name) == ["A", "B"])
}

@Test func noCPUAlarmWithoutLoads() {
    var w = Watchdog()
    w.update(loads: nil, thermal: .nominal, memory: 1, now: t0)
    #expect(w.report.alarm == nil && w.report.mood == .sleep)
}

@Test func cpuAlarmEndsThreeReadingsAfterTheCulpritIsGone() {
    var w = Watchdog()
    w.update(loads: [load("A", 300)], thermal: .nominal, memory: 1, now: t0)
    w.update(loads: [], thermal: .nominal, memory: 1, now: t0 + 10)        // A si è chiusa
    w.update(loads: [], thermal: .nominal, memory: 1, now: t0 + 20)       // ancora senza A
    #expect(w.report.alarm == .cpu(load("A", 300)) && w.hasCulprit)
    w.update(loads: [], thermal: .nominal, memory: 1, now: t0 + 30)
    #expect(w.report.alarm == nil && !w.hasCulprit && w.report.since == nil)
}

@Test func aHeavierAppTakesOverAndRestartsTheClock() {
    var w = Watchdog()
    w.update(loads: [load("A", 200)], thermal: .nominal, memory: 1, now: t0)
    w.update(loads: [load("A", 50), load("B", 300)], thermal: .nominal, memory: 1, now: t0 + 10)
    #expect(w.report.alarm == .cpu(load("B", 300)) && w.report.since == t0 + 10)
}

@Test func ignoredAppDoesNotHideAnother() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0)
    w.ignore("com.A")
    #expect(w.report.alarm == nil && w.report.ignored == "com.A" && w.report.mood == .watch)
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0 + 10)
    #expect(w.report.alarm == nil && w.report.mood == .watch)
    w.update(loads: [load("A", 400), load("B", 150)], thermal: .nominal, memory: 1, now: t0 + 20)
    #expect(w.report.alarm == .cpu(load("B", 150)))
}

@Test func ignoreEndsWhenTheAppCalmsDown() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0)
    w.ignore("com.A")
    w.update(loads: [load("A", 90)], thermal: .nominal, memory: 1, now: t0 + 10)
    #expect(w.report.ignored == nil && w.report.mood == .sleep)
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0 + 20)
    #expect(w.report.alarm == .cpu(load("A", 400)))   // ripartita: di nuovo allarme
}

@Test func theMostSevereAlarmWins() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .serious, memory: 1, now: t0)
    #expect(w.report.alarm == .heat(severe: true) && w.report.alarm?.severe == true)
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 4, now: t0 + 10)
    #expect(w.report.alarm == .memory(critical: true))
    w.update(loads: [load("A", 400)], thermal: .fair, memory: 2, now: t0 + 20)
    #expect(w.report.alarm == .cpu(load("A", 400)))   // la CPU prima del calore discreto e della memoria in attenzione
    w.update(loads: [load("A", 10)], thermal: .fair, memory: 2, now: t0 + 30)
    w.update(loads: [load("A", 10)], thermal: .fair, memory: 2, now: t0 + 40)
    w.update(loads: [load("A", 10)], thermal: .fair, memory: 2, now: t0 + 50)
    #expect(w.report.alarm == .heat(severe: false) && w.report.alarm?.kind == "heat")
    w.update(loads: [load("A", 10)], thermal: .nominal, memory: 2, now: t0 + 60)
    #expect(w.report.alarm == .memory(critical: false))
}

@Test func culpritIsOnlyAUserApp() {
    var w = Watchdog()
    let daemon = Load(owner: Owner(key: "pid:3", name: "mds", bundle: nil), percent: 300, memory: 5)
    w.update(loads: [daemon], thermal: .nominal, memory: 1, now: t0)
    #expect(w.report.alarm == .cpu(daemon) && w.report.culprit == nil)
    w.update(loads: [load("A", 10, memory: 900), load("B", 20, memory: 100)], thermal: .nominal, memory: 4, now: t0 + 10)
    #expect(w.report.culprit?.name == "A")   // memoria: chi ne usa di più
}

@Test func headlineSaysWhyAndForHowLong() {
    var w = Watchdog()
    w.update(loads: [load("Code", 412)], thermal: .nominal, memory: 1, now: t0)
    #expect(w.report.headline(now: t0 + 185) == "Code 412 % for 3 min")
    #expect(WatchdogReport().headline(now: t0) == "All quiet")
}

@Test func emptyReadingIsNeverABase() {
    var h = CPUHistory()
    h.add([], at: t0)   // ps fallito
    #expect(h.loads([sample(1, cpu: 600)], at: t0 + 60) { _ in app("A") } == nil)
}

@Test func barksOnlyAtANewAlarm() {
    var w = Watchdog()
    w.update(loads: [load("A", 300)], thermal: .nominal, memory: 1, now: t0)
    #expect(w.barks(all))
    w.update(loads: [load("A", 320)], thermal: .nominal, memory: 1, now: t0 + 10)
    #expect(!w.barks(all))   // lo stesso allarme che cambia valore
    w.update(loads: [load("A", 50), load("B", 400)], thermal: .nominal, memory: 1, now: t0 + 20)
    #expect(w.barks(all))    // un'altra app: allarme nuovo
    w.ignore("com.B")
    #expect(!w.barks(all))
}

@Test func noBarkWhenAHiddenAlarmComesBackIntoView() {
    var w = Watchdog()
    w.update(loads: [load("A", 300)], thermal: .fair, memory: 1, now: t0)
    #expect(w.report.alarm == .cpu(load("A", 300)) && w.barks(all))
    for i in 1...3 { w.update(loads: [load("A", 10)], thermal: .fair, memory: 1, now: t0 + Double(i) * 10) }
    #expect(w.report.alarm == .heat(severe: false) && !w.barks(all))   // il calore c'era già, coperto dalla CPU
    w.update(loads: [load("A", 10)], thermal: .fair, memory: 2, now: t0 + 40)
    #expect(w.report.alarm == .heat(severe: false) && !w.barks(all))   // la memoria resta coperta dal calore
    w.update(loads: [load("A", 10)], thermal: .nominal, memory: 2, now: t0 + 50)
    #expect(w.report.alarm == .memory(critical: false) && !w.barks(all))
}

@Test func withoutCPUDataCulpritAndIgnoreStay() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0)
    w.ignore("com.A")
    for _ in 1...5 { w.update(loads: nil, thermal: .nominal, memory: 1, now: t0) }
    #expect(w.report.ignored == "com.A" && w.report.mood == .watch)
    w.update(loads: [load("A", 400), load("B", 300)], thermal: .nominal, memory: 1, now: t0 + 60)
    for _ in 1...5 { w.update(loads: nil, thermal: .nominal, memory: 1, now: t0) }
    #expect(w.report.alarm == .cpu(load("B", 300)) && w.hasCulprit && !w.barks(all))
    #expect(w.report.top.map(\.owner.name) == ["A", "B"])   // la classifica resta quella dell'ultima lettura
    w.update(loads: nil, thermal: .serious, memory: 1, now: t0)
    #expect(w.report.alarm == .heat(severe: true) && w.barks(all))   // calore e memoria si aggiornano comunque
}

// Una pausa di pochi secondi (niente lettura per app) non sveglia il cane su un lavoro ignorato; la media del minuto sì.
@Test func aLullDoesNotEndAnIgnore() {
    var w = Watchdog()
    w.update(loads: [load("Xcode", 400)], thermal: .nominal, memory: 1, now: t0)
    w.ignore("com.Other")   // il menu mostrava un'altra app: niente
    #expect(w.report.ignored == nil && w.hasCulprit)
    w.ignore("com.Xcode")
    w.update(loads: nil, thermal: .nominal, memory: 1, now: t0)   // un giro col Mac sotto un core: niente ps
    w.update(loads: [load("Xcode", 333)], thermal: .nominal, memory: 1, now: t0 + 20)
    #expect(w.report.alarm == nil && w.report.mood == .watch && !w.barks(all))
    w.update(loads: [load("Xcode", 40)], thermal: .nominal, memory: 1, now: t0 + 30)
    #expect(w.report.ignored == nil && w.report.mood == .sleep)
}

@Test func heatOffersToQuitOnlyAnAppAboveTheThreshold() {
    var w = Watchdog()
    w.update(loads: [load("Safari", 6)], thermal: .serious, memory: 1, now: t0)
    #expect(w.report.alarm == .heat(severe: true) && w.report.culprit == nil)
    w.update(loads: [load("Code", 412), load("Safari", 6)], thermal: .serious, memory: 1, now: t0 + 10)
    #expect(w.report.alarm == .heat(severe: true) && w.report.culprit?.name == "Code")
}
