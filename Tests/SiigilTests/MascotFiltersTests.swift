import Foundation
import Testing
@testable import Siigil

// Le fixture sono quelle di ModelTests (session) e di WatchdogTests (t0, load, all).

// Un Monitor AI che guarda solo Claude dorme con una sessione Codex al lavoro e lavora con una Claude (spec §8). Review
// Focus: solo Codex, su un Mac senza Codex, le sessioni Claude non lo svegliano mai.
@Test func anAIMonitorSeesOnlyItsAgents() {
    let codex = ["c": session("c", .working, agent: .codex)]
    #expect(aiMood(topSession(sessions(codex, watchedBy: [.claude]))?.state) == .sleep)
    let both = codex.merging(["k": session("k", .working, agent: .claude)]) { a, _ in a }
    #expect(topSession(sessions(both, watchedBy: [.claude]))?.id == "k")
    #expect(sessionsByUrgency(sessions(both, watchedBy: [.claude, .codex])).count == 2)
    #expect(sessions(both, watchedBy: [.codex]).keys.sorted() == ["c"])
    #expect(sessions(["k": session("k", .waiting, agent: .claude)], watchedBy: [.codex]).isEmpty)
}

// Il Monitor di sistema che guarda solo la memoria resta calmo con un allarme CPU (spec §8). Più allarmi insieme, dal più
// grave; ognuno vede il più grave fra i suoi tipi, e menu e fumetto parlano di quello.
@Test func aSystemMonitorSeesOnlyItsKinds() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0)
    #expect(w.report.seen(by: [.memory]).alarm == nil && w.report.seen(by: [.memory]).mood == .sleep)
    #expect(w.report.seen(by: [.cpu]).alarm == .cpu(load("A", 400)))
    w.update(loads: [load("A", 400)], thermal: .serious, memory: 2, now: t0 + 10)
    #expect(w.report.alarms == [.heat(severe: true), .cpu(load("A", 400)), .memory(critical: false)])
    #expect(w.report.alarm == .heat(severe: true))
    #expect(w.report.seen(by: [.cpu, .memory]).alarm == .cpu(load("A", 400)))
    let memory = w.report.seen(by: [.memory])
    #expect(memory.alarm == .memory(critical: false) && memory.mood == .alarm && memory.headline(now: t0) == "Memory under pressure")
    // Il colpevole del menu è quello dell'allarme che si vede: l'app sopra il 100 % per chi guarda la CPU, quella che usa più
    // memoria (B, che di CPU ne usa poca) per chi guarda la memoria.
    w.update(loads: [load("A", 400, memory: 100), load("B", 10, memory: 900)], thermal: .nominal, memory: 2, now: t0 + 20)
    #expect(w.report.seen(by: [.memory]).culprit?.name == "B" && w.report.seen(by: [.cpu]).culprit?.name == "A")
}

// "Nuovo" per tipo: la memoria che arriva sotto un calore già in corso fa suonare chi guarda la memoria, non chi guarda
// tutto (per lui resta coperta, come prima).
@Test func newIsPerKind() {
    var w = Watchdog()
    w.update(loads: nil, thermal: .fair, memory: 1, now: t0)
    #expect(w.barks(all) && w.barks([.heat]) && !w.barks([.memory]))
    w.update(loads: nil, thermal: .fair, memory: 2, now: t0)
    #expect(!w.barks(all) && w.barks([.memory]) && !w.barks([.heat]))
    w.update(loads: nil, thermal: .fair, memory: 2, now: t0)
    #expect(!w.barks([.memory]))   // la stessa memoria alla lettura dopo: niente di nuovo
}

// Review Focus: ignorare un'app vale per tutte le mascotte; resta a guardarla solo chi guarda la CPU.
@Test func ignoringIsForEveryoneButOnlyCPUWatchersKeepWatching() {
    var w = Watchdog()
    w.update(loads: [load("A", 400)], thermal: .nominal, memory: 1, now: t0)
    w.ignore("com.A")
    #expect(w.report.seen(by: [.cpu]).mood == .watch && w.report.seen(by: [.cpu]).alarm == nil)
    #expect(w.report.seen(by: [.memory, .heat]).mood == .sleep)
    #expect(!w.barks(Set(AlarmKind.allCases)))
}
