import Foundation
import IOKit.hid

@_silgen_name("V5VirtualHIDCreate")
private func V5VirtualHIDCreate(_ properties: CFDictionary) -> UnsafeMutableRawPointer?
@_silgen_name("V5VirtualHIDHandleReport")
private func V5VirtualHIDHandleReport(_ device: UnsafeMutableRawPointer,
                                      _ report: UnsafePointer<UInt8>, _ length: Int) -> Int32
@_silgen_name("V5VirtualHIDRelease")
private func V5VirtualHIDRelease(_ device: UnsafeMutableRawPointer)

private let flydigiVID = 0x37d7
private let vader5PID = 0x2401

private let gamepadDescriptor: [UInt8] = [
    0x05, 0x01,       // Usage Page (Generic Desktop)
    0x09, 0x05,       // Usage (Game Pad)
    0xA1, 0x01,       // Collection (Application)
    0x85, 0x01,       //   Report ID (1)
    0x05, 0x09,       //   Usage Page (Button)
    0x19, 0x01,       //   Usage Minimum (1)
    0x29, 0x10,       //   Usage Maximum (16)
    0x15, 0x00,       //   Logical Minimum (0)
    0x25, 0x01,       //   Logical Maximum (1)
    0x75, 0x01,       //   Report Size (1)
    0x95, 0x10,       //   Report Count (16)
    0x81, 0x02,       //   Input (Data, Variable, Absolute)
    0x05, 0x01,       //   Usage Page (Generic Desktop)
    0x09, 0x39,       //   Usage (Hat Switch)
    0x15, 0x00,       //   Logical Minimum (0)
    0x25, 0x07,       //   Logical Maximum (7)
    0x35, 0x00,       //   Physical Minimum (0)
    0x46, 0x3B, 0x01, //   Physical Maximum (315)
    0x65, 0x14,       //   Unit (Degrees)
    0x75, 0x04,       //   Report Size (4)
    0x95, 0x01,       //   Report Count (1)
    0x81, 0x42,       //   Input (Data, Variable, Absolute, Null)
    0x75, 0x04,       //   Report Size (4)
    0x95, 0x01,       //   Report Count (1)
    0x81, 0x03,       //   Input (Constant)
    0x09, 0x30,       //   Usage (X)
    0x09, 0x31,       //   Usage (Y)
    0x09, 0x33,       //   Usage (Rx)
    0x09, 0x34,       //   Usage (Ry)
    0x16, 0x01, 0x80, //   Logical Minimum (-32767)
    0x26, 0xFF, 0x7F, //   Logical Maximum (32767)
    0x75, 0x10,       //   Report Size (16)
    0x95, 0x04,       //   Report Count (4)
    0x81, 0x02,       //   Input (Data, Variable, Absolute)
    0x09, 0x32,       //   Usage (Z / left trigger)
    0x09, 0x35,       //   Usage (Rz / right trigger)
    0x15, 0x00,       //   Logical Minimum (0)
    0x26, 0xFF, 0x00, //   Logical Maximum (255)
    0x75, 0x08,       //   Report Size (8)
    0x95, 0x02,       //   Report Count (2)
    0x81, 0x02,       //   Input (Data, Variable, Absolute)
    0xC0              // End Collection
]

private final class Vader5Bridge {
    private let manager: IOHIDManager
    private var configDevice: IOHIDDevice?
    private var virtualDevice: UnsafeMutableRawPointer?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var reportCount = 0

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    func start() throws {
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: flydigiVID,
            kIOHIDProductIDKey: vader5PID,
            kIOHIDPrimaryUsagePageKey: 0xffa0,
            kIOHIDPrimaryUsageKey: 1
        ] as CFDictionary)

        let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard managerResult == kIOReturnSuccess else { throw BridgeError.managerOpen(managerResult) }
        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            throw BridgeError.notFound
        }

        for device in devices {
            let page = (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? NSNumber)?.intValue
            if page == 0xffa0 { configDevice = device }
        }
        guard let configDevice else { throw BridgeError.configInterfaceMissing }

        let physicalResult = IOHIDDeviceOpen(configDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard physicalResult == kIOReturnSuccess else { throw BridgeError.deviceOpen(physicalResult) }

        virtualDevice = createVirtualGamepad()
        guard virtualDevice != nil else { throw BridgeError.virtualDeviceCreation }

        reportBuffer = .allocate(capacity: 64)
        reportBuffer!.initialize(repeating: 0, count: 64)
        IOHIDDeviceRegisterInputReportCallback(
            configDevice, reportBuffer!, 64,
            { context, result, _, _, _, report, length in
                guard result == kIOReturnSuccess, let context else { return }
                let bridge = Unmanaged<Vader5Bridge>.fromOpaque(context).takeUnretainedValue()
                bridge.handlePhysicalReport(report, length: length)
            },
            Unmanaged.passUnretained(self).toOpaque()
        )
        IOHIDDeviceScheduleWithRunLoop(configDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        try initializeController()
        print("Vader 5 Pro connected; virtual gamepad is active. Press Control-C to stop.")
    }

    func stop() {
        if let configDevice {
            send([0x5a, 0xa5, 0x11, 0x07, 0xff, 0x00, 0xff, 0xff, 0xff, 0x14])
            IOHIDDeviceUnscheduleFromRunLoop(configDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(configDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        reportBuffer?.deallocate()
        reportBuffer = nil
        if let virtualDevice { V5VirtualHIDRelease(virtualDevice) }
        virtualDevice = nil
    }

    private func createVirtualGamepad() -> UnsafeMutableRawPointer? {
        let properties: [String: Any] = [
            kIOHIDReportDescriptorKey: Data(gamepadDescriptor),
            kIOHIDTransportKey: "Virtual",
            kIOHIDManufacturerKey: "Open-source Flydigi bridge",
            kIOHIDProductKey: "Vader 5 Pro Virtual Gamepad",
            kIOHIDVendorIDKey: flydigiVID,
            kIOHIDProductIDKey: vader5PID,
            kIOHIDVersionNumberKey: 1,
            kIOHIDSerialNumberKey: "VADER5-MACOS"
        ]
        return V5VirtualHIDCreate(properties as CFDictionary)
    }

    private func initializeController() throws {
        let commands: [[UInt8]] = [
            [0x5a, 0xa5, 0x01, 0x02, 0x03],
            [0x5a, 0xa5, 0xa1, 0x02, 0xa3],
            [0x5a, 0xa5, 0x02, 0x02, 0x04],
            [0x5a, 0xa5, 0x04, 0x02, 0x06],
            [0x5a, 0xa5, 0x11, 0x07, 0xff, 0x01, 0xff, 0xff, 0xff, 0x15]
        ]
        for command in commands {
            guard send(command) == kIOReturnSuccess else { throw BridgeError.handshake }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
    }

    @discardableResult
    private func send(_ prefix: [UInt8]) -> IOReturn {
        guard let configDevice else { return kIOReturnNotOpen }
        var packet = [UInt8](repeating: 0, count: 32)
        for (index, byte) in prefix.enumerated() { packet[index] = byte }
        return packet.withUnsafeBytes {
            IOHIDDeviceSetReport(configDevice, kIOHIDReportTypeOutput, 0,
                                 $0.bindMemory(to: UInt8.self).baseAddress!, packet.count)
        }
    }

    private func handlePhysicalReport(_ bytes: UnsafePointer<UInt8>, length: Int) {
        guard length >= 29, bytes[0] == 0x5a, bytes[1] == 0xa5, bytes[2] == 0xef,
              let virtualDevice else { return }

        func s16(_ offset: Int) -> Int16 {
            Int16(bitPattern: UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8))
        }
        func put16(_ value: Int16, into output: inout [UInt8], at offset: Int) {
            let raw = UInt16(bitPattern: value)
            output[offset] = UInt8(raw & 0xff)
            output[offset + 1] = UInt8(raw >> 8)
        }

        let b11 = bytes[11]
        let b12 = bytes[12]
        let ext = bytes[13]
        let ext2 = bytes[14]
        var buttons: UInt16 = 0
        func button(_ index: Int, _ pressed: Bool) { if pressed { buttons |= 1 << index } }
        button(0, b11 & 0x10 != 0) // A
        button(1, b11 & 0x20 != 0) // B
        button(2, b11 & 0x80 != 0) // X
        button(3, b12 & 0x01 != 0) // Y
        button(4, b12 & 0x04 != 0) // LB
        button(5, b12 & 0x08 != 0) // RB
        button(6, b11 & 0x40 != 0) // Select
        button(7, b12 & 0x02 != 0) // Start
        button(8, b12 & 0x40 != 0) // L3
        button(9, b12 & 0x80 != 0) // R3
        button(10, ext & 0x04 != 0) // M1
        button(11, ext & 0x08 != 0) // M2
        button(12, ext & 0x10 != 0) // M3
        button(13, ext & 0x20 != 0) // M4
        button(14, ext2 & 0x08 != 0) // Home
        button(15, ext2 & 0x01 != 0) // O/Fn

        let dpadLookup: [UInt8] = [8, 0, 2, 1, 4, 8, 3, 8, 6, 7, 8, 8, 5, 8, 8, 8]
        let hat = dpadLookup[Int(b11 & 0x0f)]
        var report = [UInt8](repeating: 0, count: 14)
        report[0] = 1
        report[1] = UInt8(buttons & 0xff)
        report[2] = UInt8(buttons >> 8)
        report[3] = hat
        put16(s16(3), into: &report, at: 4)
        let leftY = Int16(clamping: -Int(s16(5)))
        let rightY = Int16(clamping: -Int(s16(9)))
        put16(leftY, into: &report, at: 6)
        put16(s16(7), into: &report, at: 8)
        put16(rightY, into: &report, at: 10)
        report[12] = bytes[15]
        report[13] = bytes[16]

        let result = report.withUnsafeBytes {
            V5VirtualHIDHandleReport(virtualDevice, $0.bindMemory(to: UInt8.self).baseAddress!, report.count)
        }
        reportCount += 1
        if reportCount == 1 {
            print(result == kIOReturnSuccess ? "Input forwarding started." : "Virtual report failed: 0x\(String(UInt32(bitPattern: result), radix: 16))")
        }
    }
}

private enum BridgeError: Error, CustomStringConvertible {
    case notFound, configInterfaceMissing, virtualDeviceCreation, handshake
    case managerOpen(IOReturn), deviceOpen(IOReturn)
    var description: String {
        switch self {
        case .notFound: return "Vader 5 Pro dongle not found."
        case .configInterfaceMissing: return "Vader 5 Pro configuration HID interface not found."
        case .virtualDeviceCreation: return "Could not create the virtual gamepad. This build must be signed with Apple's com.apple.developer.hid.virtual.device entitlement."
        case .handshake: return "The controller initialization handshake failed."
        case .managerOpen(let code): return "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code): return "Could not open dongle (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        }
    }
}

private let bridge = Vader5Bridge()
signal(SIGINT) { _ in CFRunLoopStop(CFRunLoopGetMain()) }
signal(SIGTERM) { _ in CFRunLoopStop(CFRunLoopGetMain()) }
do {
    try bridge.start()
    CFRunLoopRun()
    bridge.stop()
} catch {
    FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8)!)
    bridge.stop()
    exit(1)
}
