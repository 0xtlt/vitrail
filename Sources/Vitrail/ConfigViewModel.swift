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
	let displayName: String
	let icon: NSImage
	let isRunning: Bool

	static func == (lhs: AppInfo, rhs: AppInfo) -> Bool {
		lhs.id == rhs.id && lhs.name == rhs.name && lhs.displayName == rhs.displayName && lhs.isRunning == rhs.isRunning
	}
}

final class AppDiscovery {
	static func runningApps() -> [AppInfo] {
		NSWorkspace.shared.runningApplications
			.filter { $0.activationPolicy == .regular }
			.compactMap { app -> AppInfo? in
				let name = AppNames.preferredName(for: app)
				let displayName = app.localizedName ?? name
				let icon = app.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil) ?? NSImage()
				return AppInfo(
					id: app.bundleIdentifier ?? name,
					name: name,
					displayName: displayName,
					icon: icon,
					isRunning: true
				)
			}
			.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	static func installedApps(excludingRunning running: [AppInfo]) -> [AppInfo] {
		let runningIDs = Set(running.map { $0.id })
		var apps: [AppInfo] = []
		var seenIDs: Set<String> = []

		for record in AppNames.installedAppRecords() {
			let id = record.bundleID ?? record.displayName
			if runningIDs.contains(id) || !seenIDs.insert(id).inserted { continue }

			let icon = NSWorkspace.shared.icon(forFile: record.path)
			apps.append(AppInfo(id: id, name: record.name, displayName: record.displayName, icon: icon, isRunning: false))
		}

		return apps.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
	}

	/// Find icon for a named app in /Applications (shared utility)
	static func iconForApp(named name: String) -> NSImage? {
		for record in AppNames.installedAppRecords() where AppNames.matches(name, installedApp: record) {
			return NSWorkspace.shared.icon(forFile: record.path)
		}

		return nil
	}
}
