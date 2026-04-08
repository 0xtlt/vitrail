import Foundation

struct Updater {
	static let currentVersion = "2.1.3"
	static let repo = "0xtlt/vitrail"

	struct Release {
		let version: String
		let url: String
	}

	/// Check if installed via Homebrew
	static var isHomebrew: Bool {
		let paths = [
			"/opt/homebrew/Caskroom/vitrail",
			"/usr/local/Caskroom/vitrail",
		]
		return paths.contains { FileManager.default.fileExists(atPath: $0) }
	}

	/// Run brew upgrade in Terminal
	static func brewUpgrade() {
		let script = """
		tell application "Terminal"
			activate
			do script "brew upgrade vitrail"
		end tell
		"""
		if let appleScript = NSAppleScript(source: script) {
			var error: NSDictionary?
			appleScript.executeAndReturnError(&error)
		}
	}

	/// Check GitHub for a newer release (async, non-blocking)
	static func checkForUpdate(completion: @escaping (Release?) -> Void) {
		let urlString = "https://api.github.com/repos/\(repo)/releases/latest"
		guard let url = URL(string: urlString) else { completion(nil); return }

		var request = URLRequest(url: url)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		request.timeoutInterval = 10

		URLSession.shared.dataTask(with: request) { data, _, error in
			guard error == nil, let data = data else {
				completion(nil)
				return
			}

			guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
				  let tagName = json["tag_name"] as? String,
				  let htmlUrl = json["html_url"] as? String
			else {
				completion(nil)
				return
			}

			let remoteVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

			if isNewer(remote: remoteVersion, current: currentVersion) {
				completion(Release(version: remoteVersion, url: htmlUrl))
			} else {
				completion(nil)
			}
		}.resume()
	}

	/// Simple semver comparison
	private static func isNewer(remote: String, current: String) -> Bool {
		let r = remote.split(separator: ".").compactMap { Int($0) }
		let c = current.split(separator: ".").compactMap { Int($0) }
		for i in 0..<max(r.count, c.count) {
			let rv = i < r.count ? r[i] : 0
			let cv = i < c.count ? c[i] : 0
			if rv > cv { return true }
			if rv < cv { return false }
		}
		return false
	}
}
