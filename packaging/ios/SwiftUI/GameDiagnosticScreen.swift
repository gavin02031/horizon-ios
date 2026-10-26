import SwiftUI
import UIKit
import QuartzCore
import GameController
import Metal

// All index bits match Horizon's gamepad::Button enum. No emulation, no JIT.
private enum PadBits {
    static let jump: UInt32 = 1 << 0 // South
    static let drop: UInt32 = 1 << 1 // East
    static let swap: UInt32 = 1 << 2 // West
    static let inventory: UInt32 = 1 << 3 // North
    static let previous: UInt32 = 1 << 4 // LB
    static let next: UInt32 = 1 << 5 // RB
    static let pause: UInt32 = 1 << 9 // Start
    static let sneak: UInt32 = 1 << 11 // R3
}

@MainActor
private final class TouchPad: ObservableObject {
    var buttons: UInt32 = 0
    var moveX: Float = 0
    var moveY: Float = 0
    var lookX: Float = 0
    var lookY: Float = 0
    var use: Float = 0
    var attack: Float = 0

    func button(_ bit: UInt32, pressed: Bool) {
        if pressed { buttons |= bit } else { buttons &= ~bit }
        objectWillChange.send()
    }
    func clear() {
        buttons = 0
        moveX = 0
        moveY = 0
        lookX = 0
        lookY = 0
        use = 0
        attack = 0
        objectWillChange.send()
    }
}

@MainActor
private final class MetalStatus: ObservableObject {
    @Published var problem: String?
    @Published var controllerConnected = false
    @Published var ticks: UInt64 = 0
}

/// UIView's native layer is CAMetalLayer. wgpu owns drawable acquisition and
/// GPU submission; Swift never attempts to render over its Metal framebuffer.
final class HorizonMetalUIView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        isOpaque = true
        contentScaleFactor = UIScreen.main.scale
        let metal = layer as! CAMetalLayer
        metal.pixelFormat = .bgra8Unorm
        metal.framebufferOnly = true
        metal.contentsScale = contentScaleFactor
    }
    required init?(coder: NSCoder) { fatalError("Storyboard initialization is unsupported") }
}

/// Apple GameController reads live hardware state. Snapshots are separate
/// from touch controls, so Horizon's native Rust PadState::merge combines both.
@MainActor
private final class EmbeddedMetalCoordinator: NSObject {
    weak var view: HorizonMetalUIView?
    let touch: TouchPad
    let status: MetalStatus
    private var displayLink: CADisplayLink?
    private var opened = false
    private var failed = false
    private var lastSize: CGSize = .zero
    private var lastTimestamp: CFTimeInterval = 0
    private var frameCounter = 0

    init(touch: TouchPad, status: MetalStatus) {
        self.touch = touch
        self.status = status
    }
    func attach(view: HorizonMetalUIView) {
        self.view = view
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.preferredFramesPerSecond = 60
        link.add(to: .main, forMode: .common)
        displayLink = link
    }
    func stop() {
        displayLink?.invalidate()
        displayLink = nil
        // Drop wgpu's Surface *before* SwiftUI releases its UIView/CAMetalLayer.
        if opened { horizon_ios_metal_close() }
        opened = false
        horizon_ios_pad_snapshot(0, 0, 0, 0, 0, 0, 0, 0)
        horizon_ios_pad_snapshot(1, 0, 0, 0, 0, 0, 0, 0)
        touch.clear()
        view = nil
    }
    @objc private func frame(_ link: CADisplayLink) {
        guard !failed, let view, view.window != nil else { return }
        let scale = view.contentScaleFactor
        let width = UInt32(max(1, Int((view.bounds.width * scale).rounded())))
        let height = UInt32(max(1, Int((view.bounds.height * scale).rounded())))
        guard width > 1 && height > 1 else { return }
        if !opened {
            let err = horizon_ios_metal_open(
                Unmanaged.passUnretained(view).toOpaque(), width, height)
            guard err == 0 else {
                failed = true
                status.problem = "Couldn't create the iPhone Metal surface (code \(err)). Check device logs for the adapter error."
                return
            }
            opened = true
            lastSize = view.bounds.size
        }
        if view.bounds.size != lastSize {
            horizon_ios_metal_resize(width, height)
            lastSize = view.bounds.size
        }

        let physical = GCController.controllers().first(where: { $0.extendedGamepad != nil })?.extendedGamepad
        status.controllerConnected = physical != nil && frameCounter % 60 == 0
        if let pad = physical {
            var buttons: UInt32 = 0
            if pad.buttonA.isPressed { buttons |= PadBits.jump }
            if pad.buttonB.isPressed { buttons |= PadBits.drop }
            if pad.buttonX.isPressed { buttons |= PadBits.swap }
            if pad.buttonY.isPressed { buttons |= PadBits.inventory }
            if pad.leftShoulder.isPressed { buttons |= PadBits.previous }
            if pad.rightShoulder.isPressed { buttons |= PadBits.next }
            if pad.buttonMenu.isPressed { buttons |= PadBits.pause }
            if pad.rightThumbstickButton?.isPressed == true { buttons |= PadBits.sneak }
            if pad.dpad.up.isPressed { buttons |= 1 << 12 }
            if pad.dpad.down.isPressed { buttons |= 1 << 13 }
            if pad.dpad.left.isPressed { buttons |= 1 << 14 }
            if pad.dpad.right.isPressed { buttons |= 1 << 15 }
            horizon_ios_pad_snapshot(
                1, buttons, pad.leftThumbstick.xAxis.value, pad.leftThumbstick.yAxis.value,
                pad.rightThumbstick.xAxis.value, pad.rightThumbstick.yAxis.value,
                pad.leftTrigger.value, pad.rightTrigger.value)
        } else {
            horizon_ios_pad_snapshot(1, 0, 0, 0, 0, 0, 0, 0)
        }

        horizon_ios_pad_snapshot(0, touch.buttons, touch.moveX, touch.moveY,
                                touch.lookX, touch.lookY, touch.use, touch.attack)
        // Looking around is relative per display tick, not a permanently held
        // right stick. Reset it after each submitted input snapshot.
        touch.lookX = 0
        touch.lookY = 0
        let dt = lastTimestamp == 0 ? 1.0 / 60.0 :
            min(0.10, max(0.001, link.timestamp - lastTimestamp))
        lastTimestamp = link.timestamp
        if !horizon_ios_metal_frame(Float(dt)) {
            failed = true
            status.problem = "Metal couldn't present a frame. The Minecraft renderer is not yet embedded."
        }
        frameCounter += 1
        if frameCounter % 30 == 0 {
            status.ticks = horizon_ios_preview_ticks()
        }
    }
}

private struct EmbeddedMetalView: UIViewRepresentable {
    @ObservedObject var touch: TouchPad
    @ObservedObject var status: MetalStatus

    func makeCoordinator() -> EmbeddedMetalCoordinator {
        EmbeddedMetalCoordinator(touch: touch, status: status)
    }
    func makeUIView(context: Context) -> HorizonMetalUIView {
        let view = HorizonMetalUIView(frame: .zero)
        context.coordinator.attach(view: view)
        return view
    }
    func updateUIView(_ view: HorizonMetalUIView, context: Context) {}
    static func dismantleUIView(_ view: HorizonMetalUIView,
                                coordinator: EmbeddedMetalCoordinator) {
        coordinator.stop()
    }
}

private struct TouchStick: View {
    @ObservedObject var pad: TouchPad
    private let diameter: CGFloat = 106
    @State private var translation: CGSize = .zero

    var body: some View {
        ZStack {
            Circle().fill(Color.black.opacity(0.40))
                .overlay(Circle().stroke(.cyan.opacity(0.5), lineWidth: 1.5))
            Circle().fill(Color.cyan.opacity(0.52))
                .frame(width: 44, height: 44)
                .shadow(color: .cyan.opacity(0.2), radius: 10)
                .offset(translation)
        }
        .frame(width: diameter, height: diameter)
        .contentShape(Circle())
        .gesture(DragGesture(minimumDistance: 0)
            .onChanged { value in
                let x = (value.location.x - diameter / 2) / 38
                let y = (value.location.y - diameter / 2) / 38
                let magnitude = max(1.0, sqrt(x * x + y * y))
                let nx = x / magnitude
                let ny = y / magnitude
                translation = CGSize(width: nx * 38, height: ny * 38)
                pad.moveX = Float(nx)
                pad.moveY = Float(-ny)
            }
            .onEnded { _ in
                translation = .zero
                pad.moveX = 0
                pad.moveY = 0
            }
        )
        .accessibilityLabel("Movement joystick")
    }
}

private struct HeldControl: View {
    let label: String
    let icon: String
    let change: (Bool) -> Void
    @State private var down = false

    var body: some View {
        Label(label, systemImage: icon)
            .labelStyle(.iconOnly)
            .font(.system(size: 20, weight: .semibold))
            .frame(width: 52, height: 52)
            .foregroundStyle(down ? Color.black : Color.white)
            .background(down ? Color.cyan : Color.black.opacity(0.45),
                        in: Circle())
            .overlay(Circle().stroke(.cyan.opacity(0.48), lineWidth: 1.2))
            .contentShape(Circle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !down { down = true; change(true) }
                }
                .onEnded { _ in
                    down = false
                    change(false)
                })
            .accessibilityLabel(label)
    }
}

/// Fully separate screen; the launcher and its navigation bar are not in game.
struct GameDiagnosticScreen: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var touch = TouchPad()
    @StateObject private var status = MetalStatus()
    @State private var lastLook: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack {
                EmbeddedMetalView(touch: touch, status: status)
                    .ignoresSafeArea()

                // Right-half swipe acts as right stick; button and joystick
                // overlays above it capture their own gestures.
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: geo.size.width * 0.46)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            let dx = value.translation.width - lastLook.width
                            let dy = value.translation.height - lastLook.height
                            touch.lookX = Float(max(-1, min(1, dx / 15)))
                            touch.lookY = Float(max(-1, min(1, -dy / 15)))
                            lastLook = value.translation
                        }
                        .onEnded { _ in
                            lastLook = .zero
                            touch.lookX = 0
                            touch.lookY = 0
                        })

                VStack {
                    HStack(spacing: 10) {
                        Button {
                            touch.clear()
                            dismiss()
                        } label: {
                            Label("Back to Horizon", systemImage: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(10)
                                .background(.black.opacity(0.65), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Text(status.controllerConnected ?
                             "Bluetooth controller connected" : "Touch controls active")
                            .font(.system(size: 11, weight: .medium))
                            .padding(10)
                            .background(.black.opacity(0.60), in: Capsule())
                    }
                    Spacer()
                    HStack(alignment: .bottom) {
                        TouchStick(pad: touch)
                        Spacer()
                        HStack(spacing: 12) {
                            HeldControl(label: "Hotbar previous", icon: "chevron.left") {
                                touch.button(PadBits.previous, pressed: $0)
                            }
                            HeldControl(label: "Inventory", icon: "shippingbox") {
                                touch.button(PadBits.inventory, pressed: $0)
                            }
                            HeldControl(label: "Use", icon: "hand.tap") { touch.use = $0 ? 1 : 0 }
                            HeldControl(label: "Attack", icon: "hammer") { touch.attack = $0 ? 1 : 0 }
                            HeldControl(label: "Jump", icon: "arrow.up") {
                                touch.button(PadBits.jump, pressed: $0)
                            }
                        }
                    }
                    HStack {
                        Text("RUST + METAL DIAGNOSTIC • NOT YET MINECRAFT GAMEPLAY")
                        Spacer()
                        Text("Rust 20 Hz ticks: \(status.ticks)")
                    }
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.top, 8)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)

                if let error = status.problem {
                    VStack(spacing: 14) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error)
                            .multilineTextAlignment(.center)
                        Button("Return to Horizon") { dismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(26)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
                    .frame(maxWidth: 380)
                }
            }
            .foregroundStyle(.white)
            .background(.black)
        }
        .statusBarHidden()
    }
}
