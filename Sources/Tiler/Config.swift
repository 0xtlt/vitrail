import Foundation

// MARK: - Models

struct WindowRule {
	let app: String
	let title: String?
	let screen: Int // 1 = primary, 2 = secondary, etc.
	let x: Double
	let y: Double
	let width: Double
	let height: Double
}

struct Layout {
	let name: String
	let hotkey: String
	let windows: [WindowRule]
}

// MARK: - TOML Parser (minimal, supports our config format)

/// Spacing can be percentage ("1%") or pixels ("10px" or just "10")
struct Spacing {
	let value: Double
	let isPercent: Bool

	static let `default` = Spacing(value: 1, isPercent: true)

	static func parse(_ str: String) -> Spacing {
		let trimmed = str.trimmingCharacters(in: .whitespaces)
		if trimmed.hasSuffix("%") {
			return Spacing(value: Double(trimmed.dropLast()) ?? 1, isPercent: true)
		} else if trimmed.hasSuffix("px") {
			return Spacing(value: Double(trimmed.dropLast(2)) ?? 10, isPercent: false)
		} else {
			return Spacing(value: Double(trimmed) ?? 10, isPercent: false)
		}
	}
}

struct Config {
	let layouts: [Layout]
	let spacing: Spacing
	let hideOthers: Bool

	static func load(from path: String) throws -> Config {
		let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
		let content = try String(contentsOf: url, encoding: .utf8)
		return try parse(content)
	}

	static func parse(_ content: String) throws -> Config {
		var layouts: [Layout] = []
		var spacing: Spacing = .default
		var hideOthers: Bool = true
		var currentLayout: (name: String, hotkey: String)?
		var currentWindows: [WindowRule] = []
		var currentWindow: [String: String] = [:]

		func flushWindow() {
			guard let app = currentWindow["app"] else { return }
			currentWindows.append(WindowRule(
				app: app,
				title: currentWindow["title"],
				screen: Int(currentWindow["screen"] ?? "1") ?? 1,
				x: Double(currentWindow["x"] ?? "0") ?? 0,
				y: Double(currentWindow["y"] ?? "0") ?? 0,
				width: Double(currentWindow["width"] ?? "100") ?? 100,
				height: Double(currentWindow["height"] ?? "100") ?? 100
			))
			currentWindow = [:]
		}

		func flushLayout() {
			flushWindow()
			if let layout = currentLayout {
				layouts.append(Layout(name: layout.name, hotkey: layout.hotkey, windows: currentWindows))
				currentWindows = []
				currentLayout = nil
			}
		}

		for line in content.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// Skip comments and empty lines
			if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

			// [[layout]] header
			if trimmed == "[[layout]]" {
				flushLayout()
				currentLayout = (name: "", hotkey: "")
				continue
			}

			// [[layout.window]] header
			if trimmed == "[[layout.window]]" {
				flushWindow()
				continue
			}

			// Key = value
			if let eqIndex = trimmed.firstIndex(of: "=") {
				let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
				var value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

				// Strip quotes
				if value.hasPrefix("\"") && value.hasSuffix("\"") {
					value = String(value.dropFirst().dropLast())
				}

				if currentLayout != nil {
					switch key {
					case "name": currentLayout?.name = value
					case "hotkey": currentLayout?.hotkey = value
					default:
						// It's a window property
						currentWindow[key] = value
					}
				} else {
					// Global settings (before any [[layout]])
					switch key {
					case "spacing": spacing = Spacing.parse(value)
					case "hide_others": hideOthers = (value == "true")
					default: break
					}
				}
			}
		}

		flushLayout()
		return Config(layouts: layouts, spacing: spacing, hideOthers: hideOthers)
	}

	/// Default config path
	static var defaultPath: String {
		"~/.config/tiler/config.toml"
	}
}
