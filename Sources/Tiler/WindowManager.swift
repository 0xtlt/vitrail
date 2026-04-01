import AppKit
import ApplicationServices

// MARK: - String helpers

extension String {
	/// Replace all Unicode whitespace variants with regular space
	var normalizedSpaces: String {
		unicodeScalars.map { CharacterSet.whitespaces.contains($0) ? " " : String($0) }.joined()
	}
}

// MARK: - AXValue helpers

extension AXValue {
	func toValue<T>() -> T? {
		let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
		let success = AXValueGetValue(self, AXValueGetType(self), pointer)
		let value = pointer.pointee
		pointer.deallocate()
		return success ? value : nil
	}

	static func from<T>(value: T, type: AXValueType) -> AXValue? {
		var value = value
		return withUnsafePointer(to: &value) { AXValueCreate(type, $0) }
	}
}

// MARK: - AXUIElement helpers

extension AXUIElement {
	func setPosition(_ point: CGPoint) {
		guard let val = AXValue.from(value: point, type: .cgPoint) else { return }
		AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, val)
	}

	func setSize(_ size: CGSize) {
		guard let val = AXValue.from(value: size, type: .cgSize) else { return }
		AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, val)
	}

	var title: String? {
		var value: AnyObject?
		AXUIElementCopyAttributeValue(self, kAXTitleAttribute as CFString, &value)
		return value as? String
	}

	var windows: [AXUIElement] {
		var value: AnyObject?
		AXUIElementCopyAttributeValue(self, kAXWindowsAttribute as CFString, &value)
		return value as? [AXUIElement] ?? []
	}
}

// MARK: - WindowManager

struct WindowManager {
	/// Check if the process is trusted for Accessibility
	static func checkAccessibility() -> Bool {
		let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary
		return AXIsProcessTrustedWithOptions(options)
	}

	/// Find a window by app name and optional title substring
	/// Returns the window AXUIElement and the owning NSRunningApplication
	static func findWindow(appName: String, titleContains: String? = nil) -> (AXUIElement, NSRunningApplication)? {
		let apps = NSWorkspace.shared.runningApplications.filter {
			$0.localizedName == appName
		}

		for app in apps {
			let appElement = AXUIElementCreateApplication(app.processIdentifier)
			let appWindows = appElement.windows

			if let titleFilter = titleContains {
				let normalizedFilter = titleFilter.normalizedSpaces
				if let win = appWindows.first(where: {
					$0.title?.normalizedSpaces.contains(normalizedFilter) == true
				}) {
					return (win, app)
				}
			} else if let win = appWindows.first {
				return (win, app)
			}
		}

		return nil
	}

	/// Set a window's frame (position + size)
	/// Uses the Rectangle pattern: size → position → size for edge cases
	static func setWindowFrame(_ window: AXUIElement, origin: CGPoint, size: CGSize) {
		window.setSize(size)
		window.setPosition(origin)
		window.setSize(size)
	}

	/// Raise a window to front
	static func raiseWindow(_ window: AXUIElement, app: NSRunningApplication) {
		app.activate(options: .activateIgnoringOtherApps)
		AXUIElementPerformAction(window, kAXRaiseAction as CFString)
	}

	/// Hide all other apps not in the layout (by PID to handle same-app multi-window)
	static func hideOtherApps(exceptPIDs pids: Set<pid_t>) {
		for app in NSWorkspace.shared.runningApplications {
			guard app.activationPolicy == .regular else { continue }
			if !pids.contains(app.processIdentifier) {
				app.hide()
			}
		}
	}

	/// Apply a complete layout
	static func applyLayout(_ layout: Layout, spacing: Spacing = .default, hideOthers: Bool = true) {
		print("[tiler] Applying layout: \(layout.name)")

		// Collect all windows first, then raise in reverse order
		// so the last window in config ends up on top
		var matched: [(AXUIElement, NSRunningApplication, WindowRule)] = []

		for rule in layout.windows {
			guard let (window, app) = findWindow(appName: rule.app, titleContains: rule.title) else {
				print("[tiler]   Window not found: \(rule.app)" + (rule.title.map { " (\($0))" } ?? ""))
				continue
			}
			matched.append((window, app, rule))
		}

		// Unhide all apps first
		for (_, app, _) in matched {
			if app.isHidden { app.unhide() }
		}
		usleep(100_000) // 100ms for unhide to take effect

		// Position all windows
		for (window, _, rule) in matched {
			let (origin, size) = Screen.percentToPixels(
				x: rule.x, y: rule.y,
				width: rule.width, height: rule.height,
				screenIndex: rule.screen,
				spacing: spacing
			)
			setWindowFrame(window, origin: origin, size: size)
			print("[tiler]   \(rule.app) → \(Int(origin.x)),\(Int(origin.y)) \(Int(size.width))x\(Int(size.height))")
		}

		// Hide other apps if enabled
		if hideOthers {
			let matchedPIDs = Set(matched.map { $0.1.processIdentifier })
			hideOtherApps(exceptPIDs: matchedPIDs)
		}

		// Raise all windows (first in list = bottommost, last = topmost)
		for (window, app, _) in matched {
			raiseWindow(window, app: app)
			usleep(50_000) // 50ms
		}
	}
}
