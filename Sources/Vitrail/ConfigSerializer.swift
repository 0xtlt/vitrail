import Foundation

struct ConfigSerializer {
	static func serialize(_ config: Config) -> String {
		var lines: [String] = []
		lines.append("# Vitrail config")
		lines.append("")
		lines.append("spacing = \"\(config.spacing.toTOMLString())\"")
		lines.append("hide_others = \(config.hideOthers)")

		for layout in config.layouts {
			lines.append("")
			lines.append("[[layout]]")
			lines.append("name = \"\(esc(layout.name))\"")
			lines.append("hotkey = \"\(esc(layout.hotkey))\"")

			for window in layout.windows {
				lines.append("")
				lines.append("  [[layout.window]]")
				lines.append("  app = \"\(esc(window.app))\"")
				if let title = window.title, !title.isEmpty {
					lines.append("  title = \"\(esc(title))\"")
				}
				if window.screen != 1 {
					lines.append("  screen = \(window.screen)")
				}
				lines.append("  x = \(formatNumber(window.x))")
				lines.append("  y = \(formatNumber(window.y))")
				lines.append("  width = \(formatNumber(window.width))")
				lines.append("  height = \(formatNumber(window.height))")
			}
		}

		lines.append("")
		return lines.joined(separator: "\n")
	}

	static func save(_ config: Config, to path: String) throws {
		let expandedPath = (path as NSString).expandingTildeInPath
		let url = URL(fileURLWithPath: expandedPath)

		let dir = url.deletingLastPathComponent()
		try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

		guard let data = serialize(config).data(using: .utf8) else {
			throw NSError(domain: "Vitrail", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to encode config as UTF-8"])
		}
		try data.write(to: url, options: .atomic)
	}

	/// Escape backslashes and double-quotes for TOML strings
	private static func esc(_ s: String) -> String {
		s.replacingOccurrences(of: "\\", with: "\\\\")
		 .replacingOccurrences(of: "\"", with: "\\\"")
	}

	private static func formatNumber(_ n: Double) -> String {
		n == n.rounded() ? "\(Int(n))" : String(format: "%.2f", n)
	}
}
