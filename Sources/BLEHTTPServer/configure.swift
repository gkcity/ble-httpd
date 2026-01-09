import Vapor
import Foundation
import CoreBluetooth

public func configure(_ app: Application) throws {
    let bleManager = BLEManager()
    app.bleManager = bleManager
    
    // 注册路由
    try routes(app)
}

public func routes(_ app: Application) throws {
    app.get { req -> String in
        return """
        BLE HTTP Gateway
        ================
        
        Endpoints:
        - GET  /status                    - BLE 状态
        - POST /advertise/start           - 开始广播
        - POST /advertise/stop            - 停止广播
        - GET  /devices                   - 获取连接设备
        - POST /services                  - 添加服务
        - POST /characteristics           - 添加特征
        - GET  /characteristics           - 获取特征列表
        - POST /characteristics/value     - 更新特征值
        - GET  /characteristics/:uuid     - 获取特征值
        - POST /presets/health            - 设置健康服务
        - POST /quick-start               - 快速启动
        """
    }
    
    // BLE 状态
    app.get("status") { req -> BLEStatusResponse in
        let bleManager = req.application.bleManager
        return BLEStatusResponse(
            state: bleManager.state.rawValue,
            isAdvertising: bleManager.isAdvertising,
            connectedDevices: bleManager.connectedDevices.count,
            servicesCount: bleManager.servicesCount,
            characteristicsCount: bleManager.characteristicsCount
        )
    }
    
    // 开始广播
    app.post("advertise", "start") { req -> HTTPStatus in
        let request = try req.content.decode(StartAdvertisingRequest.self)
        let bleManager = req.application.bleManager
        
        if bleManager.startAdvertising(localName: request.deviceName,
                                       serviceUUIDs: request.serviceUUIDs) {
            return .ok
        } else {
            throw Abort(.badRequest, reason: "Failed to start advertising: \(bleManager.lastError ?? "Unknown error")")
        }
    }
    
    // 停止广播
    app.post("advertise", "stop") { req -> HTTPStatus in
        let bleManager = req.application.bleManager
        bleManager.stopAdvertising()
        return .ok
    }
    
    // 获取连接设备
    app.get("devices") { req -> [DeviceInfo] in
        let bleManager = req.application.bleManager
        return bleManager.connectedDevices.map { device in
            DeviceInfo(
                identifier: device.identifier,
                name: device.name,
                isConnected: device.isConnected,
                lastSeen: device.lastSeen
            )
        }
    }
    
    // 添加服务
    app.post("services") { req -> HTTPStatus in
        let request = try req.content.decode(AddServiceRequest.self)
        let bleManager = req.application.bleManager
        
        if bleManager.addService(uuid: request.uuid,
                                 isPrimary: request.isPrimary ?? true) {
            return .created
        } else {
            throw Abort(.badRequest, reason: "Failed to add service: \(bleManager.lastError ?? "Unknown error")")
        }
    }
    
    // 添加特征
    app.post("characteristics") { req -> HTTPStatus in
        let request = try req.content.decode(AddCharacteristicRequest.self)
        let bleManager = req.application.bleManager
        
        // 转换属性
        var properties: CBCharacteristicProperties = []
        for property in request.properties ?? [] {
            switch property.lowercased() {
            case "read": properties.insert(.read)
            case "write": properties.insert(.write)
            case "notify": properties.insert(.notify)
            case "indicate": properties.insert(.indicate)
            case "write-without-response": properties.insert(.writeWithoutResponse)
            default: break
            }
        }
        
        if properties.isEmpty {
            properties = [.read, .write, .notify]
        }
        
        // 转换权限
        var permissions: CBAttributePermissions = []
        for permission in request.permissions ?? [] {
            switch permission.lowercased() {
            case "readable": permissions.insert(.readable)
            case "writeable": permissions.insert(.writeable)
            default: break
            }
        }
        
        if permissions.isEmpty {
            permissions = [.readable, .writeable]
        }
        
        if bleManager.addCharacteristic(
            uuid: request.uuid,
            serviceUUID: request.serviceUUID,
            properties: properties,
            permissions: permissions
        ) {
            return .created
        } else {
            throw Abort(.badRequest, reason: "Failed to add characteristic: \(bleManager.lastError ?? "Unknown error")")
        }
    }
    
    // 更新特征值
    app.post("characteristics", "value") { req -> HTTPStatus in
        let request = try req.content.decode(UpdateValueRequest.self)
        let bleManager = req.application.bleManager
        
        guard let data = decodeValue(request.value, encoding: request.encoding) else {
            throw Abort(.badRequest, reason: "Invalid value encoding")
        }
        
        if bleManager.updateCharacteristicValue(
            serviceUUID: request.serviceUUID,
            characteristicUUID: request.characteristicUUID,
            data: data
        ) {
            return .ok
        } else {
            throw Abort(.badRequest, reason: "Failed to update value")
        }
    }
    
    // 预设健康服务
    app.post("presets", "health") { req -> HTTPStatus in
        let bleManager = req.application.bleManager
        
        let serviceAdded = bleManager.addService(uuid: "180D")
        
        if serviceAdded {
            _ = bleManager.addCharacteristic(
                uuid: "2A37",
                serviceUUID: "180D",
                properties: [.notify],
                permissions: [.readable]
            )
            
            _ = bleManager.addCharacteristic(
                uuid: "2A38",
                serviceUUID: "180D",
                properties: [.read],
                permissions: [.readable]
            )
            
            return .created
        } else {
            throw Abort(.internalServerError, reason: "Failed to add health service")
        }
    }
    
    // 快速启动
    app.post("quick-start") { req -> HTTPStatus in
        let bleManager = req.application.bleManager
        
        _ = bleManager.addService(uuid: "180D")
        
        _ = bleManager.addCharacteristic(
            uuid: "2A37",
            serviceUUID: "180D",
            properties: [.notify, .read],
            permissions: [.readable]
        )
        
        if bleManager.startAdvertising(localName: "BLE-HTTP-Gateway", serviceUUIDs: ["180D"]) {
            return .ok
        } else {
            throw Abort(.badRequest, reason: "Failed to start advertising")
        }
    }
}

// MARK: - 数据模型
public struct StartAdvertisingRequest: Content {
    public let deviceName: String
    public let serviceUUIDs: [String]?
    
    public init(deviceName: String, serviceUUIDs: [String]? = nil) {
        self.deviceName = deviceName
        self.serviceUUIDs = serviceUUIDs
    }
}

public struct AddServiceRequest: Content {
    public let uuid: String
    public let isPrimary: Bool?
    
    public init(uuid: String, isPrimary: Bool? = nil) {
        self.uuid = uuid
        self.isPrimary = isPrimary
    }
}

public struct AddCharacteristicRequest: Content {
    public let uuid: String
    public let serviceUUID: String
    public let properties: [String]?
    public let permissions: [String]?
    
    public init(uuid: String, serviceUUID: String, properties: [String]? = nil, permissions: [String]? = nil) {
        self.uuid = uuid
        self.serviceUUID = serviceUUID
        self.properties = properties
        self.permissions = permissions
    }
}

public struct UpdateValueRequest: Content {
    public let serviceUUID: String
    public let characteristicUUID: String
    public let value: String
    public let encoding: String?
    
    public init(serviceUUID: String, characteristicUUID: String, value: String, encoding: String? = nil) {
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        self.value = value
        self.encoding = encoding
    }
}

public struct BLEStatusResponse: Content {
    public let state: String
    public let isAdvertising: Bool
    public let connectedDevices: Int
    public let servicesCount: Int
    public let characteristicsCount: Int
    
    public init(state: String, isAdvertising: Bool, connectedDevices: Int, servicesCount: Int, characteristicsCount: Int) {
        self.state = state
        self.isAdvertising = isAdvertising
        self.connectedDevices = connectedDevices
        self.servicesCount = servicesCount
        self.characteristicsCount = characteristicsCount
    }
}

public struct DeviceInfo: Content {
    public let identifier: String
    public let name: String?
    public let isConnected: Bool
    public let lastSeen: Date
    
    public init(identifier: String, name: String?, isConnected: Bool, lastSeen: Date) {
        self.identifier = identifier
        self.name = name
        self.isConnected = isConnected
        self.lastSeen = lastSeen
    }
}

// MARK: - Application 扩展
extension Application {
    struct BLEManagerKey: StorageKey {
        typealias Value = BLEManager
    }
    
    public var bleManager: BLEManager {
        get {
            guard let manager = storage[BLEManagerKey.self] else {
                let manager = BLEManager()
                storage[BLEManagerKey.self] = manager
                return manager
            }
            return manager
        }
        set {
            storage[BLEManagerKey.self] = newValue
        }
    }
}

// MARK: - 辅助函数
private func decodeValue(_ value: String, encoding: String?) -> Data? {
    switch encoding?.lowercased() {
    case "base64":
        return Data(base64Encoded: value)
    case "hex":
        var data = Data()
        var temp = ""
        for char in value {
            temp.append(char)
            if temp.count == 2 {
                if let byte = UInt8(temp, radix: 16) {
                    data.append(byte)
                }
                temp = ""
            }
        }
        return data
    case "utf8", nil:
        return value.data(using: .utf8)
    default:
        return nil
    }
}
