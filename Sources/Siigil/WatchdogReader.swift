import Darwin
import Foundation
import os

// Le letture di sistema del Watchdog (spec 2026-09-27-siigil-watchdog-design, misure del 27/9). Nessun permesso: ps è
// setuid root e legge anche i processi di sistema (proc_pid_rusage legge solo quelli dell'utente, 503 su 788); il
// carico totale viene dal kernel. Bloccanti ma brevi: ps fuori dal main.

// Il carico di tutti i core insieme (0,004 ms).
func readHostTicks() -> HostTicks? {
    var info: processor_info_array_t?
    var count: mach_msg_type_number_t = 0
    var cores: natural_t = 0
    guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cores, &info, &count) == KERN_SUCCESS, let info else { return nil }
    defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(count) * vm_size_t(MemoryLayout<integer_t>.stride)) }
    var busy: UInt64 = 0, total: UInt64 = 0
    for core in 0..<Int(cores) {
        func ticks(_ state: Int32) -> UInt64 { UInt64(UInt32(bitPattern: info[core * Int(CPU_STATE_MAX) + Int(state)])) }
        let used = ticks(CPU_STATE_USER) + ticks(CPU_STATE_SYSTEM) + ticks(CPU_STATE_NICE)
        busy += used
        total += used + ticks(CPU_STATE_IDLE)
    }
    return HostTicks(busy: busy, total: total, cores: Int(cores))
}

// Tutti i processi con ps (-c: il nome corto). posix_spawn e non Process: 17 ms contro 95, e 17 ms di CPU contro 29
// (misurato il 27/9 su 799 processi).
func readProcesses() -> [ProcSample] {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return [] }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    posix_spawn_file_actions_adddup2(&actions, fds[1], 1)
    posix_spawn_file_actions_addclose(&actions, fds[0])
    let argv: [String] = ["/bin/ps", "-axco", "pid=,time=,rss=,comm="]
    let args = argv.map { strdup($0) } + [nil]
    var pid: pid_t = 0
    let spawned = posix_spawn(&pid, "/bin/ps", &actions, nil, args, nil)
    posix_spawn_file_actions_destroy(&actions)
    args.forEach { free($0) }
    close(fds[1])
    defer { close(fds[0]) }
    guard spawned == 0 else { logger.error("watchdog: ps non parte (\(spawned))"); return [] }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        let n = read(fds[0], &buffer, buffer.count)
        if n <= 0 { break }
        data.append(buffer, count: n)
    }
    var status: Int32 = 0
    waitpid(pid, &status, 0)
    return parsePS(String(decoding: data, as: UTF8.self))
}

// Il processo responsabile, come i gruppi di Monitoraggio Attività: funzione privata, caricata una volta; se un macOS
// futuro la toglie, nil e ogni processo sta da solo (owner(of:)).
private typealias Responsible = @convention(c) (pid_t) -> pid_t
private let responsible: Responsible? = dlsym(dlopen(nil, RTLD_NOW), "responsibility_get_pid_responsible_for_pid")
    .map { unsafeBitCast($0, to: Responsible.self) }
func responsiblePid(_ pid: pid_t) -> pid_t? { responsible.map { $0(pid) } }

// La pressione di memoria come la vede macOS: 1 normale, 2 attenzione, 4 critica.
func readMemoryPressure() -> Int32 {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
    return level
}
