import AppKit

struct Screen {
	/// Get screen by index (1-based). Falls back to main screen.
	static func screen(at index: Int) -> NSScreen {
		let screens = NSScreen.screens
		if index >= 1, index <= screens.count {
			return screens[index - 1]
		}
		return NSScreen.main ?? screens[0]
	}

	/// Convert spacing to pixels relative to a screen
	static func spacingPixels(_ spacing: Spacing, screen: NSScreen) -> Double {
		if spacing.isPercent {
			let minDim = min(screen.visibleFrame.width, screen.visibleFrame.height)
			return minDim * spacing.value / 100.0
		} else {
			return spacing.value
		}
	}

	/// Convert percentage-based rect to pixel coordinates (AX top-left origin) on a specific screen
	static func percentToPixels(
		x: Double, y: Double, width: Double, height: Double,
		screenIndex: Int = 1,
		spacing: Spacing = .default
	) -> (CGPoint, CGSize) {
		let targetScreen = screen(at: screenIndex)
		let primaryScreen = NSScreen.screens.first ?? targetScreen
		let visible = targetScreen.visibleFrame
		let gap = spacingPixels(spacing, screen: targetScreen)

		// AX API uses top-left origin relative to primary screen's top-left
		// NSScreen uses bottom-left origin
		let primaryHeight = primaryScreen.frame.height

		// Raw position and size from percentages
		let rawX = visible.origin.x + (visible.width * x / 100.0)
		// Convert from NSScreen bottom-left to AX top-left
		let rawNSY = visible.origin.y + visible.height - (visible.height * y / 100.0)
		let rawH = visible.height * height / 100.0
		let rawW = visible.width * width / 100.0
		let axY = primaryHeight - rawNSY

		// Apply spacing
		let isLeftEdge = x < 1
		let isTopEdge = y < 1
		let isRightEdge = (x + width) > 99
		let isBottomEdge = (y + height) > 99

		let leftGap = isLeftEdge ? gap : gap / 2
		let topGap = isTopEdge ? gap : gap / 2
		let rightGap = isRightEdge ? gap : gap / 2
		let bottomGap = isBottomEdge ? gap : gap / 2

		let finalX = rawX + leftGap
		let finalY = axY + topGap
		let finalW = rawW - leftGap - rightGap
		let finalH = rawH - topGap - bottomGap

		return (CGPoint(x: finalX, y: finalY), CGSize(width: finalW, height: finalH))
	}
}
