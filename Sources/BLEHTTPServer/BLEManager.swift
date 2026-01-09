import Foundation
import CoreBluetooth

public enum BLEState: String, Codable {
    case poweredOff = "Powered Off"
    case poweredOn = "Powered On"
    case unauthorized = "Unauthorized"
    case unknown = "Unknown"
    case resetting = "Resetting"
    case unsupported = "Unsupported"
}

public struct ConnectedDevice: Codable {
    public let identifier: String
    public let name: String?
    public let services: [String]
    public let isConnected: Bool
    public let lastSeen: Date
    
    public init(identifier: String, name: String?, services: [String], isConnected: Bool, lastSeen: Date) {
        self.identifier = identifier
        self.name = name
        self.services = services
        self.isConnected = isConnected
        self.lastSeen = lastSeen
    }
}

public class BLEManager: NSObject {
    
    // MARK: - 公开属性
    public var state: BLEState = .unknown
    public var isAdvertising = false
    public var connectedDevices: [ConnectedDevice] = []
    public var lastError: String?
    
    public var servicesCount: Int { return services.count }
    public var characteristicsCount: Int { return characteristics.count }
    
    // MARK: - BLE 属性
    private var peripheralManager: CBPeripheralManager!
    private var connectedCentrals: [CBCentral] = []
    
    // 服务配置
    private var services: [CBMutableService] = []
    private var characteristics: [String: CBMutableCharacteristic] = [:] // key: uuid字符串
    
    // 数据存储
    private var characteristicValues: [String: Data] = [:] // key: "serviceUUID_characteristicUUID"
    
    // 回调处理器
    public var onDataReceived: ((String, String, Data) -> Void)? // serviceUUID, characteristicUUID, data
    public var onDeviceConnected: ((String, String?) -> Void)?
    public var onDeviceDisconnected: ((String, String?) -> Void)?
    
    // MARK: - 初始化
    public override init() {
        super.init()
        peripheralManager = CBPeripheralManager(delegate: self, queue: .main)
    }
    
    // MARK: - 服务配置
    public func addService(uuid: String, isPrimary: Bool = true) -> Bool {
        let cbUUID = CBUUID(string: uuid)
        let service = CBMutableService(type: cbUUID, primary: isPrimary)
        services.append(service)
        peripheralManager.add(service)
        return true
    }
    
    public func addCharacteristic(
        uuid: String,
        serviceUUID: String,
        properties: CBCharacteristicProperties = [.read, .write, .notify],
        permissions: CBAttributePermissions = [.readable, .writeable]
    ) -> Bool {
        
        let charUUID = CBUUID(string: uuid)
        guard let service = services.first(where: {
            $0.uuid.uuidString.lowercased() == serviceUUID.lowercased()
        }) else {
            lastError = "Service not found or invalid UUID"
            return false
        }
        
        let characteristic = CBMutableCharacteristic(
            type: charUUID,
            properties: properties,
            value: nil,
            permissions: permissions
        )
        
        characteristics[uuid] = characteristic
        
        if service.characteristics == nil {
            service.characteristics = [characteristic]
        } else {
            service.characteristics?.append(characteristic)
        }
        
        // 重新添加服务以更新特征
        peripheralManager.removeAllServices()
        for service in services {
            peripheralManager.add(service)
        }
        
        return true
    }
    
    // MARK: - 广播控制
    public func startAdvertising(
        localName: String,
        serviceUUIDs: [String]? = nil
    ) -> Bool {
        
        guard peripheralManager.state == .poweredOn else {
            lastError = "Bluetooth is not powered on"
            return false
        }
        
        var advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: localName
        ]
        
        if let uuids = serviceUUIDs?.compactMap({ CBUUID(string: $0) }), !uuids.isEmpty {
            advertisementData[CBAdvertisementDataServiceUUIDsKey] = uuids
        }
        
        peripheralManager.startAdvertising(advertisementData)
        isAdvertising = true
        return true
    }
    
    public func stopAdvertising() {
        peripheralManager.stopAdvertising()
        isAdvertising = false
    }
    
    // MARK: - 数据发送
    public func updateCharacteristicValue(
        serviceUUID: String,
        characteristicUUID: String,
        data: Data,
        for central: CBCentral? = nil
    ) -> Bool {
        
        let key = "\(serviceUUID)_\(characteristicUUID)"
        characteristicValues[key] = data
        
        guard let characteristic = characteristics[characteristicUUID] else {
            return false
        }
        
        characteristic.value = data
        return peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: central != nil ? [central!] : nil)
    }
    
    // MARK: - 数据查询
    public func getCharacteristicValue(serviceUUID: String, characteristicUUID: String) -> Data? {
        let key = "\(serviceUUID)_\(characteristicUUID)"
        return characteristicValues[key]
    }
    
    public func getServices() -> [String] {
        return services.map { $0.uuid.uuidString }
    }
    
    public func getCharacteristics() -> [String] {
        return Array(characteristics.keys)
    }
}

// MARK: - CBPeripheralManagerDelegate
extension BLEManager: CBPeripheralManagerDelegate {
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        switch peripheral.state {
        case .poweredOn:
            state = .poweredOn
        case .poweredOff:
            state = .poweredOff
            isAdvertising = false
        case .unauthorized:
            state = .unauthorized
        case .unknown:
            state = .unknown
        case .resetting:
            state = .resetting
        case .unsupported:
            state = .unsupported
        @unknown default:
            state = .unknown
        }
        print("BLE State: \(state.rawValue)")
    }
    
    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            lastError = "Advertising failed: \(error.localizedDescription)"
            isAdvertising = false
        } else {
            print("Started advertising successfully")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            lastError = "Failed to add service: \(error.localizedDescription)"
        } else {
            print("Service added: \(service.uuid.uuidString)")
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let device = ConnectedDevice(
            identifier: central.identifier.uuidString,
            name: nil,
            services: [],
            isConnected: true,
            lastSeen: Date()
        )
        
        if !connectedDevices.contains(where: { $0.identifier == device.identifier }) {
            connectedDevices.append(device)
        }
        
        onDeviceConnected?(central.identifier.uuidString, nil)
        print("Device subscribed: \(central.identifier.uuidString)")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        connectedDevices.removeAll { $0.identifier == central.identifier.uuidString }
        onDeviceDisconnected?(central.identifier.uuidString, nil)
        print("Device unsubscribed: \(central.identifier.uuidString)")
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) {
        guard let characteristic = request.characteristic as? CBMutableCharacteristic else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
            return
        }
        
        if let data = characteristic.value {
            request.value = data
            peripheral.respond(to: request, withResult: .success)
            print("Read request handled for \(characteristic.uuid.uuidString)")
        } else {
            peripheral.respond(to: request, withResult: .attributeNotFound)
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            guard let data = request.value,
                  let characteristic = request.characteristic as? CBMutableCharacteristic else {
                peripheral.respond(to: request, withResult: .attributeNotFound)
                continue
            }
            
            if let service = services.first(where: {
                $0.characteristics?.contains(characteristic) ?? false
            }) {
                let key = "\(service.uuid.uuidString)_\(characteristic.uuid.uuidString)"
                characteristicValues[key] = data
                onDataReceived?(service.uuid.uuidString, characteristic.uuid.uuidString, data)
                print("Received write: \(String(data: data, encoding: .utf8) ?? "Binary data")")
            }
            
            peripheral.respond(to: request, withResult: .success)
        }
    }
    
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("Ready to update subscribers")
    }
}
