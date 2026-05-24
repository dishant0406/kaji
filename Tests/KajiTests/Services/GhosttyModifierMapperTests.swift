import AppKit
import GhosttyKit
import Testing

@testable import Kaji

struct GhosttyModifierMapperTests {
    @Test
    func includesRightSideModifierBits() {
        let flags = NSEvent.ModifierFlags(rawValue: NSEvent.ModifierFlags.option.rawValue | UInt(NX_DEVICERALTKEYMASK))
        let mods = GhosttyModifierMapper.mods(from: flags)

        #expect(mods.rawValue & GHOSTTY_MODS_ALT.rawValue != 0)
        #expect(mods.rawValue & GHOSTTY_MODS_ALT_RIGHT.rawValue != 0)
    }
}
