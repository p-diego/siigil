import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import Foundation
import IOKit.ps
import os

// Errori nel log unificato (Console.app, o `/usr/bin/log stream --predicate 'subsystem == "com.siigil.app"'`): l'app installata
// parte da LaunchServices con stdout e stderr su /dev/null (lsof, 2026-09-25), quindi `fputs` non arrivava a nessuno.
let logger = Logger(subsystem: "com.siigil.app", category: "siigil")

// Una CLI: stdout se esce con 0, nil se non parte o fallisce (stderr scartato). Bloccante: non sul main.
// Una CLI bloccata congelerebbe chi la aspetta per sempre (la barra, con AeroSpace): dopo `timeout` s viene uccisa.
func shell(_ path: String, _ args: [String], timeout: TimeInterval = 5) -> String? {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    let out = Pipe()
    p.standardOutput = out
    p.standardError = FileHandle.nullDevice
    do { try p.run() } catch { logger.error("\(path, privacy: .public): \(String(describing: error), privacy: .public)"); return nil }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
        if p.isRunning { p.terminate(); logger.error("\(path, privacy: .public): timeout \(args.joined(separator: " "), privacy: .public)") }
    }
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return p.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
}

// Le app aperte davvero: tutte, o quelle di un bundle. Su macOS 27 un'app uscita con processi ancora in background resta
// registrata ("exited-with-subordinates" in lsappinfo, pallino grigio nel Dock) e, quando un'altra app si apre o esce,
// rientra per un momento nell'elenco come un'app del Dock qualunque, col pid del processo già finito (riprodotto il
// 2026-09-27): si scarta chi non ha più il processo.
func runningApps(bundle: String? = nil) -> [NSRunningApplication] {
    let apps = bundle.map(NSRunningApplication.runningApplications(withBundleIdentifier:)) ?? NSWorkspace.shared.runningApplications
    return apps.filter { processAlive($0.processIdentifier) }
}

// Segnale 0: niente di inviato, solo il controllo. EPERM = esiste ma è di un altro utente (root).
func processAlive(_ pid: pid_t) -> Bool { kill(pid, 0) == 0 || errno == EPERM }

// `open` di macOS, senza aspettarlo: NSWorkspace.openApplication da un'app mai attiva lancia senza finestra, `open` no.
func open(_ args: String...) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    p.arguments = args
    try? p.run()
}

// Per il menu della batteria (autore, 4/10): i watt dell'alimentatore quando è collegato, altrimenti nil.
func adapterWatts() -> Int? {
    (IOPSCopyExternalPowerAdapterDetails()?.takeRetainedValue() as? [String: Any])?[kIOPSPowerAdapterWattsKey] as? Int
}

func readBattery() -> Battery? {
    let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
    let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
    guard let src = list.first,
          let d = IOPSGetPowerSourceDescription(info, src)?.takeUnretainedValue() as? [String: Any]
    else { return nil }
    return Battery(percent: min(max(d[kIOPSCurrentCapacityKey] as? Int ?? 0, 0), 100),
                   // Fulmine quando è attaccato alla corrente, come la menu bar: la ricarica ottimizzata
                   // ferma la carica all'80% e kIOPSIsChargingKey diventa false.
                   charging: (d[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue,
                   lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled)
}

private func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
}
func deviceAddress(input: Bool) -> AudioObjectPropertyAddress {
    address(input ? kAudioHardwarePropertyDefaultInputDevice : kAudioHardwarePropertyDefaultOutputDevice)
}

// Una proprietà di CoreAudio, letta come `T` (il valore di partenza ne dà il tipo); nil se non c'è.
private func audioValue<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ initial: T) -> T? {
    var addr = addr, value = initial, size = UInt32(MemoryLayout<T>.size)
    return withUnsafeMutableBytes(of: &value) { AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0.baseAddress!) } == noErr ? value : nil
}

// La scrittura gemella; falso se non riesce.
@discardableResult private func setAudioValue<T>(_ object: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) -> Bool {
    var addr = addr
    return withUnsafeBytes(of: value) { AudioObjectSetPropertyData(object, &addr, 0, nil, UInt32($0.count), $0.baseAddress!) } == noErr
}

func defaultOutputDevice() -> AudioDeviceID? { defaultDevice(input: false) }

func outputAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress { address(selector, scope: kAudioDevicePropertyScopeOutput) }

// Livello 0...100 del dispositivo, anche da muto. Il volume "virtuale" di AudioToolbox, non il canale main: le cuffie
// Bluetooth (AirPods, misurato il 2026-09-22) espongono solo i canali 1 e 2 e col main il widget spariva. Sugli
// altoparlanti del Mac il valore è identico. Il muto invece sta sul canale main anche sulle AirPods.
let volumeSelector = kAudioHardwareServiceDeviceProperty_VirtualMainVolume
func readVolume(_ device: AudioDeviceID) -> Int? {
    audioValue(device, outputAddress(volumeSelector), Float32(0)).map { Int(($0 * 100).rounded()) }
}

func isMuted(_ device: AudioDeviceID) -> Bool { audioValue(device, outputAddress(kAudioDevicePropertyMute), UInt32(0)).map { $0 != 0 } ?? false }

// I dispositivi di uscita o d'ingresso, col nome e se sono quello attivo; e il cambio dell'attivo. CoreAudio
// pubblica, come il resto del volume: nessun permesso. Per il menu del volume (autore, 4/10).
func audioDevices(input: Bool) -> [(id: AudioDeviceID, name: String, transport: UInt32)] {
    var addr = address(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    let scope = input ? kAudioDevicePropertyScopeInput : kAudioDevicePropertyScopeOutput
    return ids.compactMap { id in
        // Ha canali in quella direzione? (gli aggregati nascosti e i dispositivi solo-uscita/solo-ingresso si filtrano qui)
        var streams = address(kAudioDevicePropertyStreams, scope: scope), streamSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &streamSize) == noErr, streamSize > 0,
              let name = audioValue(id, address(kAudioObjectPropertyName), "" as CFString) else { return nil }
        return (id, name as String, audioValue(id, address(kAudioDevicePropertyTransportType), UInt32(0)) ?? 0)
    }
}

// Il simbolo di un dispositivo audio come nel pannello di macOS: dal tipo di trasporto, col nome a sciogliere i
// Bluetooth (AirPods o cuffie generiche). Le Apple TV compaiono solo quando sono già l'uscita (AirPlay via CoreAudio):
// scoprirle prima è il canale privato di AirPlay, fuori dalla nostra linea (autore, 4/10).
func audioDeviceSymbol(transport: UInt32, name: String, input: Bool) -> String {
    switch transport {
    case kAudioDeviceTransportTypeBuiltIn: input ? "microphone" : "laptopcomputer"
    case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
        name.localizedCaseInsensitiveContains("airpods") ? "airpods" : "headphones"
    case kAudioDeviceTransportTypeAirPlay: "airplay.audio"
    case kAudioDeviceTransportTypeDisplayPort, kAudioDeviceTransportTypeHDMI: "display"
    case kAudioDeviceTransportTypeUSB: input ? "microphone" : "hifispeaker"
    default: input ? "microphone" : "speaker.wave.2"
    }
}

func defaultDevice(input: Bool) -> AudioDeviceID? {
    audioValue(AudioObjectID(kAudioObjectSystemObject), deviceAddress(input: input), AudioDeviceID(0))
}

func setDefaultDevice(_ id: AudioDeviceID, input: Bool) { setAudioValue(AudioObjectID(kAudioObjectSystemObject), deviceAddress(input: input), id) }

// Una scrittura sull'uscita attiva: volume (il regolatore del menu) e muto passano di qui (review 4/10). Falso se non
// riesce: alcune uscite (USB, HDMI) il muto non ce l'hanno.
@discardableResult private func setOutput<T>(_ selector: AudioObjectPropertySelector, _ value: T) -> Bool {
    defaultOutputDevice().map { setAudioValue($0, outputAddress(selector), value) } ?? false
}

func setVolume(_ value: Float) { setOutput(volumeSelector, max(0, min(1, value))) }

@discardableResult func setMuted(_ on: Bool) -> Bool { setOutput(kAudioDevicePropertyMute, UInt32(on ? 1 : 0)) }

func toggleMute() {
    guard demo == nil else { return }   // in demo non si tocca l'audio vero
    guard let device = defaultOutputDevice() else { return }
    setMuted(!isMuted(device))
}

// Id delle finestre da mostrare. AeroSpace elenca anche palette e pannelli flottanti (layer > 0 del window server,
// es. Affinity): con il documento ridotto a icona resterebbe un'icona in barra per un pannello invisibile. Si tengono
// le finestre a layer 0 e, per i processi che non ne hanno nessuna (quick terminal di Ghostty, hotkey window di
// iTerm, player sempre in primo piano), anche quelle a layer > 0: lì la finestra flottante è l'app.
// Nella stessa lettura, quali di queste sono fuori schermo per macOS: minimizzate o di un'app nascosta. Quelle degli
// altri spazi di AeroSpace no: AeroSpace le sposta in un angolo, ma restano a schermo (misurato il 2026-09-26).
// Una finestra in uno spazio nativo a schermo intero è fuori schermo allo stesso modo, e ci sta: non è più nel suo
// workspace, da dove sei non la vedi, quindi l'app va nella pillola delle nascoste e da lì un click la raggiunge —
// ma piena, non attenuata: è parcheggiata, non minimizzata (deciso con l'autore il 3/10, su 27.2). La si riconosce
// dalla taglia: fuori schermo ma grande quanto il suo schermo (coversTheScreen, la regola della barra).
// Schermi da CoreGraphics, non da NSScreen: screenWindows gira sulla coda del Poller e NSScreen vuole il main
// thread (review 3/10); i bounds CG sono già con l'origine in alto a sinistra, senza conversioni.
private func fullscreenSized(_ b: CGRect) -> Bool {
    var ids = [CGDirectDisplayID](repeating: 0, count: 8); var n: UInt32 = 0
    CGGetActiveDisplayList(8, &ids, &n)
    return ids.prefix(Int(n)).map(CGDisplayBounds).contains { s in
        b.minX < s.maxX && b.maxX > s.minX &&
            coversTheScreen(top: b.minY - s.minY, height: b.height, screenHeight: s.height, barHeight: BarPanel.height)
    }
}

func screenWindows() -> (normal: Set<Int>, offscreen: Set<Int>, fullscreen: Set<pid_t>, visible: Set<pid_t>) {
    let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
        .compactMap { w -> (id: Int, pid: pid_t, layer: Int, onScreen: Bool, bounds: CGRect?)? in
            guard let id = w[kCGWindowNumber as String] as? Int, let pid = w[kCGWindowOwnerPID as String] as? Int,
                  let layer = w[kCGWindowLayer as String] as? Int else { return nil }
            return (id, pid_t(pid), layer, w[kCGWindowIsOnscreen as String] as? Bool ?? false,
                    (w[kCGWindowBounds as String] as? NSDictionary).flatMap(CGRect.init(dictionaryRepresentation:)))
        }
    let withNormal = Set(list.filter { $0.layer == 0 }.map(\.pid))
    let normal = list.filter { $0.layer == 0 || !withNormal.contains($0.pid) }
    let parked = normal.filter { !$0.onScreen && ($0.bounds.map(fullscreenSized) ?? false) }
    // `visible`: i pid con almeno una finestra normale a schermo — la pillola ridotta senza AeroSpace (Model.swift).
    return (Set(normal.map(\.id)), Set(normal.filter { !$0.onScreen }.map(\.id)), Set(parked.map(\.pid)),
            Set(normal.filter { $0.onScreen && $0.layer == 0 }.map(\.pid)))
}
