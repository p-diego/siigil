import SwiftUI

// ⌘-trascina un widget nella barra (spec §4). Mentre trascini il widget segue il mouse e la barra si sistema già come
// sarà al rilascio (dropPlace, anteprima in BarView); al rilascio Settings.move salva quello che vedi. Senza ⌘ il gesto
// non parte: tap, tasto destro e glass restano come sono. Le pillole degli spazi sono un widget solo.

// Lato: a sinistra del notch (`leftWidth`) o, senza notch, prima del primo widget di destra (escluso quello trascinato).
// Indice: subito dopo l'ultimo widget di quel lato (escluso quello trascinato) col centro prima del punto. Chi non è
// disegnato non ha frame e non conta: contato come prima del punto, il widget finiva dopo quello giusto (27/9).
func dropTarget(x: CGFloat, dragging: BarItem, left: [BarItem], right: [BarItem],
                leftWidth: CGFloat?, frames: [BarItem: CGRect]) -> (side: Side, index: Int) {
    let boundary = leftWidth ?? right.filter { $0 != dragging }.compactMap { frames[$0]?.minX }.min() ?? .infinity
    let side: Side = x < boundary ? .left : .right
    let others = (side == .left ? left : right).filter { $0 != dragging }
    let before = others.lastIndex { frames[$0].map { $0.midX < x } ?? false }
    return (side, before.map { $0 + 1 } ?? 0)
}

// Una mascotte, su uno schermo col notch, sta nello spazio vuoto del suo lato attaccata al notch o ai widget. Lasciata
// nello spazio vuoto (`free`, da widget a notch a sinistra, da notch a widget a destra) si attacca al notch nella metà
// vicina al notch.
func nearNotch(x: CGFloat, side: Side, free: ClosedRange<CGFloat>) -> Bool {
    let mid = (free.lowerBound + free.upperBound) / 2
    return side == .left ? x > mid : x < mid
}

// Lo spazio vuoto di un lato (`area`) senza l'elemento trascinato: tra le mascotte attaccate al notch (o il bordo del
// notch) e gli altri widget di quel lato.
func freeSpace(_ side: Side, without id: BarItem, in list: [BarItem], area: CGRect, frames: [BarItem: CGRect],
               besideNotch: (BarItem) -> Bool) -> ClosedRange<CGFloat>? {
    let others = list.filter { $0 != id }
    let atNotch = others.filter { $0.isMascot && besideNotch($0) }.compactMap { frames[$0] }
    let rest = others.filter { !($0.isMascot && besideNotch($0)) }.compactMap { frames[$0] }
    let low = side == .left ? rest.map(\.maxX).max() ?? area.minX : atNotch.map(\.maxX).max() ?? area.minX
    let high = side == .left ? atNotch.map(\.minX).min() ?? area.maxX : rest.map(\.minX).min() ?? area.maxX
    return low <= high ? low...high : nil
}

// Dove finisce un elemento lasciato al punto x: lato e indice (dropTarget) e, per una mascotte su uno schermo col notch,
// se si attacca al notch (nearNotch; nil = com'era). La stessa regola per l'anteprima mentre trascini e per il rilascio,
// sulle posizioni di quando il trascinamento è cominciato: gli altri che si spostano per l'anteprima non la fanno ballare.
func dropPlace(of id: BarItem, at x: CGFloat, left: [BarItem], right: [BarItem], leftWidth: CGFloat?,
               frames: [BarItem: CGRect], sides: [Side: CGRect], besideNotch: (BarItem) -> Bool)
    -> (side: Side, index: Int, besideNotch: Bool?) {
    let t = dropTarget(x: x, dragging: id, left: left, right: right, leftWidth: leftWidth, frames: frames)
    guard id.isMascot, leftWidth != nil, let area = sides[t.side],
          let free = freeSpace(t.side, without: id, in: t.side == .left ? left : right, area: area, frames: frames, besideNotch: besideNotch)
    else { return (t.side, t.index, nil) }
    return (t.side, t.index, nearNotch(x: x, side: t.side, free: free))
}

// Le mascotte guardano verso lo spazio vuoto, dove cresce il fumetto: riflesse se il vuoto è alla loro sinistra. A destra
// del notch il vuoto è a sinistra, a sinistra del notch è a destra; una mascotte attaccata al notch guarda dall'altra
// parte, verso il vuoto tra lei e i widget. Senza notch ognuna segue il suo lato: verso il vuoto, una regola sola.
func mirroredMascot(_ w: BarItem, notch: Bool, left: [BarItem], right: [BarItem], besideNotch: Bool) -> Bool {
    guard notch else { return right.contains(w) }
    // Le mascotte al bordo del loro lato (le ultime a sinistra, le prime a destra): chi è attaccata al notch guarda via da lui.
    let atEdge = left.reversed().prefix { $0.isMascot }.contains(w) || right.prefix { $0.isMascot }.contains(w)
    return right.contains(w) != (w.isMascot && besideNotch && atEdge)
}

// Dove sta il vuoto tra le mascotte attaccate al notch e il resto del lato: a sinistra prima della prima di loro, a destra
// dopo l'ultima (BarView ci mette uno Spacer). nil = nessuna attaccata al notch su quel lato.
func notchGap(_ side: Side, list: [BarItem], besideNotch: (BarItem) -> Bool) -> BarItem? {
    side == .left ? list.first { $0.isMascot && besideNotch($0) } : list.last { $0.isMascot && besideNotch($0) }
}

// Il ⌘-trascina in corso: dove era il puntatore all'inizio e dove è adesso (coordinate space "bar"), e le posizioni di
// tutti e dei due lati a quel momento, su cui decide dropPlace.
struct Drag { let id: BarItem; let start: CGFloat; var x: CGFloat; let frames: [BarItem: CGRect]; let sides: [Side: CGRect] }

// Un elemento che si può ⌘-trascinare: registra dove sta e, mentre lo trascini, resta sotto il puntatore anche quando
// l'anteprima gli cambia posto, con la posizione di adesso letta mentre si disegna (visualEffect). Il gesto è uno solo,
// sulla barra (BarView): passando il notch l'elemento cambia fila, e un gesto suo finirebbe con lui.
struct Rearrangeable: ViewModifier {
    let id: BarItem
    @Binding var frames: [BarItem: CGRect]
    let drag: Drag?

    func body(content: Content) -> some View {
        let grab = drag.flatMap { d in d.id == id ? d.frames[id].map { d.start - $0.minX } : nil }   // dove l'hai preso
        return content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("bar")) } action: { frames[id] = $0 }
            .visualEffect { [x = drag?.x] effect, proxy in
                effect.offset(x: grab.map { x! - $0 - proxy.frame(in: .named("bar")).minX } ?? 0)
            }
            .zIndex(drag?.id == id ? 1 : 0)
            // Quello trascinato cambia posto senza animazione (resta incollato al puntatore); gli altri scivolano.
            .transaction { if drag?.id == id { $0.animation = nil } }
    }
}
