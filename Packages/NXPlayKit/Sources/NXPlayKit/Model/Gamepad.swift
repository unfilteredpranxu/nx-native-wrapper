import AppKit
import GameController
import Observation

/// The game controller as a remote for NX Play: the D-pad or left stick moves the selection (repeating while
/// held), A plays, B backs out, Menu toggles Console Mode. Any controller GameController knows works: Joy-Con,
/// Pro Controller, Xbox, DualShock / DualSense, 8BitDo. macOS gives controller input only to the frontmost app,
/// so a running game's input never reaches NX Play.
@MainActor @Observable
public final class Gamepad {
    public enum Command: Sendable, Equatable {
        case left, right, up, down, confirm, back, menu
    }

    public private(set) var controller: GCController?
    var onCommand: ((Command) -> Void)?

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var held: Command?
    @ObservationIgnored private var repeater: Task<Void, Never>?

    public var name: String? { controller.map { $0.vendorName ?? "Controller" } }

    /// 0…1, when the controller reports its battery.
    public var battery: Float? {
        guard let battery = controller?.battery, battery.batteryState != .unknown else {
            return nil
        }
        return battery.batteryLevel
    }

    init() {
        let center = NotificationCenter.default
        for name in [
            Notification.Name.GCControllerDidBecomeCurrent, .GCControllerDidConnect,
            .GCControllerDidDisconnect,
        ] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.attach(GCController.current ?? GCController.controllers().first)
                    }
                })
        }
        attach(GCController.current ?? GCController.controllers().first)
    }

    /// The symbol the connected controller prints on a button (Ⓐ, ✕, …), for on-screen hints.
    public func symbol(for command: Command) -> String? {
        guard let pad = controller?.extendedGamepad else { return nil }
        return switch command {
        case .confirm: pad.buttonA.sfSymbolsName
        case .back: pad.buttonB.sfSymbolsName
        case .menu: pad.buttonMenu.sfSymbolsName
        default: pad.dpad.sfSymbolsName
        }
    }

    private func attach(_ controller: GCController?) {
        guard controller !== self.controller else { return }
        stopRepeat()
        self.controller = controller
        guard let pad = controller?.extendedGamepad else { return }
        // handlers run on the main queue (GameController's default handler queue)
        func press(_ command: Command) -> GCControllerButtonValueChangedHandler {
            { [weak self] _, _, pressed in
                MainActor.assumeIsolated { if pressed { self?.send(command) } }
            }
        }
        func direction(_ command: Command) -> GCControllerButtonValueChangedHandler {
            { [weak self] _, _, pressed in MainActor.assumeIsolated { self?.hold(command, pressed) }
            }
        }
        pad.buttonA.pressedChangedHandler = press(.confirm)
        pad.buttonB.pressedChangedHandler = press(.back)
        pad.buttonMenu.pressedChangedHandler = press(.menu)
        pad.dpad.left.pressedChangedHandler = direction(.left)
        pad.dpad.right.pressedChangedHandler = direction(.right)
        pad.dpad.up.pressedChangedHandler = direction(.up)
        pad.dpad.down.pressedChangedHandler = direction(.down)
        pad.leftThumbstick.valueChangedHandler = { [weak self] _, x, y in
            MainActor.assumeIsolated { self?.stick(x: x, y: y) }
        }
    }

    /// The stick as a D-pad: past half way it presses the nearest direction, back near the middle it lets go.
    private func stick(x: Float, y: Float) {
        let command: Command? =
            max(abs(x), abs(y)) < 0.5
            ? nil
            : abs(x) > abs(y)
                ? (x < 0 ? .left : .right)
                : (y > 0 ? .up : .down)
        if command != held {
            if let held { hold(held, false) }
            if let command { hold(command, true) }
        }
    }

    /// A direction moves once, then again and again while held, as a keyboard repeats.
    private func hold(_ command: Command, _ pressed: Bool) {
        guard pressed else {
            if held == command { stopRepeat() }
            return
        }
        stopRepeat()
        held = command
        send(command)
        repeater = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(380))
            while !Task.isCancelled {
                self?.send(command)
                try? await Task.sleep(for: .milliseconds(110))
            }
        }
    }

    private func stopRepeat() {
        repeater?.cancel()
        repeater = nil
        held = nil
    }

    private func send(_ command: Command) {
        guard NSApp?.isActive != false else { return }
        onCommand?(command)
    }
}
