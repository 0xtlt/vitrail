import AppKit

final class AppController {
	var config: Config
	let hotKeyManager = HotKeyManager()
	private(set) var statusBar: StatusBar!
	let configPath: String
	private var configuratorWindow: ConfiguratorWindow?

	init(configPath: String) throws {
		self.configPath = configPath
		self.config = try Config.load(from: configPath)
	}

	func start() {
		if config.layouts.isEmpty {
			print("[vitrail] No layouts found in config. Open Configure... to add layouts.")
		} else {
			print("[vitrail] Loaded \(config.layouts.count) layout(s)")
		}

		hotKeyManager.register(layouts: config.layouts, spacing: config.spacing, hideOthers: config.hideOthers)

		statusBar = StatusBar(appController: self)
		statusBar.setup()

		print("[vitrail] Listening for hotkeys... (ctrl+c to quit)")

		let app = NSApplication.shared
		app.setActivationPolicy(.accessory)
		setupMainMenu()
		app.run()
	}

	private func setupMainMenu() {
		let mainMenu = NSMenu()

		// Edit menu (enables Cmd+A/C/V/X/Z in text fields)
		let editMenu = NSMenu(title: "Edit")
		editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
		editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
		editMenu.addItem(.separator())
		editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
		editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
		editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
		editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

		let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
		editItem.submenu = editMenu
		mainMenu.addItem(editItem)

		NSApplication.shared.mainMenu = mainMenu
	}

	func reload() {
		do {
			config = try Config.load(from: configPath)
			hotKeyManager.unregisterAll()
			hotKeyManager.register(layouts: config.layouts, spacing: config.spacing, hideOthers: config.hideOthers)
			statusBar.rebuildMenu()
			print("[vitrail] Config reloaded (\(config.layouts.count) layout(s))")
		} catch {
			print("[vitrail] Failed to reload config: \(error)")
		}
	}

	func openConfigurator() {
		if configuratorWindow == nil {
			configuratorWindow = ConfiguratorWindow()
		}
		configuratorWindow!.show(appController: self)
	}

	func openConfigInTextEditor() {
		let path = (Config.defaultPath as NSString).expandingTildeInPath
		let url = URL(fileURLWithPath: path)
		let fm = FileManager.default

		let dir = url.deletingLastPathComponent().path
		if !fm.fileExists(atPath: dir) {
			try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
		}

		if !fm.fileExists(atPath: path) {
			let defaultConfig = """
			# Vitrail config
			spacing = "1%"
			hide_others = true

			[[layout]]
			name = "main"
			hotkey = "alt+1"

			  [[layout.window]]
			  app = "Terminal"
			  x = 0
			  y = 0
			  width = 50
			  height = 100

			  [[layout.window]]
			  app = "Safari"
			  x = 50
			  y = 0
			  width = 50
			  height = 100
			"""
			fm.createFile(atPath: path, contents: defaultConfig.data(using: .utf8))
		}

		NSWorkspace.shared.open(url)
	}
}
