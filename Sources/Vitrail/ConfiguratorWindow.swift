import AppKit

final class ConfiguratorWindow: NSObject, NSWindowDelegate {
	private var window: NSWindow?

	func show(appController: AppController) {
		if let existing = window, existing.isVisible {
			existing.makeKeyAndOrderFront(nil)
			NSApp.activate(ignoringOtherApps: true)
			return
		}

		let vc = ConfiguratorViewController(config: appController.config)
		vc.appController = appController
		vc.onSave = { [weak appController] config in
			guard let appController = appController else { return }
			do {
				try ConfigSerializer.save(config, to: appController.configPath)
				appController.reload()
			} catch {
				print("[vitrail] Failed to save config: \(error)")
			}
		}
		vc.onClose = { [weak self] in
			self?.window?.close()
		}

		// Switch to regular app BEFORE creating the window
		NSApp.setActivationPolicy(.regular)

		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 720, height: 520),
			styleMask: [.titled, .closable, .resizable, .miniaturizable],
			backing: .buffered,
			defer: false
		)
		window.contentViewController = vc
		window.title = "Vitrail Configuration"
		window.minSize = NSSize(width: 620, height: 420)
		window.maxSize = NSSize(width: 1000, height: 700)
		window.center()
		window.delegate = self
		window.isReleasedWhenClosed = false
		self.window = window

		window.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func windowShouldClose(_ sender: NSWindow) -> Bool {
		guard let vc = sender.contentViewController as? ConfiguratorViewController else { return true }
		return vc.canClose()
	}

	func windowWillClose(_ notification: Notification) {
		// Resign first responder to stop hotkey recorder and resume global hotkeys
		window?.makeFirstResponder(nil)
		DispatchQueue.main.async {
			NSApp.setActivationPolicy(.accessory)
		}
		window = nil
	}
}
