import Foundation
import SwiftUI
import Testing
@testable import Siigil

// Il simbolo di un dispositivo abbinato: dalla classe Bluetooth (maggiore, minore), col nome per AirPods e trackpad.
@Test func bluetoothSymbolFromClassAndName() {
    #expect(bluetoothSymbol(major: 0x04, minor: 0x06, name: "AirPods Pro di Diego") == "airpods.pro")
    #expect(bluetoothSymbol(major: 0x04, minor: 0x06, name: "AirPods Max") == "airpodsmax")
    #expect(bluetoothSymbol(major: 0x04, minor: 0x01, name: "AirPods") == "airpods")
    #expect(bluetoothSymbol(major: 0x04, minor: 0x06, name: "WH-1000XM4") == "headphones")
    #expect(bluetoothSymbol(major: 0x04, minor: 0x05, name: "JBL Flip") == "hifispeaker.fill")
    #expect(bluetoothSymbol(major: 0x05, minor: 0x10, name: "Magic Keyboard") == "keyboard")
    #expect(bluetoothSymbol(major: 0x05, minor: 0x30, name: "Tastiera e touchpad") == "keyboard")
    #expect(bluetoothSymbol(major: 0x05, minor: 0x20, name: "Magic Mouse") == "magicmouse.fill")
    #expect(bluetoothSymbol(major: 0x05, minor: 0x20, name: "Magic Trackpad") == "rectangle.and.hand.point.up.left.fill")
    #expect(bluetoothSymbol(major: 0x05, minor: 0x02, name: "Xbox Wireless Controller") == "gamecontroller")
    #expect(bluetoothSymbol(major: 0x02, minor: 0x03, name: "iPhone") == "iphone")
    #expect(bluetoothSymbol(major: 0x01, minor: 0x03, name: "MacBook") == "laptopcomputer")
    #expect(bluetoothSymbol(major: 0x07, minor: 0x01, name: "Watch") == "applewatch")
    #expect(bluetoothSymbol(major: 0x1F, minor: 0x00, name: "?") == "dot.radiowaves.left.and.right")
}

// Nel blocco unito niente riquadro fisso: dalle icone vicine la separano solo i margini (8 + 2 per lato), uguali per tutti;
// da sola resta larga come le altre icone.
@MainActor @Test func bluetoothHasNoFixedBoxInTheJoinedBlock() {
    func width(_ merged: Bool) -> CGFloat {
        NSHostingView(rootView: BluetoothView(on: true).environment(\.mergedPill, merged)).fittingSize.width
    }
    #expect(width(false) == 39)
    #expect(width(true) == 27)   // il logo (7) e i margini
}
