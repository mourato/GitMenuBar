import Carbon.HIToolbox
@testable import GitMenuBar
import XCTest

final class ShortcutConfigTests: XCTestCase {
    func testDisplayPartsPreserveRecorderOrder() {
        let shortcut = ShortcutConfig(
            keyCode: UInt32(kVK_ANSI_C),
            modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)
        )

        XCTAssertEqual(shortcut.displayParts, ["⌃", "⌥", "⌘", "C"])
        XCTAssertEqual(shortcut.description, "⌃⌥⌘C")
    }

    func testFunctionKeyMayBeUnmodified() {
        let shortcut = ShortcutConfig(keyCode: UInt32(kVK_F8), modifiers: 0)

        XCTAssertTrue(shortcut.isUsable)
        XCTAssertEqual(shortcut.displayParts, ["F8"])
    }

    func testUnsupportedModifiersAreRejected() {
        let shortcut = ShortcutConfig(keyCode: UInt32(kVK_ANSI_C), modifiers: 0x2000)

        XCTAssertFalse(shortcut.isUsable)
    }
}
