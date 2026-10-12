import AppKit
import Observation

struct Battery: Equatable {
    let percent: Int
    let charging: Bool
    var lowPower = false   // Risparmio energetico: la pillola si tinge di giallo, come su iOS (autore, 4/10)
}

// Wi-Fi: acceso/spento, tacche 0...3 (0 = acceso ma non collegato) e VPN attiva (lucchetto sull'icona).
struct WiFi: Equatable {
    let on: Bool
    let bars: Int
    let vpn: Bool
}

// Full immersione attiva: identificativo di sistema della modalità (es. com.apple.donotdisturb.mode.default) e il suo
// simbolo SF.
struct Focus: Equatable {
    let mode: String
    let symbol: String
}

// Come l'orologio di sistema con giorno e data ("Sat 19 Sep 16:05"), nella prima lingua di sistema;
// giorno e mese con l'iniziale maiuscola in ogni lingua (l'italiano li ha minuscoli). `format` è un pattern
// Unicode (impostazioni: Orologio); vuoto = default.
func clockString(_ date: Date, format: String = clockDefaultFormat,
                 locale: Locale = Locale(identifier: Locale.preferredLanguages.first ?? "en"),
                 timeZone: TimeZone = .current) -> String {
    let f = DateFormatter()
    f.locale = locale
    f.timeZone = timeZone
    // Gli spazi all'inizio e alla fine non contano: nel blocco unito si vedevano come un vuoto accanto all'orologio (11/10).
    let format = format.trimmingCharacters(in: .whitespaces)
    f.dateFormat = format.isEmpty ? clockDefaultFormat : format
    // Maiuscola all'inizio di ogni parola ("sab 19 set" → "Sab 19 Set"), il resto com'è: capitalized abbassava anche il
    // resto, e "PM" diventava "Pm" (27/9).
    var out = "", start = true
    for c in f.string(from: date) {
        out += start ? String(c).uppercased() : String(c)
        start = c.isWhitespace
    }
    return out
}

// Onde accese dell'altoparlante: livelli con lo stesso numero di onde si vedono uguali.
func waves(_ level: Int) -> Int { level <= 0 ? 0 : level < 34 ? 1 : level < 67 ? 2 : 3 }

@Observable
final class BarState {
    var reports: [SpaceReport] = []
    var hidden: [AppEntry] = []      // app senza finestre visibili
    var frontWindow: Int?    // id AeroSpace della finestra a fuoco: il nome dell'app compare accanto alla sua icona
    var battery: Battery?
    var volume: Int?      // 0...100, 0 anche quando è muto
    var muted = false
    var wifi: WiFi?       // nil = nessuna interfaccia Wi-Fi: il widget sparisce
    var bluetooth: Bool?  // acceso/spento (Bluetooth.swift); nil = pillola mai accesa, senza permesso o senza Bluetooth
    var focus: Focus?     // nil = nessuna modalità attiva, o file illeggibile (il perché lo dice Impostazioni › Barra)
    var track: Track?        // "In riproduzione" (NowPlaying.swift); nil = niente o widget spento
    var artwork: NSImage?    // la copertina della traccia, quando arriva
    var sessions: [String: AgentSession] = [:]   // sessioni di agenti AI per session_id (AgentServer)
    var watchdog = WatchdogReport()   // Watchdog: allarme, app più pesanti, app ignorata (Poller.watchdogTick)
    var clockOverride: Date?   // la modalità demo: l'ora da mostrare al posto di quella vera (Demo.swift)
}
