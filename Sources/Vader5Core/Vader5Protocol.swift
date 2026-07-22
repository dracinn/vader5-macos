import Foundation

public enum Vader5Protocol {
    public static let vendorID = 0x37d7
    public static let productID = 0x2401
    public static let usagePage = 0xffa0
    public static let usage = 1

    public static let firmwareQueryCommand: [UInt8] = [0x5a, 0xa5, 0x01, 0x02, 0x03]

    static func ledConfigReadCommand(configID: UInt8 = 0) -> [UInt8] {
        let payloadSize: UInt8 = 20
        let length: UInt8 = 4
        return [0x5a, 0xa5, 0xa7, length, configID, payloadSize,
                0xa7 &+ length &+ configID &+ payloadSize]
    }

    static func parseLEDConfigChunk(_ data: UnsafeBufferPointer<UInt8>)
        -> (total: Int, index: Int, bytes: [UInt8])?
    {
        guard data.count >= 26, data[0] == 0x5a, data[1] == 0xa5,
              data[2] == 0xa7, data[3] > 0, data[4] < data[3] else { return nil }
        return (Int(data[3]), Int(data[4]), Array(data[6..<26]))
    }

    static func parseLEDConfigChunk(_ data: [UInt8])
        -> (total: Int, index: Int, bytes: [UInt8])?
    {
        data.withUnsafeBufferPointer(parseLEDConfigChunk)
    }

    static func parseLightingConfiguration(_ data: [UInt8])
        -> Vader5LightingConfiguration?
    {
        guard data.count >= 20, data[0] == 0, data[1] == 2 || data[1] == 3 else {
            return nil
        }
        let mode = Vader5LightingMode(rawValue: data[8]) ?? (data[8] == 0 ? .off : .steady)
        var colors: [Vader5RGBColor] = []
        var index = 20
        while index + 2 < data.count && colors.count < 5 {
            let color = Vader5RGBColor(red: data[index], green: data[index + 1], blue: data[index + 2])
            if (color.red != 0 || color.green != 0 || color.blue != 0),
               !colors.contains(color) {
                colors.append(color)
            }
            index += 3
        }
        if colors.isEmpty { colors = [.init(red: 0, green: 116, blue: 255)] }
        let needed = mode.minimumColorCount
        while colors.count < needed { colors.append(colors.last!) }
        return Vader5LightingConfiguration(
            mode: mode, colors: colors, brightness: min(data[6], 100),
            period: max(1, min(data[5], 100)))
    }

    /// Builds the verified New XInput A8/A9 packet sequence used by Space
    /// Station 4.2.0.9. The caller must first read a valid version 2 or 3 LED
    /// configuration from the device; no guessed version or LED count is used.
    static func lightingPackets(
        basedOn current: [UInt8], configuration: Vader5LightingConfiguration,
        configID: UInt8 = 0
    ) -> [[UInt8]]? {
        guard current.count >= 20, current[0] == 0,
              current[1] == 2 || current[1] == 3 else { return nil }
        let rgbCount = max(1, min(Int(current[7]), 16))
        var config = Array(current.prefix(20))
        config[3] = 0 // loop start
        config[4] = configuration.mode.isAnimated ? UInt8(max(1, configuration.colors.count)) : 0
        config[5] = configuration.mode.isAnimated ? configuration.period : 0
        config[6] = configuration.mode == .off ? 0 : min(configuration.brightness, 100)
        config[7] = UInt8(rgbCount)
        if current[1] == 2 && configuration.mode == .off {
            config[8] = 0
        } else if current[1] == 2 && configuration.mode == .deviceDefault {
            config[8] = Vader5LightingMode.flow.rawValue
        } else {
            config[8] = configuration.mode.rawValue
        }

        let colors = normalizedColors(for: configuration)
        if configuration.mode == .flow || configuration.mode == .deviceDefault || configuration.mode == .off {
            config += current.dropFirst(20)
        } else if current[1] == 3 {
            // V3 stores one RGB triple per physical LED in each animation
            // frame. Each selected Space Station color becomes one frame.
            for color in colors {
                for _ in 0..<rgbCount { config += [color.red, color.green, color.blue] }
            }
        } else {
            // V2 has 16 fixed LED groups with ten color slots per group.
            for group in 0..<16 {
                for unit in 0..<10 {
                    let color = colors[unit % colors.count]
                    config += group < rgbCount
                        ? [color.red, color.green, color.blue] : [0, 0, 0]
                }
            }
        }

        let chunks = stride(from: 0, to: config.count, by: 20).map {
            Array(config[$0..<min($0 + 20, config.count)])
        }
        let startBody: [UInt8] = [0xa8, 6, configID, 0,
                                  UInt8(chunks.count), 20]
        var packets = [packet(body: startBody)]
        packets += chunks.enumerated().map { index, chunk in
            packet(body: [0xa9, UInt8(chunk.count + 3), UInt8(index)] + chunk)
        }
        return packets
    }

    static func solidLEDPackets(
        basedOn current: [UInt8], red: UInt8, green: UInt8, blue: UInt8,
        brightness: UInt8, configID: UInt8 = 0
    ) -> [[UInt8]]? {
        lightingPackets(
            basedOn: current,
            configuration: .init(
                mode: .steady, colors: [.init(red: red, green: green, blue: blue)],
                brightness: brightness),
            configID: configID)
    }

    private static func normalizedColors(
        for configuration: Vader5LightingConfiguration
    ) -> [Vader5RGBColor] {
        var colors = Array(configuration.colors.prefix(5))
        if colors.isEmpty { colors = [.init(red: 0, green: 116, blue: 255)] }
        let minimum = configuration.mode.minimumColorCount
        while colors.count < minimum { colors.append(colors.last!) }
        if !configuration.mode.allowsMultipleColors { colors = [colors[0]] }
        return colors
    }

    private static func packet(body: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: 32)
        result[0] = 0x5a
        result[1] = 0xa5
        for (index, byte) in body.enumerated() { result[index + 2] = byte }
        result[body.count + 2] = body.reduce(0, &+)
        return result
    }

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
        set(.c, when: ext & 0x01 != 0)
        set(.z, when: ext & 0x02 != 0)
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
        report[3] = UInt8((state.buttons.rawValue >> 16) & 0x0f)
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
