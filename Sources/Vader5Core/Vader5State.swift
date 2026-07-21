import Foundation

public struct Vader5Buttons: OptionSet, Sendable, Equatable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let a = Self(rawValue: 1 << 0)
    public static let b = Self(rawValue: 1 << 1)
    public static let x = Self(rawValue: 1 << 2)
    public static let y = Self(rawValue: 1 << 3)
    public static let leftBumper = Self(rawValue: 1 << 4)
    public static let rightBumper = Self(rawValue: 1 << 5)
    public static let select = Self(rawValue: 1 << 6)
    public static let start = Self(rawValue: 1 << 7)
    public static let leftStick = Self(rawValue: 1 << 8)
    public static let rightStick = Self(rawValue: 1 << 9)
    public static let m1 = Self(rawValue: 1 << 10)
    public static let m2 = Self(rawValue: 1 << 11)
    public static let m3 = Self(rawValue: 1 << 12)
    public static let m4 = Self(rawValue: 1 << 13)
    public static let home = Self(rawValue: 1 << 14)
    public static let function = Self(rawValue: 1 << 15)
    public static let leftMacro = Self(rawValue: 1 << 16)
    public static let rightMacro = Self(rawValue: 1 << 17)
}

public struct Vector3: Sendable, Equatable {
    public let x: Int16
    public let y: Int16
    public let z: Int16

    public init(x: Int16, y: Int16, z: Int16) {
        self.x = x
        self.y = y
        self.z = z
    }
}

public struct Vader5SensorCalibration: Sendable, Equatable {
    public let gyroBias: Vector3
    public let accelerometerBias: Vector3

    public init(gyroBias: Vector3, accelerometerBias: Vector3) {
        self.gyroBias = gyroBias
        self.accelerometerBias = accelerometerBias
    }
}

public struct Vader5State: Sendable, Equatable {
    public let leftX: Int16
    public let leftY: Int16
    public let rightX: Int16
    public let rightY: Int16
    public let leftTrigger: UInt8
    public let rightTrigger: UInt8
    public let dpad: UInt8
    public let buttons: Vader5Buttons
    public let extraButtons: UInt8
    public let gyro: Vector3
    public let accelerometer: Vector3

    public static let neutral = Self(
        leftX: 0, leftY: 0, rightX: 0, rightY: 0,
        leftTrigger: 0, rightTrigger: 0, dpad: 8,
        buttons: [], extraButtons: 0,
        gyro: .init(x: 0, y: 0, z: 0),
        accelerometer: .init(x: 0, y: 0, z: 0)
    )

    public func applyingSensorCalibration(_ calibration: Vader5SensorCalibration) -> Self {
        func subtract(_ value: Vector3, _ bias: Vector3) -> Vector3 {
            Vector3(
                x: Int16(clamping: Int(value.x) - Int(bias.x)),
                y: Int16(clamping: Int(value.y) - Int(bias.y)),
                z: Int16(clamping: Int(value.z) - Int(bias.z))
            )
        }
        return Self(
            leftX: leftX, leftY: leftY, rightX: rightX, rightY: rightY,
            leftTrigger: leftTrigger, rightTrigger: rightTrigger,
            dpad: dpad, buttons: buttons, extraButtons: extraButtons,
            gyro: subtract(gyro, calibration.gyroBias),
            accelerometer: subtract(accelerometer, calibration.accelerometerBias)
        )
    }
}
