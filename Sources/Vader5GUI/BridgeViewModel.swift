import Foundation
import Vader5Core

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var mode: Vader5BridgeMode = .monitor
    @Published var status: Vader5BridgeStatus = .stopped
    @Published var state: Vader5State = .neutral
    @Published var errorMessage: String?
    @Published var isCalibratingSensors = false
    @Published var calibrationMessage = "Place the controller flat and keep it still before calibrating."

    private let bridge = Vader5Bridge()
    private var rawState: Vader5State = .neutral
    private var sensorCalibration: Vader5SensorCalibration?
    private var calibrationAccumulator = SensorCalibrationAccumulator()
    private var calibrationTask: Task<Void, Never>?

    init() {
        bridge.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        bridge.onState = { [weak self] state in
            Task { @MainActor in self?.receive(state) }
        }
    }

    var isRunning: Bool {
        if case .running = status { return true }
        return false
    }

    var statusTitle: String {
        switch status {
        case .stopped: "Disconnected"
        case .connecting: "Connecting…"
        case .running(.monitor): "Monitoring"
        case .running(.virtualGamepad): "Gamepad active"
        case .failed: "Connection failed"
        }
    }

    func toggle() {
        errorMessage = nil
        if isRunning {
            stop()
        } else {
            do { try bridge.start(mode: mode) }
            catch { errorMessage = String(describing: error) }
        }
    }

    func stop() {
        calibrationTask?.cancel()
        calibrationTask = nil
        isCalibratingSensors = false
        bridge.stop()
    }

    func calibrateSensors() {
        guard isRunning, !isCalibratingSensors else {
            if !isRunning { calibrationMessage = "Start the bridge before calibrating." }
            return
        }
        calibrationAccumulator = SensorCalibrationAccumulator()
        isCalibratingSensors = true
        calibrationMessage = "Calibrating… keep the controller still and flat."
        calibrationTask?.cancel()
        calibrationTask = Task {
            do { try await Task.sleep(for: .milliseconds(1_500)) }
            catch { return }
            finishSensorCalibration()
        }
    }

    private func receive(_ state: Vader5State) {
        rawState = state
        if isCalibratingSensors { calibrationAccumulator.add(state) }
        applySensorCalibration()
    }

    private func finishSensorCalibration() {
        guard isCalibratingSensors else { return }
        calibrationTask = nil
        isCalibratingSensors = false
        guard let calibration = calibrationAccumulator.calibration else {
            calibrationMessage = "Calibration failed: not enough live motion samples were received."
            return
        }
        sensorCalibration = calibration
        calibrationMessage = "Calibrated from \(calibrationAccumulator.count) resting samples."
        applySensorCalibration()
    }

    private func applySensorCalibration() {
        state = sensorCalibration.map(rawState.applyingSensorCalibration) ?? rawState
    }
}

private struct SensorCalibrationAccumulator {
    private(set) var count = 0
    private var gyroX: Int64 = 0
    private var gyroY: Int64 = 0
    private var gyroZ: Int64 = 0
    private var accelerometerX: Int64 = 0
    private var accelerometerY: Int64 = 0
    private var accelerometerZ: Int64 = 0

    mutating func add(_ state: Vader5State) {
        count += 1
        gyroX += Int64(state.gyro.x)
        gyroY += Int64(state.gyro.y)
        gyroZ += Int64(state.gyro.z)
        accelerometerX += Int64(state.accelerometer.x)
        accelerometerY += Int64(state.accelerometer.y)
        accelerometerZ += Int64(state.accelerometer.z)
    }

    var calibration: Vader5SensorCalibration? {
        guard count >= 10 else { return nil }
        let divisor = Int64(count)
        return Vader5SensorCalibration(
            gyroBias: Vector3(
                x: Int16(clamping: gyroX / divisor),
                y: Int16(clamping: gyroY / divisor),
                z: Int16(clamping: gyroZ / divisor)),
            accelerometerBias: Vector3(
                x: Int16(clamping: accelerometerX / divisor),
                y: Int16(clamping: accelerometerY / divisor),
                z: Int16(clamping: accelerometerZ / divisor))
        )
    }
}
