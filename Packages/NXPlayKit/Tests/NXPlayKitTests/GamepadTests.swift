import GameController
import Testing

@testable import NXPlayKit

@Suite struct GamepadTests {
    @Test func namesAGenericControllerByItsKind() {
        // an Xbox controller on a USB cable: its USB product name is just "Controller"
        #expect(
            Gamepad.displayName(vendor: "Controller", category: GCProductCategoryXboxOne)
                == "Xbox Controller")
        #expect(
            Gamepad.displayName(vendor: nil, category: GCProductCategoryDualSense) == "DualSense")
        #expect(
            Gamepad.displayName(vendor: " ", category: GCProductCategoryDualShock4) == "DualShock 4"
        )
        // a generic HID pad has no better name
        #expect(
            Gamepad.displayName(vendor: "USB Gamepad", category: GCProductCategoryHID)
                == "USB Gamepad")
        #expect(Gamepad.displayName(vendor: nil, category: GCProductCategoryHID) == "Controller")
    }

    @Test func keepsAControllersOwnName() {
        #expect(
            Gamepad.displayName(
                vendor: "Xbox Wireless Controller", category: GCProductCategoryXboxOne)
                == "Xbox Wireless Controller")
        #expect(
            Gamepad.displayName(
                vendor: "DualSense Wireless Controller", category: GCProductCategoryDualSense)
                == "DualSense Wireless Controller")
        #expect(
            Gamepad.displayName(vendor: "8BitDo Pro 2", category: GCProductCategoryHID)
                == "8BitDo Pro 2")
    }
}
