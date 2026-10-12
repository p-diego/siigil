import Foundation
import Testing
@testable import Siigil

// La barra si abbassa solo quando quella di macOS sta davvero scendendo (sentinella sparita), col mouse nella
// fascia; sfiorare il bordo da solo non basta (review 3/10: abbassarsi al tocco regalava il click dopo alla
// trappola). Da abbassata resta giù finché quella è visibile, anche col mouse in fondo a un suo menu.
@Test func theBarDodgesOnlyWhileTheSystemBarIsVisible() {
    #expect(!dodgesMenuBar(distanceFromTop: 0, lowered: false, visible: false, dwelling: false))     // sfioro di passaggio: su, il click resta nostro
    #expect(dodgesMenuBar(distanceFromTop: 0, lowered: false, visible: false, dwelling: true))       // fermo al bordo ~0,3 s: giù PRIMA che lei sbuchi (review: scendeva dietro)
    #expect(dodgesMenuBar(distanceFromTop: 1, lowered: false, visible: true, dwelling: false))       // sta scendendo: giù
    #expect(dodgesMenuBar(distanceFromTop: 20, lowered: false, visible: true, dwelling: false))      // scende col mouse tra le pillole: giù
    #expect(!dodgesMenuBar(distanceFromTop: 500, lowered: false, visible: true, dwelling: false))    // visibile ma mouse lontano: resta su
    #expect(dodgesMenuBar(distanceFromTop: 500, lowered: true, visible: true, dwelling: false))      // giù in un suo menu: resta giù
    #expect(!dodgesMenuBar(distanceFromTop: 0, lowered: true, visible: false, dwelling: false))      // sparita e niente sosta: su
    #expect(!dodgesMenuBar(distanceFromTop: .infinity, lowered: true, visible: true, dwelling: false))   // mouse su un altro schermo: su
}

// A schermo intero la barra sparisce (regola di sempre; su 27.2 gli spazi a schermo intero la invitano, prima no):
// una finestra copre lo schermo se è alta quasi quanto lui ED entra nella striscia della barra. Le finestre di
// AeroSpace partono SOTTO la barra (y 39) e non contano, il video a schermo intero parte sotto il notch (y 33-34).
@Test func aWindowCoversTheScreenOnlyIfTallAndIntoTheBarStrip() {
    #expect(coversTheScreen(top: 34, height: 1073, screenHeight: 1107, barHeight: 38))    // video sotto il notch
    #expect(coversTheScreen(top: 0, height: 1107, screenHeight: 1107, barHeight: 38))     // gioco senza bordi
    #expect(!coversTheScreen(top: 39, height: 1062, screenHeight: 1107, barHeight: 38))   // finestra di AeroSpace: sotto la barra
    #expect(!coversTheScreen(top: 34, height: 500, screenHeight: 1107, barHeight: 38))    // bassa: non copre
    #expect(!coversTheScreen(top: -1107, height: 1080, screenHeight: 1107, barHeight: 38))  // finestra d'un altro schermo sopra (review 3/10: spegneva la barra dello schermo sotto)
    #expect(!coversTheScreen(top: 1061, height: 1062, screenHeight: 1107, barHeight: 38))   // d'un altro schermo sotto
}
