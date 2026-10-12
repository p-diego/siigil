import SwiftUI

// Trascinare l'icona di una finestra su un'altra pillola spazio (spec 2026-09-26-siigil-trascina-icone-design.md):
// la finestra passa a quello spazio. Qui lo stato e le due decisioni pure; il gesto sta in WorkspacePill, la copia che
// segue il puntatore e il rilascio in BarView. Sul modello del ⌘-trascina dei widget (Rearrange.swift).

// Il trascinamento in corso, nello spazio di coordinate "bar": la finestra, lo spazio di partenza, il punto di presa
// (dove torna la copia se il rilascio non va a segno) e il puntatore.
struct IconDrag {
    let app: AppEntry
    let from: String
    let start: CGPoint
    var location: CGPoint
}

// Su quale pillola cade: quella la cui colonna (intervallo orizzontale, estremi inclusi) contiene il puntatore, purché
// il puntatore sia dentro l'altezza della barra. Nessuna se è la pillola di partenza, se cade tra due pillole o sopra
// o sotto la barra.
func iconDropTarget(at point: CGPoint, from: String, pills: [String: CGRect]) -> String? {
    guard (0...BarPanel.height).contains(point.y) else { return nil }
    let hit = pills.first { $0.value.minX <= point.x && point.x <= $0.value.maxX }?.key
    return hit == from ? nil : hit
}

// Il comando di AeroSpace. `follow`: la finestra era quella a fuoco, lo spazio la segue. `--` prima del nome: uno spazio
// che si chiama "-1" non diventa un'opzione.
func moveWindowArgs(windowID: Int, to workspace: String, follow: Bool) -> [String] {
    ["move-node-to-workspace"] + (follow ? ["--focus-follows-window"] : []) + ["--window-id", String(windowID), "--", workspace]
}
