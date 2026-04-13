import AppKit
import CoreServices

private extension String {
	var normalizedAppMatchKey: String {
		components(separatedBy: .whitespacesAndNewlines)
			.filter { !$0.isEmpty }
			.joined(separator: " ")
			.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
			.lowercased()
	}

	var deletingAppExtension: String {
		(self as NSString).deletingPathExtension
	}
}

struct InstalledAppRecord {
	let path: String
	let bundleID: String?
	let name: String
	let displayName: String
	let aliases: [String]
}

enum AppNames {
	static let applicationDirectories = [
		"/Applications",
		"/Applications/Utilities",
		"/System/Applications",
	]

	static func installedAppRecords() -> [InstalledAppRecord] {
		let fm = FileManager.default
		var records: [InstalledAppRecord] = []

		for dir in applicationDirectories {
			guard let contents = try? fm.contentsOfDirectory(atPath: dir) else { continue }
			for item in contents where item.hasSuffix(".app") {
				let path = "\(dir)/\(item)"
				records.append(installedAppRecord(at: path))
			}
		}

		return records
	}

	static func installedAppRecord(at path: String) -> InstalledAppRecord {
		let fallbackName = (path as NSString).lastPathComponent.deletingAppExtension
		let bundle = Bundle(path: path)
		let name = preferredName(bundle: bundle, fallbackName: fallbackName)
		let displayName = localizedDisplayName(at: path, bundle: bundle, fallbackName: fallbackName)
		let aliases = deduplicatedNames(
			[
				name,
				displayName,
				bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
				bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
				bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
				bundle?.infoDictionary?["CFBundleName"] as? String,
				bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
				bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
				fallbackName,
			]
		)

		return InstalledAppRecord(
			path: path,
			bundleID: bundle?.bundleIdentifier,
			name: name,
			displayName: displayName,
			aliases: aliases
		)
	}

	static func preferredName(for app: NSRunningApplication) -> String {
		let bundle = app.bundleURL.flatMap { Bundle(path: $0.path) }
		let fallbackName = app.localizedName
			?? app.bundleURL?.lastPathComponent.deletingAppExtension
			?? bundle?.bundleIdentifier
			?? ""

		return preferredName(bundle: bundle, fallbackName: fallbackName)
	}

	static func aliases(for app: NSRunningApplication) -> [String] {
		let bundle = app.bundleURL.flatMap { Bundle(path: $0.path) }
		let fallbackName = app.localizedName
			?? app.bundleURL?.lastPathComponent.deletingAppExtension
			?? bundle?.bundleIdentifier
			?? ""

		return deduplicatedNames(
			[
				app.localizedName,
				app.bundleURL?.lastPathComponent.deletingAppExtension,
				bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
				bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
				bundle?.infoDictionary?["CFBundleDisplayName"] as? String,
				bundle?.infoDictionary?["CFBundleName"] as? String,
				bundle?.localizedInfoDictionary?["CFBundleDisplayName"] as? String,
				bundle?.localizedInfoDictionary?["CFBundleName"] as? String,
				bundle.flatMap { localizedDisplayName(at: app.bundleURL?.path, bundle: $0, fallbackName: fallbackName) },
				fallbackName,
			]
		)
	}

	static func matches(_ name: String, runningApp: NSRunningApplication) -> Bool {
		matches(name, against: aliases(for: runningApp))
	}

	static func matches(_ name: String, installedApp: InstalledAppRecord) -> Bool {
		matches(name, against: installedApp.aliases)
	}

	static func matches(_ name: String, against aliases: [String]) -> Bool {
		let normalizedName = name.normalizedAppMatchKey
		guard !normalizedName.isEmpty else { return false }
		return aliases.contains { $0.normalizedAppMatchKey == normalizedName }
	}

	private static func localizedDisplayName(at path: String?, bundle: Bundle?, fallbackName: String) -> String {
		guard let path else { return fallbackName }

		if let item = MDItemCreateWithURL(kCFAllocatorDefault, URL(fileURLWithPath: path) as CFURL),
		   let displayName = MDItemCopyAttribute(item, kMDItemDisplayName) as? String {
			let strippedName = displayName.deletingAppExtension
			if !strippedName.isEmpty {
				return strippedName
			}
		}

		if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
		   !displayName.isEmpty {
			return displayName
		}

		if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
		   !bundleName.isEmpty {
			return bundleName
		}

		return fallbackName
	}

	private static func preferredName(bundle: Bundle?, fallbackName: String) -> String {
		if let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
		   !bundleName.isEmpty {
			return bundleName
		}

		if let displayName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
		   !displayName.isEmpty {
			return displayName
		}

		return fallbackName
	}

	private static func deduplicatedNames(_ names: [String?]) -> [String] {
		var seen: Set<String> = []
		var result: [String] = []

		for name in names.compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) }) where !name.isEmpty {
			let key = name.normalizedAppMatchKey
			guard seen.insert(key).inserted else { continue }
			result.append(name)
		}

		return result
	}
}
