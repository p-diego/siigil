import AppKit
import CoreBluetooth
import IOBluetooth

// Bluetooth (autore, 4/10): la pillola col logo e il menu dei dispositivi abbinati, come il Wi-Fi. API pubbliche:
// acceso o spento dagli avvisi di CoreBluetooth (nessun controllo continuo), i dispositivi abbinati e il collegamento da
// IOBluetooth. Accendere e spegnere no: IOBluetooth dà lo stato solo in lettura (powerState, header di macOS 27) e la
// funzione che lo cambia è privata — lo fa la scorciatoia "Siigil Bluetooth" (Focus.swift), come Risparmio energetico.
// Serve il permesso Bluetooth: macOS lo chiede al primo uso, cioè quando si accende la pillola, mai a pillola spenta.

// Il simbolo di un dispositivo abbinato dalla sua classe Bluetooth: maggiore (computer, telefono, audio, periferica,
// indossabile) e minore (audio: 0x05 la cassa; periferiche: tastiera 0x10, puntatore 0x20, joystick e gamepad nei 4 bit
// bassi). Il nome scioglie AirPods e trackpad, che la classe non distingue.
func bluetoothSymbol(major: UInt32, minor: UInt32, name: String) -> String {
    func named(_ s: String) -> Bool { name.localizedCaseInsensitiveContains(s) }
    switch major {
    case 0x01: return "laptopcomputer"
    case 0x02: return "iphone"
    case 0x04:
        if named("airpods max") { return "airpodsmax" }
        if named("airpods pro") { return "airpods.pro" }
        if named("airpods") { return "airpods" }
        return minor == 0x05 ? "hifispeaker.fill" : "headphones"
    case 0x05 where minor & 0x10 != 0: return "keyboard"
    case 0x05 where minor & 0x20 != 0: return named("trackpad") ? "rectangle.and.hand.point.up.left.fill" : "magicmouse.fill"
    case 0x05 where [0x01, 0x02].contains(minor & 0x0F): return "gamecontroller"
    case 0x07: return "applewatch"
    default: return "dot.radiowaves.left.and.right"
    }
}

struct PairedDevice: Equatable {
    let address: String
    let name: String
    let symbol: String
    let connected: Bool
}

// I dispositivi abbinati, nell'ordine di IOBluetooth. Senza permesso la lista è vuota. Solo quelli con una classe
// (cuffie, tastiera…): IOBluetooth dà anche i dispositivi Apple dello stesso iCloud (iPhone, Watch, Apple TV, Mac),
// senza classe, che il menu di macOS non mostra (autore, 4/10; nel profilo di sistema sono quelli senza "Minor Type").
// ponytail: un accessorio solo Bluetooth LE senza classe sparirebbe; se capita, distinguerlo in altro modo.
func pairedDevices() -> [PairedDevice] {
    (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).compactMap { d in
        guard d.classOfDevice != 0, let address = d.addressString else { return nil }
        let name = d.name ?? address
        return PairedDevice(address: address, name: name,
                            symbol: bluetoothSymbol(major: d.deviceClassMajor, minor: d.deviceClassMinor, name: name),
                            connected: d.isConnected())
    }
}

// Collega o scollega un dispositivo abbinato. Collegare è asincrono: IOBluetooth risponde a connectionComplete sul main
// e intanto la riga del menu mostra la rotellina (`pending`). Un errore è un beep, come il Wi-Fi. Senza risposta entro
// 10 s la rotellina si spegne comunque, così si può ritentare (autore, 4/10). Globale: IOBluetooth non trattiene il
// bersaglio, e la risposta può arrivare a menu chiuso.
@Observable final class BluetoothLinks: NSObject {
    private(set) var pending: [String: Date] = [:]   // indirizzo → quando è partito il tentativo

    func toggle(_ device: PairedDevice) {
        let address = device.address
        guard pending[address] == nil, let d = IOBluetoothDevice(addressString: address) else { return }
        if d.isConnected() {
            if d.closeConnection() != kIOReturnSuccess { NSSound.beep() }
        } else if d.openConnection(self) == kIOReturnSuccess {
            let start = Date()
            pending[address] = start
            // Solo questo tentativo: uno nuovo partito nel frattempo ha la sua data e il suo limite.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [self] in
                if pending[address] == start { pending[address] = nil }
            }
        } else {
            NSSound.beep()
        }
    }

    @objc func connectionComplete(_ device: IOBluetoothDevice!, status: IOReturn) {
        if let address = device?.addressString { pending[address] = nil }
        if status != kIOReturnSuccess { NSSound.beep() }
    }
}
let bluetoothLinks = BluetoothLinks()

// Acceso o spento, dagli avvisi di CoreBluetooth: crearlo chiede il permesso la prima volta, poi ogni cambio arriva sul
// main. `onChange(nil)` senza permesso o senza Bluetooth: la pillola sparisce, il perché lo dice Impostazioni › Pillole.
// Gli stati di passaggio (sconosciuto, in ripristino) non cambiano niente. Niente avviso di sistema "accendi il
// Bluetooth": a spento la pillola si barra e basta.
final class BluetoothWatcher: NSObject, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private let onChange: (Bool?) -> Void

    init(onChange: @escaping (Bool?) -> Void) { self.onChange = onChange }

    func start() {
        guard central == nil else { return }
        central = CBCentralManager(delegate: self, queue: .main, options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: onChange(true)
        case .poweredOff: onChange(false)
        case .unauthorized, .unsupported: onChange(nil)
        default: break
        }
    }
}

// Il permesso manca anche se negato: la riga resta e il pulsante porta alle Impostazioni (come la Posizione).
// Leggerlo non chiede niente.
func bluetoothMissing() -> Bool { CBManager.authorization != .allowedAlways }

// Mai chiesto → la richiesta di macOS (accende l'osservatore); negato → la pagina Privacy di Impostazioni di Sistema.
func requestBluetooth() {
    if CBManager.authorization == .notDetermined { poller.bluetoothWatcher.start() }
    else { open("x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") }
}
