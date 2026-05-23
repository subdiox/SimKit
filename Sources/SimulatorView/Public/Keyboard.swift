import Foundation

/// One physical key on a US-layout keyboard, identified by its HID usage on page 7 (the
/// keyboard / keypad page). Build via `KeyboardKey.from(wireCode:)` (W3C
/// `KeyboardEvent.code` style) or `KeyboardKey.decompose(character:)` (ASCII typing).
///
/// Derived from baguette (Apache 2.0).
public struct KeyboardKey: Equatable, Hashable, Sendable {
    public let hidUsage: HIDUsage
    public init(hidUsage: HIDUsage) {
        self.hidUsage = hidUsage
    }

    /// Wire code → key. Returns nil for codes outside the supported set (letters / digits
    /// / arrows / common named keys / punctuation).
    public static func from(wireCode: String) -> KeyboardKey? {
        guard let usage = wireCodeMap[wireCode] else { return nil }
        return KeyboardKey(hidUsage: HIDUsage(page: 7, usage: usage))
    }

    /// Decompose an ASCII character into the key + modifier set needed to type it on a US
    /// layout. `'A'` → `(KeyA, [shift])`, `'!'` → `(Digit1, [shift])`, etc.
    public static func decompose(character c: Character) -> (key: KeyboardKey, modifiers: Set<KeyModifier>)? {
        guard let scalar = c.unicodeScalars.first,
              c.unicodeScalars.count == 1, scalar.isASCII else { return nil }
        let value = Int(scalar.value)

        if value >= Int(Character("a").asciiValue!), value <= Int(Character("z").asciiValue!) {
            let usage = UInt32(0x04 + value - Int(Character("a").asciiValue!))
            return (KeyboardKey(hidUsage: HIDUsage(page: 7, usage: usage)), [])
        }
        if value >= Int(Character("A").asciiValue!), value <= Int(Character("Z").asciiValue!) {
            let usage = UInt32(0x04 + value - Int(Character("A").asciiValue!))
            return (KeyboardKey(hidUsage: HIDUsage(page: 7, usage: usage)), [.shift])
        }
        if value >= Int(Character("0").asciiValue!), value <= Int(Character("9").asciiValue!) {
            let usage: UInt32 = (c == "0")
                ? 0x27
                : UInt32(0x1E + value - Int(Character("1").asciiValue!))
            return (KeyboardKey(hidUsage: HIDUsage(page: 7, usage: usage)), [])
        }
        if let pair = punctuationMap[c] {
            return (KeyboardKey(hidUsage: HIDUsage(page: 7, usage: pair.usage)), pair.shifted ? [.shift] : [])
        }
        return nil
    }

    private static let wireCodeMap: [String: UInt32] = {
        var m: [String: UInt32] = [
            "Enter": 0x28, "Escape": 0x29, "Backspace": 0x2A, "Tab": 0x2B, "Space": 0x2C,
            "Minus": 0x2D, "Equal": 0x2E, "BracketLeft": 0x2F, "BracketRight": 0x30,
            "Backslash": 0x31, "Semicolon": 0x33, "Quote": 0x34, "Backquote": 0x35,
            "Comma": 0x36, "Period": 0x37, "Slash": 0x38,
            "ArrowRight": 0x4F, "ArrowLeft": 0x50, "ArrowDown": 0x51, "ArrowUp": 0x52
        ]
        for (i, c) in "ABCDEFGHIJKLMNOPQRSTUVWXYZ".enumerated() {
            m["Key\(c)"] = UInt32(0x04 + i)
        }
        for i in 1...9 { m["Digit\(i)"] = UInt32(0x1E + i - 1) }
        m["Digit0"] = 0x27
        return m
    }()

    private static let punctuationMap: [Character: (usage: UInt32, shifted: Bool)] = [
        " ": (0x2C, false),
        "-": (0x2D, false), "_": (0x2D, true),
        "=": (0x2E, false), "+": (0x2E, true),
        "[": (0x2F, false), "{": (0x2F, true),
        "]": (0x30, false), "}": (0x30, true),
        "\\": (0x31, false), "|": (0x31, true),
        ";": (0x33, false), ":": (0x33, true),
        "'": (0x34, false), "\"": (0x34, true),
        "`": (0x35, false), "~": (0x35, true),
        ",": (0x36, false), "<": (0x36, true),
        ".": (0x37, false), ">": (0x37, true),
        "/": (0x38, false), "?": (0x38, true),
        "!": (0x1E, true), "@": (0x1F, true), "#": (0x20, true), "$": (0x21, true),
        "%": (0x22, true), "^": (0x23, true), "&": (0x24, true), "*": (0x25, true),
        "(": (0x26, true), ")": (0x27, true)
    ]
}

/// Modifier keys bracketed around a `KeyboardKey` press. Each modifier itself lives on HID
/// page 7 (left-side variants).
public enum KeyModifier: String, Sendable, Hashable, CaseIterable {
    case shift, control, option, command

    public var hidUsage: HIDUsage {
        switch self {
        case .control: return HIDUsage(page: 7, usage: 0xE0)
        case .shift:   return HIDUsage(page: 7, usage: 0xE1)
        case .option:  return HIDUsage(page: 7, usage: 0xE2)
        case .command: return HIDUsage(page: 7, usage: 0xE3)
        }
    }
}
