import Testing
@testable import Vader5Core

@Test func parsesEnhancedReport() {
    var report = [UInt8](repeating: 0, count: 32)
    report[0...2] = [0x5a, 0xa5, 0xef]
    report[3] = 0x34; report[4] = 0x12
    report[5] = 0x00; report[6] = 0x80
    report[11] = 0x11 // A + dpad up
    report[12] = 0x0c // LB + RB
    report[13] = 0x14 // M1 + M3
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
    #expect(state?.buttons.contains(.home) == true)
    #expect(state?.leftTrigger == 127)
    #expect(state?.rightTrigger == 255)
}

@Test func rejectsUnrecognizedReport() {
    #expect(Vader5Protocol.parse([UInt8](repeating: 0, count: 32)) == nil)
}
