import Foundation
import IOKit.hid

public enum Vader5BridgeMode: String, CaseIterable, Sendable {
    case monitor = "Monitor only"
    case virtualGamepad = "Virtual gamepad"
}

public enum Vader5Transport: String, CaseIterable, Sendable {
    case usbReceiver = "USB receiver"
    case bluetooth = "Bluetooth"
}

public enum Vader5BridgeStatus: Sendable, Equatable {
    case stopped
    case connecting
    case running(Vader5BridgeMode)
    case failed(String)
}

public enum Vader5Error: Error, CustomStringConvertible {
    case notFound(Vader5Transport), configInterfaceMissing, virtualDeviceCreation, handshake
    case managerOpen(IOReturn), deviceOpen(IOReturn)

    public var description: String {
        switch self {
        case .notFound(.usbReceiver): "Vader 5 Pro USB receiver not found."
        case .notFound(.bluetooth): "Bluetooth controller not found. Pair the Vader 5 Pro in Xbox-compatible mode and wake it, then try again."
        case .configInterfaceMissing: "Vader 5 Pro controller interface not found."
        case .virtualDeviceCreation: "Virtual gamepad permission is unavailable. Sign with Apple's com.apple.developer.hid.virtual.device entitlement or use Monitor only."
        case .handshake: "Controller initialization handshake failed."
        case .managerOpen(let code): "Could not open HID manager (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        case .deviceOpen(let code): "Could not open receiver (0x\(String(UInt32(bitPattern: code), radix: 16)))."
        }
    }
}

public final class Vader5Bridge {
    public var onState: (@Sendable (Vader5State) -> Void)?
    public var onStatus: (@Sendable (Vader5BridgeStatus) -> Void)?

    private var manager: IOHIDManager?
    private var configDevice: IOHIDDevice?
    private var reportBuffer: UnsafeMutablePointer<UInt8>?
    private var virtualGamepad: VirtualGamepad?
    private var activeTransport: Vader5Transport = .usbReceiver
    private var lastState: Vader5State = .neutral
    private var isRunning = false

    public init() {}

    public func start(
        mode: Vader5BridgeMode,
        transport: Vader5Transport = .usbReceiver
    ) throws {
        guard !isRunning else { return }
        onStatus?(.connecting)
        let effectiveMode: Vader5BridgeMode = transport == .bluetooth ? .monitor : mode
        activeTransport = transport
        lastState = .neutral

        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = manager
        IOHIDManagerSetDeviceMatching(manager, matchingDictionary(for: transport))

        do {
            let managerResult = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            guard managerResult == kIOReturnSuccess else { throw Vader5Error.managerOpen(managerResult) }
            guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>,
                  let device = devices.first else { throw Vader5Error.notFound(transport) }
            configDevice = device
            let deviceResult = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeNone))
            guard deviceResult == kIOReturnSuccess else { throw Vader5Error.deviceOpen(deviceResult) }

            if effectiveMode == .virtualGamepad {
                let output = VirtualGamepad()
                try output.start()
                virtualGamepad = output
            }

            reportBuffer = .allocate(capacity: 64)
            reportBuffer!.initialize(repeating: 0, count: 64)
            IOHIDDeviceRegisterInputReportCallback(
                device, reportBuffer!, 64,
                { context, result, _, _, _, report, length in
                    guard result == kIOReturnSuccess, let context else { return }
                    Unmanaged<Vader5Bridge>.fromOpaque(context)
                        .takeUnretainedValue().handle(report, length: length)
                },
                Unmanaged.passUnretained(self).toOpaque()
            )
            IOHIDDeviceScheduleWithRunLoop(
                device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            if transport == .usbReceiver { try initializeController() }
            isRunning = true
            onStatus?(.running(effectiveMode))
        } catch {
            stop()
            onStatus?(.failed(String(describing: error)))
            throw error
        }
    }

    public func stop() {
        if let configDevice {
            if activeTransport == .usbReceiver { _ = send(Vader5Protocol.stopCommand) }
            IOHIDDeviceUnscheduleFromRunLoop(
                configDevice, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(configDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        }
        if let manager { IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone)) }
        reportBuffer?.deallocate()
        reportBuffer = nil
        virtualGamepad?.stop()
        virtualGamepad = nil
        configDevice = nil
        manager = nil
        isRunning = false
        onStatus?(.stopped)
    }

    private func initializeController() throws {
        for command in Vader5Protocol.initCommands {
            guard send(command) == kIOReturnSuccess else { throw Vader5Error.handshake }
            RunLoop.current.run(until: Date().addingTimeInterval(0.06))
        }
    }

    private func matchingDictionary(for transport: Vader5Transport) -> CFDictionary {
        switch transport {
        case .usbReceiver:
            [
                kIOHIDVendorIDKey: Vader5Protocol.vendorID,
                kIOHIDProductIDKey: Vader5Protocol.productID,
                kIOHIDPrimaryUsagePageKey: Vader5Protocol.usagePage,
                kIOHIDPrimaryUsageKey: Vader5Protocol.usage,
            ] as CFDictionary
        case .bluetooth:
            [
                kIOHIDTransportKey: "Bluetooth",
                kIOHIDProductKey: Vader5Protocol.bluetoothProductName,
                kIOHIDPrimaryUsagePageKey: Vader5Protocol.bluetoothUsagePage,
                kIOHIDPrimaryUsageKey: Vader5Protocol.bluetoothUsage,
            ] as CFDictionary
        }
    }

    @discardableResult
    private func send(_ prefix: [UInt8]) -> IOReturn {
        guard let configDevice else { return kIOReturnNotOpen }
        var packet = [UInt8](repeating: 0, count: 32)
        for (index, byte) in prefix.enumerated() { packet[index] = byte }
        return packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(configDevice, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
    }

    private func handle(_ report: UnsafePointer<UInt8>, length: Int) {
        let data = UnsafeBufferPointer(start: report, count: length)
        if activeTransport == .bluetooth,
           let homePressed = Vader5Protocol.parseBluetoothHome(data) {
            var buttons = lastState.buttons
            if homePressed { buttons.insert(.home) } else { buttons.remove(.home) }
            lastState = state(lastState, replacing: buttons)
            publish(lastState)
            return
        }

        guard var parsed = activeTransport == .bluetooth
                ? Vader5Protocol.parseBluetooth(data)
                : Vader5Protocol.parse(data) else { return }
        if activeTransport == .bluetooth, lastState.buttons.contains(.home) {
            var buttons = parsed.buttons
            buttons.insert(.home)
            parsed = state(parsed, replacing: buttons)
        }
        lastState = parsed
        publish(parsed)
    }

    private func publish(_ state: Vader5State) {
        virtualGamepad?.send(state)
        onState?(state)
    }

    private func state(_ state: Vader5State, replacing buttons: Vader5Buttons) -> Vader5State {
        Vader5State(
            leftX: state.leftX, leftY: state.leftY,
            rightX: state.rightX, rightY: state.rightY,
            leftTrigger: state.leftTrigger, rightTrigger: state.rightTrigger,
            dpad: state.dpad, buttons: buttons, extraButtons: state.extraButtons,
            gyro: state.gyro, accelerometer: state.accelerometer)
    }

    deinit { stop() }
}
