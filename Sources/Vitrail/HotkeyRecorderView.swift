import AppKit

/// A clickable view that records a keyboard shortcut when focused.
final class HotkeyRecorderView: NSView {
	var hotkey: String = "" {
		didSet {
			needsDisplay = true
			if oldValue != hotkey { onChange?(hotkey) }
		}
	}
	var onChange: ((String) -> Void)?
	/// Called when recording starts/stops — use to pause/resume global hotkeys
	var onRecordingChanged: ((Bool) -> Void)?

	private var isRecording = false {
		didSet {
			needsDisplay = true
			onRecordingChanged?(isRecording)
			if isRecording { startMonitor() } else { stopMonitor() }
		}
	}
	private var eventMonitor: Any?

	override var acceptsFirstResponder: Bool { true }
	override var isFlipped: Bool { true }

	override init(frame: NSRect) {
		super.init(frame: frame)
		wantsLayer = true
		layer?.cornerRadius = 5
	}

	required init?(coder: NSCoder) { fatalError() }

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		let bg: NSColor
		let borderColor: NSColor

		if isRecording {
			bg = NSColor.controlAccentColor.withAlphaComponent(0.08)
			borderColor = .controlAccentColor
		} else {
			bg = NSColor.controlBackgroundColor
			borderColor = .separatorColor
		}

		bg.setFill()
		let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 5, yRadius: 5)
		path.fill()
		borderColor.setStroke()
		path.lineWidth = 1
		path.stroke()

		// Text
		let text: String
		let color: NSColor
		if isRecording {
			text = "Press shortcut…"
			color = .controlAccentColor
		} else if hotkey.isEmpty {
			text = "Click to set"
			color = .tertiaryLabelColor
		} else {
			text = displayString(for: hotkey)
			color = .labelColor
		}

		let attrs: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: 12, weight: isRecording ? .medium : .regular),
			.foregroundColor: color,
		]
		let size = (text as NSString).size(withAttributes: attrs)
		let y = (bounds.height - size.height) / 2
		(text as NSString).draw(at: NSPoint(x: 8, y: y), withAttributes: attrs)

		// Clear button when has value and not recording
		if !hotkey.isEmpty && !isRecording {
			let clearX = bounds.width - 18
			let clearY = (bounds.height - 12) / 2
			let clearRect = NSRect(x: clearX, y: clearY, width: 12, height: 12)
			NSColor.tertiaryLabelColor.setFill()
			let circle = NSBezierPath(ovalIn: clearRect)
			circle.fill()

			let xAttrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: 8, weight: .bold),
				.foregroundColor: NSColor.white,
			]
			let xSize = ("✕" as NSString).size(withAttributes: xAttrs)
			("✕" as NSString).draw(at: NSPoint(x: clearX + (12 - xSize.width) / 2, y: clearY + (12 - xSize.height) / 2), withAttributes: xAttrs)
		}
	}

	// MARK: - Mouse

	override func mouseDown(with event: NSEvent) {
		let pt = convert(event.locationInWindow, from: nil)

		// Check clear button hit
		if !hotkey.isEmpty && !isRecording {
			let clearRect = NSRect(x: bounds.width - 20, y: 0, width: 20, height: bounds.height)
			if clearRect.contains(pt) {
				hotkey = ""
				return
			}
		}

		window?.makeFirstResponder(self)
		isRecording = true
	}

	// MARK: - Event Monitor

	private func startMonitor() {
		stopMonitor()
		eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			guard let self, self.isRecording else { return event }

			// Escape cancels
			if event.keyCode == 53 {
				self.isRecording = false
				self.window?.makeFirstResponder(nil)
				return nil // consume
			}

			guard let key = self.keyString(from: event) else { return nil }

			var parts: [String] = []
			let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			if mods.contains(.control) { parts.append("ctrl") }
			if mods.contains(.option) { parts.append("alt") }
			if mods.contains(.shift) { parts.append("shift") }
			if mods.contains(.command) { parts.append("cmd") }

			guard !parts.isEmpty else { return nil }

			parts.append(key)
			self.hotkey = parts.joined(separator: "+")
			self.isRecording = false
			self.window?.makeFirstResponder(nil)
			return nil // consume the event
		}
	}

	private func stopMonitor() {
		if let monitor = eventMonitor {
			NSEvent.removeMonitor(monitor)
			eventMonitor = nil
		}
	}

	override func resignFirstResponder() -> Bool {
		isRecording = false
		return super.resignFirstResponder()
	}

	deinit {
		stopMonitor()
	}

	// MARK: - Key Mapping (uses keyCode, not characters — immune to modifier interference)

	private func keyString(from event: NSEvent) -> String? {
		switch event.keyCode {
		// Numbers
		case 29: return "0"
		case 18: return "1"
		case 19: return "2"
		case 20: return "3"
		case 21: return "4"
		case 23: return "5"
		case 22: return "6"
		case 26: return "7"
		case 28: return "8"
		case 25: return "9"
		// Letters
		case 0: return "a"
		case 11: return "b"
		case 8: return "c"
		case 2: return "d"
		case 14: return "e"
		case 3: return "f"
		case 5: return "g"
		case 4: return "h"
		case 34: return "i"
		case 38: return "j"
		case 40: return "k"
		case 37: return "l"
		case 46: return "m"
		case 45: return "n"
		case 31: return "o"
		case 35: return "p"
		case 12: return "q"
		case 15: return "r"
		case 1: return "s"
		case 17: return "t"
		case 32: return "u"
		case 9: return "v"
		case 13: return "w"
		case 7: return "x"
		case 16: return "y"
		case 6: return "z"
		// Special
		case 49: return "space"
		case 48: return "tab"
		case 36: return "return"
		default: return nil
		}
	}

	// MARK: - Display

	private func displayString(for hotkey: String) -> String {
		hotkey.split(separator: "+").map { part -> String in
			switch part.lowercased() {
			case "alt", "option", "opt": return "⌥"
			case "cmd", "command": return "⌘"
			case "ctrl", "control": return "⌃"
			case "shift": return "⇧"
			case "space": return "Space"
			case "tab": return "Tab"
			case "return", "enter": return "↩"
			default: return part.uppercased()
			}
		}.joined()
	}
}
