import AppKit

private final class SidebarRowView: NSView {
	var onHoverChanged: ((Bool) -> Void)?

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach { removeTrackingArea($0) }
		addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
	}

	override func mouseEntered(with event: NSEvent) {
		onHoverChanged?(true)
	}

	override func mouseExited(with event: NSEvent) {
		onHoverChanged?(false)
	}
}

final class ConfiguratorViewController: NSViewController, LayoutCanvasDelegate, NSTextFieldDelegate {

	// MARK: - Data

	private var layouts: [EditableLayout]
	private var spacing: String
	private var hideOthers: Bool
	private var selectedLayoutIndex: Int?
	private var selectedVariantIndex: Int?
	private var selectedWindowID: UUID?
	private var sidebarSelections: [SidebarSelection] = []
	private var setupEditSignaturesByTag: [Int: String] = [:]
	private var nextSetupEditTag = 10_000

	private enum SidebarSelection: Equatable {
		case setup(String)
		case layout(Int)
		case variant(Int, Int)
	}

	var onSave: ((Config) -> Void)?
	var onClose: (() -> Void)?
	weak var appController: AppController?

	// Snapshot for dirty detection
	private var initialLayouts: [EditableLayout] = []
	private var initialSpacing: String = ""
	private var initialHideOthers: Bool = true
	private var didSave = false

	// MARK: - UI — Sidebar

	private let sidebarView = NSVisualEffectView()
	private let layoutStack = NSStackView()
	private let addLayoutBtn = NSButton()
	private let spacingField = NSTextField()
	private let spacingUnitToggle = NSSegmentedControl(labels: ["%", "px"], trackingMode: .selectOne, target: nil, action: nil)
	private let hideOthersCheck = NSButton(checkboxWithTitle: "Hide other apps", target: nil, action: nil)

	// MARK: - UI — Content

	private let contentView = NSView()
	private let placeholderLabel = NSTextField(labelWithString: "Select a layout")
	private let placeholderIcon = NSImageView()

	// Header
	private let headerView = NSView()
	private let nameField = NSTextField()
	private let hotkeyRecorder = HotkeyRecorderView()

	// Variant controls
	private let variantBarView = NSView()
	private let variantNameField = NSTextField()
	private let setupStatusLabel = NSTextField(labelWithString: "")
	private let captureSetupBtn = NSButton(title: "Add Current Setup", target: nil, action: nil)
	private let duplicateVariantBtn = NSButton(title: "Copy to Current Setup", target: nil, action: nil)
	private let deleteVariantBtn = NSButton(title: "Delete Setup", target: nil, action: nil)

	// Canvas
	private let canvasView = LayoutCanvasView()

	// Inspector
	private let inspectorView = NSView()
	private let appField = NSTextField()
	private let appBrowseBtn = NSButton()
	private let titleField = NSTextField()
	private let screenPopup = NSPopUpButton()
	private let xField = NSTextField()
	private let yField = NSTextField()
	private let wField = NSTextField()
	private let hField = NSTextField()
	private let addWindowBtn = NSButton()
	private let deleteWindowBtn = NSButton()
	private let noWindowLabel = NSTextField(labelWithString: "Click a window in the preview, or add one.")

	// Labels
	private let nameLabel = NSTextField(labelWithString: "Name")
	private let hotkeyLabel = NSTextField(labelWithString: "Hotkey")
	private let variantNameLabel = NSTextField(labelWithString: "Setup name")
	private let spacingLabel = NSTextField(labelWithString: "Spacing")
	private let appLabel = NSTextField(labelWithString: "App")
	private let titleLabel = NSTextField(labelWithString: "Title")
	private let screenLabel = NSTextField(labelWithString: "Screen")
	private let xLabel = NSTextField(labelWithString: "X")
	private let yLabel = NSTextField(labelWithString: "Y")
	private let wLabel = NSTextField(labelWithString: "W")
	private let hLabel = NSTextField(labelWithString: "H")

	// Buttons
	private let cancelBtn = NSButton(title: "Cancel", target: nil, action: nil)
	private let saveBtn = NSButton(title: "Save", target: nil, action: nil)

	// MARK: - Init

	init(config: Config) {
		self.layouts = config.layouts.map { EditableLayout(from: $0) }
		self.spacing = config.spacing.toTOMLString()
		self.hideOthers = config.hideOthers
		super.init(nibName: nil, bundle: nil)
		self.initialLayouts = self.layouts
		self.initialSpacing = self.spacing
		self.initialHideOthers = self.hideOthers
	}

	required init?(coder: NSCoder) { fatalError() }

	// MARK: - Lifecycle

	override func loadView() {
		let root = NSView(frame: NSRect(x: 0, y: 0, width: 720, height: 520))
		self.view = root

		buildSidebar()
		buildContent()

		layoutConstraints()
		refreshSidebar()
		refreshContent()
		updateSaveButton()

		// Prevent auto-focus on any text field
		DispatchQueue.main.async { [weak self] in
			self?.view.window?.makeFirstResponder(nil)
		}
	}

	// MARK: - Build Sidebar

	private func buildSidebar() {
		sidebarView.material = .sidebar
		sidebarView.blendingMode = .withinWindow
		sidebarView.state = .active

		// Layout list
		layoutStack.orientation = .vertical
		layoutStack.alignment = .leading
		layoutStack.spacing = 2

		// Add button
		addLayoutBtn.bezelStyle = .inline
		addLayoutBtn.title = ""
		addLayoutBtn.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")
		addLayoutBtn.imagePosition = .imageLeading
		addLayoutBtn.target = self
		addLayoutBtn.action = #selector(addLayout)
		addLayoutBtn.isBordered = false
		addLayoutBtn.font = .systemFont(ofSize: 12)
		addLayoutBtn.attributedTitle = NSAttributedString(string: " Add Layout", attributes: [.font: NSFont.systemFont(ofSize: 12)])

		// Spacing — value field + unit toggle
		let parsed = Spacing.parse(spacing)
		spacingField.stringValue = parsed.value == parsed.value.rounded() ? "\(Int(parsed.value))" : "\(parsed.value)"
		spacingField.placeholderString = "1"
		spacingField.alignment = .right
		spacingField.delegate = self
		spacingField.bezelStyle = .squareBezel
		spacingField.font = .systemFont(ofSize: 12)
		spacingField.wantsLayer = true
		spacingField.layer?.cornerRadius = 4
		spacingField.layer?.maskedCorners = [.layerMinXMinYCorner, .layerMinXMaxYCorner]
		spacingField.layer?.masksToBounds = true

		spacingUnitToggle.font = .systemFont(ofSize: 10)
		spacingUnitToggle.segmentStyle = .smallSquare
		spacingUnitToggle.selectedSegment = parsed.isPercent ? 0 : 1
		spacingUnitToggle.target = self
		spacingUnitToggle.action = #selector(spacingUnitChanged)

		// Hide others
		hideOthersCheck.state = hideOthers ? .on : .off
		hideOthersCheck.target = self
		hideOthersCheck.action = #selector(hideOthersChanged)
		hideOthersCheck.font = .systemFont(ofSize: 12)

		spacingLabel.font = .systemFont(ofSize: 11)
		spacingLabel.textColor = .secondaryLabelColor

		sidebarView.addSubview(layoutStack)
		sidebarView.addSubview(addLayoutBtn)
		sidebarView.addSubview(spacingLabel)
		sidebarView.addSubview(spacingField)
		sidebarView.addSubview(spacingUnitToggle)
		sidebarView.addSubview(hideOthersCheck)
	}

	// MARK: - Build Content

	private func buildContent() {
		// Placeholder
		placeholderLabel.font = .systemFont(ofSize: 14)
		placeholderLabel.textColor = .secondaryLabelColor
		placeholderLabel.alignment = .center
		placeholderIcon.image = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
		placeholderIcon.symbolConfiguration = .init(pointSize: 40, weight: .thin)
		placeholderIcon.contentTintColor = .tertiaryLabelColor
		contentView.addSubview(placeholderIcon)
		contentView.addSubview(placeholderLabel)

		// Header
		nameField.bezelStyle = .roundedBezel
		nameField.font = .systemFont(ofSize: 13)
		nameField.delegate = self
		nameField.placeholderString = "Layout name"

		hotkeyRecorder.onChange = { [weak self] newHotkey in
			guard let self, let idx = self.selectedLayoutIndex else { return }
			let duplicate = self.layouts.enumerated().contains { otherIndex, layout in
				otherIndex != idx && !newHotkey.isEmpty && layout.hotkey == newHotkey
			}
			if duplicate {
				self.hotkeyRecorder.hotkey = self.layouts[idx].hotkey
				self.showAlert(message: "Hotkey already used", informativeText: "Choose a different hotkey for this layout group.")
				return
			}
			self.layouts[idx].hotkey = newHotkey
			self.refreshSidebar()
			self.updateSaveButton()
		}
		hotkeyRecorder.onRecordingChanged = { [weak self] recording in
			guard let self else { return }
			if recording {
				self.appController?.hotKeyManager.pause()
			} else {
				self.appController?.hotKeyManager.resume()
			}
		}

		for l in [nameLabel, hotkeyLabel] {
			l.font = .systemFont(ofSize: 11)
			l.textColor = .secondaryLabelColor
		}

		headerView.addSubview(nameLabel)
		headerView.addSubview(nameField)
		headerView.addSubview(hotkeyLabel)
		headerView.addSubview(hotkeyRecorder)
		contentView.addSubview(headerView)

		variantNameField.bezelStyle = .roundedBezel
		variantNameField.font = .systemFont(ofSize: 12)
		variantNameField.delegate = self
		variantNameField.isEditable = true
		variantNameField.isSelectable = true
		variantNameField.placeholderString = "Variant name"

		setupStatusLabel.font = .systemFont(ofSize: 11)
		setupStatusLabel.textColor = .secondaryLabelColor
		setupStatusLabel.lineBreakMode = .byTruncatingTail

		for button in [captureSetupBtn, duplicateVariantBtn, deleteVariantBtn] {
			button.bezelStyle = .rounded
			button.font = .systemFont(ofSize: 11)
			button.target = self
			button.isHidden = true
		}
		captureSetupBtn.action = #selector(captureCurrentSetup)
		duplicateVariantBtn.action = #selector(duplicateVariant)
		deleteVariantBtn.action = #selector(deleteVariant)

		variantNameLabel.font = .systemFont(ofSize: 11)
		variantNameLabel.textColor = .secondaryLabelColor

		variantBarView.addSubview(variantNameLabel)
		variantBarView.addSubview(variantNameField)
		variantBarView.addSubview(setupStatusLabel)
		variantBarView.addSubview(captureSetupBtn)
		variantBarView.addSubview(duplicateVariantBtn)
		variantBarView.addSubview(deleteVariantBtn)
		contentView.addSubview(variantBarView)

		// Canvas
		canvasView.delegate = self
		canvasView.startObservingScreenChanges()

		// Update screen popup when monitors change
		NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
			self?.rebuildScreenPopup()
		}
		contentView.addSubview(canvasView)

		// Inspector
		buildInspector()
		contentView.addSubview(inspectorView)

		// Buttons
		cancelBtn.bezelStyle = .rounded
		cancelBtn.target = self
		cancelBtn.action = #selector(cancel)
		cancelBtn.keyEquivalent = "\u{1b}" // Escape

		saveBtn.bezelStyle = .rounded
		saveBtn.target = self
		saveBtn.action = #selector(save)
		saveBtn.keyEquivalent = "s"
		saveBtn.keyEquivalentModifierMask = .command

		contentView.addSubview(cancelBtn)
		contentView.addSubview(saveBtn)

		view.addSubview(sidebarView)
		view.addSubview(contentView)
	}

	private func buildInspector() {
		appField.bezelStyle = .roundedBezel
		appField.font = .systemFont(ofSize: 12)
		appField.placeholderString = "App name"
		appField.delegate = self

		appBrowseBtn.bezelStyle = .rounded
		appBrowseBtn.title = "Browse…"
		appBrowseBtn.font = .systemFont(ofSize: 11)
		appBrowseBtn.target = self
		appBrowseBtn.action = #selector(showAppMenu)

		titleField.bezelStyle = .roundedBezel
		titleField.font = .systemFont(ofSize: 12)
		titleField.placeholderString = "Title filter"
		titleField.delegate = self

		screenPopup.font = .systemFont(ofSize: 12)
		let screenCount = Screen.currentDisplaySetup().displayCount
		for i in 1...max(screenCount, 1) { screenPopup.addItem(withTitle: "\(i)") }
		screenPopup.target = self
		screenPopup.action = #selector(screenChanged)
		screenLabel.isHidden = screenCount <= 1
		screenPopup.isHidden = screenCount <= 1

		for f in [xField, yField, wField, hField] {
			f.bezelStyle = .roundedBezel
			f.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
			f.alignment = .center
			f.delegate = self
		}
		xField.placeholderString = "X"
		yField.placeholderString = "Y"
		wField.placeholderString = "W"
		hField.placeholderString = "H"

		addWindowBtn.bezelStyle = .inline
		addWindowBtn.image = NSImage(systemSymbolName: "plus.rectangle", accessibilityDescription: "Add")
		addWindowBtn.imagePosition = .imageLeading
		addWindowBtn.isBordered = false
		addWindowBtn.target = self
		addWindowBtn.action = #selector(addWindow)
		addWindowBtn.attributedTitle = NSAttributedString(string: " Add Window", attributes: [.font: NSFont.systemFont(ofSize: 12)])

		deleteWindowBtn.bezelStyle = .inline
		deleteWindowBtn.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Delete")
		deleteWindowBtn.isBordered = false
		deleteWindowBtn.target = self
		deleteWindowBtn.action = #selector(deleteSelectedWindow)
		deleteWindowBtn.contentTintColor = .systemRed

		noWindowLabel.font = .systemFont(ofSize: 12)
		noWindowLabel.textColor = .tertiaryLabelColor
		noWindowLabel.alignment = .center

		for l in [appLabel, titleLabel, screenLabel, xLabel, yLabel, wLabel, hLabel] {
			l.font = .systemFont(ofSize: 10)
			l.textColor = .tertiaryLabelColor
		}

		for v: NSView in [appLabel, appField, appBrowseBtn, titleLabel, titleField, screenLabel, screenPopup,
						   xLabel, xField, yLabel, yField, wLabel, wField, hLabel, hField,
						   addWindowBtn, deleteWindowBtn, noWindowLabel] {
			inspectorView.addSubview(v)
		}
	}

	// MARK: - Auto Layout

	private func layoutConstraints() {
		let all: [NSView] = [sidebarView, contentView, layoutStack, addLayoutBtn, spacingLabel, spacingField, spacingUnitToggle, hideOthersCheck,
			placeholderIcon, placeholderLabel, headerView, nameLabel, nameField, hotkeyLabel, hotkeyRecorder,
			variantBarView, variantNameLabel, variantNameField, setupStatusLabel, captureSetupBtn, duplicateVariantBtn, deleteVariantBtn, canvasView,
			inspectorView, cancelBtn, saveBtn, appLabel, appField, appBrowseBtn, titleLabel, titleField, screenLabel, screenPopup,
			xLabel, xField, yLabel, yField, wLabel, wField, hLabel, hField, addWindowBtn, deleteWindowBtn, noWindowLabel]
		for v in all { v.translatesAutoresizingMaskIntoConstraints = false }

		NSLayoutConstraint.activate([
			// Sidebar
			sidebarView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
			sidebarView.topAnchor.constraint(equalTo: view.topAnchor),
			sidebarView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
			sidebarView.widthAnchor.constraint(equalToConstant: 200),

			// Content
			contentView.leadingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: 1),
			contentView.topAnchor.constraint(equalTo: view.topAnchor),
			contentView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
			contentView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

			// Sidebar internals
			layoutStack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 8),
			layoutStack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 8),
			layoutStack.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -8),

			addLayoutBtn.topAnchor.constraint(equalTo: layoutStack.bottomAnchor, constant: 6),
			addLayoutBtn.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),

			spacingLabel.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),
			spacingLabel.centerYAnchor.constraint(equalTo: spacingField.centerYAnchor),

			spacingUnitToggle.bottomAnchor.constraint(equalTo: hideOthersCheck.topAnchor, constant: -8),
			spacingUnitToggle.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -12),
			spacingUnitToggle.widthAnchor.constraint(equalToConstant: 56),

			spacingField.centerYAnchor.constraint(equalTo: spacingUnitToggle.centerYAnchor),
			spacingField.trailingAnchor.constraint(equalTo: spacingUnitToggle.leadingAnchor),
			spacingField.widthAnchor.constraint(equalToConstant: 36),
			spacingField.heightAnchor.constraint(equalTo: spacingUnitToggle.heightAnchor),

			hideOthersCheck.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -12),
			hideOthersCheck.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 12),

			// Placeholder
			placeholderIcon.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			placeholderIcon.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: -16),
			placeholderLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			placeholderLabel.topAnchor.constraint(equalTo: placeholderIcon.bottomAnchor, constant: 8),

			// Header (label row + field row)
			headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 10),
			headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			headerView.heightAnchor.constraint(equalToConstant: 42),

			nameLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
			nameLabel.topAnchor.constraint(equalTo: headerView.topAnchor),

			nameField.leadingAnchor.constraint(equalTo: headerView.leadingAnchor),
			nameField.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
			nameField.widthAnchor.constraint(greaterThanOrEqualToConstant: 140),

			hotkeyLabel.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 12),
			hotkeyLabel.topAnchor.constraint(equalTo: headerView.topAnchor),

			hotkeyRecorder.leadingAnchor.constraint(equalTo: nameField.trailingAnchor, constant: 12),
			hotkeyRecorder.bottomAnchor.constraint(equalTo: headerView.bottomAnchor),
			hotkeyRecorder.widthAnchor.constraint(equalToConstant: 120),
			hotkeyRecorder.heightAnchor.constraint(equalToConstant: 24),

			variantBarView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 8),
			variantBarView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			variantBarView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			variantBarView.heightAnchor.constraint(equalToConstant: 54),

			variantNameLabel.leadingAnchor.constraint(equalTo: variantBarView.leadingAnchor),
			variantNameLabel.topAnchor.constraint(equalTo: variantBarView.topAnchor),

			variantNameField.leadingAnchor.constraint(equalTo: variantBarView.leadingAnchor),
			variantNameField.topAnchor.constraint(equalTo: variantNameLabel.bottomAnchor, constant: 4),
			variantNameField.widthAnchor.constraint(equalToConstant: 150),
			variantNameField.heightAnchor.constraint(equalToConstant: 22),

			setupStatusLabel.leadingAnchor.constraint(equalTo: variantNameField.trailingAnchor, constant: 12),
			setupStatusLabel.centerYAnchor.constraint(equalTo: variantNameField.centerYAnchor),
			setupStatusLabel.trailingAnchor.constraint(equalTo: variantBarView.trailingAnchor),

			// Buttons (anchor to bottom first)
			saveBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
			saveBtn.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
			cancelBtn.trailingAnchor.constraint(equalTo: saveBtn.leadingAnchor, constant: -8),

			// Inspector (anchored above buttons, taller for labels + spacing)
			inspectorView.bottomAnchor.constraint(equalTo: cancelBtn.topAnchor, constant: -12),
			inspectorView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			inspectorView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			inspectorView.heightAnchor.constraint(equalToConstant: 86),

			// Canvas (fills space between variant controls and inspector)
			canvasView.topAnchor.constraint(equalTo: variantBarView.bottomAnchor, constant: 8),
			canvasView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
			canvasView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
			canvasView.bottomAnchor.constraint(equalTo: inspectorView.topAnchor, constant: -10),

			// Inspector internals — row 1: labels
			appLabel.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
			appLabel.topAnchor.constraint(equalTo: inspectorView.topAnchor),

			titleLabel.leadingAnchor.constraint(equalTo: appBrowseBtn.trailingAnchor, constant: 10),
			titleLabel.topAnchor.constraint(equalTo: inspectorView.topAnchor),

			screenLabel.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
			screenLabel.topAnchor.constraint(equalTo: inspectorView.topAnchor),

			// Inspector internals — row 2: app/title/screen fields
			appField.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
			appField.topAnchor.constraint(equalTo: appLabel.bottomAnchor, constant: 4),
			appField.widthAnchor.constraint(equalToConstant: 120),
			appField.heightAnchor.constraint(equalToConstant: 22),

			appBrowseBtn.leadingAnchor.constraint(equalTo: appField.trailingAnchor, constant: 2),
			appBrowseBtn.centerYAnchor.constraint(equalTo: appField.centerYAnchor),

			titleField.leadingAnchor.constraint(equalTo: appBrowseBtn.trailingAnchor, constant: 8),
			titleField.topAnchor.constraint(equalTo: appField.topAnchor),
			titleField.widthAnchor.constraint(equalToConstant: 90),
			titleField.heightAnchor.constraint(equalToConstant: 22),

			screenPopup.leadingAnchor.constraint(equalTo: titleField.trailingAnchor, constant: 8),
			screenPopup.centerYAnchor.constraint(equalTo: appField.centerYAnchor),
			screenPopup.widthAnchor.constraint(equalToConstant: 48),

			// Inspector internals — row 3: labels + geometry fields
			xLabel.leadingAnchor.constraint(equalTo: inspectorView.leadingAnchor),
			xLabel.topAnchor.constraint(equalTo: appField.bottomAnchor, constant: 10),

			xField.leadingAnchor.constraint(equalTo: xLabel.trailingAnchor, constant: 2),
			xField.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),
			xField.widthAnchor.constraint(equalToConstant: 40),
			xField.heightAnchor.constraint(equalToConstant: 20),

			yLabel.leadingAnchor.constraint(equalTo: xField.trailingAnchor, constant: 8),
			yLabel.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),

			yField.leadingAnchor.constraint(equalTo: yLabel.trailingAnchor, constant: 2),
			yField.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),
			yField.widthAnchor.constraint(equalToConstant: 40),
			yField.heightAnchor.constraint(equalToConstant: 20),

			wLabel.leadingAnchor.constraint(equalTo: yField.trailingAnchor, constant: 12),
			wLabel.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),

			wField.leadingAnchor.constraint(equalTo: wLabel.trailingAnchor, constant: 2),
			wField.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),
			wField.widthAnchor.constraint(equalToConstant: 40),
			wField.heightAnchor.constraint(equalToConstant: 20),

			hLabel.leadingAnchor.constraint(equalTo: wField.trailingAnchor, constant: 8),
			hLabel.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),

			hField.leadingAnchor.constraint(equalTo: hLabel.trailingAnchor, constant: 2),
			hField.centerYAnchor.constraint(equalTo: xLabel.centerYAnchor),
			hField.widthAnchor.constraint(equalToConstant: 40),
			hField.heightAnchor.constraint(equalToConstant: 20),

			addWindowBtn.trailingAnchor.constraint(equalTo: inspectorView.trailingAnchor),
			addWindowBtn.topAnchor.constraint(equalTo: inspectorView.topAnchor),

			deleteWindowBtn.trailingAnchor.constraint(equalTo: addWindowBtn.leadingAnchor, constant: -8),
			deleteWindowBtn.centerYAnchor.constraint(equalTo: addWindowBtn.centerYAnchor),

			noWindowLabel.centerXAnchor.constraint(equalTo: inspectorView.centerXAnchor),
			noWindowLabel.centerYAnchor.constraint(equalTo: inspectorView.centerYAnchor),
		])
	}

	// MARK: - Refresh

	private func selectedPath() -> (layout: Int, variant: Int)? {
		guard let layoutIndex = selectedLayoutIndex,
			  layouts.indices.contains(layoutIndex),
			  let variantIndex = selectedVariantIndex,
			  layouts[layoutIndex].variants.indices.contains(variantIndex) else { return nil }
		return (layoutIndex, variantIndex)
	}

	private func currentWindows() -> [EditableWindowRule] {
		guard let path = selectedPath() else { return [] }
		return layouts[path.layout].variants[path.variant].windows
	}

	private func setCurrentWindows(_ windows: [EditableWindowRule]) {
		guard let path = selectedPath() else { return }
		layouts[path.layout].variants[path.variant].windows = windows
		canvasView.windows = windows
	}

	private func currentVariant() -> EditableLayoutVariant? {
		guard let path = selectedPath() else { return nil }
		return layouts[path.layout].variants[path.variant]
	}

	private func setupName(for signature: String) -> String {
		for layout in layouts {
			if let variant = layout.variants.first(where: { $0.displaySetup.signature == signature }) {
				return variant.name.isEmpty ? variant.displaySetup.shortName : variant.name
			}
		}
		return DisplaySetup.decode(signature)?.shortName ?? "Setup"
	}

	private func renameSetup(signature: String, name: String) {
		for layoutIndex in layouts.indices {
			for variantIndex in layouts[layoutIndex].variants.indices
				where layouts[layoutIndex].variants[variantIndex].displaySetup.signature == signature {
				layouts[layoutIndex].variants[variantIndex].name = name
			}
		}
	}

	private func ensureVariantSelection() {
		guard let layoutIndex = selectedLayoutIndex, layouts.indices.contains(layoutIndex) else {
			selectedVariantIndex = nil
			return
		}
		if layouts[layoutIndex].variants.isEmpty {
			layouts[layoutIndex].variants.append(EditableLayoutVariant())
		}
		if let variantIndex = selectedVariantIndex, layouts[layoutIndex].variants.indices.contains(variantIndex) {
			return
		}
		selectedVariantIndex = 0
	}

	private func refreshSidebar() {
		layoutStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
		sidebarSelections = []
		setupEditSignaturesByTag = [:]
		nextSetupEditTag = 10_000
		let currentSignature = Screen.currentDisplaySetup().signature
		var setupOrder: [(signature: String, name: String)] = []
		var seenSetups: Set<String> = []

		for layout in layouts {
			for variant in layout.variants {
					let signature = variant.displaySetup.signature
					if seenSetups.insert(signature).inserted {
						setupOrder.append((signature, variant.name.isEmpty ? variant.displaySetup.shortName : variant.name))
					}
			}
		}

		setupOrder.sort { lhs, rhs in
			if lhs.signature == currentSignature { return true }
			if rhs.signature == currentSignature { return false }
			return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
		}

		for setup in setupOrder {
				let row = makeSidebarRow(
				name: setup.name,
				detail: setup.signature == currentSignature ? "current" : "",
				index: -1,
				selected: false,
				kind: .setupHeader,
				setupSignature: setup.signature
			)
			sidebarSelections.append(.setup(setup.signature))
			layoutStack.addArrangedSubview(row)

			for (layoutIndex, layout) in layouts.enumerated() {
				guard let variantIndex = layout.variants.firstIndex(where: { $0.displaySetup.signature == setup.signature }) else { continue }
				let selected = layoutIndex == selectedLayoutIndex && variantIndex == selectedVariantIndex
				let layoutRow = makeSidebarRow(
					name: layout.name.isEmpty ? "Untitled" : layout.name,
					detail: layout.hotkey,
					index: layoutIndex,
					selected: selected,
					kind: .layoutChild,
					setupSignature: nil
				)
				sidebarSelections.append(.variant(layoutIndex, variantIndex))
				layoutStack.addArrangedSubview(layoutRow)
			}
		}
	}

	private enum SidebarRowKind {
		case setupHeader
		case layoutChild
	}

	private func makeSidebarRow(name: String, detail: String, index: Int, selected: Bool, kind: SidebarRowKind, setupSignature: String?) -> NSView {
		let row = SidebarRowView()
		row.translatesAutoresizingMaskIntoConstraints = false
		row.wantsLayer = true

		let selectArea = NSView()
		selectArea.translatesAutoresizingMaskIntoConstraints = false

		let label = NSTextField(labelWithString: name)
		label.font = .systemFont(ofSize: kind == .setupHeader ? 13 : 12, weight: kind == .setupHeader ? .medium : .regular)
		label.lineBreakMode = .byTruncatingTail
		label.translatesAutoresizingMaskIntoConstraints = false

		let hkLabel = NSTextField(labelWithString: detail)
		hkLabel.font = .systemFont(ofSize: 10)
		hkLabel.alignment = .right
		hkLabel.lineBreakMode = .byTruncatingTail
		hkLabel.translatesAutoresizingMaskIntoConstraints = false

		let del = NSButton(image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Delete")!, target: self, action: #selector(deleteLayoutClicked(_:)))
		del.bezelStyle = .inline
		del.isBordered = false
		del.tag = index
		del.isHidden = kind == .setupHeader
		del.translatesAutoresizingMaskIntoConstraints = false

		let edit = NSButton(image: NSImage(systemSymbolName: "pencil", accessibilityDescription: "Rename setup")!, target: self, action: #selector(renameSetupClicked(_:)))
		edit.bezelStyle = .inline
		edit.isBordered = false
		edit.translatesAutoresizingMaskIntoConstraints = false
		edit.isHidden = kind != .setupHeader
		edit.alphaValue = 0
		edit.contentTintColor = .tertiaryLabelColor
		edit.toolTip = "Rename setup"
		if let setupSignature {
			edit.tag = nextSetupEditTag
			setupEditSignaturesByTag[edit.tag] = setupSignature
			nextSetupEditTag += 1
		}
		row.onHoverChanged = { hovering in
			edit.animator().alphaValue = hovering ? 1 : 0
		}

		if selected {
			row.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
			row.layer?.cornerRadius = 5
			label.textColor = .white
			hkLabel.textColor = .white.withAlphaComponent(0.6)
			del.contentTintColor = .white.withAlphaComponent(0.7)
		} else {
			label.textColor = .labelColor
			hkLabel.textColor = .tertiaryLabelColor
			del.contentTintColor = .tertiaryLabelColor
		}

		row.addSubview(selectArea)
		selectArea.addSubview(label)
		selectArea.addSubview(hkLabel)
		row.addSubview(edit)
		row.addSubview(del)

		NSLayoutConstraint.activate([
			row.heightAnchor.constraint(equalToConstant: 30),
			row.widthAnchor.constraint(equalToConstant: 176),

			selectArea.leadingAnchor.constraint(equalTo: row.leadingAnchor),
			selectArea.topAnchor.constraint(equalTo: row.topAnchor),
			selectArea.bottomAnchor.constraint(equalTo: row.bottomAnchor),
			selectArea.trailingAnchor.constraint(equalTo: kind == .setupHeader ? edit.leadingAnchor : del.leadingAnchor, constant: -6),

			label.leadingAnchor.constraint(equalTo: selectArea.leadingAnchor, constant: kind == .setupHeader ? 10 : 22),
			label.centerYAnchor.constraint(equalTo: selectArea.centerYAnchor),

			hkLabel.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 4),
			hkLabel.trailingAnchor.constraint(equalTo: selectArea.trailingAnchor),
			hkLabel.centerYAnchor.constraint(equalTo: selectArea.centerYAnchor),
			hkLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 60),

			del.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
			del.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			del.widthAnchor.constraint(equalToConstant: 16),
			del.heightAnchor.constraint(equalToConstant: 16),

			edit.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -6),
			edit.centerYAnchor.constraint(equalTo: row.centerYAnchor),
			edit.widthAnchor.constraint(equalToConstant: 16),
			edit.heightAnchor.constraint(equalToConstant: 16),
		])

		if kind == .layoutChild {
			let click = NSClickGestureRecognizer(target: self, action: #selector(sidebarRowClicked(_:)))
			selectArea.addGestureRecognizer(click)
		}

		return row
	}

	private func indexOfSidebarRow(_ view: NSView) -> Int? {
		layoutStack.arrangedSubviews.firstIndex(of: view)
	}

	private func refreshContent() {
		updateSaveButton()
		ensureVariantSelection()
		let hasLayout = selectedLayoutIndex != nil
		headerView.isHidden = !hasLayout
		variantBarView.isHidden = !hasLayout
		canvasView.isHidden = !hasLayout
		inspectorView.isHidden = !hasLayout
		placeholderIcon.isHidden = hasLayout
		placeholderLabel.isHidden = hasLayout

		guard let idx = selectedLayoutIndex, layouts.indices.contains(idx) else { return }
		let layout = layouts[idx]

		nameField.stringValue = layout.name
		hotkeyRecorder.hotkey = layout.hotkey

			if let variant = currentVariant() {
			variantNameField.stringValue = setupName(for: variant.displaySetup.signature)
			let currentSetup = Screen.currentDisplaySetup()
			setupStatusLabel.stringValue = variant.displaySetup.signature == currentSetup.signature
				? "Current setup matches this variant"
				: "Selected setup: \(variant.displaySetup.displayCount) display(s)"
			canvasView.displaySetupOverride = variant.displaySetup
		}
		canvasView.windows = currentWindows()
		canvasView.spacingPercent = Spacing.parse(spacing).isPercent ? Spacing.parse(spacing).value : 0
		canvasView.selectedWindowID = selectedWindowID

		refreshInspector()
	}

	private func refreshInspector() {
		let hasWindow = selectedWindowID != nil
		let multiScreen = (currentVariant()?.displaySetup.displayCount ?? Screen.currentDisplaySetup().displayCount) > 1

		for v: NSView in [appLabel, appField, appBrowseBtn, titleLabel, titleField,
						   xLabel, xField, yLabel, yField, wLabel, wField, hLabel, hField, deleteWindowBtn] {
			v.isHidden = !hasWindow
		}
		screenLabel.isHidden = !hasWindow || !multiScreen
		screenPopup.isHidden = !hasWindow || !multiScreen
		noWindowLabel.isHidden = hasWindow

		guard let wid = selectedWindowID,
			  let rule = currentWindows().first(where: { $0.id == wid }) else { return }

		appField.stringValue = rule.app
		titleField.stringValue = rule.title
		screenPopup.selectItem(at: rule.screen - 1)
		xField.stringValue = "\(Int(rule.x))"
		yField.stringValue = "\(Int(rule.y))"
		wField.stringValue = "\(Int(rule.width))"
		hField.stringValue = "\(Int(rule.height))"
	}

	// MARK: - Actions — Sidebar

	@objc private func renameSetupClicked(_ sender: NSButton) {
		guard let signature = setupEditSignaturesByTag[sender.tag] else { return }
		let alert = NSAlert()
		alert.messageText = "Rename setup"
		alert.informativeText = "This name is shared by every layout under this display setup."
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
		field.stringValue = setupName(for: signature)
		alert.accessoryView = field
		alert.addButton(withTitle: "Rename")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		let newName = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !newName.isEmpty else { return }
		renameSetup(signature: signature, name: newName)
		if currentVariant()?.displaySetup.signature == signature {
			variantNameField.stringValue = newName
		}
		refreshSidebar()
		updateSaveButton()
	}

	@objc private func sidebarRowClicked(_ sender: NSClickGestureRecognizer) {
		guard let selectArea = sender.view, let row = selectArea.superview, let idx = indexOfSidebarRow(row) else { return }
		guard sidebarSelections.indices.contains(idx) else { return }
		switch sidebarSelections[idx] {
		case .setup:
			return
		case .layout(let layoutIndex):
			selectedLayoutIndex = layoutIndex
			selectedVariantIndex = layouts[layoutIndex].variants.isEmpty ? nil : 0
		case .variant(let layoutIndex, let variantIndex):
			selectedLayoutIndex = layoutIndex
			selectedVariantIndex = variantIndex
		}
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
	}

	@objc private func addLayout() {
		var layout = EditableLayout()
		layout.hotkey = nextAvailableHotkey()
		layouts.append(layout)
		selectedLayoutIndex = layouts.count - 1
		selectedVariantIndex = 0
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
	}

	private func nextAvailableHotkey() -> String {
		let used = Set(layouts.map(\.hotkey))
		for n in 1...9 {
			let candidate = "alt+\(n)"
			if !used.contains(candidate) { return candidate }
		}
		for c in "abcdefghijklmnopqrstuvwxyz" {
			let candidate = "alt+\(c)"
			if !used.contains(candidate) { return candidate }
		}
		return ""
	}

	@objc private func deleteLayoutClicked(_ sender: NSButton) {
		let idx = sender.tag
		guard layouts.indices.contains(idx) else { return }

		let name = layouts[idx].name.isEmpty ? "Untitled" : layouts[idx].name
		let alert = NSAlert()
		alert.messageText = "Delete \"\(name)\"?"
		alert.informativeText = "This layout and all its windows will be removed."
		alert.alertStyle = .informational
		alert.icon = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
		alert.addButton(withTitle: "Delete")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }

		layouts.remove(at: idx)
		if selectedLayoutIndex == idx {
			selectedLayoutIndex = layouts.isEmpty ? nil : max(0, idx - 1)
			selectedVariantIndex = selectedLayoutIndex == nil ? nil : 0
		} else if let sel = selectedLayoutIndex, sel > idx {
			selectedLayoutIndex = sel - 1
		}
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
	}

	@objc private func hideOthersChanged() {
		hideOthers = hideOthersCheck.state == .on
		updateSaveButton()
	}

	@objc private func spacingUnitChanged() {
		rebuildSpacingString()
		updateSaveButton()
	}

	private func rebuildSpacingString() {
		let value = spacingField.stringValue
		let unit = spacingUnitToggle.selectedSegment == 0 ? "%" : "px"
		spacing = "\(value)\(unit)"
		canvasView.spacingPercent = Spacing.parse(spacing).isPercent ? Spacing.parse(spacing).value : 0
	}

	// MARK: - Actions — Content

	@objc private func captureCurrentSetup() {
		guard let layoutIndex = selectedLayoutIndex, layouts.indices.contains(layoutIndex) else { return }
		let setup = Screen.currentDisplaySetup()
		if let existing = layouts[layoutIndex].variants.firstIndex(where: { $0.displaySetup.signature == setup.signature }) {
			selectedVariantIndex = existing
			selectedWindowID = nil
			refreshSidebar()
			refreshContent()
			return
		}
		let copiedWindows = currentWindows()
		layouts[layoutIndex].variants.append(EditableLayoutVariant(copying: copiedWindows, setup: setup))
		selectedVariantIndex = layouts[layoutIndex].variants.count - 1
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
		updateSaveButton()
	}

	@objc private func duplicateVariant() {
		guard let path = selectedPath() else { return }
		let variant = layouts[path.layout].variants[path.variant]
		let setup = Screen.currentDisplaySetup()
		if layouts[path.layout].variants.contains(where: { $0.displaySetup.signature == setup.signature }) {
			showAlert(message: "Current setup already exists", informativeText: "Select the existing variant or connect a different display setup before duplicating.")
			return
		}
		var copy = EditableLayoutVariant(copying: variant.windows, setup: setup)
		copy.name = setup.shortName
		layouts[path.layout].variants.append(copy)
		selectedVariantIndex = layouts[path.layout].variants.count - 1
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
		updateSaveButton()
	}

	@objc private func deleteVariant() {
		guard let path = selectedPath(), layouts[path.layout].variants.count > 1 else { return }
		layouts[path.layout].variants.remove(at: path.variant)
		selectedVariantIndex = max(0, path.variant - 1)
		selectedWindowID = nil
		refreshSidebar()
		refreshContent()
		updateSaveButton()
	}

	@objc private func addWindow() {
		let rule = EditableWindowRule()
		var windows = currentWindows()
		windows.append(rule)
		setCurrentWindows(windows)
		selectedWindowID = rule.id
		canvasView.selectedWindowID = rule.id
		refreshInspector()
		updateSaveButton()
	}

	@objc private func deleteSelectedWindow() {
		guard let wid = selectedWindowID,
			  let rule = currentWindows().first(where: { $0.id == wid }) else { return }
		confirmDeleteWindow(name: rule.app.isEmpty ? "this window" : "\"\(rule.app)\"") { [self] in
			var windows = currentWindows()
			windows.removeAll { $0.id == wid }
			setCurrentWindows(windows)
			selectedWindowID = nil
			canvasView.selectedWindowID = nil
			refreshInspector()
			updateSaveButton()
		}
	}

	private func confirmDeleteWindow(name: String, action: @escaping () -> Void) {
		let alert = NSAlert()
		alert.messageText = "Remove \(name)?"
		alert.informativeText = "This window rule will be removed from the layout."
		alert.alertStyle = .informational
		alert.icon = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
		alert.addButton(withTitle: "Remove")
		alert.addButton(withTitle: "Cancel")
		guard alert.runModal() == .alertFirstButtonReturn else { return }
		action()
	}

	@objc private func showAppMenu() {
		let menu = NSMenu()

		// Running apps
		let running = AppDiscovery.runningApps()
		if !running.isEmpty {
			let header = NSMenuItem(title: "Running", action: nil, keyEquivalent: "")
			header.isEnabled = false
			menu.addItem(header)
			for app in running {
				menu.addItem(makeAppMenuItem(app))
			}
		}

		// Installed apps (not running)
		let installed = AppDiscovery.installedApps(excludingRunning: running)
		if !installed.isEmpty {
			menu.addItem(.separator())
			let header = NSMenuItem(title: "Installed", action: nil, keyEquivalent: "")
			header.isEnabled = false
			menu.addItem(header)
			for app in installed {
				menu.addItem(makeAppMenuItem(app))
			}
		}

		if running.isEmpty && installed.isEmpty {
			let item = NSMenuItem(title: "No apps found", action: nil, keyEquivalent: "")
			item.isEnabled = false
			menu.addItem(item)
		}

		menu.popUp(positioning: nil, at: NSPoint(x: 0, y: appBrowseBtn.bounds.height), in: appBrowseBtn)
	}

	private func makeAppMenuItem(_ app: AppInfo) -> NSMenuItem {
		let item = NSMenuItem(title: app.displayName, action: #selector(appMenuSelected(_:)), keyEquivalent: "")
		item.target = self
		item.representedObject = app.name
		if let icon = app.icon.copy() as? NSImage {
			icon.size = NSSize(width: 16, height: 16)
			item.image = icon
		}
		return item
	}

	@objc private func appMenuSelected(_ sender: NSMenuItem) {
		guard let name = sender.representedObject as? String else { return }
		appField.stringValue = name
		updateSelectedWindowField(\.app, value: name)
	}

	private func rebuildScreenPopup() {
		let current = screenPopup.indexOfSelectedItem
		let screenCount = currentVariant()?.displaySetup.displayCount ?? Screen.currentDisplaySetup().displayCount
		screenPopup.removeAllItems()
		for i in 1...max(screenCount, 1) { screenPopup.addItem(withTitle: "\(i)") }
		if current >= 0 && current < screenPopup.numberOfItems { screenPopup.selectItem(at: current) }
		screenLabel.isHidden = screenCount <= 1
		screenPopup.isHidden = screenCount <= 1
	}

	@objc private func screenChanged() {
		updateSelectedWindowField(\.screen, value: screenPopup.indexOfSelectedItem + 1)
	}

	var isDirty: Bool {
		layouts != initialLayouts || spacing != initialSpacing || hideOthers != initialHideOthers
	}

	/// Returns true if it's OK to close (saved, no changes, or user confirmed discard)
	func canClose() -> Bool {
		if didSave || !isDirty { return true }
		let alert = NSAlert()
		alert.messageText = "Unsaved Changes"
		alert.informativeText = "You have unsaved changes. Do you want to save before closing?"
		alert.icon = NSImage(systemSymbolName: "rectangle.split.3x1", accessibilityDescription: nil)
		alert.addButton(withTitle: "Save")
		alert.addButton(withTitle: "Don't Save")
		alert.addButton(withTitle: "Cancel")
		let response = alert.runModal()
		switch response {
		case .alertFirstButtonReturn:
			save()
			return didSave
		case .alertSecondButtonReturn:
			return true
		default:
			return false
		}
	}

	@objc private func save() {
		guard isDirty else { return }
		let config = ConfigConvert.toConfig(layouts: layouts, spacing: spacing, hideOthers: hideOthers)
		onSave?(config)
		// Update snapshot to current state
		initialLayouts = layouts
		initialSpacing = spacing
		initialHideOthers = hideOthers
		didSave = true
		updateSaveButton()
		showSaveConfirmation()
	}

	private func updateSaveButton() {
		saveBtn.isEnabled = isDirty
		if isDirty {
			saveBtn.bezelColor = .controlAccentColor
			saveBtn.attributedTitle = NSAttributedString(string: "Save", attributes: [
				.foregroundColor: NSColor.white,
				.font: NSFont.systemFont(ofSize: 13, weight: .medium),
			])
		} else {
			saveBtn.bezelColor = nil
			saveBtn.attributedTitle = NSAttributedString(string: "Save", attributes: [
				.foregroundColor: NSColor.disabledControlTextColor,
				.font: NSFont.systemFont(ofSize: 13),
			])
		}
	}

	/// Call after any data mutation to keep save button in sync
	private func didMutate() {
		updateSaveButton()
	}

	private var toastView: NSView?

	private func showAlert(message: String, informativeText: String) {
		let alert = NSAlert()
		alert.messageText = message
		alert.informativeText = informativeText
		alert.alertStyle = .informational
		alert.addButton(withTitle: "OK")
		alert.runModal()
	}

	private func showSaveConfirmation() {
		// Show a toast overlay on the window
		guard let window = view.window else { return }
		let contentView = window.contentView!

		// Remove existing toast
		toastView?.removeFromSuperview()

		let pill = NSView()
		pill.wantsLayer = true
		pill.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.9).cgColor
		pill.layer?.cornerRadius = 8
		pill.translatesAutoresizingMaskIntoConstraints = false

		let label = NSTextField(labelWithString: "✓  Configuration saved")
		label.font = .systemFont(ofSize: 13, weight: .medium)
		label.textColor = .white
		label.alignment = .center
		label.backgroundColor = .clear
		label.isBezeled = false
		label.isEditable = false
		label.translatesAutoresizingMaskIntoConstraints = false

		pill.addSubview(label)
		contentView.addSubview(pill)

		NSLayoutConstraint.activate([
			pill.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
			pill.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -56),
			pill.heightAnchor.constraint(equalToConstant: 32),
			pill.widthAnchor.constraint(equalToConstant: 210),
			label.centerXAnchor.constraint(equalTo: pill.centerXAnchor),
			label.centerYAnchor.constraint(equalTo: pill.centerYAnchor),
		])
		toastView = pill

		// Fade out after 1.5s
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak pill] in
			NSAnimationContext.runAnimationGroup({ ctx in
				ctx.duration = 0.4
				pill?.animator().alphaValue = 0
			}, completionHandler: {
				pill?.removeFromSuperview()
			})
		}
	}

	@objc private func cancel() {
		if canClose() { onClose?() }
	}

	// MARK: - NSTextFieldDelegate

	func controlTextDidChange(_ obj: Notification) {
		guard let field = obj.object as? NSTextField else { return }
		updateSaveButton()

		if field === nameField {
			guard let idx = selectedLayoutIndex else { return }
			layouts[idx].name = field.stringValue
			refreshSidebar()
		} else if field === variantNameField {
			guard let path = selectedPath() else { return }
			let signature = layouts[path.layout].variants[path.variant].displaySetup.signature
			renameSetup(signature: signature, name: field.stringValue)
			refreshSidebar()
			updateSaveButton()
		} else if field === spacingField {
			rebuildSpacingString()
		} else if field === appField {
			updateSelectedWindowField(\.app, value: field.stringValue)
		} else if field === titleField {
			updateSelectedWindowField(\.title, value: field.stringValue)
		} else if field === xField || field === yField || field === wField || field === hField {
			updateWindowGeometryFromFields()
		}
	}

	private func updateSelectedWindowField<T>(_ keyPath: WritableKeyPath<EditableWindowRule, T>, value: T) {
		guard let wid = selectedWindowID else { return }
		var windows = currentWindows()
		guard let widx = windows.firstIndex(where: { $0.id == wid }) else { return }
		windows[widx][keyPath: keyPath] = value
		setCurrentWindows(windows)
		updateSaveButton()
	}

	private func updateWindowGeometryFromFields() {
		guard let wid = selectedWindowID else { return }
		var windows = currentWindows()
		guard let widx = windows.firstIndex(where: { $0.id == wid }) else { return }
		windows[widx].x = Double(xField.stringValue) ?? windows[widx].x
		windows[widx].y = Double(yField.stringValue) ?? windows[widx].y
		windows[widx].width = Double(wField.stringValue) ?? windows[widx].width
		windows[widx].height = Double(hField.stringValue) ?? windows[widx].height
		setCurrentWindows(windows)
	}

	// MARK: - LayoutCanvasDelegate

	func canvasDidSelectWindow(_ canvas: LayoutCanvasView, windowID: UUID?) {
		selectedWindowID = windowID
		refreshInspector()
	}

	func canvasDidUpdateWindow(_ canvas: LayoutCanvasView, windowID: UUID) {
		guard canvas.windows.contains(where: { $0.id == windowID }) else { return }
		setCurrentWindows(canvas.windows)
		if windowID == selectedWindowID { refreshInspector() }
		updateSaveButton()
	}

	func canvasDidCreateWindow(_ canvas: LayoutCanvasView, rule: EditableWindowRule) {
		var windows = currentWindows()
		windows.append(rule)
		setCurrentWindows(windows)
		selectedWindowID = rule.id
		canvasView.selectedWindowID = rule.id
		refreshInspector()
		updateSaveButton()
	}

	func canvasDidDeleteWindow(_ canvas: LayoutCanvasView, windowID: UUID) {
		guard let rule = currentWindows().first(where: { $0.id == windowID }) else { return }
		confirmDeleteWindow(name: rule.app.isEmpty ? "this window" : "\"\(rule.app)\"") { [self] in
			var windows = currentWindows()
			windows.removeAll { $0.id == windowID }
			setCurrentWindows(windows)
			if selectedWindowID == windowID { selectedWindowID = nil }
			canvasView.selectedWindowID = selectedWindowID
			refreshInspector()
			updateSaveButton()
		}
	}
}
