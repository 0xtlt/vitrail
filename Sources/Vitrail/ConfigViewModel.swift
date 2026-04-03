import AppKit

// MARK: - Editable Models

struct EditableWindowRule: Identifiable, Equatable {
	let id = UUID()
	var app: String
	var title: String
	var screen: Int
	var x: Double
	var y: Double
	var width: Double
	var height: Double

	init(from rule: WindowRule) {
		self.app = rule.app
		self.title = rule.title ?? ""
		self.screen = rule.screen
		self.x = rule.x
		self.y = rule.y
		self.width = rule.width
		self.height = rule.height
	}

	init() {
		self.app = ""
		self.title = ""
		self.screen = 1
		self.x = 0
		self.y = 0
		self.width = 50
		self.height = 100
	}

	func toWindowRule() -> WindowRule {
		WindowRule(
			app: app,
			title: title.isEmpty ? nil : title,
			screen: screen,
			x: x, y: y, width: width, height: height
		)
	}
}

struct EditableLayout: Identifiable, Equatable {
	let id = UUID()
	var name: String
	var hotkey: String
	var windows: [EditableWindowRule]

	init(from layout: Layout) {
		self.name = layout.name
		self.hotkey = layout.hotkey
		self.windows = layout.windows.map { EditableWindowRule(from: $0) }
	}

	init() {
		self.name = "New Layout"
		self.hotkey = ""
		self.windows = []
	}

	func toLayout() -> Layout {
		Layout(name: name, hotkey: hotkey, windows: windows.map { $0.toWindowRule() })
	}
}

// MARK: - Conversion helpers

enum ConfigConvert {
	static func toConfig(layouts: [EditableLayout], spacing: String, hideOthers: Bool) -> Config {
		Config(
			layouts: layouts.map { $0.toLayout() },
			spacing: Spacing.parse(spacing),
			hideOthers: hideOthers
		)
	}
}

// MARK: - App Discovery

struct AppInfo: Identifiable, Equatable {
	let id: String
	let name: String
	let icon: NSImage
	let isRunning: Bool

	static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
		lhs.id == rhs.id && lhs.name == rhs.name && lhs.isRunning == rhs.isRunning
	}
}

final class AppDiscovery {
	static func runningApps() -> [AppInfo] {
		NSWorkspace.shared.runningApplications
			.filter { $0.activationPolicy == .regular }
			.compactMap { app -> AppInfo? in
				guard let name = app.localizedName else { return nil }
				let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
				return AppInfo(
					id: app.bundleIdentifier ?? name,
					name: name,
					icon: icon,
					isRunning: true
				)
			}
			.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	static func installedApps(excludingRunning running: [AppInfo]) -> [AppInfo] {
		let runningNames = Set(running.map { $0.name })
		var apps: [AppInfo] = []
		let fm = FileManager.default
		let dirs = ["/Applications", "/Applications/Utilities", "/System/Applications"]

		for dir in dirs {
			guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
			for item in contents where item.hasSuffix(".app") {
				let path = "\(dir)/\(item)"
				let name: String
				if let bundle = Bundle(path: path),
				   let bundleName = bundle.infoDictionary?["CFBundleName"] as? String {
					name = bundleName
				} else {
					name = (item as NSString).deletingPathExtension
				}

				if runningNames.contains(name) { continue }

				let icon = NSWorkspace.shared.icon(forFile: path)
				let bundleID = Bundle(path: path)?.bundleIdentifier ?? name
				apps.append(AppInfo(id: bundleID, name: name, icon: icon, isRunning: false))
			}
		}

		return apps.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
	}

	/// Find icon for a named app in /Applications (shared utility)
	static func iconForApp(named name: String) -> NSImage? {
		let fm = FileManager.default
		for dir in ["/Applications", "/Applications/Utilities", "/System/Applications"] {
			guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
			for item in contents where item.hasSuffix(".app") {
				let path = "\(dir)/\(item)"
				let appName: String
				if let bundle = Bundle(path: path),
				   let bn = bundle.infoDictionary?["CFBundleName"] as? String {
					appName = bn
				} else {
					appName = (item as NSString).deletingPathExtension
				}
				if appName == name {
					return NSWorkspace.shared.icon(forFile: path)
				}
			}
		}
		return nil
	}
}
