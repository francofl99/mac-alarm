import AppKit
import Carbon.HIToolbox

struct HotKeyConfig: Codable {
    var key: String
    var modifiers: [String]

    var carbonKeyCode: UInt32? { KeyCodes.code(for: key) }

    var carbonModifiers: UInt32 {
        modifiers.reduce(into: UInt32(0)) { acc, name in
            switch name.lowercased() {
            case "command", "cmd", "⌘": acc |= UInt32(cmdKey)
            case "option", "alt", "⌥": acc |= UInt32(optionKey)
            case "control", "ctrl", "⌃": acc |= UInt32(controlKey)
            case "shift", "⇧": acc |= UInt32(shiftKey)
            default: break
            }
        }
    }

    var cocoaFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for name in modifiers {
            switch name.lowercased() {
            case "command", "cmd", "⌘": flags.insert(.command)
            case "option", "alt", "⌥": flags.insert(.option)
            case "control", "ctrl", "⌃": flags.insert(.control)
            case "shift", "⇧": flags.insert(.shift)
            default: break
            }
        }
        return flags
    }
}

struct Config: Codable {
    var delaySeconds: Double = 20
    var message: String = "NO TOQUES EL TECLADO"
    var soundPath: String = "/System/Library/Sounds/Sosumi.aiff"
    var repeatIntervalSeconds: Double = 3
    var blockKeyboard: Bool = true
    var volume: Double = 1.0
    var hotKey: HotKeyConfig = HotKeyConfig(key: "A", modifiers: ["control", "option", "command"])

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Config()
        delaySeconds = try c.decodeIfPresent(Double.self, forKey: .delaySeconds) ?? fallback.delaySeconds
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? fallback.message
        soundPath = try c.decodeIfPresent(String.self, forKey: .soundPath) ?? fallback.soundPath
        repeatIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .repeatIntervalSeconds) ?? fallback.repeatIntervalSeconds
        blockKeyboard = try c.decodeIfPresent(Bool.self, forKey: .blockKeyboard) ?? fallback.blockKeyboard
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? fallback.volume
        hotKey = try c.decodeIfPresent(HotKeyConfig.self, forKey: .hotKey) ?? fallback.hotKey
    }

    var hotKeyDescription: String {
        let symbols = hotKey.modifiers.map { name -> String in
            switch name.lowercased() {
            case "command", "cmd": return "⌘"
            case "option", "alt": return "⌥"
            case "control", "ctrl": return "⌃"
            case "shift": return "⇧"
            default: return name
            }
        }
        return symbols.joined() + hotKey.key.uppercased()
    }

    static let directory = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/MacAlarm", isDirectory: true)

    static let url = directory.appendingPathComponent("config.json")

    static func load() -> Config {
        guard let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Config.self, from: data) else {
            let fallback = Config()
            fallback.save()
            return fallback
        }
        return config
    }

    func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? FileManager.default.createDirectory(at: Config.directory, withIntermediateDirectories: true)
        try? encoder.encode(self).write(to: Config.url)
    }
}

enum KeyCodes {
    private static let map: [String: UInt32] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "space": 49, "escape": 53, "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96,
        "f6": 97, "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111
    ]

    static func code(for key: String) -> UInt32? {
        let normalized = key.lowercased()
        if let code = map[normalized] { return code }
        return UInt32(normalized)
    }

    static func name(for code: UInt32) -> String {
        map.first { $0.value == code }?.key.uppercased() ?? String(code)
    }
}
