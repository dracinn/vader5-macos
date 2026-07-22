import Testing
@testable import Vader5Core

@Test func parsesEnhancedReport() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...2] = [0x5a, 0xa5, 0xef]
    report[3] = 0x34; report[4] = 0x12
    report[5] = 0x00; report[6] = 0x80
    report[11] = 0x11 // A + dpad up
    report[12] = 0x0c // LB + RB
    report[13] = 0xd7 // C + Z + M1 + M3 + LM + RM
    report[14] = 0x08 // Home
    report[15] = 127; report[16] = 255

    let state = Vader5Protocol.parse(report)
    #expect(state != nil)
    #expect(state?.leftX == 0x1234)
    #expect(state?.leftY == 32767)
    #expect(state?.dpad == 0)
    #expect(state?.buttons.contains(.a) == true)
    #expect(state?.buttons.contains(.m1) == true)
    #expect(state?.buttons.contains(.m3) == true)
    #expect(state?.buttons.contains(.c) == true)
    #expect(state?.buttons.contains(.z) == true)
    #expect(state?.buttons.contains(.leftMacro) == true)
    #expect(state?.buttons.contains(.rightMacro) == true)
    #expect(state?.buttons.contains(.home) == true)
    #expect(state?.leftTrigger == 127)
    #expect(state?.rightTrigger == 255)
}

@Test func virtualReportIncludesLMAndRM() {
    let state = Vader5State(
        leftX: 1, leftY: 2, rightX: 3, rightY: 4,
        leftTrigger: 5, rightTrigger: 6, dpad: 8,
        buttons: [.leftMacro, .rightMacro], extraButtons: 0xc0,
        gyro: .init(x: 0, y: 0, z: 0),
        accelerometer: .init(x: 0, y: 0, z: 0)
    )
    let report = Vader5Protocol.virtualReport(for: state)
    #expect(report.count == 15)
    #expect(report[3] & 0x03 == 0x03)
    #expect(report[4] == 8)
    #expect(report[13] == 5)
    #expect(report[14] == 6)
}

@Test func virtualReportIncludesCAndZ() {
    let state = Vader5State(
        leftX: 0, leftY: 0, rightX: 0, rightY: 0,
        leftTrigger: 0, rightTrigger: 0, dpad: 8,
        buttons: [.c, .z], extraButtons: 0x03,
        gyro: .init(x: 0, y: 0, z: 0),
        accelerometer: .init(x: 0, y: 0, z: 0))
    let report = Vader5Protocol.virtualReport(for: state)
    #expect(report[3] & 0x0c == 0x0c)
}

@Test func rejectsUnrecognizedReport() {
    #expect(Vader5Protocol.parse([UInt8](repeating: 0, count: 32)) == nil)
}

@Test func parsesFirmwareVersionsFromHeartbeat() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...4] = [0x5a, 0xa5, 0x01, 0x18, 0x80]
    report[14...19] = [0x71, 0x52, 0x15, 0x45, 0x35, 0x17]
    report[26...27] = [0x10, 0x26]

    #expect(Vader5Protocol.parseFirmwareVersions(report) == Vader5FirmwareVersions(
        main: "7.1.5.2",
        rf: "1.0.2.6",
        si: "3.5.1.7",
        dongle: "1.5.4.5"
    ))
}

@Test func parsesSegmentedFirmwareHeartbeatAndOmitsEmptyModules() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...5] = [0x5a, 0xa5, 0x01, 0x02, 0x00, 0x80]
    report[15...16] = [0x71, 0x52]

    #expect(Vader5Protocol.parseFirmwareVersions(report) == Vader5FirmwareVersions(
        main: "7.1.5.2"
    ))
}

@Test func rejectsHeartbeatWithoutAControllerVersion() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...4] = [0x5a, 0xa5, 0x01, 0x18, 0x80]
    #expect(Vader5Protocol.parseFirmwareVersions(report) == nil)
}

@Test func buildsVerifiedLEDReadCommand() {
    #expect(Vader5Protocol.ledConfigReadCommand() == [0x5a, 0xa5, 0xa7, 4, 0, 20, 0xbf])
}

@Test func parsesNewXInputLEDChunk() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...5] = [0x5a, 0xa5, 0xa7, 2, 1, 20]
    report.replaceSubrange(6...25, with: Array(20...39).map(UInt8.init))
    let chunk = Vader5Protocol.parseLEDConfigChunk(report)
    #expect(chunk?.total == 2)
    #expect(chunk?.index == 1)
    #expect(chunk?.bytes == Array(20...39).map(UInt8.init))
}

@Test func buildsVersionThreeSteadyLEDPackets() {
    var current = [UInt8](repeating: 0xff, count: 40)
    current[0] = 0
    current[1] = 3
    current[7] = 5
    let packets = Vader5Protocol.solidLEDPackets(
        basedOn: current, red: 0x11, green: 0x22, blue: 0x33, brightness: 75)
    #expect(packets?.count == 3)
    #expect(Array(packets![0][0...8]) == [0x5a, 0xa5, 0xa8, 6, 0, 0, 2, 20, 0xc4])
    #expect(Array(packets![1][0...4]) == [0x5a, 0xa5, 0xa9, 23, 0])
    #expect(packets![1][12] == 5)
    #expect(packets![1][11] == 75)
    #expect(Array(packets![2][5...19]) == Array(repeating: [0x11, 0x22, 0x33], count: 5).flatMap { $0 })
}

@Test func parsesSpaceStationLightingSettings() {
    var current = [UInt8](repeating: 0xff, count: 40)
    current[0...8] = [0, 3, 0, 0, 2, 64, 80, 5, Vader5LightingMode.gradient.rawValue]
    current[20...34] = [255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0]
    current[35...39] = [0, 0, 255, 0, 0]

    let parsed = Vader5Protocol.parseLightingConfiguration(current)
    #expect(parsed?.mode == .gradient)
    #expect(parsed?.brightness == 80)
    #expect(parsed?.period == 64)
    #expect(parsed?.colors.first == Vader5RGBColor(red: 255, green: 0, blue: 0))
    #expect(parsed?.colors.contains(Vader5RGBColor(red: 0, green: 0, blue: 255)) == true)
}

@Test func buildsBreathingFramesLikeSpaceStationColorList() {
    var current = [UInt8](repeating: 0xff, count: 40)
    current[0] = 0
    current[1] = 3
    current[7] = 2
    let settings = Vader5LightingConfiguration(
        mode: .breathing,
        colors: [.init(red: 255, green: 0, blue: 0), .init(red: 0, green: 0, blue: 255)],
        brightness: 70, period: 35)
    let packets = Vader5Protocol.lightingPackets(basedOn: current, configuration: settings)
    let payload = packets!.dropFirst().flatMap { packet -> [UInt8] in
        let count = Int(packet[3]) - 3
        return Array(packet[5..<(5 + count)])
    }
    #expect(payload[5] == 35)
    #expect(payload[6] == 70)
    #expect(payload[8] == Vader5LightingMode.breathing.rawValue)
    #expect(Array(payload[20...25]) == [255, 0, 0, 255, 0, 0])
    #expect(Array(payload[26...31]) == [0, 0, 255, 0, 0, 255])
}
