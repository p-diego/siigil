import Foundation
import Testing
@testable import Siigil

@Test func psReadsEveryProcessIncludingThisOne() {
    let all = readProcesses()
    #expect(all.count > 50)
    #expect(all.contains { $0.pid == getpid() })
    #expect(all.contains { $0.pid == 1 && $0.name == "launchd" })   // anche i processi di root
}

@Test func kernelTicksAdvance() throws {
    let a = try #require(readHostTicks())
    let end = Date() + 0.05
    while Date() < end {}   // un po' di lavoro
    let b = try #require(readHostTicks())
    #expect(b.total > a.total && b.busy > a.busy && a.cores == ProcessInfo.processInfo.processorCount)
}

@Test func responsibleFunctionExistsAndKnowsThisProcess() {
    #expect(responsiblePid(getpid()) != nil)
}

@Test func memoryPressureIsAKnownLevel() {
    #expect([1, 2, 4].contains(readMemoryPressure()))
}
