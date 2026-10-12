import AppKit
import SwiftUI
import IOKit.ps
import CoreAudio
import SystemConfiguration

// Rimanda `f` di `delay` secondi sul main, annullando il giro precedente: segnali ravvicinati riprogrammano
// l'esecuzione (il rilascio del mouse, i segnali da fuori, il cambio degli schermi in main.swift).
func debounce(_ work: inout DispatchWorkItem?, after delay: TimeInterval, _ f: @escaping () -> Void) {
    work?.cancel()
    let w = DispatchWorkItem(block: f)
    work = w
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: w)
}

final class Poller {
    let state: BarState
    private var audioDevice = AudioDeviceID(0)
    // Le chiamate ad AeroSpace (socket o CLI) girano qui; lo stato si scrive sul main.
    private let queue = DispatchQueue(label: "siigil.poll")
    private var inFlight = false
    private var pending = false
    private var wifiEvents: WiFiEvents?
    // La pillola Bluetooth accesa (all'avvio o dalle Impostazioni) lo fa partire: la prima volta chiede il permesso.
    lazy var bluetoothWatcher = BluetoothWatcher { [weak self] on in
        withAnimation(.smooth(duration: 0.3)) { self?.state.bluetooth = on }
    }
    private var networkStore: SCDynamicStore?
    private lazy var focusWatcher = FocusWatcher { [weak self] in self?.refreshFocus() }
    // Eventi di AeroSpace (Aerospace.swift): con la connessione aperta la barra si aggiorna a ogni evento e il timer fa
    // solo da rete di sicurezza; senza, il timer aggiorna ogni 5 s e riprova a iscriversi.
    private var eventsConnected = false
    private var connecting = false
    private var focusedWindowID: Int?     // dall'ultimo focus-changed; nil = nessuna finestra a fuoco
    private var lastTick = Date.distantPast
    private var mouseUpTick: DispatchWorkItem?
    // Gli ultimi avvisi di SkyLight (WindowEvents.swift): finestra a schermo o no, e quando. Valgono per `settle`.
    private var recent = [Int: (onScreen: Bool, at: Date)]()
    // L'ultima riga di AeroSpace di ogni finestra: serve per quelle che AeroSpace toglie dalla lista (minimizzate).
    private var lastKnown = [Int: Window]()
    private var settleTick: DispatchWorkItem?
    // Il tempo che AeroSpace e l'elenco di macOS impiegano a raggiungere un avviso di macOS: AeroSpace rimette in lista
    // una finestra riaperta 0,9 s dopo, l'elenco di macOS è indietro fino a 0,1 s (misurato il 2026-09-26).
    private let settle: TimeInterval = 1.5
    // Watchdog (spec 2026-09-27-siigil-watchdog-design §1): l'automa, la storia delle letture di ps, l'ultimo carico
    // totale del kernel, l'ultima lettura di ps, e una lettura in corso (fuori dal main).
    private var watchdog = Watchdog()
    private var procHistory = CPUHistory()
    private var hostTicks: HostTicks?
    private var lastProcRead = Date.distantPast
    private var watchdogReading = false
    private var beat = 0   // il timer da 5 s, una volta su due

    init(state: BarState) { self.state = state }

    func start() {
        tick()
        refreshBattery()
        startVolumeListener()
        refreshWiFi()
        wifiEvents = WiFiEvents { [weak self] in self?.refreshWiFi() }
        // VPN collegata o scollegata: cambia l'IPv4 di un'interfaccia (State:/Network/Interface/utun9/IPv4). SCDynamicStore,
        // nessun permesso; callback C senza contesto come quella della batteria, passa dal globale `poller`.
        networkStore = SCDynamicStoreCreate(nil, "Siigil" as CFString, { _, _, _ in poller.refreshWiFi() }, nil)
        if let store = networkStore {
            SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Interface/.*/IPv4"] as CFArray)
            CFRunLoopAddSource(CFRunLoopGetMain(), SCDynamicStoreCreateRunLoopSource(nil, store, 0), .commonModes)
        }
        refreshFocus()
        focusWatcher.attach()
        if Settings.shared.isOn(.bluetooth) { bluetoothWatcher.start() }   // a pillola spenta niente CoreBluetooth: niente richiesta di permesso
        connectEvents()
        // I Timer e la source IOPS li trattiene il run loop; nessuno li invalida mai. Modo .common:
        // continuano anche con un menu aperto. La batteria si rilegge al minuto (la percentuale scende senza notifica IOPS).
        // Rete di sicurezza per AeroSpace: con gli eventi un aggiornamento ogni 60 s, senza ogni 5 s più un nuovo
        // tentativo di iscriversi (così dopo un riavvio di AeroSpace gli eventi ripartono da soli).
        RunLoop.main.add(Timer(timeInterval: 5, repeats: true) { [self] _ in
            if !eventsConnected { connectEvents(); tick() } else if Date().timeIntervalSince(lastTick) >= 60 { tick() }
            beat += 1
            if beat % 2 == 0 { watchdogTick() }   // Watchdog ogni 10 s
        }, forMode: .common)
        // Il Mac che si scalda sveglia i Monitor di sistema subito, senza aspettare la lettura dei 10 s.
        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [self] _ in
            watchdogTick()
        }
        // Al minuto anche Full immersione (riaggancia l'osservatore dopo che l'utente ha dato il permesso, e rilegge)
        // e il Wi-Fi come rete di sicurezza se gli eventi CoreWLAN si fermano (wifid riavviato, sleep/wake).
        // Allo stesso ritmo, all'avvio e poi al minuto: le quote Claude e ChatGPT (la rete solo per gli account che una
        // mascotte accesa usa o con la pagina Account AI aperta, e solo quando è passato l'intervallo delle impostazioni,
        // default 5 min) e l'aggiornamento (Updater.swift; la rete solo quando è dovuto: 24 h dopo un controllo riuscito,
        // 1 h dopo uno fallito).
        func checks() {
            let s = Settings.shared, shown = SettingsShown.shared
            let accounts = quotaAccounts(s.mascots, isOn: { s.isOn(.mascot($0.id)) }, accountsPage: shown.accountsVisible)
            Task { await QuotaCache.shared.refreshIfDue(accounts: accounts) }
            Task { await Updater.shared.checkIfDue() }
        }
        checks()
        RunLoop.main.add(Timer(timeInterval: 60, repeats: true) { [self] _ in
            refreshBattery(); refreshWiFi(); focusWatcher.attach(); refreshFocus(); checks()
        }, forMode: .common)
        // Callback C senza contesto: raggiunge il Poller tramite il globale `poller` di main.swift.
        if let s = IOPSNotificationCreateRunLoopSource({ _ in poller.refreshBattery() }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), s, .defaultMode)
        }
        // App lanciate: un aggiornamento subito, la finestra nuova arriva poi con window-detected.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [self] _ in tick() }
        // Risparmio energetico acceso/spento: la pillola della batteria si tinge subito (l'avviso arriva fuori dal main).
        NotificationCenter.default.addObserver(forName: Notification.Name.NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [self] _ in refreshBattery() }
        // Cambio di app in primo piano, solo in ridotto: con AeroSpace il focus arriva dai suoi eventi, e questo avviso
        // faceva sfarfallare (spec M2 §1); senza, il nome e l'app a fuoco aspetterebbero il timer.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [self] _ in
            if state.reports.first?.workspace.name.isEmpty == true { tick() }
        }
        // App chiuse: AeroSpace se ne accorge dopo il sistema (lo elabora in modo asincrono) e per le finestre chiuse non
        // manda eventi, quindi anche un aggiornamento a cose assestate (refresh).
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [self] _ in
            refresh()
        }
        // Pulsante rosso di una finestra non a fuoco: AeroSpace lo scopre al rilascio del mouse e non manda eventi.
        // Rilasci ravvicinati riprogrammano l'aggiornamento. Monitor globale del mouse: nessun permesso.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [self] _ in
            debounce(&mouseUpTick, after: 0.3) { [weak self] in self?.tick() }
        }
        // Click sul Dock sull'app già in primo piano mentre il workspace a fuoco è vuoto (tipico dopo un cambio di space):
        // macOS manda solo un "reopen", nessuna attivazione, e AeroSpace non ha un focus da seguire (riprodotto il
        // 2026-09-20; attivando un'app diversa AeroSpace segue da solo). Monitor globale del mouse: non serve Accessibilità.
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [self] e in
            guard let screen = NSScreen.main, e.locationInWindow.y - screen.frame.minY < 120 else { return }   // fascia del Dock (in basso)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier, bundle != Bundle.main.bundleIdentifier { followActivated(bundle: bundle) }
            }
        }
    }

    // Il workspace a fuoco è vuoto e `bundle` è in primo piano: alla sua prima finestra visibile, ovunque sia.
    private func followActivated(bundle: String) {
        queue.async {
            guard focusedWindow() == nil else { return }   // c'è già una finestra a fuoco qui: ci pensa AeroSpace
            guard let id = firstShowableWindow(bundle: bundle) else { return }
            focusWindow(id: id)
        }
    }

    // Iscrizione agli eventi di AeroSpace, fuori dal main (la connessione è bloccante). `connecting` evita due
    // iscrizioni in parallelo se il timer riprova mentre la prima è ancora in corso.
    private func connectEvents() {
        guard !eventsConnected, !connecting else { return }
        connecting = true
        DispatchQueue.global().async { [weak self] in
            subscribeAerospace(
                onStart: { self?.connecting = false; self?.eventsConnected = true },
                onEvent: { self?.handle($0) },
                onEnd: { self?.connecting = false; self?.eventsConnected = false })
        }
    }

    private func handle(_ event: AerospaceEvent) {
        if event.type == "focus-changed" { focusedWindowID = event.windowId }
        tick()
    }

    // Un tick in corso assorbe le richieste arrivate nel frattempo in un solo tick successivo.
    func tick() {
        guard demo == nil else { return }   // in demo la barra ha i suoi dati (Demo.swift)
        if inFlight { pending = true; return }
        inFlight = true
        let now = Date(), apps = runningApps(), frontmost = NSWorkspace.shared.frontmostApplication
        lastTick = now
        let bundles = Set(apps.compactMap(\.bundleIdentifier))
        state.sessions = state.sessions.filter { !expired($0.value, now: now, front: frontmost?.bundleIdentifier, running: bundles) }
        let sessions = Array(state.sessions.values)   // letto sul main, prima di lasciare il thread
        // Le app del Dock (policy .regular): AppKit, sul main. Servono alle nascoste e, senza AeroSpace, alla pillola ridotta.
        let running = apps
            .filter { $0.activationPolicy == .regular }
            .compactMap { a in a.localizedName.map { AppEntry(name: $0, pid: a.processIdentifier, windowID: 0, bundle: a.bundleIdentifier ?? "") } }
        let frontApp = frontmost?.processIdentifier
        // AeroSpace spento: non lo si interroga proprio — niente socket né CLI che falliscono a ogni giro, costavano 1,6% misurato il 3/10.
        let aerospaceAlive = aerospaceRunning()
        // Con gli eventi la finestra a fuoco è già nota (.some(nil) = nessuna); senza, la si chiede ad AeroSpace.
        let focus: Int?? = eventsConnected ? .some(focusedWindowID) : nil
        let settle = settle
        let recent = self.recent.filter { now.timeIntervalSince($0.value.at) < settle }.mapValues(\.onScreen), lastKnown = self.lastKnown
        queue.async { [self] in
            let screen = screenWindows()
            let windows = aerospaceAlive ? readWindows() : []
            let workspaces = aerospaceAlive ? readWorkspaces() : []
            let visible = visibleWindows(windows.filter { screen.normal.contains($0.id) }, offscreen: screen.offscreen, recent: recent,
                                         lastKnown: lastKnown, focusedWorkspace: workspaces.first(where: \.isFocused)?.name)
            // Senza AeroSpace (spazi vuoti: da vivo ne ha sempre almeno uno a fuoco) la barra passa al rapporto
            // ridotto, con quello che macOS ha già dato in questo stesso giro; al primo giro buono torna alle
            // pillole vere (spec senza-aerospace §1).
            let reduced = workspaces.isEmpty
            let reports = reduced ? [reducedReport(running: running, visible: screen.visible, sessions: sessions)]
                                  : report(workspaces: workspaces, windows: visible, sessions: sessions)
            let front = reduced ? frontApp.map { -Int($0) } : (focus ?? focusedWindow())
            DispatchQueue.main.async { [self] in
                remember(windows, offscreen: screen.offscreen)
                let hidden = hiddenApps(running: running, reports: reports, sessions: sessions, fullscreen: screen.fullscreen)
                // Un valore uguale a quello di prima non ridisegna niente: @Observable non avvisa (verificato il 27/9).
                withAnimation(.smooth(duration: 0.3)) {
                    state.reports = reports
                    state.hidden = hidden
                    state.frontWindow = front
                }
                inFlight = false
                if pending { pending = false; tick() }
            }
        }
    }

    // Un segnale da fuori (app chiusa, avviso di SkyLight): un aggiornamento subito e uno a cose assestate, quando anche
    // AeroSpace e l'elenco di macOS lo hanno raggiunto. Segnali ravvicinati riprogrammano il secondo.
    func refresh() {
        tick()
        debounce(&settleTick, after: settle) { [weak self] in self?.tick() }
    }

    // Watchdog: ogni 10 s il carico totale del Mac dal kernel (gratis). ps (17 ms) solo se in quei 10 s il Mac ha usato
    // almeno un core, se c'è un colpevole da seguire, o se l'ultima lettura ha un minuto: così la media ha sempre la sua
    // base di un minuto prima e il menu i dati dell'ultimo minuto. A riposo, cioè quasi sempre, ps una volta al minuto.
    func watchdogTick() {
        guard Settings.shared.systemMonitorOn, !watchdogReading else { return }
        let now = Date()
        let ticks = readHostTicks()
        var busy = 0.0
        if let a = hostTicks, let b = ticks { busy = busyCores(from: a, to: b) }
        hostTicks = ticks
        let thermal = ProcessInfo.processInfo.thermalState, memory = readMemoryPressure()
        guard busy >= 1 || watchdog.hasCulprit || now.timeIntervalSince(lastProcRead) >= 60 else {
            return applyWatchdog(loads: nil, thermal: thermal, memory: memory, now: now)
        }
        watchdogReading = true
        lastProcRead = now
        // Le app del Dock sul main (AppKit), prima di lasciare il thread; la storia come valore.
        let apps = Dictionary(runningApps().filter { $0.activationPolicy == .regular }.map {
            ($0.processIdentifier, AppInfo(name: $0.localizedName ?? "?", bundle: $0.bundleIdentifier ?? ""))
        }, uniquingKeysWith: { a, _ in a })
        let history = procHistory
        DispatchQueue.global(qos: .utility).async { [self] in   // non sulla coda di AeroSpace: una CLI lenta non ritarda ps
            let samples = readProcesses()
            let at = Date()   // l'istante della lettura, non della richiesta: la media è sul tempo vero
            let owners = Dictionary(samples.map { ($0.pid, owner(of: $0, responsible: responsiblePid($0.pid), apps: apps)) },
                                    uniquingKeysWith: { a, _ in a })
            let loads = samples.isEmpty ? nil : history.loads(samples, at: at) { owners[$0.pid] ?? Owner(key: "pid:\($0.pid)", name: $0.name, bundle: nil) }
            DispatchQueue.main.async { [self] in
                procHistory.add(samples, at: at)
                watchdogReading = false
                applyWatchdog(loads: loads, thermal: thermal, memory: memory, now: at)
            }
        }
    }

    // Con i carichi per app di ps (media dell'ultimo minuto) cambia anche la CPU; senza (niente ps in questo giro, ps
    // senza una base di un minuto o fallito) solo calore e memoria. Un fatto, un suono (spec sezione Mascotte §5): suona
    // la mascotte accesa, con gli effetti sonori, per cui l'allarme che vede è nuovo (Watchdog.barks, whoSounds); al più
    // uno al minuto (alarmSound).
    private func applyWatchdog(loads: [Load]?, thermal: ProcessInfo.ThermalState, memory: Int32, now: Date) {
        guard Settings.shared.systemMonitorOn else { return }   // spento mentre ps girava
        watchdog.update(loads: loads, thermal: thermal, memory: memory, now: now)
        state.watchdog = watchdog.report
        if let who = Settings.shared.whoSounds({ watchdog.barks($0.function.kinds) }) { alarmSound(by: who) }
    }

    // "Ignora finché non smette" dal menu di un Monitor di sistema, per l'app che il menu mostrava (vale per tutte).
    func ignoreWatchdog(_ key: String) { watchdog.ignore(key); state.watchdog = watchdog.report }

    // Un avviso di SkyLight: 816 la finestra esce dallo schermo (⌘M, ⌘H), 815 ci rientra. Solo per le finestre che
    // AeroSpace conosce o conosceva (non menu e popup); vale per `settle` (visibleWindows).
    func windowEvent(id: Int, onScreen: Bool) {
        guard lastKnown[id] != nil else { return }
        recent[id] = (onScreen, Date())
        refresh()
    }

    // Dopo ogni lettura: l'ultima riga di ogni finestra in lista, più quelle fuori lista ma ancora vive (minimizzate:
    // macOS le ha fuori schermo) o appena segnalate. Una finestra chiusa sparisce da macOS e da qui. Poi gli avvisi
    // di SkyLight per tutte.
    private func remember(_ windows: [Window], offscreen: Set<Int>) {
        recent = recent.filter { Date().timeIntervalSince($0.value.at) < settle }
        lastKnown = lastKnown.filter { id, _ in offscreen.contains(id) || recent[id] != nil }
            .merging(windows.map { ($0.id, $0) }) { _, new in new }
        windowEvents.watch(Set(lastKnown.keys))
    }

    func refreshBattery() {
        state.battery = readBattery()
    }

    // Volume e muto arrivano da CoreAudio quando cambiano; si riaggancia il device di uscita se cambia.
    func startVolumeListener() {
        var addr = deviceAddress(input: false)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [self] _, _ in listenToDefaultDevice() }
        listenToDefaultDevice()
    }

    // ponytail: i listener del device precedente non vengono rimossi; sono innocui
    private func listenToDefaultDevice() {
        guard let device = defaultOutputDevice(), device != audioDevice else { refreshVolume(); return }
        audioDevice = device
        for selector in [volumeSelector, kAudioDevicePropertyMute] {
            var addr = outputAddress(selector)
            AudioObjectAddPropertyListenerBlock(device, &addr, .main) { [self] _, _ in refreshVolume() }
        }
        refreshVolume()
    }

    func refreshVolume() {
        let device = defaultOutputDevice()
        state.volume = device.flatMap(readVolume)
        state.muted = device.map(isMuted) ?? false
    }

    // La qualità del segnale arriva spesso (ogni pochi secondi): la barra si ridisegna solo se le tacche cambiano.
    func refreshWiFi() {
        state.wifi = readWiFi()
    }

    func refreshFocus() {
        state.focus = readFocus()
    }
}
