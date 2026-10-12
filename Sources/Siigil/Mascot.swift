import Foundation

// Le mascotte (spec 2026-10-11-siigil-sezione-mascotte-design): quante se ne vuole, ognuna con un aspetto (forma, colori,
// voce) e una funzione (Monitor AI o Monitor di sistema, col suo filtro), ma ogni cosa guardata ha al massimo una mascotte
// (taken, free). Le opzioni che la funzione non usa restano salvate ma non si vedono.

// Gli agenti che un Monitor AI può guardare, e quello di ogni sessione (AgentServer); il valore è il loro nome.
enum Agent: String, Codable, CaseIterable { case claude = "Claude", codex = "Codex" }

// I tipi di allarme che un Monitor di sistema può guardare (Watchdog.swift).
enum AlarmKind: String, Codable, CaseIterable { case cpu, heat, memory }

// La voce dei suoni (Sounds.swift): bollicina, quella di Mostro, e bottiglia, quella di Mirtillo.
enum MascotVoice: String, Codable, CaseIterable { case bubble, bottle }

// La funzione col suo filtro: almeno un agente o un tipo (le Impostazioni non lasciano togliere l'ultimo).
enum MascotFunction: Codable, Equatable {
    case ai(agents: Set<Agent>)
    case system(kinds: Set<AlarmKind>)

    var isAI: Bool { if case .ai = self { true } else { false } }
    var agents: Set<Agent> { if case .ai(let a) = self { a } else { [] } }
    var kinds: Set<AlarmKind> { if case .system(let k) = self { k } else { [] } }
}

// Una cosa guardata, una mascotte (autore, 11/10: «Se ho già una mascotte claude non posso metterne un'altra», e lo stesso
// per il sistema): ogni agente e ogni tipo d'allarme ha al massimo una mascotte, contando anche le nascoste. Così ogni fatto
// ha la sua mascotte e chi suona non va scelto. La seguono il + e la pagina della mascotte (MascotsPage).
// ponytail: al caricamento niente correzioni: dalla 0.31 nascono un Monitor AI con tutti gli agenti e un Monitor di sistema
// con tutto, senza doppioni; un doppione (build di prova) resta finché non lo si toglie dalla pagina, e intanto suona la
// mascotte più vecchia (Settings.whoSounds, in ordine di aggiunta).
extension Array where Element == Mascot {
    // Le cose che guardano le altre mascotte (tutte tranne `id`), nascoste comprese.
    func taken(except id: UUID? = nil) -> (agents: Set<Agent>, kinds: Set<AlarmKind>) {
        filter { $0.id != id }.reduce(into: (agents: Set<Agent>(), kinds: Set<AlarmKind>())) {
            $0.agents.formUnion($1.function.agents); $0.kinds.formUnion($1.function.kinds)
        }
    }

    // La funzione con tutte le cose ancora libere, per una mascotte nuova (id nil: il +) o che cambia funzione; nil se non
    // ne resta nessuna.
    func free(ai: Bool, for id: UUID? = nil) -> MascotFunction? {
        let t = taken(except: id)
        if ai {
            let agents = Set(Agent.allCases).subtracting(t.agents)
            return agents.isEmpty ? nil : .ai(agents: agents)
        }
        let kinds = Set(AlarmKind.allCases).subtracting(t.kinds)
        return kinds.isEmpty ? nil : .system(kinds: kinds)
    }
}

// Una mascotte, salvata in `siigil.mascots` (JSON, in ordine di aggiunta: è l'ordine dell'elenco). La forma è salvata col
// suo nome (MascotKind è un enum di String): le forme nuove si aggiungono come casi, e quello che è già salvato si legge.
// ponytail: decodifica sintetizzata, un campo che manca (o una forma, una voce o una funzione che questa versione non
// conosce) rende illeggibile tutto l'elenco; un campo aggiunto in futuro va letto con decodeIfPresent, altrimenti quello
// che salva questa versione non si legge più. Un elenco illeggibile non si sovrascrive all'avvio (Settings).
struct Mascot: Codable, Identifiable, Equatable {
    var id = UUID()
    var shape: MascotKind
    var body: Int      // 0xRRGGBB
    var eyes: Int
    var voice: MascotVoice
    var function: MascotFunction
    var sounds = true
    var volume = 35    // 0…100
    var captions = true
    var renewedBadge = true
    var quotaInMenu = true
    var background = true
    var besideNotch = false   // nello spazio vuoto: attaccata al notch o ai widget (Rearrange.swift)
    // Gli occhi rispetto a quelli della forma (spec sezione Mascotte §10): grandezza e distanza come fattori, altezza in
    // unità della tela (100 = l'altezza della mascotte), in su se positiva. Gli intervalli li decide la forma (EyeRanges).
    var eyeSize = 1.0
    var eyeLift = 0.0
    var eyeSpread = 1.0
    var size = 1.0   // la mascotte nella barra, rispetto a oggi (§10: dal 70 % al massimo che entra)
}

// Un elemento della barra: un widget o una mascotte. Salvato come "clock" o "mascot:<uuid>".
enum BarItem: Hashable {
    case widget(WidgetID), mascot(UUID)

    init?(_ token: String) {
        if token.hasPrefix("mascot:") {
            guard let id = UUID(uuidString: String(token.dropFirst(7))) else { return nil }
            self = .mascot(id)
        } else {
            guard let w = WidgetID(rawValue: token) else { return nil }
            self = .widget(w)
        }
    }

    var token: String {
        switch self {
        case .widget(let w): w.rawValue
        case .mascot(let id): "mascot:\(id.uuidString)"
        }
    }

    var isMascot: Bool { if case .mascot = self { true } else { false } }
}

// I colori di una mascotte di prima: ogni colore salvato vale per sé; quello che manca si ricava dalla versione del 7/10
// (2 bianca, 3 nera), e con la 1 (sfumata) o nessuna dai predefiniti.
func legacyColors(_ d: UserDefaults, _ who: String, version: String, body fallback: Int) -> (body: Int, eyes: Int) {
    let v = d.integer(forKey: "siigil.\(version)")
    let (b, e) = v == 2 ? (0xF5F7FC, 0x14141A) : v == 3 ? (0x14141A, 0xF5F7FC) : (fallback, 0x14141A)
    return ((d.object(forKey: "siigil.\(who)BodyColor") as? Int ?? b) & 0xFFFFFF,
            (d.object(forKey: "siigil.\(who)EyeColor") as? Int ?? e) & 0xFFFFFF)
}

// Chi aggiorna (spec sezione Mascotte §6): le due mascotte di prima dalle chiavi di prima, filtri su "tutto", e le liste
// della barra con loro al posto di cat e dog (una spenta nasce spenta; un widget sconosciuto si scarta). Solo letture: le
// chiavi di prima restano com'erano, così la 0.31 riaperta le ritrova.
func legacyMascots(_ d: UserDefaults) -> (mascots: [Mascot], left: [BarItem], right: [BarItem]) {
    func bool(_ key: String, _ fallback: Bool) -> Bool { d.object(forKey: "siigil.\(key)") as? Bool ?? fallback }
    func int(_ key: String, _ fallback: Int) -> Int { d.object(forKey: "siigil.\(key)") as? Int ?? fallback }
    let cat = legacyColors(d, "cat", version: "catMascot", body: 0xF5F7FC)
    let dog = legacyColors(d, "dog", version: "dogMascot", body: 0x739EFA)
    // Come la 0.31: senza chiave la quota ChatGPT era accesa solo se c'è la cartella di Codex (accountAvailable).
    let quota = bool("quotaEnabled", true) || bool("codexQuotaEnabled", accountAvailable(.codex))
    // Con le due quote spente la 0.31 non scaricava niente e "Sessione rinnovata!" era grigio: acceso qui, scaricherebbe
    // di nuovo la quota (quotaAccounts) a chi l'aveva spenta.
    let ai = Mascot(shape: .mostro, body: cat.body, eyes: cat.eyes, voice: .bubble, function: .ai(agents: Set(Agent.allCases)),
                    sounds: bool("meow", true), volume: int("meowVolume", 35), captions: bool("captions", true),
                    renewedBadge: bool("renewedBadge", true) && quota, quotaInMenu: quota,
                    background: bool("catBackground", true), besideNotch: bool("catBesideNotch", true))
    let system = Mascot(shape: .mirtillo, body: dog.body, eyes: dog.eyes, voice: .bottle, function: .system(kinds: Set(AlarmKind.allCases)),
                        sounds: bool("bark", true), volume: int("barkVolume", 35), captions: bool("dogCaptions", true),
                        background: bool("dogBackground", true), besideNotch: bool("dogBesideNotch", false))
    func items(_ key: String, _ fallback: [String]) -> [BarItem] {
        (d.stringArray(forKey: "siigil.\(key)") ?? fallback).compactMap {
            $0 == "cat" ? .mascot(ai.id) : $0 == "dog" ? .mascot(system.id) : BarItem($0)
        }
    }
    return ([ai, system], items("left", ["workspaces", "hidden"]),
            items("right", ["cat", "dog", "focus", "wifi", "volume", "battery", "clock"]))
}
