import AppKit
import SwiftUI

// La sezione Mascotte delle Impostazioni (spec 2026-10-11-siigil-sezione-mascotte-design §1): nomi, regole e il disegno
// fermo dell'elenco.

extension MascotFunction {
    // Una funzione con tutte le sue cose: da qui il nome della funzione (il + e il selettore della pagina).
    static func all(ai: Bool) -> MascotFunction { ai ? .ai(agents: Set(Agent.allCases)) : .system(kinds: Set(AlarmKind.allCases)) }

    var name: String { isAI ? String(localized: "AI monitor") : String(localized: "System monitor") }

    // Il filtro scritto: "Tutti", "Claude", "Codex"; "Tutto", "CPU", "Calore", "Memoria", "CPU e memoria"…: le caselle
    // spuntate in quest'ordine, unite da "e" (tutte e tre: "Tutto"). La CPU è sempre la prima: la seconda va minuscola.
    var filterName: String {
        switch self {
        case .ai(let agents):
            // ponytail: il nome di un agente è il suo rawValue (Claude, Codex: nomi propri, uguali in ogni lingua); con un
            // agente da tradurre serve un `name` come quello di AlarmKind
            return agents.count == Agent.allCases.count ? String(localized: "All") : agents.first?.rawValue ?? ""
        case .system(let kinds):
            let names = AlarmKind.allCases.filter(kinds.contains).map(\.name)
            // ponytail: tre tipi; con un quarto, tre caselle su quattro direbbero solo la prima: allora scriverle tutte
            switch names.count {
            case AlarmKind.allCases.count: return String(localized: "Everything")
            case 2: return String(localized: "\(names[0]) and \(names[1].lowercased())")
            default: return names.first ?? ""
            }
        }
    }

    // Una casella del filtro: spunta o toglie; l'ultima spuntata non si toglie (almeno una). Una cosa che ha già un'altra
    // mascotte (`taken`) non si spunta; se fosse già spuntata (un doppione) si può togliere, ma non rimettere.
    func toggling(_ a: Agent, taken: Set<Agent> = []) -> MascotFunction {
        guard case .ai(var agents) = self else { return self }
        if !agents.contains(a) { if !taken.contains(a) { agents.insert(a) } } else if agents.count > 1 { agents.remove(a) }
        return .ai(agents: agents)
    }
    func toggling(_ k: AlarmKind, taken: Set<AlarmKind> = []) -> MascotFunction {
        guard case .system(var kinds) = self else { return self }
        if !kinds.contains(k) { if !taken.contains(k) { kinds.insert(k) } } else if kinds.count > 1 { kinds.remove(k) }
        return .system(kinds: kinds)
    }
}

extension AlarmKind {
    var name: String {
        switch self {
        case .cpu: "CPU"
        case .heat: String(localized: "Heat")
        case .memory: String(localized: "Memory")
        }
    }
}

extension MascotVoice {
    // ponytail: due voci, un ternario; con la terza uno switch
    var name: String { self == .bubble ? String(localized: "Bubble") : String(localized: "Bottle") }
}

// I nomi delle forme, solo per VoiceOver (spec §10: le forme si scelgono da figure senza scritte); Mostro e Mirtillo sono
// nomi propri e restano quelli.
extension MascotKind {
    var name: String {
        switch self {
        case .mostro: "Mostro"
        case .mirtillo: "Mirtillo"
        case .ball: String(localized: "Ball")
        case .pebble: String(localized: "Pebble")
        case .squircle: String(localized: "Squircle")
        case .capsule: String(localized: "Capsule")
        case .hexagon: String(localized: "Hexagon")
        case .cloud: String(localized: "Cloud")
        case .drop: String(localized: "Drop")
        }
    }
}

extension Mascot {
    // La riga dell'elenco e il titolo della sua pagina: "Monitor AI · Claude".
    var title: String { "\(function.name) · \(function.filterName)" }

    // Un'altra forma (la pagina della mascotte): gli occhi scelti restano, riportati dentro gli intervalli della forma nuova
    // (EyeSettings), e si salvano così.
    mutating func reshape(_ kind: MascotKind) {
        shape = kind
        let e = EyeSettings(self)
        (eyeSize, eyeLift, eyeSpread) = (e.size, e.lift, e.spread)
    }
}

// Il disegno fermo di una mascotte con la sua forma e i suoi occhi (spec §9, punto 3: niente displayLink per riga): sveglia,
// occhi aperti, sguardo dritto, senza pallino. Si disegna quando serve, a qualunque risoluzione. Con `geometry` i suoi
// colori su un'altra sagoma (le forme fra cui scegliere).
func mascotThumbnail(_ m: Mascot, height: CGFloat, geometry: MascotGeometry? = nil) -> NSImage {
    let size = CGSize(width: height * mascotBarSize.width / mascotBarSize.height, height: height)
    return NSImage(size: size, flipped: true) { _ in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        var look = MascotLook()
        look.left = .open; look.right = .open
        drawMascot(geometry ?? .of(m), look, MascotColors(body: cgColor(hex: m.body), eyes: cgColor(hex: m.eyes), dot: nil), in: ctx, size: size, mirrored: false)
        return true
    }
}

// La cronologia delle Impostazioni senza i passi verso mascotte eliminate (indietro non deve riportare a una pagina che
// non c'è più); due passi uguali di fila diventano uno, e in cima non resta il posto di adesso: sarebbe un indietro (o un
// avanti) che non va da nessuna parte.
func pruned(_ places: [SettingsPlace], alive: Set<UUID>, here: SettingsPlace) -> [SettingsPlace] {
    var out = places.filter { $0.mascot.map(alive.contains) ?? true }.reduce(into: [SettingsPlace]()) { if $0.last != $1 { $0.append($1) } }
    while out.last == here { out.removeLast() }
    return out
}

// Mascotte (spec §1): una riga per mascotte, sempre in ordine di aggiunta (autore, 11/10), col disegno fermo,
// "Funzione · filtro" e l'interruttore per la barra; un clic apre la sua pagina. Il + chiede la funzione, crea la mascotte
// con l'aspetto a caso, la accende e apre la sua pagina. Oltre 6 accese, quanto costano.
struct MascotsPage: View {
    let open: (UUID) -> Void
    @Bindable var settings = Settings.shared

    var body: some View {
        Section {
            if settings.mascots.isEmpty { Text("No mascots. Add one with + below.").foregroundStyle(.secondary) }
            ForEach(settings.mascots) { m in
                HStack(spacing: 12) {
                    Button { open(m.id) } label: {
                        HStack(spacing: 12) {
                            Image(nsImage: mascotThumbnail(m, height: 28))
                            Text(m.title)
                            Spacer()
                        }
                        .contentShape(Rectangle())   // il click vale su disegno e nome fino all'interruttore; la freccetta pure
                    }
                    .buttonStyle(.plain)
                    Toggle("In the bar", isOn: Binding(get: { settings.isOn(.mascot(m.id)) }, set: { settings.setMascot(m.id, on: $0) }))
                        .labelsHidden()
                        .accessibilityLabel(Text("\(m.title), in the bar"))   // per VoiceOver di quale mascotte, come in Pillole
                    Button { open(m.id) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(.tertiary)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHidden(true)   // per VoiceOver la riga apre già la pagina
                }
            }
            HStack {
                Spacer()
                Menu {
                    // con le cose ancora libere al momento del clic (una cosa guardata, una mascotte);
                    // grigia se non ne resta nessuna
                    ForEach([true, false], id: \.self) { ai in
                        Button(MascotFunction.all(ai: ai).name) { if let free = settings.mascots.free(ai: ai) { open(settings.addMascot(free)) } }
                            .disabled(settings.mascots.free(ai: ai) == nil)
                    }
                } label: { Image(systemName: "plus") }
                .menuIndicator(.hidden)
                .fixedSize()
                .help(String(localized: "Add a mascot"))
                .accessibilityLabel(String(localized: "Add a mascot"))
            }
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if settings.mascots.filter({ settings.isOn(.mascot($0.id)) }).count > 6 {   // spec §9, punto 6 (misure del 10/10)
                    Text("Each mascot in the bar uses a little CPU, about half a point per screen.")
                }
                Text("⌘-drag a mascot in the bar to move it.")
            }
        }
    }
}

// Una casella del filtro: l'ultima spuntata non si toglie; una cosa che guarda già un'altra mascotte è grigia, con accanto
// "Già di un'altra mascotte", ma se fosse spuntata (un doppione) si può togliere.
private struct FilterBox: View {
    let title: String
    let on: Bool, taken: Bool
    let still: Bool   // cliccarla non cambierebbe niente (toggling): spenta
    let toggle: () -> Void

    var body: some View {
        let busy = taken && !on   // di un'altra mascotte: il perché accanto, e per VoiceOver come suggerimento
        HStack {
            Toggle(title, isOn: Binding(get: { on }, set: { _ in toggle() }))
                .toggleStyle(.checkbox)
                .disabled(still)
                .accessibilityHint(busy ? String(localized: "Taken by another mascot") : "")
            if busy {
                Spacer()
                Text("Taken by another mascot").foregroundStyle(.secondary)
                    .accessibilityHidden(true)   // VoiceOver lo dice già dal suggerimento della casella
            }
        }
    }
}

// Un fattore (1 = come la forma) come percento intero per i cursori, a passi di 1 %: arrotondato, se no 1,13 × 100 =
// 112,99… e il cursore mostrava 112.
func percent(_ v: Binding<Double>) -> Binding<Double> {
    Binding(get: { (v.wrappedValue * 100).rounded() }, set: { v.wrappedValue = $0 / 100 })
}

// La pagina di una mascotte (spec §1 e §10), dall'alto: anteprima viva con un umore tipico della funzione; Aspetto (forma,
// corpo, occhi coi loro tre cursori, voce); Funzione col filtro; Opzioni della funzione; Barra (sfondo e grandezza);
// Elimina con conferma. La mascotte si legge e si scrive per id: eliminata, la pagina non trova più niente da mostrare (e
// SettingsRoot torna all'elenco).
struct MascotScreen: View {
    let id: UUID
    @Bindable var settings = Settings.shared
    @State private var deleting = false

    var body: some View {
        if let m = mascot {
            let now = m.wrappedValue
            Form {
                Section {
                    // Anche qui si schiaccia e reagisce ai clic (autore, 11/10): i 12 pt sopra la tela sono lo spazio del
                    // cuoricino, al posto del margine in alto (stessa altezza del riquadro).
                    LiveMascot(geometry: .of(now), bodyHex: now.body, eyesHex: now.eyes, mood: now.function.isAI ? .wait : .alarm,
                               dot: now.function.isAI ? AgentState.waiting.color(in: nil) : .orange, running: SettingsShown.shared.open,
                               headroom: 12 / (0.27 * 3))
                        .frame(width: mascotBarSize.width * 3, height: mascotBarSize.height * 3 + 12)
                        .frame(maxWidth: .infinity)
                        .padding(.bottom, 12)
                        .background(Color(white: 0.16), in: RoundedRectangle(cornerRadius: 8))
                }
                Section("Appearance") {
                    HStack {
                        Text("Shape")
                        Spacer()
                        // Le sagome come figure da toccare, senza scritte, coi colori di adesso e gli occhi di partenza di
                        // ogni forma: nove geometrie calcolate una volta (con gli occhi di adesso ogni passo dei cursori le
                        // ricalcolava tutte, 16–27 ms); quelli scelti li mostra l'anteprima. I nomi solo per VoiceOver (spec §1
                        // e §10).
                        ForEach(MascotKind.allCases, id: \.self) { kind in
                            Button { m.wrappedValue.reshape(kind) } label: {
                                Image(nsImage: mascotThumbnail(now, height: 24, geometry: .of(kind)))
                                    .padding(3)
                                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.accentColor, lineWidth: 2).opacity(now.shape == kind ? 1 : 0))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text(kind.name))
                            .accessibilityAddTraits(now.shape == kind ? .isSelected : [])
                        }
                    }
                    SwatchRow(title: "Body", value: m.body)
                    SwatchRow(title: "Eyes", value: m.eyes)
                    // I tre cursori degli occhi (spec §10), in percento e in unità della tela, fin dove arriva la forma: ogni
                    // combinazione tiene gli occhi dentro (EyeRanges).
                    let eyes = EyeRanges.of(now.shape)
                    SliderRow(title: "Eye size", value: percent(m.eyeSize), range: percents(eyes.sizes), icon: "eye", unit: "%")
                    SliderRow(title: "Eye height", value: m.eyeLift, range: eyes.lifts, icon: "arrow.up.and.down", unit: "")
                    SliderRow(title: "Eye spacing", value: percent(m.eyeSpread), range: percents(eyes.spreads), icon: "arrow.left.and.right", unit: "%")
                    HStack {
                        Picker("Voice", selection: m.voice) {
                            ForEach(MascotVoice.allCases, id: \.self) { Text($0.name).tag($0) }
                        }
                        Button { playVoice(m.wrappedValue) } label: { Image(systemName: "play.fill") }
                            .help(String(localized: "Listen"))
                            .accessibilityLabel(String(localized: "Listen"))
                    }
                }
                Section("Function") {
                    // Una cosa guardata, una mascotte: l'altra funzione prende le cose ancora libere, e il suo segmento è
                    // spento se non ne resta nessuna (selectionDisabled: solo quello, lo scelto resta acceso). Una casella è
                    // spenta quando spuntarla o toglierla non cambierebbe niente (toggling: l'ultima spuntata, o una cosa di
                    // un'altra mascotte, che ha accanto il perché).
                    let others = settings.mascots.taken(except: id)
                    Picker("Function", selection: Binding(get: { now.function.isAI }, set: { ai in
                        if ai != m.wrappedValue.function.isAI, let f = settings.mascots.free(ai: ai, for: id) { m.wrappedValue.function = f }
                    })) {
                        ForEach([true, false], id: \.self) { ai in
                            Text(MascotFunction.all(ai: ai).name).tag(ai)
                                .selectionDisabled(ai != now.function.isAI && settings.mascots.free(ai: ai, for: id) == nil)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()   // il titolo della sezione lo dice già; VoiceOver lo legge comunque
                    switch now.function {
                    case .ai(let agents):
                        ForEach(Agent.allCases, id: \.self) { a in
                            FilterBox(title: a.rawValue, on: agents.contains(a), taken: others.agents.contains(a),
                                      still: now.function.toggling(a, taken: others.agents) == now.function) {
                                m.wrappedValue.function = m.wrappedValue.function.toggling(a, taken: settings.mascots.taken(except: id).agents)
                            }
                        }
                    case .system(let kinds):
                        ForEach(AlarmKind.allCases, id: \.self) { k in
                            FilterBox(title: k.name, on: kinds.contains(k), taken: others.kinds.contains(k),
                                      still: now.function.toggling(k, taken: others.kinds) == now.function) {
                                m.wrappedValue.function = m.wrappedValue.function.toggling(k, taken: settings.mascots.taken(except: id).kinds)
                            }
                        }
                    }
                }
                Section("Options") {
                    Toggle("Sound effects", isOn: m.sounds)
                    SliderRow(title: "Volume", value: Binding(get: { Double(now.volume) }, set: { m.wrappedValue.volume = Int($0) }),
                              range: 0...100, icon: "speaker.wave.2.fill", unit: "%", action: ("Try", { trySounds(m.wrappedValue) }))
                        .disabled(!now.sounds)
                    Toggle("Speech bubbles", isOn: m.captions)
                    if now.function.isAI {
                        // Attivo solo coi fumetti e se guarda un agente il cui account c'è su questo Mac (accountAvailable).
                        Toggle(isOn: m.renewedBadge) { RowLabel(title: "“Session renewed!” bubble", description: "When a Claude or ChatGPT usage window resets after running out.") }
                            .disabled(!now.captions || !now.function.agents.contains { accountAvailable($0) })
                        Toggle("Quota in the menu", isOn: m.quotaInMenu)
                    }
                }
                Section("Bar") {
                    Toggle(isOn: m.background) { RowLabel(title: "Background", description: "A pill like the others. Turned off, just the mascot, at the same height.") }
                    SliderRow(title: "Size", value: percent(m.size), range: percents(mascotSizes), icon: "arrow.up.left.and.arrow.down.right", unit: "%")
                }
                Section {
                    Button("Delete mascot…", role: .destructive) { deleting = true }
                        .alert("Delete this mascot?", isPresented: $deleting) {
                            Button("Delete", role: .destructive) { settings.deleteMascot(id) }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("Its settings will be lost.") }
                }
            }
            .formStyle(.grouped)
        }
    }

    // L'intervallo di un fattore in percento, per i cursori (percent).
    private func percents(_ r: ClosedRange<Double>) -> ClosedRange<Double> { r.lowerBound * 100...r.upperBound * 100 }

    // La scheda della mascotte, letta e scritta per id: dopo l'eliminazione la lettura dà l'ultima vista e la scrittura
    // non fa niente (un indice nell'elenco, a pagina ancora aperta, farebbe cadere l'app).
    private var mascot: Binding<Mascot>? {
        guard let last = settings.mascot(id) else { return nil }
        return Binding(get: { settings.mascot(id) ?? last },
                       set: { new in if let i = settings.mascots.firstIndex(where: { $0.id == id }) { settings.mascots[i] = new } })
    }
}
