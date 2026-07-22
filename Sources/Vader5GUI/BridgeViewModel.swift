import Foundation
import AppKit
import SwiftUI
import Vader5Core

@MainActor
final class BridgeViewModel: ObservableObject {
    @Published var mode: Vader5BridgeMode = .monitor
    @Published var transport: Vader5Transport = .usbReceiver {
        didSet {
            if transport == .bluetooth { mode = .monitor }
        }
    }
    @Published var status: Vader5BridgeStatus = .stopped
    @Published var state: Vader5State = .neutral
    @Published var errorMessage: String?
    @Published var lightingStatus: Vader5LightingStatus = .checking
    @Published var lightingMode: Vader5LightingMode = .steady
    @Published var lightingColors: [Color] = [Color(red: 0, green: 116 / 255, blue: 1)]
    @Published var lightingBrightness: Double = 100
    @Published var lightingPeriod: Double = 50

    private let bridge = Vader5Bridge()
    private struct LightingDraft {
        var colors: [Color]
        var brightness: Double
        var period: Double
    }
    private var lightingDrafts: [Vader5LightingMode: LightingDraft] = [:]

    init() {
        bridge.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        bridge.onState = { [weak self] state in
            Task { @MainActor in self?.state = state }
        }
        bridge.onLightingStatus = { [weak self] status in
            Task { @MainActor in self?.lightingStatus = status }
        }
        bridge.onLightingConfiguration = { [weak self] configuration in
            Task { @MainActor in self?.loadLightingConfiguration(configuration) }
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
        case .running(.monitor): transport == .bluetooth ? "Bluetooth connected" : "Monitoring"
        case .running(.virtualGamepad): "Gamepad active"
        case .failed: "Connection failed"
        }
    }

    func toggle() {
        errorMessage = nil
        if isRunning {
            bridge.stop()
        } else {
            do { try bridge.start(mode: mode, transport: transport) }
            catch { errorMessage = String(describing: error) }
        }
    }

    func stop() { bridge.stop() }

    var canSetLighting: Bool {
        if case .ready = lightingStatus { return isRunning }
        return false
    }

    func applyLighting() {
        errorMessage = nil
        saveLightingDraft()
        do {
            try bridge.setLighting(.init(
                mode: lightingMode,
                colors: lightingColors.map(rgbColor),
                brightness: UInt8(clamping: Int(lightingBrightness.rounded())),
                period: UInt8(clamping: Int(lightingPeriod.rounded()))))
        } catch {
            errorMessage = String(describing: error)
        }
    }

    var availableLightingModes: [Vader5LightingMode] {
        if case .ready(.sdl) = lightingStatus { return [.steady] }
        return [.deviceDefault, .flow, .breathing, .feedback, .gradient, .steady, .off]
    }

    func addLightingColor() {
        guard lightingMode.allowsMultipleColors, lightingColors.count < 5 else { return }
        lightingColors.append(Color(red: 0, green: 116 / 255, blue: 1))
    }

    func selectLightingMode(_ mode: Vader5LightingMode) {
        guard mode != lightingMode else { return }
        saveLightingDraft()
        lightingMode = mode
        if let draft = lightingDrafts[mode] {
            lightingColors = draft.colors
            lightingBrightness = draft.brightness
            lightingPeriod = draft.period
        } else if mode.usesColors {
            let blue = Color(red: 0, green: 116 / 255, blue: 1)
            lightingColors = mode == .gradient
                ? [blue, Color(red: 195 / 255, green: 32 / 255, blue: 230 / 255)]
                : [blue]
        }
        normalizeLightingColors()
    }

    func removeLightingColor() {
        guard lightingColors.count > lightingMode.minimumColorCount else { return }
        lightingColors.removeLast()
    }

    private func normalizeLightingColors() {
        guard lightingMode.usesColors else { return }
        if lightingColors.isEmpty { lightingColors = [.blue] }
        while lightingColors.count < lightingMode.minimumColorCount {
            lightingColors.append(lightingColors.last!)
        }
        if !lightingMode.allowsMultipleColors, lightingColors.count > 1 {
            lightingColors = [lightingColors[0]]
        }
    }

    private func loadLightingConfiguration(_ configuration: Vader5LightingConfiguration) {
        lightingMode = configuration.mode
        lightingColors = configuration.colors.map {
            Color(red: Double($0.red) / 255, green: Double($0.green) / 255,
                  blue: Double($0.blue) / 255)
        }
        lightingBrightness = Double(configuration.brightness)
        lightingPeriod = Double(configuration.period)
        normalizeLightingColors()
        saveLightingDraft()
    }

    private func saveLightingDraft() {
        lightingDrafts[lightingMode] = LightingDraft(
            colors: lightingColors,
            brightness: lightingBrightness,
            period: lightingPeriod)
    }

    private func rgbColor(_ color: Color) -> Vader5RGBColor {
        let nativeColor = NSColor(color)
        let converted = nativeColor.usingColorSpace(.deviceRGB) ?? nativeColor
        return Vader5RGBColor(
            red: UInt8(clamping: Int((converted.redComponent * 255).rounded())),
            green: UInt8(clamping: Int((converted.greenComponent * 255).rounded())),
            blue: UInt8(clamping: Int((converted.blueComponent * 255).rounded())))
    }
}
