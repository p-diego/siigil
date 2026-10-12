import AppKit
import SwiftUI

// Il Benvenuto (spec benvenuto §1 e §3): tre passi nello stesso Form — impostazioni base, permessi, agenti AI — uno
// alla volta con `step`. Ogni riga ha un titolo che dice da solo a cosa serve e, a destra, il segno verde o i
// pulsanti; sotto, in rosso, l'errore dell'ultima azione. Le righe che non servono non compaiono. Lo stato si rilegge
// dopo ogni pulsante (SetupModel.refresh); quando torna key lo fa la finestra, windowDidBecomeKey.
struct WelcomeView: View {
    let model: SetupModel
    let close: () -> Void
    private let settings = Settings.shared

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 64, height: 64)
                Text("Welcome to Siigil").font(.title.bold())
                Text("A few things to set up. You'll find this again in Settings › General.").foregroundStyle(.secondary)
            }
            .padding(.top, 28).padding(.bottom, 4)   // sopra ci sono i semafori della finestra
            Form {
                Section {
                    switch model.step {
                    case 0:
                        if !model.isInApplications {
                            row("folder", "Siigil in Applications", error: model.moveError) {
                                Button("Move to Applications") { move() }
                            }
                        }
                        // Consiglio, non requisito (spec senza-aerospace §4): senza, la barra mostra le app aperte.
                        row("rectangle.3.group", "AeroSpace window manager",
                            description: "With AeroSpace the bar shows your workspaces; without it, the open apps.",
                            done: model.aerospace == .running) {
                            if model.aerospace == .installedNotRunning {
                                // AeroSpace ci mette un momento ad apparire tra le app in esecuzione: un refresh
                                // immediato lo trova ancora spento e la riga non diventa verde da sola.
                                Button("Open AeroSpace") {
                                    open("-b", aerospaceBundle)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { model.refresh() }
                                }
                            } else {
                                Button(homebrewPath == nil ? "Download…" : "Install with Homebrew") { installAerospaceInTerminal() }
                            }
                        }
                    case 1:
                        // Solo i permessi veri di macOS: le scorciatoie (installazioni, non permessi) stanno nella
                        // loro sezione qui sotto (autore, 4/10).
                        if settings.isOn(.focus) {
                            permission(.fullDiskAccess, "moon.fill", "Full Disk Access for the Focus widget")
                        }
                        if settings.isOn(.wifi) {
                            permission(.location, "wifi", "Location for Wi-Fi name")
                        }
                        if settings.isOn(.bluetooth) {
                            permission(.bluetooth, "dot.radiowaves.left.and.right", "Bluetooth for your devices")
                        }
                    default:
                        let agents = integrations.compactMap { i in model.hooks[i.id].flatMap { $0.isMissing ? nil : (i, $0) } }
                        if agents.isEmpty { Text("No AI agents found.").foregroundStyle(.secondary) }
                        ForEach(agents, id: \.0.id) { i, status in
                            IntegrationRow(integration: i, status: status, inWelcome: true, refresh: model.refresh)
                        }
                    }
                } header: {
                    Text(stepTitle).font(.headline).textCase(nil)
                } footer: {
                    if model.step == 0 {
                        Text("Siigil starts at login, hid the macOS menu bar and turned off window snapping. Change them in General.")
                    }
                }
                // Le scorciatoie di Comandi rapidi: installazioni, non permessi — sezione loro, icone col significato
                // (luna-zz = Non disturbare, batteria = Risparmio), niente descrizioni (autore, 4/10).
                if model.step == 1 {
                    Section {
                        permission(.dndShortcut, "moon.zzz.fill", "“Siigil DND” shortcut for DND")
                        permission(.lowPowerShortcut, "battery.50percent", "“Siigil Low Power” shortcut for Low Power")
                        if settings.isOn(.bluetooth) {
                            permission(.bluetoothShortcut, "dot.radiowaves.left.and.right", "“Siigil Bluetooth” shortcut for Bluetooth")
                        }
                    } header: {
                        Text("Shortcuts").font(.headline).textCase(nil)
                    }
                }
            }
            .formStyle(.grouped)
            .animation(.smooth(duration: 0.2), value: model.step)
            HStack {
                Button("Settings…") { SettingsWindow.shared.open() }
                Spacer()
                Button("Back") { model.step -= 1 }.disabled(model.step == 0)
                if model.step < 2 {
                    Button("Next") { model.step += 1 }
                } else {
                    Button("Done", action: close).keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .modifier(PageBackground())   // quasi nero, come le pagine delle impostazioni (la finestra è sempre scura)
    }

    private var stepTitle: LocalizedStringKey {
        switch model.step {
        case 0: return "Basic setup"
        case 1: return "Permissions"
        default: return "AI agents"
        }
    }

    // Una riga: `done` mette il segno verde al posto di `trailing`; `error` in rosso sotto.
    @ViewBuilder private func row<Trailing: View>(_ symbol: String, _ title: LocalizedStringKey,
                                                    description: LocalizedStringKey? = nil,
                                                    done: Bool = false, error: String? = nil,
                                                    @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).frame(width: 20).foregroundStyle(.secondary)
            RowLabel(title: title, description: description)
            Spacer()
            if done { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3) } else { trailing() }
        }
        if let error { Text(error).font(.callout).foregroundStyle(.red) }
    }

    // Le righe dei permessi e della scorciatoia: pulsante e azione da `Missing`, come in Generali › Widget.
    private func permission(_ m: Missing, _ symbol: String, _ title: LocalizedStringKey) -> some View {
        row(symbol, title, done: !model.missing.contains(m)) { Button(m.button) { m.fix(); model.refresh() } }
    }

    private func move() {
        do { try moveToApplications(); model.moveError = nil } catch { model.moveError = error.localizedDescription }
        model.refresh()
    }
}
