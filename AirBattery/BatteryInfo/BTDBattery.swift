//
//  BTDBattery.swift
//  AirBattery
//
//  Created by apple on 2024/6/23.
//

import SwiftUI
import Foundation
import IOBluetooth

private struct BluetoothLogDevice: Decodable {
    let time: String
    let type: String
    let mac: String
    let name: String
    let level: Int
    let status: String
}

class BTDBattery {
    var scanTimer: Timer?
    static var allDevices = [String]()
    @AppStorage("readBTHID") var readBTHID = true
    
    func startScan() {
        let interval = TimeInterval(59 * updateInterval)
        scanTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(scanDevices), userInfo: nil, repeats: true)
        print("ℹ️ Start scanning Bluetooth HID devices...")
        scanDevices(longScan: true)
    }
    
    @objc func scanDevices(longScan: Bool = false) {
        Thread.detachNewThread {
            if self.readBTHID {
                if longScan { BTDBattery.getOtherDevice(last: "2h", timeout: 25) }
                let connects = BTDBattery.getConnected()
                let names = BTDBattery.allDevices.filter({ connects.contains($0) })
                for name in names {
                    if var device = AirBatteryModel.getByName(name) {
                        device.lastUpdate = Date().timeIntervalSince1970
                        AirBatteryModel.updateDevice(device)
                    }
                }
            }
        }
    }
    
    static func getConnected(mac: Bool = false) -> [String]{
        guard var bluetoothDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return [] }
        bluetoothDevices = bluetoothDevices.filter({ $0.isConnected() })
        if mac {
            let devices = bluetoothDevices.map({ ($0.addressString ?? "").uppercased().replacingOccurrences(of: "-", with: ":") })
            return devices.filter({ $0 != "" })
        }
        return bluetoothDevices.map({ $0.name ?? "" }).filter({ $0 != "" })
    }
    
    static func getOtherDevice(last: String = "10m", timeout: Int = 0) {
        let parent = ud.string(forKey: "deviceName") ?? "Mac"
        guard let resourcePath = Bundle.main.resourcePath,
              let result = process(path: "/bin/bash", arguments: ["\(resourcePath)/logReader.sh", "mac", last], timeout: timeout) else { return }

        let connected = getConnected(mac: true)
        var latestDevices = [String: BluetoothLogDevice]()
        var deviceOrder = [String]()

        for line in result.split(separator: "\n") {
            guard let device = try? JSONDecoder().decode(BluetoothLogDevice.self, from: Data(line.utf8)) else { continue }

            let identifier = "\(device.name)\u{0}\(device.mac)\u{0}\(device.type)"
            if latestDevices[identifier] == nil {
                deviceOrder.append(identifier)
            }
            latestDevices[identifier] = device
        }

        for identifier in deviceOrder {
            guard let device = latestDevices[identifier] else { continue }

            let mac = device.mac
            var name = device.name
            let type = device.type
            let level = device.level
            let status = device.status == "+" ? 1 : 0
            if name == "" { name = "\(type) (\(mac))" }
            if connected.contains(mac) {
                if let index = allDevices.firstIndex(of: name) { allDevices[index] = name } else { allDevices.append(name) }
                AirBatteryModel.updateDevice(Device(deviceID: mac, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: parent, lastUpdate: Date().timeIntervalSince1970, realUpdate: isoFormatter.date(from: device.time)?.timeIntervalSince1970 ?? 0.0))
            }/* else {
                if let index = allDevices.firstIndex(of: name) { allDevices.remove(at: index) }
                AirBatteryModel.updateDevice(Device(deviceID: mac, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: parent, lastUpdate: Date(timeIntervalSince1970: 0).timeIntervalSince1970))
            }*/
        }
        
        /*guard let result = process(path: "\(Bundle.main.resourcePath!)/hidpp/bin/hidpp-list-devices", arguments: []) else { return }
        let devices = result.components(separatedBy: "\n")
        for device in devices {
            if let json = try? JSONSerialization.jsonObject(with: Data(device.utf8), options: []) as? [String: Any] {
                if var name = json["name"] as? String, let pid = json["pid"] as? String,
                   let status = json["status"] as? Int, let level = json["level"] as? Int {
                    if name == "" { name = getDeviceName("0x\(pid.uppercased())", "Logitech Device") }
                    let type = getDeviceTypeWithPID("0x\(pid.uppercased())", "hid")
                    if !(status == 1 && level == 0) {
                        AirBatteryModel.updateDevice(Device(deviceID: pid, deviceType: type, deviceName: name, batteryLevel: min(100, max(0, level)), isCharging: status, parentName: deviceName, lastUpdate: Date().timeIntervalSince1970))
                    }
                }
            }
        }*/
    }
}
