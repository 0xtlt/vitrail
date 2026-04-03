import AppKit

protocol LayoutCanvasDelegate: AnyObject {
	func canvasDidSelectWindow(_ canvas: LayoutCanvasView, windowID: UUID?)
	func canvasDidUpdateWindow(_ canvas: LayoutCanvasView, windowID: UUID)
	func canvasDidDeleteWindow(_ canvas: LayoutCanvasView, windowID: UUID)
	func canvasDidCreateWindow(_ canvas: LayoutCanvasView, rule: EditableWindowRule)
}

final class LayoutCanvasView: NSView {
	weak var delegate: LayoutCanvasDelegate?

	var windows: [EditableWindowRule] = [] {
		didSet {
			// Invalidate cache for changed/removed app names
			let currentNames = Set(windows.map(\.app))
			let cachedNames = Set(iconCache.keys)
			for gone in cachedNames.subtracting(currentNames) { iconCache.removeValue(forKey: gone) }
			// Reset not-found for names no longer in list (allow retry on re-add)
			iconNotFound.formIntersection(currentNames)
			needsDisplay = true
		}
	}
	var selectedWindowID: UUID? { didSet { needsDisplay = true } }
	var spacingPercent: Double = 1.0 { didSet { needsDisplay = true } }
	var gridStep: Double = 5.0

	override var isFlipped: Bool { true }
	override var acceptsFirstResponder: Bool { true }

	private var screenObserver: Any?

	func startObservingScreenChanges() {
		screenObserver = NotificationCenter.default.addObserver(
			forName: NSApplication.didChangeScreenParametersNotification,
			object: nil, queue: .main
		) { [weak self] _ in
			self?.needsDisplay = true
		}
	}

	deinit {
		if let obs = screenObserver { NotificationCenter.default.removeObserver(obs) }
	}

	// MARK: - Icon Cache

	private var iconCache: [String: NSImage] = [:]
	private var iconNotFound: Set<String> = []

	private func iconForApp(_ name: String) -> NSImage? {
		if name.isEmpty || iconNotFound.contains(name) { return nil }
		if let cached = iconCache[name] { return cached }

		// Check running apps
		if let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }),
		   let icon = app.icon {
			iconCache[name] = icon
			return icon
		}

		// Search /Applications
		if let icon = AppDiscovery.iconForApp(named: name) {
			iconCache[name] = icon
			return icon
		}

		iconNotFound.insert(name)
		return nil
	}

	// MARK: - Colors

	private let windowColors: [NSColor] = [
		.systemBlue, .systemGreen, .systemOrange, .systemPurple,
		.systemPink, .systemTeal, .systemIndigo, .systemMint
	]

	// MARK: - Drag State

	private enum DragMode { case none, move, resize(Handle), create }
	private enum Handle: CaseIterable {
		case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
	}

	private var dragMode: DragMode = .none
	private var dragWindowID: UUID?
	private var dragStart: NSPoint = .zero
	private var dragStartRule: EditableWindowRule?
	private let handleSize: CGFloat = 7
	private var createRect: NSRect = .zero
	private var createScreen: Int = 1

	// MARK: - Multi-Screen Layout

	var screenCount: Int {
		NSScreen.screens.count
	}

	private var screenAspect: CGFloat {
		guard let screen = NSScreen.main else { return 16.0 / 10.0 }
		return screen.frame.width / screen.frame.height
	}

	/// Returns the rect for a given screen index (1-based)
	private func screenRect(for screen: Int) -> NSRect {
		let rects = allScreenRects()
		let idx = max(0, min(screen - 1, rects.count - 1))
		return rects[idx]
	}

	private func allScreenRects() -> [NSRect] {
		let count = max(screenCount, maxScreenInWindows())
		let pad: CGFloat = 16
		let gap: CGFloat = 10
		let totalW = bounds.width - pad * 2 - gap * CGFloat(count - 1)
		let totalH = bounds.height - pad * 2

		let singleW = totalW / CGFloat(count)
		var singleH = singleW / screenAspect
		var finalW = singleW
		if singleH > totalH {
			singleH = totalH
			finalW = singleH * screenAspect
		}

		let totalUsedW = finalW * CGFloat(count) + gap * CGFloat(count - 1)
		let startX = (bounds.width - totalUsedW) / 2
		let startY = (bounds.height - singleH) / 2

		return (0..<count).map { i in
			NSRect(x: startX + (finalW + gap) * CGFloat(i), y: startY, width: finalW, height: singleH)
		}
	}

	private func maxScreenInWindows() -> Int {
		windows.map(\.screen).max() ?? 1
	}

	// MARK: - Coordinate Conversion

	private func ruleToRect(_ rule: EditableWindowRule) -> NSRect {
		let sr = screenRect(for: rule.screen)
		let sp = spacingPercent / 2
		let x = sr.minX + sr.width * (rule.x + sp) / 100
		let y = sr.minY + sr.height * (rule.y + sp) / 100
		let w = sr.width * max(rule.width - spacingPercent, 1) / 100
		let h = sr.height * max(rule.height - spacingPercent, 1) / 100
		return NSRect(x: x, y: y, width: w, height: h)
	}

	/// Convert pixel point to (percent x, percent y, screen index 1-based)
	private func pixelToPercent(_ point: NSPoint) -> (x: Double, y: Double, screen: Int) {
		// Find which screen the point is in
		for (i, sr) in allScreenRects().enumerated() {
			if sr.contains(point) {
				return (
					x: Double((point.x - sr.minX) / sr.width * 100),
					y: Double((point.y - sr.minY) / sr.height * 100),
					screen: i + 1
				)
			}
		}
		// Default to screen 1
		let sr = screenRect(for: 1)
		return (
			x: Double((point.x - sr.minX) / sr.width * 100),
			y: Double((point.y - sr.minY) / sr.height * 100),
			screen: 1
		)
	}

	private func snap(_ v: Double) -> Double { (v / gridStep).rounded() * gridStep }
	private func clamp(_ v: Double, _ lo: Double, _ hi: Double) -> Double { max(lo, min(hi, v)) }

	// MARK: - Drawing

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		drawBackground()
		drawGrid()
		drawWindows()
		drawCreatePreview()
	}

	private func drawBackground() {
		NSColor.windowBackgroundColor.setFill()
		bounds.fill()

		for (i, sr) in allScreenRects().enumerated() {
			NSColor.controlBackgroundColor.setFill()
			let bg = NSBezierPath(roundedRect: sr, xRadius: 6, yRadius: 6)
			bg.fill()

			NSColor.separatorColor.setStroke()
			bg.lineWidth = 1
			bg.stroke()

			// Screen label: number + name
			let screens = NSScreen.screens
			let screenName = i < screens.count ? screens[i].localizedName : "Screen \(i + 1)"
			let label = "\(i + 1) — \(screenName)"
			let attrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: 10, weight: .medium),
				.foregroundColor: NSColor.tertiaryLabelColor,
			]
			let sz = (label as NSString).size(withAttributes: attrs)
			(label as NSString).draw(at: NSPoint(x: sr.midX - sz.width / 2, y: sr.maxY + 4), withAttributes: attrs)
		}
	}

	private func drawGrid() {
		let dotColor = NSColor.tertiaryLabelColor.withAlphaComponent(0.4)
		dotColor.setFill()

		let step = 10.0
		for sr in allScreenRects() {
			for ix in 0...Int(100 / step) {
				for iy in 0...Int(100 / step) {
					let px = sr.minX + sr.width * CGFloat(ix) * CGFloat(step) / 100
					let py = sr.minY + sr.height * CGFloat(iy) * CGFloat(step) / 100
					NSBezierPath(ovalIn: NSRect(x: px - 1.5, y: py - 1.5, width: 3, height: 3)).fill()
				}
			}
		}
	}

	private func drawWindows() {
		for (i, rule) in windows.enumerated() {
			let rect = ruleToRect(rule)
			let color = windowColors[i % windowColors.count]
			let selected = rule.id == selectedWindowID

			// Shadow for selected
			if selected {
				let shadow = NSShadow()
				shadow.shadowBlurRadius = 6
				shadow.shadowOffset = NSSize(width: 0, height: -2)
				shadow.shadowColor = NSColor.black.withAlphaComponent(0.15)
				NSGraphicsContext.saveGraphicsState()
				shadow.set()
			}

			// Fill
			let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
			color.withAlphaComponent(selected ? 0.22 : 0.10).setFill()
			path.fill()

			if selected { NSGraphicsContext.restoreGraphicsState() }

			// Border
			color.withAlphaComponent(selected ? 0.9 : 0.35).setStroke()
			path.lineWidth = selected ? 2 : 1
			path.stroke()

			// App icon + name
			let name = rule.app.isEmpty ? "Untitled" : rule.app
			let fontSize = min(11, rect.height * 0.2)
			let attrs: [NSAttributedString.Key: Any] = [
				.font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
				.foregroundColor: color.withAlphaComponent(0.85),
			]
			let textSz = (name as NSString).size(withAttributes: attrs)

			if let icon = iconForApp(rule.app) {
				let iconSide = min(min(rect.width * 0.4, rect.height * 0.4), 32)
				let totalH = iconSide + 2 + textSz.height
				let startY = rect.midY - totalH / 2

				if totalH < rect.height - 6 && iconSide >= 12 {
					let iconRect = NSRect(x: rect.midX - iconSide / 2, y: startY, width: iconSide, height: iconSide)
					icon.draw(in: iconRect)

					if textSz.width < rect.width - 6 {
						(name as NSString).draw(at: NSPoint(x: rect.midX - textSz.width / 2, y: startY + iconSide + 2), withAttributes: attrs)
					}
				} else {
					// Too small for icon + text, just draw icon
					let s = min(rect.width * 0.5, rect.height * 0.5, 24)
					icon.draw(in: NSRect(x: rect.midX - s / 2, y: rect.midY - s / 2, width: s, height: s))
				}
			} else if textSz.width < rect.width - 8 && textSz.height < rect.height - 4 {
				(name as NSString).draw(at: NSPoint(x: rect.midX - textSz.width / 2, y: rect.midY - textSz.height / 2), withAttributes: attrs)
			}

			// Handles
			if selected { drawHandles(for: rect) }
		}
	}

	private func drawCreatePreview() {
		guard case .create = dragMode, createRect.width > 2, createRect.height > 2 else { return }
		let path = NSBezierPath(roundedRect: createRect, xRadius: 4, yRadius: 4)
		NSColor.controlAccentColor.withAlphaComponent(0.15).setFill()
		path.fill()
		NSColor.controlAccentColor.withAlphaComponent(0.6).setStroke()
		path.lineWidth = 1.5
		let dashPattern: [CGFloat] = [4, 3]
		path.setLineDash(dashPattern, count: 2, phase: 0)
		path.stroke()
	}

	// MARK: - Resize Handles

	private func handlePoints(for rect: NSRect) -> [Handle: NSPoint] {
		[
			.topLeft: NSPoint(x: rect.minX, y: rect.minY),
			.top: NSPoint(x: rect.midX, y: rect.minY),
			.topRight: NSPoint(x: rect.maxX, y: rect.minY),
			.right: NSPoint(x: rect.maxX, y: rect.midY),
			.bottomRight: NSPoint(x: rect.maxX, y: rect.maxY),
			.bottom: NSPoint(x: rect.midX, y: rect.maxY),
			.bottomLeft: NSPoint(x: rect.minX, y: rect.maxY),
			.left: NSPoint(x: rect.minX, y: rect.midY),
		]
	}

	private func drawHandles(for rect: NSRect) {
		for (_, pt) in handlePoints(for: rect) {
			let hr = NSRect(x: pt.x - handleSize / 2, y: pt.y - handleSize / 2, width: handleSize, height: handleSize)
			NSColor.white.setFill()
			NSColor.controlAccentColor.setStroke()
			let p = NSBezierPath(roundedRect: hr, xRadius: 2, yRadius: 2)
			p.fill()
			p.lineWidth = 1.5
			p.stroke()
		}
	}

	// MARK: - Hit Testing

	private func hitHandle(at point: NSPoint) -> Handle? {
		guard let sid = selectedWindowID, let rule = windows.first(where: { $0.id == sid }) else { return nil }
		let rect = ruleToRect(rule)
		for (handle, pt) in handlePoints(for: rect) {
			let hr = NSRect(x: pt.x - handleSize, y: pt.y - handleSize, width: handleSize * 2, height: handleSize * 2)
			if hr.contains(point) { return handle }
		}
		return nil
	}

	private func hitWindow(at point: NSPoint) -> UUID? {
		for rule in windows.reversed() {
			if ruleToRect(rule).contains(point) { return rule.id }
		}
		return nil
	}

	// MARK: - Mouse Events

	override func mouseDown(with event: NSEvent) {
		window?.makeFirstResponder(self)
		let pt = convert(event.locationInWindow, from: nil)

		// Check resize handle first
		if let handle = hitHandle(at: pt), let sid = selectedWindowID {
			dragMode = .resize(handle)
			dragWindowID = sid
			dragStart = pt
			dragStartRule = windows.first { $0.id == sid }
			return
		}

		// Check window hit
		if let wid = hitWindow(at: pt) {
			selectedWindowID = wid
			dragMode = .move
			dragWindowID = wid
			dragStart = pt
			dragStartRule = windows.first { $0.id == wid }
			delegate?.canvasDidSelectWindow(self, windowID: wid)
			needsDisplay = true
			return
		}

		// Empty space — start creating a new window
		selectedWindowID = nil
		delegate?.canvasDidSelectWindow(self, windowID: nil)

		// Only start create if click is inside a screen rect
		let (_, _, screen) = pixelToPercent(pt)
		let sr = screenRect(for: screen)
		if sr.contains(pt) {
			dragMode = .create
			dragStart = pt
			createScreen = screen
			createRect = .zero
		}
		needsDisplay = true
	}

	override func mouseDragged(with event: NSEvent) {
		let pt = convert(event.locationInWindow, from: nil)

		// Handle create mode separately
		if case .create = dragMode {
			let sr = screenRect(for: createScreen)
			let x1 = min(dragStart.x, pt.x)
			let y1 = min(dragStart.y, pt.y)
			let x2 = max(dragStart.x, pt.x)
			let y2 = max(dragStart.y, pt.y)
			// Clamp to screen rect
			createRect = NSRect(
				x: max(x1, sr.minX), y: max(y1, sr.minY),
				width: min(x2, sr.maxX) - max(x1, sr.minX),
				height: min(y2, sr.maxY) - max(y1, sr.minY)
			)
			needsDisplay = true
			return
		}

		guard let wid = dragWindowID, let start = dragStartRule,
			  let idx = windows.firstIndex(where: { $0.id == wid }) else { return }

		let sr = screenRect(for: start.screen)
		let dx = Double((pt.x - dragStart.x) / sr.width * 100)
		let dy = Double((pt.y - dragStart.y) / sr.height * 100)

		switch dragMode {
		case .none, .create: break
		case .move:
			let currentSR = screenRect(for: start.screen)
			let centerPx = NSPoint(
				x: currentSR.minX + currentSR.width * (start.x + start.width / 2) / 100 + (pt.x - dragStart.x),
				y: currentSR.minY + currentSR.height * (start.y + start.height / 2) / 100 + (pt.y - dragStart.y)
			)
			let (_, _, newScreen) = pixelToPercent(centerPx)
			let targetSR = screenRect(for: newScreen)

			let nx = snap(clamp(start.x + dx * (currentSR.width / targetSR.width), 0, 100 - start.width))
			let ny = snap(clamp(start.y + dy * (currentSR.height / targetSR.height), 0, 100 - start.height))
			windows[idx].x = nx
			windows[idx].y = ny
			windows[idx].screen = newScreen
		case .resize(let h):
			applyResize(h, idx: idx, start: start, dx: dx, dy: dy)
		}

		delegate?.canvasDidUpdateWindow(self, windowID: wid)
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		if case .create = dragMode {
			let sr = screenRect(for: createScreen)
			let minDrag: CGFloat = 10
			if createRect.width > minDrag && createRect.height > minDrag {
				let x = snap(Double((createRect.minX - sr.minX) / sr.width * 100))
				let y = snap(Double((createRect.minY - sr.minY) / sr.height * 100))
				let w = snap(Double(createRect.width / sr.width * 100))
				let h = snap(Double(createRect.height / sr.height * 100))

				var rule = EditableWindowRule()
				rule.x = clamp(x, 0, 100)
				rule.y = clamp(y, 0, 100)
				rule.width = clamp(w, 5, 100 - x)
				rule.height = clamp(h, 5, 100 - y)
				rule.screen = createScreen
				delegate?.canvasDidCreateWindow(self, rule: rule)
			}
			createRect = .zero
		}

		if case .move = dragMode { NSCursor.openHand.set() }
		dragMode = .none
		dragWindowID = nil
		dragStartRule = nil
		needsDisplay = true
	}

	override func keyDown(with event: NSEvent) {
		// Delete/Backspace to remove selected window
		if (event.keyCode == 51 || event.keyCode == 117), let sid = selectedWindowID {
			delegate?.canvasDidDeleteWindow(self, windowID: sid)
		} else {
			super.keyDown(with: event)
		}
	}

	// MARK: - Cursor

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach { removeTrackingArea($0) }
		addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInActiveApp, .inVisibleRect], owner: self))
	}

	override func mouseMoved(with event: NSEvent) {
		let pt = convert(event.locationInWindow, from: nil)

		if let handle = hitHandle(at: pt) {
			switch handle {
			case .left, .right: NSCursor.resizeLeftRight.set()
			case .top, .bottom: NSCursor.resizeUpDown.set()
			default: NSCursor.crosshair.set()
			}
		} else if hitWindow(at: pt) != nil {
			NSCursor.openHand.set()
		} else {
			NSCursor.arrow.set()
		}
	}

	// MARK: - Resize Logic

	private func applyResize(_ handle: Handle, idx: Int, start: EditableWindowRule, dx: Double, dy: Double) {
		var x = start.x, y = start.y, w = start.width, h = start.height
		let minS = 5.0

		switch handle {
		case .topLeft:     x = snap(start.x + dx); y = snap(start.y + dy); w = snap(start.width - dx); h = snap(start.height - dy)
		case .top:         y = snap(start.y + dy); h = snap(start.height - dy)
		case .topRight:    y = snap(start.y + dy); w = snap(start.width + dx); h = snap(start.height - dy)
		case .right:       w = snap(start.width + dx)
		case .bottomRight: w = snap(start.width + dx); h = snap(start.height + dy)
		case .bottom:      h = snap(start.height + dy)
		case .bottomLeft:  x = snap(start.x + dx); w = snap(start.width - dx); h = snap(start.height + dy)
		case .left:        x = snap(start.x + dx); w = snap(start.width - dx)
		}

		w = max(minS, w); h = max(minS, h)
		x = clamp(x, 0, 100 - minS); y = clamp(y, 0, 100 - minS)
		if x + w > 100 { w = 100 - x }
		if y + h > 100 { h = 100 - y }

		windows[idx].x = x; windows[idx].y = y
		windows[idx].width = w; windows[idx].height = h
	}
}
