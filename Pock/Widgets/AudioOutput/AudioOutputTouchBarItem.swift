import AppKit

internal enum AudioOutputTouchBarItem {
	static let itemIdentifier = NSTouchBarItem.Identifier("io.github.pock.audio-output")
	static let name = "Audio Output".localized

	static func make(target: AnyObject, action: Selector) -> NSTouchBarItem {
		let item = NSCustomTouchBarItem(identifier: itemIdentifier)
		let button = AudioOutputButton(width: 40, target: target, action: action)
		button.setIcon("speaker.wave.2", fallback: NSImage.touchBarAudioOutputVolumeHighTemplateName, label: name)
		item.view = button
		item.customizationLabel = name
		return item
	}
}

internal final class AudioOutputPanel: NSObject {
	private let service = AudioOutputService()
	private let onClose: () -> Void
	private var snapshot: AudioOutputSnapshot?
	private var pendingDevice: AudioOutputDevice?
	private var confirmationTimer: Timer?
	private var isOpen = false
	private var page = 0
	private let pageSize = 3

	private let row = NSStackView()
	private let status = NSTextField(labelWithString: "")
	private lazy var previous = navigationButton("chevron.left", fallback: NSImage.touchBarGoBackTemplateName,
		label: "Previous audio outputs".localized, action: #selector(previousPage))
	private lazy var next = navigationButton("chevron.right", fallback: NSImage.touchBarGoForwardTemplateName,
		label: "More audio outputs".localized, action: #selector(nextPage))
	private lazy var deviceButtons = (0..<pageSize).map { index in
		let button = AudioDeviceButton(width: 124, target: self, action: #selector(selectDevice(_:)))
		button.tag = index
		return button
	}
	private lazy var close = navigationButton("xmark", fallback: NSImage.stopProgressTemplateName,
		label: "Close Audio Output".localized, action: #selector(closePanel), width: 42)
	internal private(set) lazy var touchBar = makeTouchBar()

	init(onClose: @escaping () -> Void) {
		self.onClose = onClose
		super.init()
	}

	func start() {
		guard !isOpen else { return }
		isOpen = true
		service.startObserving { [weak self] in self?.refresh() }
		refresh()
	}

	func stop() {
		guard isOpen else { return }
		isOpen = false
		service.stopObserving()
		cancelSelection()
		snapshot = nil
		page = 0
	}

	deinit { confirmationTimer?.invalidate() }

	private func makeTouchBar() -> NSTouchBar {
		status.font = .systemFont(ofSize: 11, weight: .medium)
		status.textColor = .secondaryLabelColor
		status.alignment = .center
		row.orientation = .horizontal
		row.alignment = .centerY
		row.spacing = 6
		for view in [previous] + deviceButtons + [next, status] {
			row.addArrangedSubview(view)
		}
		let item = NSCustomTouchBarItem(identifier: .init("io.github.pock.audio-output.panel"))
		item.view = row
		let closeItem = NSCustomTouchBarItem(identifier: .init("io.github.pock.audio-output.close"))
		closeItem.view = close
		let bar = NSTouchBar()
		bar.templateItems = [item, closeItem]
		bar.defaultItemIdentifiers = [.flexibleSpace, item.identifier, .flexibleSpace, closeItem.identifier]
		return bar
	}

	private func refresh() {
		guard isOpen else { return }
		do {
			let updated = try service.snapshot()
			if let pending = pendingDevice {
				if updated.devices.contains(where: { $0.uid == pending.uid && $0.id == updated.defaultDeviceID }) {
					closePanel()
					return
				}
				if !updated.devices.contains(where: { $0.uid == pending.uid }) {
					cancelSelection()
					snapshot = updated
					render(message: "Audio device disconnected".localized)
					return
				}
			}
			guard snapshot != updated else { return }
			if snapshot == nil, let active = updated.devices.firstIndex(where: { $0.id == updated.defaultDeviceID }) {
				page = active / pageSize
			}
			snapshot = updated
			render()
		} catch {
			cancelSelection()
			snapshot = nil
			render(message: "Audio outputs unavailable".localized)
		}
	}

	private func render(message: String? = nil) {
		let devices = snapshot?.devices ?? []
		page = min(page, max(0, (devices.count - 1) / pageSize))
		let hasPages = devices.count > pageSize
		previous.isHidden = !hasPages || page == 0
		next.isHidden = !hasPages || (page + 1) * pageSize >= devices.count
		previous.isEnabled = pendingDevice == nil
		next.isEnabled = pendingDevice == nil
		for button in deviceButtons {
			let index = page * pageSize + button.tag
			button.isHidden = !devices.indices.contains(index)
			guard devices.indices.contains(index) else { continue }
			let device = devices[index]
			let selected = device.id == snapshot?.defaultDeviceID
			let displayName = device.name == "MacBook Pro Speakers" ? "Speakers".localized : device.name
			button.setDevice(device, title: displayName, selected: selected)
			button.isEnabled = pendingDevice == nil
		}
		let label = message ?? (pendingDevice != nil ? "Switching…".localized : nil)
			?? (devices.isEmpty ? "No audio outputs".localized : nil)
		status.stringValue = label ?? ""
		status.isHidden = label == nil
	}

	@objc private func selectDevice(_ sender: NSButton) {
		guard isOpen, pendingDevice == nil, let snapshot = snapshot else { return }
		let index = page * pageSize + sender.tag
		guard snapshot.devices.indices.contains(index) else { return }
		let device = snapshot.devices[index]
		if device.id == snapshot.defaultDeviceID {
			closePanel()
			return
		}
		pendingDevice = device
		do {
			try service.select(device)
			render()
			confirmationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: false) { [weak self] _ in
				guard let self = self else { return }
				self.refresh()
				guard self.pendingDevice != nil else { return }
				self.cancelSelection()
				self.render(message: "Could not switch audio output".localized)
			}
			refresh()
		} catch {
			cancelSelection()
			refresh()
			render(message: "Could not switch audio output".localized)
		}
	}

	private func cancelSelection() {
		confirmationTimer?.invalidate()
		confirmationTimer = nil
		pendingDevice = nil
	}

	@objc private func closePanel() { onClose() }
	@objc private func previousPage() {
		page = max(0, page - 1)
		render()
	}

	@objc private func nextPage() {
		page += 1
		render()
	}

	private func navigationButton(_ symbol: String, fallback: NSImage.Name, label: String,
			action: Selector, width: CGFloat = 30) -> AudioOutputButton {
		let button = AudioOutputButton(width: width, target: self, action: action)
		button.isBordered = false
		button.contentTintColor = .secondaryLabelColor
		button.setIcon(symbol, fallback: fallback, label: label)
		return button
	}
}

private class AudioOutputButton: NSButton {
	private let size: NSSize

	init(width: CGFloat, target: AnyObject?, action: Selector?) {
		size = NSSize(width: width, height: 30)
		super.init(frame: NSRect(origin: .zero, size: size))
		self.target = target
		self.action = action
		bezelStyle = .rounded
		setContentHuggingPriority(.required, for: .horizontal)
	}

	required init?(coder: NSCoder) { return nil }
	override var intrinsicContentSize: NSSize { size }

	func setIcon(_ symbol: String, fallback: NSImage.Name, label: String) {
		title = ""
		image = Self.icon(symbol, fallback: fallback, size: 14)
		imagePosition = .imageOnly
		setAccessibilityLabel(label)
		toolTip = label
	}

	static func icon(_ symbol: String, fallback: NSImage.Name, size: CGFloat) -> NSImage? {
		if #available(macOS 11, *), let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
			return image.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) ?? image
		}
		return NSImage(named: fallback)
	}
}

private final class AudioDeviceButton: AudioOutputButton {
	private let deviceIcon = NSImageView()
	private let nameLabel = NSTextField(labelWithString: "")
	private let checkmark = NSImageView()

	override init(width: CGFloat, target: AnyObject?, action: Selector?) {
		super.init(width: width, target: target, action: action)
		title = ""
		nameLabel.font = .systemFont(ofSize: 10, weight: .medium)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.maximumNumberOfLines = 1
		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		checkmark.image = Self.icon("checkmark", fallback: NSImage.menuOnStateTemplateName, size: 10)
		checkmark.contentTintColor = .white
		let content = NSStackView(views: [deviceIcon, nameLabel, checkmark])
		content.alignment = .centerY
		content.spacing = 6
		content.translatesAutoresizingMaskIntoConstraints = false
		for view in content.arrangedSubviews { view.setAccessibilityElement(false) }
		addSubview(content)
		NSLayoutConstraint.activate([
			content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
			content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
			content.centerYAnchor.constraint(equalTo: centerYAnchor),
			deviceIcon.widthAnchor.constraint(equalToConstant: 15),
			checkmark.widthAnchor.constraint(equalToConstant: 12)
		])
	}

	required init?(coder: NSCoder) { return nil }

	override func hitTest(_ point: NSPoint) -> NSView? {
		return super.hitTest(point) == nil ? nil : self
	}

	func setDevice(_ device: AudioOutputDevice, title: String, selected: Bool) {
		nameLabel.stringValue = title
		deviceIcon.image = Self.icon(device.symbolName,
			fallback: NSImage.touchBarAudioOutputVolumeHighTemplateName, size: 12)
		deviceIcon.contentTintColor = selected ? .white : .secondaryLabelColor
		checkmark.isHidden = !selected
		bezelColor = selected ? .systemBlue : nil
		setAccessibilityLabel(selected ? "%@, selected".localized(device.name) : device.name)
		toolTip = device.name
	}
}
