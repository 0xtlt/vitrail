import AppKit
import Foundation

// ─── Config path ─────────────────────────────────────────────

let configPath: String
if CommandLine.arguments.count > 1 {
	configPath = CommandLine.arguments[1]
} else {
	configPath = Config.defaultPath
}

// ─── Check Accessibility ─────────────────────────────────────

if !WindowManager.checkAccessibility() {
	print("[vitrail] Accessibility permission required.")
	print("[vitrail] Go to System Settings > Privacy & Security > Accessibility")
	print("[vitrail] Add this terminal app or the vitrail binary, then restart.")
	exit(1)
}

// ─── Start ───────────────────────────────────────────────────

do {
	let controller = try AppController(configPath: configPath)
	controller.start()
} catch {
	print("[vitrail] Failed to load config from \(configPath): \(error)")
	exit(1)
}
