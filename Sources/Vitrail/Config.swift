import CoreGraphics
import Foundation

// MARK: - Models

struct WindowRule: Equatable {
	let app: String
	let title: String?
	let screen: Int // 1 = primary, 2 = secondary, etc.
	let x: Double
	let y: Double
	let width: Double
	let height: Double
}

struct DisplayDescriptor: Equatable {
	let name: String
	let isBuiltin: Bool
	let isPrimary: Bool
	let scale: Double
	let frame: CGRect

	var encoded: String {
		[
			"name=\(Self.escape(name))",
			"kind=\(isBuiltin ? "builtin" : "external")",
			"primary=\(isPrimary ? "1" : "0")",
			"scale=\(Self.format(scale))",
			"frame=\(Self.format(frame.minX)),\(Self.format(frame.minY)),\(Self.format(frame.width)),\(Self.format(frame.height))",
		].joined(separator: ";")
	}

	static func decode(_ value: String) -> DisplayDescriptor? {
		var fields: [String: String] = [:]
		for part in value.split(separator: ";", omittingEmptySubsequences: false) {
			guard let eq = part.firstIndex(of: "=") else { continue }
			let key = String(part[..<eq])
			let rawValue = String(part[part.index(after: eq)...])
			fields[key] = unescape(rawValue)
		}

		guard let name = fields["name"],
			  let kind = fields["kind"],
			  let primary = fields["primary"],
			  let scale = Double(fields["scale"] ?? ""),
			  let frameString = fields["frame"] else { return nil }

		let parts = frameString.split(separator: ",").compactMap { Double($0) }
		guard parts.count == 4 else { return nil }

		return DisplayDescriptor(
			name: name,
			isBuiltin: kind == "builtin",
			isPrimary: primary == "1",
			scale: scale,
			frame: CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
		)
	}

	private static func escape(_ value: String) -> String {
		value
			.replacingOccurrences(of: "%", with: "%25")
			.replacingOccurrences(of: "|", with: "%7C")
			.replacingOccurrences(of: ";", with: "%3B")
			.replacingOccurrences(of: "=", with: "%3D")
	}

	private static func unescape(_ value: String) -> String {
		value
			.replacingOccurrences(of: "%3D", with: "=")
			.replacingOccurrences(of: "%3B", with: ";")
			.replacingOccurrences(of: "%7C", with: "|")
			.replacingOccurrences(of: "%25", with: "%")
	}

	static func format(_ value: Double) -> String {
		value == value.rounded() ? "\(Int(value))" : String(format: "%.3f", value)
	}
}

struct DisplaySetup: Equatable {
	let displays: [DisplayDescriptor]

	var signature: String {
		displays.map(\.encoded).joined(separator: "|")
	}

	var displayCount: Int { displays.count }

	var shortName: String {
		if displays.count == 1 {
			return displays[0].isBuiltin ? "MacBook" : displays[0].name
		}
		if let external = displays.first(where: { !$0.isBuiltin }) {
			return "\(external.name) + \(displays.count - 1)"
		}
		return "\(displays.count) Displays"
	}

	static func decode(_ signature: String) -> DisplaySetup? {
		let descriptors = signature
			.split(separator: "|", omittingEmptySubsequences: false)
			.compactMap { DisplayDescriptor.decode(String($0)) }
		guard !descriptors.isEmpty else { return nil }
		return DisplaySetup(displays: descriptors)
	}
}

struct LayoutVariant: Equatable {
	let name: String
	let displaySetup: DisplaySetup
	let windows: [WindowRule]
}

struct Layout: Equatable {
	let name: String
	let hotkey: String
	let variants: [LayoutVariant]

	func matchingVariant(for setup: DisplaySetup = Screen.currentDisplaySetup()) -> LayoutVariant? {
		variants.first { $0.displaySetup.signature == setup.signature }
	}
}

// MARK: - TOML Parser (minimal, supports our config format)

/// Spacing can be percentage ("1%") or pixels ("10px" or just "10")
struct Spacing {
	let value: Double
	let isPercent: Bool

	static let `default` = Spacing(value: 1, isPercent: true)

	func toTOMLString() -> String {
		let num = value == value.rounded() ? "\(Int(value))" : "\(value)"
		return isPercent ? "\(num)%" : "\(num)px"
	}

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
		enum WindowScope {
			case legacy
			case variant
		}

		var layouts: [Layout] = []
		var spacing: Spacing = .default
		var hideOthers: Bool = true
		var currentLayout: (name: String, hotkey: String)?
		var currentVariants: [LayoutVariant] = []
		var currentLegacyWindows: [WindowRule] = []
		var currentVariant: (name: String, displaySetup: DisplaySetup)?
		var currentVariantWindows: [WindowRule] = []
		var currentWindow: [String: String] = [:]
		var windowScope: WindowScope = .legacy

		func makeWindow(from values: [String: String]) -> WindowRule? {
			guard let app = values["app"] else { return nil }
			return WindowRule(
				app: app,
				title: values["title"],
				screen: Int(values["screen"] ?? "1") ?? 1,
				x: Double(values["x"] ?? "0") ?? 0,
				y: Double(values["y"] ?? "0") ?? 0,
				width: Double(values["width"] ?? "100") ?? 100,
				height: Double(values["height"] ?? "100") ?? 100
			)
		}

		func flushWindow() {
			guard let window = makeWindow(from: currentWindow) else {
				currentWindow = [:]
				return
			}
			switch windowScope {
			case .legacy:
				currentLegacyWindows.append(window)
			case .variant:
				currentVariantWindows.append(window)
			}
			currentWindow = [:]
		}

		func flushVariant() {
			flushWindow()
			if let variant = currentVariant {
				currentVariants.append(LayoutVariant(
					name: variant.name.isEmpty ? variant.displaySetup.shortName : variant.name,
					displaySetup: variant.displaySetup,
					windows: currentVariantWindows
				))
			}
			currentVariant = nil
			currentVariantWindows = []
		}

		func flushLayout() {
			flushVariant()
			if let layout = currentLayout {
				if !currentLegacyWindows.isEmpty {
					let setup = Screen.currentDisplaySetup()
					currentVariants.append(LayoutVariant(
						name: setup.shortName,
						displaySetup: setup,
						windows: currentLegacyWindows
					))
				}
				layouts.append(Layout(name: layout.name, hotkey: layout.hotkey, variants: currentVariants))
				currentVariants = []
				currentLegacyWindows = []
				currentLayout = nil
			}
		}

		func assign(_ key: String, value: String) {
			if currentVariant != nil {
				switch key {
				case "name":
					currentVariant?.name = value
				case "display_setup":
					if let setup = DisplaySetup.decode(value) {
						currentVariant?.displaySetup = setup
					}
				default:
					currentWindow[key] = value
				}
				return
			}

			if currentLayout != nil {
				switch key {
				case "name": currentLayout?.name = value
				case "hotkey": currentLayout?.hotkey = value
				default:
					currentWindow[key] = value
				}
				return
			}

			switch key {
			case "spacing": spacing = Spacing.parse(value)
			case "hide_others": hideOthers = (value == "true")
			default: break
			}
		}

		for line in content.components(separatedBy: .newlines) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)

			// Skip comments and empty lines
			if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

			if trimmed == "[[layout]]" {
				flushLayout()
				currentLayout = (name: "", hotkey: "")
				windowScope = .legacy
				continue
			}

			if trimmed == "[[layout.window]]" {
				flushWindow()
				windowScope = .legacy
				continue
			}

			if trimmed == "[[layout.variant]]" {
				flushVariant()
				currentVariant = (name: "", displaySetup: Screen.currentDisplaySetup())
				windowScope = .variant
				continue
			}

			if trimmed == "[[layout.variant.window]]" {
				flushWindow()
				windowScope = .variant
				continue
			}

			if let eqIndex = trimmed.firstIndex(of: "=") {
				let key = trimmed[trimmed.startIndex..<eqIndex].trimmingCharacters(in: .whitespaces)
				var value = trimmed[trimmed.index(after: eqIndex)...].trimmingCharacters(in: .whitespaces)

				if value.hasPrefix("\"") && value.hasSuffix("\"") {
					value = String(value.dropFirst().dropLast())
				}

				assign(key, value: value)
			}
		}

		flushLayout()
		return Config(layouts: layouts, spacing: spacing, hideOthers: hideOthers)
	}

	/// Default config path
	static var defaultPath: String {
		"~/.config/vitrail/config.toml"
	}
}
