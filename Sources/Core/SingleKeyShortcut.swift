import AppKit

/// A modifier shortcut fires on release, only when it was pressed on its own.
struct SingleKeyShortcutTracker {
    private var pending: UInt16?

    mutating func reset() { pending = nil }

    mutating func releasedKey(for event: NSEvent) -> UInt16? {
        guard event.type == .flagsChanged else { reset(); return nil }
        guard let mask = Self.modifierMask(for: event.keyCode) else { reset(); return nil }
        // InputMethodKit can omit device-dependent bits. The event key code
        // still identifies the side; use the generic flag in that case.
        let physicalFlags = event.modifierFlags.rawValue & 0x207f
        let pressed = physicalFlags != 0
            ? event.modifierFlags.rawValue & mask != 0
            : event.modifierFlags.contains(Self.modifierFamily(for: event.keyCode))
        if pressed {
            pending = Self.hasOtherModifiers(event.modifierFlags, except: event.keyCode) ? nil : event.keyCode
            return nil
        }
        let key = pending
        pending = nil
        return key == event.keyCode && !Self.hasOtherModifiers(event.modifierFlags, except: event.keyCode) ? key : nil
    }

    // Device-dependent flags identify each physical side even when both sides are held.
    static func modifierMask(for code: UInt16) -> UInt? {
        switch code {
        case 54: return 0x10 // right Command
        case 55: return 0x08 // left Command
        case 56: return 0x02 // left Shift
        case 60: return 0x04 // right Shift
        case 58: return 0x20 // left Option
        case 61: return 0x40 // right Option
        case 59: return 0x01 // left Control
        case 62: return 0x2000 // right Control
        case 63: return NSEvent.ModifierFlags.function.rawValue
        default: return nil
        }
    }

    private static func hasOtherModifiers(_ flags: NSEvent.ModifierFlags, except code: UInt16) -> Bool {
        let family = modifierFamily(for: code)
        let relevant: NSEvent.ModifierFlags = [.command, .control, .option, .shift, .function]
        let otherPhysical = flags.rawValue & 0x207f & ~(modifierMask(for: code) ?? 0)
        return !flags.intersection(relevant.subtracting(family)).isEmpty || otherPhysical != 0
    }

    private static func modifierFamily(for code: UInt16) -> NSEvent.ModifierFlags {
        switch code {
        case 54, 55: return .command
        case 56, 60: return .shift
        case 58, 61: return .option
        case 59, 62: return .control
        default: return .function
        }
    }

    static func name(for code: UInt16) -> String? {
        switch code {
        case 54: return "右 Command ⌘"
        case 55: return "左 Command ⌘"
        case 56: return "左 Shift ⇧"
        case 60: return "右 Shift ⇧"
        case 58: return "左 Option ⌥"
        case 61: return "右 Option ⌥"
        case 59: return "左 Control ⌃"
        case 62: return "右 Control ⌃"
        case 63: return "Fn 🌐"
        case 36: return "Return ↩"
        case 48: return "Tab ⇥"
        case 49: return "空格"
        case 51: return "Delete ⌫"
        case 117: return "向前删除 ⌦"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return nil
        }
    }
}
