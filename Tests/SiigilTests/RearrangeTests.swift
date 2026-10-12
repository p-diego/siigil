import Foundation
import Testing
@testable import Siigil

// Due mascotte qualunque: il "gatto" e il "cane" dei test di prima.
private let cat = BarItem.mascot(UUID()), dog = BarItem.mascot(UUID())
private let workspaces = BarItem.widget(.workspaces), hidden = BarItem.widget(.hidden), focus = BarItem.widget(.focus)
private let wifi = BarItem.widget(.wifi), volume = BarItem.widget(.volume), battery = BarItem.widget(.battery), clock = BarItem.widget(.clock)

// Frame in coordinate della barra: pillole 0-200 a sinistra; a destra la mascotte `cat` 700-730, volume 1000-1030, batteria 1040-1070, orologio 1080-1200.
private let frames: [BarItem: CGRect] = [
    workspaces: CGRect(x: 0, y: 0, width: 200, height: 26),
    cat: CGRect(x: 700, y: 0, width: 30, height: 26),
    volume: CGRect(x: 1000, y: 0, width: 30, height: 26),
    battery: CGRect(x: 1040, y: 0, width: 30, height: 26),
    clock: CGRect(x: 1080, y: 0, width: 120, height: 26),
]
private let left: [BarItem] = [workspaces], right: [BarItem] = [cat, volume, battery, clock]

@Test func dropWithNotchUsesLeftWidthAsBoundary() {
    // notch da 600 a 800: rilascio a 500 = sinistra, dopo le pillole
    let t = dropTarget(x: 500, dragging: clock, left: left, right: right, leftWidth: 600, frames: frames)
    #expect(t.side == .left && t.index == 1)
    // a 1035: destra, dopo `cat` e volume (centri 715 e 1015), prima della batteria
    let u = dropTarget(x: 1035, dragging: clock, left: left, right: right, leftWidth: 600, frames: frames)
    #expect(u.side == .right && u.index == 2)
}

@Test func dropWithoutNotchSplitsAtTheFirstRightWidget() {
    // senza notch il confine è l'inizio del primo widget di destra che non sto trascinando
    let t = dropTarget(x: 650, dragging: battery, left: left, right: right, leftWidth: nil, frames: frames)
    #expect(t.side == .left && t.index == 1)
    let u = dropTarget(x: 690, dragging: cat, left: left, right: right, leftWidth: nil, frames: frames)   // trascino `cat`: confine = volume (1000)
    #expect(u.side == .left && u.index == 1)
}

@Test func dropIgnoresTheDraggedWidgetWhenCounting() {
    // il volume trascinato a 1100: gli altri di destra col centro prima di 1100 sono `cat` e batteria → indice 2
    let t = dropTarget(x: 1100, dragging: volume, left: left, right: right, leftWidth: 600, frames: frames)
    #expect(t.side == .right && t.index == 2)
    let u = dropTarget(x: 5, dragging: workspaces, left: left, right: right, leftWidth: 600, frames: frames)
    #expect(u.side == .left && u.index == 0)
}

// Un widget in lista ma non disegnato (app nascoste senza app) non ha frame: non conta prima del punto (27/9: il clock
// lasciato prima degli spazi finiva dopo). Se sta in mezzo, l'indice va dopo l'ultimo disegnato prima del punto.
@Test func dropSkipsWidgetsThatAreNotShown() {
    let t = dropTarget(x: 5, dragging: clock, left: [workspaces, hidden], right: right, leftWidth: 600, frames: frames)
    #expect(t.side == .left && t.index == 0)
    var f = frames; f[focus] = CGRect(x: 300, y: 0, width: 30, height: 26)
    let u = dropTarget(x: 400, dragging: clock, left: [workspaces, hidden, focus], right: right, leftWidth: 600, frames: f)
    #expect(u.side == .left && u.index == 3)
    let v = dropTarget(x: 250, dragging: clock, left: [workspaces, hidden, focus], right: right, leftWidth: 600, frames: f)
    #expect(v.side == .left && v.index == 1)
}

// Una mascotte lasciata nello spazio vuoto del suo lato (schermo col notch): nella metà vicina al notch si attacca al
// notch, nell'altra ai widget. A sinistra il notch è a destra del vuoto, a destra è a sinistra.
@Test func catSticksToTheNotchInTheNotchHalfOfTheEmptySpace() {
    #expect(nearNotch(x: 380, side: .left, free: 200...500))
    #expect(!nearNotch(x: 300, side: .left, free: 200...500))
    #expect(nearNotch(x: 900, side: .right, free: 800...1200))
    #expect(!nearNotch(x: 1100, side: .right, free: 800...1200))
}

// Una mascotte guarda verso lo spazio vuoto, dove cresce il fumetto: riflessa se il vuoto è alla sua sinistra. Le quattro
// posizioni col notch: dopo le pillole, attaccata al notch da sinistra, attaccata al notch da destra, prima dei widget.
// In mezzo ai widget di destra il vuoto è comunque a sinistra. Senza notch ogni mascotte guarda lo spazio vuoto del suo
// lato: riflessa a destra, dritta a sinistra.
@Test func catFacesTheEmptySpace() {
    let l: [BarItem] = [workspaces, cat], r: [BarItem] = [wifi, clock]
    #expect(!mirroredMascot(cat, notch: true, left: l, right: r, besideNotch: false))
    #expect(mirroredMascot(cat, notch: true, left: l, right: r, besideNotch: true))
    #expect(!mirroredMascot(cat, notch: true, left: [workspaces], right: [cat] + r, besideNotch: true))
    #expect(mirroredMascot(cat, notch: true, left: [workspaces], right: [cat] + r, besideNotch: false))
    #expect(mirroredMascot(cat, notch: true, left: [workspaces], right: [wifi, cat, clock], besideNotch: true))
    #expect(!mirroredMascot(cat, notch: true, left: [cat, workspaces], right: r, besideNotch: true))
    #expect(mirroredMascot(cat, notch: false, left: [workspaces], right: [cat] + r, besideNotch: true))
    // Senza notch ogni mascotte segue il suo lato: a sinistra guarda a destra, verso lo spazio vuoto (prima il gatto no).
    #expect(!mirroredMascot(cat, notch: false, left: [workspaces, cat], right: r, besideNotch: true))
}

// Due mascotte sullo stesso lato: ognuna guarda secondo il suo posto; il vuoto sta dopo (a destra) o prima (a sinistra)
// di quelle attaccate al notch.
@Test func twoMascotsOnOneSide() {
    let r: [BarItem] = [dog, cat, wifi, clock]   // `dog` al notch, `cat` ai widget
    #expect(!mirroredMascot(dog, notch: true, left: [workspaces], right: r, besideNotch: true))
    #expect(mirroredMascot(cat, notch: true, left: [workspaces], right: r, besideNotch: false))
    let atNotch: (BarItem) -> Bool = { $0 == dog }
    #expect(notchGap(.right, list: r, besideNotch: atNotch) == dog)
    #expect(notchGap(.left, list: [workspaces, cat, dog], besideNotch: atNotch) == dog)
    #expect(notchGap(.right, list: r, besideNotch: { _ in false }) == nil)
}

// Il sasso di Codex dell'11/10: attaccato al notch a sinistra, lasciato accanto alle altre due mascotte si stacca e va
// dopo di loro; lasciato nella metà del vuoto vicina al notch resta lì. Un widget questa scelta non ce l'ha (nil).
@Test func aNotchMascotDroppedNextToTheOthersLeavesTheNotch() {
    let mostro = BarItem.mascot(UUID()), quadrato = BarItem.mascot(UUID()), sasso = BarItem.mascot(UUID())
    let left = [workspaces, hidden, mostro, quadrato, sasso]
    let f: [BarItem: CGRect] = [workspaces: CGRect(x: 6, y: 0, width: 264, height: 26), mostro: CGRect(x: 276, y: 0, width: 40, height: 26),
                                quadrato: CGRect(x: 322, y: 0, width: 34, height: 26), sasso: CGRect(x: 716, y: 0, width: 40, height: 26)]
    let sides: [Side: CGRect] = [.left: CGRect(x: 6, y: 0, width: 750.5, height: 38)]
    let atNotch = { (i: BarItem) in i == sasso }
    let near = dropPlace(of: sasso, at: 380, left: left, right: [clock], leftWidth: 762.5, frames: f, sides: sides, besideNotch: atNotch)
    #expect(near.side == .left && near.index == 4 && near.besideNotch == false)
    let far = dropPlace(of: sasso, at: 700, left: left, right: [clock], leftWidth: 762.5, frames: f, sides: sides, besideNotch: atNotch)
    #expect(far.side == .left && far.besideNotch == true)
    #expect(dropPlace(of: clock, at: 300, left: left, right: [clock], leftWidth: 762.5, frames: f, sides: sides, besideNotch: atNotch).besideNotch == nil)
}

// Quello che vedi mentre trascini è quello che ottieni: l'anteprima (i due lati spostati, con la scelta del notch della
// mascotte trascinata) è uguale a quello che Settings salva al rilascio. Qui il Monitor AI, attaccato al notch a destra,
// lasciato accanto agli spazi a sinistra.
@Test func thePreviewIsWhatTheDropSaves() {
    let (d, name) = fresh(); defer { d.removePersistentDomain(forName: name) }
    let s = Settings(defaults: d), ai = BarItem.mascot(s.mascots[0].id)
    #expect(s.besideNotch(ai))
    let f: [BarItem: CGRect] = [workspaces: CGRect(x: 6, y: 0, width: 194, height: 26), ai: CGRect(x: 806, y: 0, width: 40, height: 26),
                                clock: CGRect(x: 1560, y: 0, width: 130, height: 26)]
    let sides: [Side: CGRect] = [.left: CGRect(x: 6, y: 0, width: 588, height: 38), .right: CGRect(x: 806, y: 0, width: 894, height: 38)]
    let place = dropPlace(of: ai, at: 230, left: s.left, right: s.right, leftWidth: 600, frames: f, sides: sides, besideNotch: s.besideNotch)
    #expect(place.side == .left && place.besideNotch == false)
    let preview = moved(ai, to: place.side, index: place.index, left: s.left, right: s.right,
                        besideNotch: { $0 == ai ? place.besideNotch ?? s.besideNotch($0) : s.besideNotch($0) })
    s.setBesideNotch(ai, false)
    s.move(ai, to: place.side, index: place.index)
    #expect(s.left == preview.left && s.right == preview.right)
    #expect(s.left == [workspaces, hidden, ai] && !s.besideNotch(ai))
}
