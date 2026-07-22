import AppKit
import SwiftUI
import Vader5Core

private enum ControllerOverlayInput: String, CaseIterable, Hashable {
    case leftTrigger, rightTrigger, leftBumper, rightBumper, leftMacro, rightMacro
    case leftStick, rightStick, dpad
    case a, b, x, y, c, z
    case view, menu, home, function
    case m1, m2, m3, m4

    var label: String {
        switch self {
        case .leftTrigger: "LT"
        case .rightTrigger: "RT"
        case .leftBumper: "LB"
        case .rightBumper: "RB"
        case .leftMacro: "LM"
        case .rightMacro: "RM"
        case .leftStick: "L3"
        case .rightStick: "R3"
        case .dpad: "D-pad"
        case .a: "A"
        case .b: "B"
        case .x: "X"
        case .y: "Y"
        case .c: "C"
        case .z: "Z"
        case .view: "View"
        case .menu: "Menu"
        case .home: "Home"
        case .function: "Fn"
        case .m1: "M1"
        case .m2: "M2"
        case .m3: "M3"
        case .m4: "M4"
        }
    }
}

private struct SavedOverlayPoint: Codable {
    var x: Double
    var y: Double
    var point: CGPoint { CGPoint(x: x, y: y) }
    init(_ point: CGPoint) { x = point.x; y = point.y }
}

@MainActor
private final class ControllerOverlayLayout: ObservableObject {
    @Published private var savedPositions: [String: SavedOverlayPoint]

    private static let storageKey = "ControlLab.controllerOverlayLayout.v1"
    private static let defaults: [ControllerOverlayInput: CGPoint] = [
        .leftTrigger: CGPoint(x: 145, y: 27), .rightTrigger: CGPoint(x: 455, y: 27),
        .leftBumper: CGPoint(x: 175, y: 55), .rightBumper: CGPoint(x: 425, y: 55),
        .leftMacro: CGPoint(x: 243.078125, y: 25.015625),
        .rightMacro: CGPoint(x: 357.36328125, y: 24.57421875),
        .leftStick: CGPoint(x: 186.9765625, y: 117.88671875),
        .rightStick: CGPoint(x: 354.6484375, y: 177.515625),
        .dpad: CGPoint(x: 240.8125, y: 185.23046875),
        .y: CGPoint(x: 406.74609375, y: 104.171875),
        .x: CGPoint(x: 379.24609375, y: 130.08984375),
        .b: CGPoint(x: 435, y: 131),
        .a: CGPoint(x: 407.63671875, y: 154.8046875),
        .z: CGPoint(x: 454.7734375, y: 174.65234375),
        .c: CGPoint(x: 426.625, y: 195.265625),
        .view: CGPoint(x: 264.30859375, y: 117.92578125),
        .menu: CGPoint(x: 332.00390625, y: 117.2578125),
        .home: CGPoint(x: 298.453125, y: 89.6484375),
        .function: CGPoint(x: 296.92578125, y: 264.23046875),
        .m2: CGPoint(x: 225, y: 290), .m1: CGPoint(x: 375, y: 290),
        .m4: CGPoint(x: 170, y: 322), .m3: CGPoint(x: 430, y: 322),
    ]

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([String: SavedOverlayPoint].self, from: data) {
            savedPositions = decoded
        } else {
            savedPositions = [:]
        }
    }

    func position(for input: ControllerOverlayInput) -> CGPoint {
        savedPositions[input.rawValue]?.point ?? Self.defaults[input] ?? .zero
    }

    func move(_ input: ControllerOverlayInput, to point: CGPoint) {
        let clamped = CGPoint(x: min(max(point.x, 15), 585), y: min(max(point.y, 15), 345))
        savedPositions[input.rawValue] = SavedOverlayPoint(clamped)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(savedPositions) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    func restoreDefaults() {
        savedPositions = [:]
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }
}

struct ControllerInputView: View {
    let state: Vader5State
    var allowsLayoutEditing = false
    @StateObject private var overlayLayout = ControllerOverlayLayout()
    @State private var isEditingLayout = false
    @State private var dragOrigins: [ControllerOverlayInput: CGPoint] = [:]

    var body: some View {
        GeometryReader { proxy in
            let scale = min(proxy.size.width / 600, proxy.size.height / 360)
            ZStack(alignment: .topTrailing) {
                controller
                    .frame(width: 600, height: 360)
                    .scaleEffect(scale)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if allowsLayoutEditing { layoutEditorControls }
            }
        }
        .frame(height: 360)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Live Vader 5 Pro controller input")
    }

    private var controller: some View {
        ZStack {
            if let imageURL = officialRenderURL,
               let officialRender = NSImage(contentsOf: imageURL) {
                Image(nsImage: officialRender)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .frame(width: 460, height: 318)
                    .position(x: 300, y: 205)
                    .shadow(color: .black.opacity(0.3), radius: 18, y: 10)
            }

            positioned(.leftTrigger) { TriggerMeter(label: "LT", value: state.leftTrigger) }
            positioned(.rightTrigger) { TriggerMeter(label: "RT", value: state.rightTrigger) }
            positioned(.leftBumper) { ShoulderButton(label: "LB", active: pressed(.leftBumper)) }
            positioned(.rightBumper) { ShoulderButton(label: "RB", active: pressed(.rightBumper)) }
            positioned(.leftMacro) { SmallButton(label: "LM", active: pressed(.leftMacro), width: 46) }
            positioned(.rightMacro) { SmallButton(label: "RM", active: pressed(.rightMacro), width: 46) }

            positioned(.leftStick) {
                LiveStick(label: "L3", x: state.leftX, y: state.leftY, active: pressed(.leftStick))
            }
            positioned(.rightStick) {
                LiveStick(label: "R3", x: state.rightX, y: state.rightY, active: pressed(.rightStick))
            }

            positioned(.dpad) { LiveDPad(direction: state.dpad) }

            positioned(.y) { FaceButton(label: "Y", active: pressed(.y), tint: .yellow) }
            positioned(.x) { FaceButton(label: "X", active: pressed(.x), tint: .blue) }
            positioned(.b) { FaceButton(label: "B", active: pressed(.b), tint: .red) }
            positioned(.a) { FaceButton(label: "A", active: pressed(.a), tint: .green) }
            positioned(.z) { FaceButton(label: "Z", active: pressed(.z), tint: .orange, size: 27) }
            positioned(.c) { FaceButton(label: "C", active: pressed(.c), tint: .purple, size: 27) }

            positioned(.view) {
                SmallButton(label: "View", active: pressed(.select), width: 38, restsVisible: false)
            }
            positioned(.menu) {
                SmallButton(label: "Menu", active: pressed(.start), width: 38, restsVisible: false)
            }
            positioned(.home) { RoundSymbolButton(symbol: "house.fill", active: pressed(.home)) }
            positioned(.function) { SmallButton(label: "Fn", active: pressed(.function), width: 38) }

            positioned(.m2) { RearButton(label: "M2", active: pressed(.m2)) }
            positioned(.m1) { RearButton(label: "M1", active: pressed(.m1)) }
            positioned(.m4) { RearButton(label: "M4", active: pressed(.m4)) }
            positioned(.m3) { RearButton(label: "M3", active: pressed(.m3)) }

            Text("LX \(state.leftX)  LY \(state.leftY)")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .position(readoutPosition(for: .leftStick))
            Text("RX \(state.rightX)  RY \(state.rightY)")
                .font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                .position(readoutPosition(for: .rightStick))
        }
    }

    private var layoutEditorControls: some View {
        HStack(spacing: 7) {
            if isEditingLayout {
                Button { overlayLayout.restoreDefaults() } label: {
                    Label("Reset", systemImage: "arrow.counterclockwise")
                }
                .help("Restore the original input positions")
            }
            Button { isEditingLayout.toggle() } label: {
                Label(isEditingLayout ? "Done" : "Edit layout",
                      systemImage: isEditingLayout ? "checkmark" : "move.3d")
            }
            .buttonStyle(.borderedProminent)
            .help(isEditingLayout ? "Finish positioning inputs" : "Drag inputs to align them")
        }
        .font(.caption)
        .controlSize(.small)
        .padding(8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(10)
    }

    private func positioned<Content: View>(
        _ input: ControllerOverlayInput,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(isEditingLayout ? 3 : 0)
            .contentShape(Rectangle())
            .overlay {
                if isEditingLayout {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.accentColor.opacity(0.9),
                                style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                }
            }
            .overlay(alignment: .topLeading) {
                if isEditingLayout {
                    Text(input.label)
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3).padding(.vertical, 1)
                        .background(Color.accentColor, in: Capsule())
                        .offset(y: -9)
                }
            }
            .position(overlayLayout.position(for: input))
            .gesture(dragGesture(for: input), including: isEditingLayout ? .all : .none)
    }

    private func dragGesture(for input: ControllerOverlayInput) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                if dragOrigins[input] == nil {
                    dragOrigins[input] = overlayLayout.position(for: input)
                }
                guard let origin = dragOrigins[input] else { return }
                overlayLayout.move(input, to: CGPoint(
                    x: origin.x + value.translation.width,
                    y: origin.y + value.translation.height))
            }
            .onEnded { _ in
                dragOrigins[input] = nil
                overlayLayout.save()
            }
    }

    private func readoutPosition(for input: ControllerOverlayInput) -> CGPoint {
        let inputPosition = overlayLayout.position(for: input)
        return CGPoint(x: inputPosition.x, y: min(inputPosition.y + 40, 350))
    }

    private func pressed(_ button: Vader5Buttons) -> Bool {
        state.buttons.contains(button)
    }

    private var officialRenderURL: URL? {
        if let packaged = Bundle.main.url(
            forResource: "Vader5Pro-Official", withExtension: "png") {
            return packaged
        }
        let sourceResource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Vader5Pro-Official.png")
        return FileManager.default.fileExists(atPath: sourceResource.path) ? sourceResource : nil
    }
}

private struct LiveStick: View {
    let label: String
    let x: Int16
    let y: Int16
    let active: Bool

    var body: some View {
        let dx = CGFloat(x) / 32767 * 15
        let dy = CGFloat(y) / 32767 * 15
        let engaged = active || x != 0 || y != 0
        ZStack {
            Circle().stroke(engaged ? Color.accentColor : .clear, lineWidth: 2).frame(width: 57, height: 57)
            Circle()
                .fill(engaged ? Color.accentColor : Color.white.opacity(0.28))
                .overlay(Circle().stroke(engaged ? .white.opacity(0.7) : .clear))
                .frame(width: 14, height: 14)
                .offset(x: dx, y: dy)
            if active {
                Text(label).font(.system(size: 8, weight: .bold)).foregroundStyle(.white)
            }
        }
        .frame(width: 60, height: 60)
        .shadow(color: engaged ? Color.accentColor.opacity(0.5) : .clear, radius: 7)
    }
}

private struct FaceButton: View {
    let label: String
    let active: Bool
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Circle()
            .fill(active ? tint : .clear)
            .overlay(Circle().stroke(active ? tint.opacity(0.9) : .clear, lineWidth: 2))
            .shadow(color: active ? tint.opacity(0.55) : .clear, radius: 7)
            .frame(width: size, height: size)
            .overlay(Text(label).font(.system(size: 12, weight: .heavy))
                .foregroundStyle(active ? .white : .clear))
    }
}

private struct SmallButton: View {
    let label: String
    let active: Bool
    var width: CGFloat = 42
    var restsVisible = true

    var body: some View {
        Text(label)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(active ? .white : (restsVisible ? .secondary : .clear))
            .frame(width: width, height: 22)
            .background(active ? Color.accentColor : (restsVisible ? Color(nsColor: .controlColor) : .clear))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(
                restsVisible || active ? Color.secondary.opacity(0.4) : Color.clear))
            .shadow(color: active ? Color.accentColor.opacity(0.45) : .clear, radius: 5)
    }
}

private struct RearButton: View {
    let label: String
    let active: Bool

    var body: some View {
        SmallButton(label: label, active: active, width: 52)
            .rotationEffect(.degrees(label == "M2" || label == "M4" ? -12 : 12))
    }
}

private struct ShoulderButton: View {
    let label: String
    let active: Bool

    var body: some View {
        SmallButton(label: label, active: active, width: 84)
    }
}

private struct RoundSymbolButton: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Circle()
            .fill(active ? Color.accentColor : Color(nsColor: .controlColor))
            .overlay(Circle().stroke(.secondary.opacity(0.4)))
            .frame(width: 34, height: 34)
            .overlay(Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .foregroundStyle(active ? .white : .secondary))
    }
}

private struct TriggerMeter: View {
    let label: String
    let value: UInt8

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.system(size: 9, weight: .bold))
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.16))
                Capsule().fill(Color.accentColor)
                    .frame(width: 76 * CGFloat(value) / 255)
            }
            .frame(width: 76, height: 7)
            Text("\(value)").font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
        }
    }
}

private struct LiveDPad: View {
    let direction: UInt8

    private func active(_ side: UInt8) -> Bool {
        switch side {
        case 0: direction == 0 || direction == 1 || direction == 7
        case 2: direction == 1 || direction == 2 || direction == 3
        case 4: direction == 3 || direction == 4 || direction == 5
        default: direction == 5 || direction == 6 || direction == 7
        }
    }

    var body: some View {
        ZStack {
            DPadPart(symbol: "▲", active: active(0)).offset(y: -27)
            DPadPart(symbol: "▶", active: active(2)).offset(x: 27)
            DPadPart(symbol: "▼", active: active(4)).offset(y: 27)
            DPadPart(symbol: "◀", active: active(6)).offset(x: -27)
        }
    }
}

private struct DPadPart: View {
    let symbol: String
    let active: Bool

    var body: some View {
        Text(symbol).font(.system(size: 10, weight: .black))
            .foregroundStyle(active ? .white : .clear)
            .frame(width: 28, height: 28)
            .background(active ? Color.accentColor : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .shadow(color: active ? Color.accentColor.opacity(0.5) : .clear, radius: 5)
    }
}
