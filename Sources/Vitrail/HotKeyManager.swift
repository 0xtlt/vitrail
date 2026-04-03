import AppKit
import HotKey

final class HotKeyManager {
	private var hotKeys: [HotKey] = []

	func unregisterAll() {
		hotKeys.removeAll()
	}

	func pause() {
		for hk in hotKeys { hk.isPaused = true }
	}

	func resume() {
		for hk in hotKeys { hk.isPaused = false }
	}

	func register(layouts: [Layout], spacing: Spacing, hideOthers: Bool) {
		for layout in layouts {
			guard let (key, modifiers) = Self.parseHotkey(layout.hotkey) else {
				print("[vitrail] Invalid hotkey: \(layout.hotkey)")
				continue
			}

			let hotKey = HotKey(key: key, modifiers: modifiers)
			let capturedLayout = layout
			let capturedSpacing = spacing
			let capturedHide = hideOthers
			hotKey.keyDownHandler = {
				WindowManager.applyLayout(capturedLayout, spacing: capturedSpacing, hideOthers: capturedHide)
			}
			hotKeys.append(hotKey)
			print("[vitrail] Registered: \(layout.hotkey) → \(layout.name)")
		}
	}

	/// Parse "alt+1" style string into Key + modifiers
	static func parseHotkey(_ str: String) -> (Key, NSEvent.ModifierFlags)? {
		let parts = str.lowercased().split(separator: "+").map(String.init)
		guard parts.count >= 2 else { return nil }

		var modifiers: NSEvent.ModifierFlags = []
		for part in parts.dropLast() {
			switch part {
			case "alt", "option", "opt": modifiers.insert(.option)
			case "cmd", "command": modifiers.insert(.command)
			case "ctrl", "control": modifiers.insert(.control)
			case "shift": modifiers.insert(.shift)
			default: return nil
			}
		}

		guard let key = keyFromString(parts.last!) else { return nil }
		return (key, modifiers)
	}

	private static func keyFromString(_ str: String) -> Key? {
		switch str {
		case "1": return .one
		case "2": return .two
		case "3": return .three
		case "4": return .four
		case "5": return .five
		case "6": return .six
		case "7": return .seven
		case "8": return .eight
		case "9": return .nine
		case "0": return .zero
		case "a": return .a
		case "b": return .b
		case "c": return .c
		case "d": return .d
		case "e": return .e
		case "f": return .f
		case "g": return .g
		case "h": return .h
		case "i": return .i
		case "j": return .j
		case "k": return .k
		case "l": return .l
		case "m": return .m
		case "n": return .n
		case "o": return .o
		case "p": return .p
		case "q": return .q
		case "r": return .r
		case "s": return .s
		case "t": return .t
		case "u": return .u
		case "v": return .v
		case "w": return .w
		case "x": return .x
		case "y": return .y
		case "z": return .z
		case "space": return .space
		case "tab": return .tab
		case "return", "enter": return .return
		default: return nil
		}
	}
}
