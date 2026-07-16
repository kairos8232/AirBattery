//
//  AirBatteryModel.swift
//  AirBattery
//
//  Created by apple on 2024/2/6.
//
import SwiftUI
import Foundation

class IDeviceBattery {
    static var shared: IDeviceBattery = IDeviceBattery()
    
    //var scanTimer: Timer?
    @AppStorage("readPencil") var readPencil = false
    @AppStorage("readIDevice") var readIDevice = true
    @AppStorage("updateInterval") var updateInterval = 1
    
    func startScan() {
        //let interval = TimeInterval(5.0)
        //scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning iDevice devices...")
        scanDevices()
    }
    
    @objc func scanDevices() {
        Thread.detachNewThread {
            if !self.readIDevice { return }
            self.getIDeviceBattery()
        }
    }
    
    func getPencil(d: Device, type: String = "") {
        if d.deviceType == "iPad" && readPencil {
            Thread.detachNewThread {
                guard let resourcePath = Bundle.main.resourcePath else { return }
                if let result = process(path: "/bin/bash", arguments: ["\(resourcePath)/logReader.sh", "\(resourcePath)/libimobiledevice/bin/idevicesyslog", type, d.deviceID], timeout: 11 * self.updateInterval) {
                    if let json = try? JSONSerialization.jsonObject(with: Data(result.utf8), options: []) as? [String: Any] {
                        if let level = json["level"] as? Int, let model = json["model"] as? String, let vendor = json["vendor"] as? String {
                            let status = (json["status"] as? Int) ?? 0
                            print("ℹ️ Pencil of \(d.deviceName): \(result)")
                            AirBatteryModel.updateDevice(Device(deviceID: "Pencil_"+d.deviceID, deviceType: vendor == "Apple" ? "ApplePencil" : "Pencil", deviceName: vendor == "Apple" ? "Apple Pencil".local : "Pencil".local, deviceModel: model, batteryLevel: level, isCharging: status, parentName: d.deviceName, lastUpdate: Date().timeIntervalSince1970))
                        }
                    }
                }
            }
        }
    }
    
    func getIDeviceBattery() {
        guard let resourcePath = Bundle.main.resourcePath else { return }

        if let result = process(path: "\(resourcePath)/libimobiledevice/bin/idevice_id", arguments: ["-n"]) {
            for id in deviceIDs(from: result) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "-n") }
                    getPencil(d: d, type: "-n")
                } else {
                    writeBatteryInfo(id, "-n")
                }
            }
        }
        if let result = process(path: "\(resourcePath)/libimobiledevice/bin/idevice_id", arguments: ["-l"]) {
            for id in deviceIDs(from: result) {
                if let d = AirBatteryModel.getByID(id) {
                    if (Double(Date().timeIntervalSince1970) - d.lastUpdate) > Double(60 * updateInterval) { writeBatteryInfo(id, "") }
                    getPencil(d: d)
                } else {
                    writeBatteryInfo(id, "")
                }
            }
        }
    }
    
    func writeBatteryInfo(_ id: String, _ connectType: String) {
        guard !id.isEmpty, let resourcePath = Bundle.main.resourcePath else { return }

        let lastUpdate = Date().timeIntervalSince1970
        if connectType == "" { _ = process(path: "\(resourcePath)/libimobiledevice/bin/wificonnection", arguments: ["-u", id, "true"]) }
        if let deviceInfo = process(path: "\(resourcePath)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id]){
            let i = deviceInfo.components(separatedBy: .newlines)
            if let deviceName = value(for: "DeviceName", in: i),
               let model = value(for: "ProductType", in: i),
               let type = value(for: "DeviceClass", in: i) {
                if let batteryInfo = process(path: "\(resourcePath)/libimobiledevice/bin/ideviceinfo", arguments: [connectType, "-u", id, "-q", "com.apple.mobile.battery"]) {
                    let b = batteryInfo.components(separatedBy: .newlines)
                    if let level = value(for: "BatteryCurrentCapacity", in: b),
                       let charging = value(for: "BatteryIsCharging", in: b),
                       let batteryLevel = Int(level),
                       let isCharging = Bool(charging) {
                        AirBatteryModel.updateDevice(Device(deviceID: id, deviceType: type, deviceName: deviceName, deviceModel: model, batteryLevel: batteryLevel, isCharging: isCharging ? 1 : 0, lastUpdate: lastUpdate))
                        if let watchInfo = process(path: "\(resourcePath)/libimobiledevice/bin/comptest", arguments: [id]) {
                            let w = watchInfo.components(separatedBy: .newlines)
                            if let watchID = w.first(where: { $0.hasPrefix("Checking watch") })?.split(separator: " ").last.map(String.init),
                               let watchName = value(for: "DeviceName", in: w),
                               let watchModel = value(for: "ProductType", in: w),
                               let watchLevel = value(for: "BatteryCurrentCapacity", in: w),
                               let watchCharging = value(for: "BatteryIsCharging", in: w),
                               let watchBatteryLevel = Int(watchLevel),
                               let isWatchCharging = Bool(watchCharging) {
                                AirBatteryModel.updateDevice(Device(deviceID: watchID, deviceType: "Watch", deviceName: watchName, deviceModel: watchModel, batteryLevel: watchBatteryLevel, isCharging: isWatchCharging ? 1 : 0, parentName: deviceName, lastUpdate: lastUpdate))
                            }
                        }
                    }
                }
            }
        }
    }

    private func deviceIDs(from output: String) -> [String] {
        output.split(whereSeparator: { $0.isNewline }).map(String.init)
    }

    private func value(for key: String, in lines: [String]) -> String? {
        guard let line = lines.first(where: { $0.hasPrefix("\(key):") }),
              let separator = line.firstIndex(of: ":") else { return nil }

        return line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
    }
}
