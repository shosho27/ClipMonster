import Cocoa

// MARK: - Models
struct CustomShortcut: Codable, Equatable {
    var keyCode: UInt16
    var modifiers: UInt
    var keyString: String
    
    var displayString: String {
        var str = ""
        let mods = NSEvent.ModifierFlags(rawValue: modifiers)
        if mods.contains(.control) { str += "⌃" }
        if mods.contains(.option) { str += "⌥" }
        if mods.contains(.shift) { str += "⇧" }
        if mods.contains(.command) { str += "⌘" }
        if mods.contains(.function) { str += "Fn " }
        str += keyString
        return str
    }
}
