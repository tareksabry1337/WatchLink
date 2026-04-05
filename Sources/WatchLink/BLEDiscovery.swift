import Foundation
@preconcurrency import CoreBluetooth
import WatchLinkCore

package actor BLEDiscovery {
    private let serviceUUID: CBUUID
    private let ipCharacteristicUUID: CBUUID
    private let delegate: CentralDelegate
    private let centralManager: CBCentralManager

    package init(
        serviceUUID: UUID,
        ipCharacteristicUUID: UUID
    ) {
        self.serviceUUID = CBUUID(nsuuid: serviceUUID)
        self.ipCharacteristicUUID = CBUUID(nsuuid: ipCharacteristicUUID)
        self.delegate = CentralDelegate()
        self.centralManager = CBCentralManager(delegate: delegate, queue: nil)
    }

    package func startScanning() -> AsyncStream<String> {
        let serviceCBUUID = serviceUUID
        let ipCBUUID = ipCharacteristicUUID
        let manager = centralManager

        delegate.serviceUUID = serviceCBUUID
        delegate.ipCharacteristicUUID = ipCBUUID
        delegate.centralManager = manager

        return AsyncStream { continuation in
            delegate.onIPDiscovered = { ip in
                continuation.yield(ip)
            }

            delegate.onPoweredOn = {
                manager.scanForPeripherals(
                    withServices: [serviceCBUUID],
                    options: nil
                )
            }

            if manager.state == .poweredOn {
                delegate.onPoweredOn?()
            }

            continuation.onTermination = { _ in
                manager.stopScan()
            }
        }
    }

    package func stopScanning() {
        centralManager.stopScan()
    }
}

private final class CentralDelegate: NSObject,
    CBCentralManagerDelegate,
    CBPeripheralDelegate,
    @unchecked Sendable
{
    var onIPDiscovered: (@Sendable (String) -> Void)?
    var onPoweredOn: (() -> Void)?
    var serviceUUID: CBUUID?
    var ipCharacteristicUUID: CBUUID?
    weak var centralManager: CBCentralManager?
    private var discoveredPeripheral: CBPeripheral?

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            onPoweredOn?()
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        discoveredPeripheral = peripheral
        peripheral.delegate = self
        central.stopScan()
        central.connect(peripheral, options: nil)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        let filter = serviceUUID.map { [$0] }
        peripheral.discoverServices(filter)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        discoveredPeripheral = nil
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        discoveredPeripheral = nil
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        let charFilter = ipCharacteristicUUID.map { [$0] }
        for service in services {
            peripheral.discoverCharacteristics(charFilter, for: service)
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics {
            if characteristic.uuid == ipCharacteristicUUID {
                peripheral.readValue(for: characteristic)
                peripheral.setNotifyValue(true, for: characteristic)
            }
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard characteristic.uuid == ipCharacteristicUUID,
              let data = characteristic.value,
              let ip = String(data: data, encoding: .utf8)
        else { return }
        onIPDiscovered?(ip)
    }
}
