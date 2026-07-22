import Foundation

public enum Vader5Protocol {
    public static let vendorID = 0x37d7
    public static let productID = 0x2401
    public static let usagePage = 0xffa0
    public static let usage = 1
    public static let bluetoothProductName = "Xbox Wireless Controller"
    public static let bluetoothUsagePage = 0x01
    public static let bluetoothUsage = 0x05

    public static let firmwareQueryCommand: [UInt8] = [0x5a, 0xa5, 0x01, 0x02, 0x03]

    static let initCommands: [[UInt8]] = [
        firmwareQueryCommand,
        [0x5a, 0xa5, 0xa1, 0x02, 0xa3],
        [0x5a, 0xa5, 0x02, 0x02, 0x04],
        [0x5a, 0xa5, 0x04, 0x02, 0x06],
        [0x5a, 0xa5, 0x11, 0x07, 0xff, 0x01, 0xff, 0xff, 0xff, 0x15],
    ]

    static let stopCommand: [UInt8] =
        [0x5a, 0xa5, 0x11, 0x07, 0xff, 0x00, 0xff, 0xff, 0xff, 0x14]

    public static func parse(_ data: UnsafeBufferPointer<UInt8>) -> Vader5State? {
        guard data.count >= 29,
              data[0] == 0x5a, data[1] == 0xa5, data[2] == 0xef else { return nil }

        func s16(_ offset: Int) -> Int16 {
            Int16(bitPattern: UInt16(data[offset]) | UInt16(data[offset + 1]) << 8)
        }
        let b11 = data[11]
        let b12 = data[12]
        let ext = data[13]
        let ext2 = data[14]
        var buttons: Vader5Buttons = []
        func set(_ button: Vader5Buttons, when pressed: Bool) {
            if pressed { buttons.insert(button) }
        }
        set(.a, when: b11 & 0x10 != 0)
        set(.b, when: b11 & 0x20 != 0)
        set(.x, when: b11 & 0x80 != 0)
        set(.y, when: b12 & 0x01 != 0)
        set(.leftBumper, when: b12 & 0x04 != 0)
        set(.rightBumper, when: b12 & 0x08 != 0)
        set(.select, when: b11 & 0x40 != 0)
        set(.start, when: b12 & 0x02 != 0)
        set(.leftStick, when: b12 & 0x40 != 0)
        set(.rightStick, when: b12 & 0x80 != 0)
        set(.m1, when: ext & 0x04 != 0)
        set(.m2, when: ext & 0x08 != 0)
        set(.m3, when: ext & 0x10 != 0)
        set(.m4, when: ext & 0x20 != 0)
        set(.home, when: ext2 & 0x08 != 0)
        set(.function, when: ext2 & 0x01 != 0)
        set(.leftMacro, when: ext & 0x40 != 0)
        set(.rightMacro, when: ext & 0x80 != 0)

        let dpadMap: [UInt8] = [8, 0, 2, 1, 4, 8, 3, 8, 6, 7, 8, 8, 5, 8, 8, 8]
        return Vader5State(
            leftX: s16(3), leftY: Int16(clamping: -Int(s16(5))),
            rightX: s16(7), rightY: Int16(clamping: -Int(s16(9))),
            leftTrigger: data[15], rightTrigger: data[16],
            dpad: dpadMap[Int(b11 & 0x0f)], buttons: buttons,
            extraButtons: ext,
            gyro: .init(x: s16(17), y: s16(19), z: s16(21)),
            accelerometer: .init(x: s16(23), y: s16(25), z: s16(27))
        )
    }

    public static func parse(_ data: [UInt8]) -> Vader5State? {
        data.withUnsafeBufferPointer(parse)
    }

    /// Parses the standard Xbox-compatible Bluetooth report exposed by Vader 5.
    public static func parseBluetooth(_ data: UnsafeBufferPointer<UInt8>) -> Vader5State? {
        guard data.count >= 16, data[0] == 0x01 else { return nil }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | UInt16(data[offset + 1]) << 8
        }
        func axis(_ offset: Int, inverted: Bool = false) -> Int16 {
            let centered = Int(u16(offset)) - 32_768
            return Int16(clamping: inverted ? -centered : centered)
        }
        func trigger(_ offset: Int) -> UInt8 {
            let raw = Int(u16(offset) & 0x03ff)
            return UInt8((raw * 255 + 511) / 1023)
        }

        let rawButtons = UInt16(data[14]) | UInt16(data[15] & 0x03) << 8
        var buttons: Vader5Buttons = []
        let mappings: [(UInt16, Vader5Buttons)] = [
            (1 << 0, .a), (1 << 1, .b), (1 << 2, .x), (1 << 3, .y),
            (1 << 4, .leftBumper), (1 << 5, .rightBumper),
            (1 << 6, .select), (1 << 7, .start),
            (1 << 8, .leftStick), (1 << 9, .rightStick),
        ]
        for (mask, button) in mappings where rawButtons & mask != 0 {
            buttons.insert(button)
        }

        let hat = data[13] & 0x0f
        return Vader5State(
            leftX: axis(1), leftY: axis(3, inverted: true),
            rightX: axis(5), rightY: axis(7, inverted: true),
            leftTrigger: trigger(9), rightTrigger: trigger(11),
            dpad: (1...8).contains(hat) ? hat - 1 : 8,
            buttons: buttons, extraButtons: 0,
            gyro: .init(x: 0, y: 0, z: 0),
            accelerometer: .init(x: 0, y: 0, z: 0)
        )
    }

    public static func parseBluetooth(_ data: [UInt8]) -> Vader5State? {
        data.withUnsafeBufferPointer(parseBluetooth)
    }

    public static func parseBluetoothHome(_ data: UnsafeBufferPointer<UInt8>) -> Bool? {
        guard data.count >= 2, data[0] == 0x02 else { return nil }
        return data[1] & 0x01 != 0
    }

    public static func parseBluetoothHome(_ data: [UInt8]) -> Bool? {
        data.withUnsafeBufferPointer(parseBluetoothHome)
    }

    /// Parses the NewXInput heartbeat returned by command 0x01.
    ///
    /// Vader 5 stores each four-part version in two packed BCD bytes. The
    /// heartbeat can include a segment number at byte 4; the first segment
    /// still contains all version fields used here.
    public static func parseFirmwareVersions(_ data: UnsafeBufferPointer<UInt8>) -> Vader5FirmwareVersions? {
        guard data.count >= 28,
              data[0] == 0x5a, data[1] == 0xa5, data[2] == 0x01 else { return nil }

        let segmented = data[4] < data[3]
        guard !segmented || data[4] == 0 else { return nil }
        let payload = segmented ? 5 : 4
        let mainOffset = payload + 10
        let dongleOffset = mainOffset + 2
        let siOffset = dongleOffset + 2
        let rfOffset = mainOffset + 12
        guard rfOffset + 1 < data.count else { return nil }

        func version(at offset: Int) -> String? {
            let first = data[offset]
            let second = data[offset + 1]
            if (first == 0 && second == 0) || (first == 0xff && second == 0xff) {
                return nil
            }
            return "\(first >> 4).\(first & 0x0f).\(second >> 4).\(second & 0x0f)"
        }

        guard let main = version(at: mainOffset) else { return nil }
        return Vader5FirmwareVersions(
            main: main,
            rf: version(at: rfOffset),
            si: version(at: siOffset),
            dongle: version(at: dongleOffset)
        )
    }

    public static func parseFirmwareVersions(_ data: [UInt8]) -> Vader5FirmwareVersions? {
        data.withUnsafeBufferPointer(parseFirmwareVersions)
    }

    static func virtualReport(for state: Vader5State) -> [UInt8] {
        func put16(_ value: Int16, into output: inout [UInt8], at offset: Int) {
            let raw = UInt16(bitPattern: value)
            output[offset] = UInt8(raw & 0xff)
            output[offset + 1] = UInt8(raw >> 8)
        }
        var report = [UInt8](repeating: 0, count: 15)
        report[0] = 1
        report[1] = UInt8(state.buttons.rawValue & 0xff)
        report[2] = UInt8((state.buttons.rawValue >> 8) & 0xff)
        report[3] = UInt8((state.buttons.rawValue >> 16) & 0x03)
        report[4] = state.dpad
        put16(state.leftX, into: &report, at: 5)
        put16(state.leftY, into: &report, at: 7)
        put16(state.rightX, into: &report, at: 9)
        put16(state.rightY, into: &report, at: 11)
        report[13] = state.leftTrigger
        report[14] = state.rightTrigger
        return report
    }
}
