import SwiftUI

// Il contrasto minimo fra occhi e corpo di una mascotte nuova: 3:1, la soglia WCAG 1.4.11 per la grafica (a 4,5:1, quella
// del testo, nascevano quasi sempre con gli occhi neri e mai viola).
let mascotEyeContrast = 3.0

// Una mascotte nuova (spec sezione Mascotte §2): forma a caso; corpo a caso fra i 12 colori pronti; occhi a caso fra i
// colori pronti che si vedono bene sul corpo (mascotEyeContrast); se forma + corpo + occhi c'è già, si ripesca. Voce di
// partenza: bollicina per il Monitor AI, bottiglia per il Monitor di sistema; le opzioni sono quelle di partenza di Mascot.
// Col generatore fisso è ripetibile.
func newMascot<R: RandomNumberGenerator>(_ function: MascotFunction, existing: [Mascot], using rng: inout R) -> Mascot {
    let readable = Dictionary(uniqueKeysWithValues: mascotSwatches.map { body in
        (body, mascotSwatches.filter { contrast(Color(hex: $0), Color(hex: body)) >= mascotEyeContrast })
    })
    func taken(_ s: MascotKind, _ b: Int, _ e: Int) -> Bool { existing.contains { $0.shape == s && $0.body == b && $0.eyes == e } }
    // Tutte le combinazioni già prese (34 coppie corpo-occhi per forma): va bene anche un doppione, piuttosto che non nascere.
    let full = MascotKind.allCases.allSatisfy { s in mascotSwatches.allSatisfy { b in readable[b]!.allSatisfy { taken(s, b, $0) } } }
    var shape: MascotKind, body: Int, eye: Int
    repeat {
        shape = MascotKind.allCases.randomElement(using: &rng)!
        body = mascotSwatches.randomElement(using: &rng)!
        eye = readable[body]!.randomElement(using: &rng)!   // a 3:1 tutti i corpi hanno almeno un colore d'occhi
    } while !full && taken(shape, body, eye)
    return Mascot(shape: shape, body: body, eyes: eye, voice: function.isAI ? .bubble : .bottle, function: function)
}

func newMascot(_ function: MascotFunction, existing: [Mascot]) -> Mascot {
    var rng = SystemRandomNumberGenerator()
    return newMascot(function, existing: existing, using: &rng)
}
