//
//  Based on the original Status widget created by Pierluigi Galdi on 23/02/2019.
//  Copyright © 2019 Pierluigi Galdi. All rights reserved.
//

import AppKit
import CoreWLAN
import IOKit.ps

internal final class StatusTouchBarItem: NSCustomTouchBarItem {
	static let itemIdentifier = NSTouchBarItem.Identifier("Status")
	static var name: String { "Status".localized }

	private let statusView = StatusView()

	convenience init() {
		self.init(identifier: Self.itemIdentifier)
		customizationLabel = Self.name
		view = statusView
	}

	func startRefreshing() { statusView.startRefreshing() }
	func stopRefreshing() { statusView.stopRefreshing() }
}

private enum StatusSettings {
	// Read the same preferences as the original built-in widget.
	enum Display: String, CaseIterable {
		case wifi = "shouldShowWifiItem"
		case battery = "shouldShowPowerItem"
		case batteryIcon = "shouldShowBatteryIcon"
		case batteryPercentage = "shouldShowBatteryPercentage"
		case clock = "shouldShowDateItem"

		var title: String {
			switch self {
			case .wifi: return "Show Wi-Fi".localized
			case .battery: return "Show battery".localized
			case .batteryIcon: return "Show battery icon".localized
			case .batteryPercentage: return "Show battery percentage".localized
			case .clock: return "Show date and time".localized
			}
		}

		var isEnabled: Bool {
			UserDefaults.standard.object(forKey: rawValue) as? Bool ?? true
		}
	}

	static let didChange = Notification.Name("PockStatusSettingsDidChange")
	static let defaultDateFormat = "EE dd MMM HH:mm"
	static let dateFormatKey = "timeFormatTextField"
	static var dateFormat: String { UserDefaults.standard.string(forKey: dateFormatKey) ?? defaultDateFormat }

	static func dateFormatter(for format: String) -> DateFormatter {
		let formatter = DateFormatter()
		formatter.locale = .autoupdatingCurrent
		formatter.timeZone = .autoupdatingCurrent
		formatter.dateFormat = format
		if formatter.string(from: Date()).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			formatter.dateFormat = defaultDateFormat
		}
		return formatter
	}
}

private final class StatusView: NSStackView {
	private let wifi = NSImageView()
	private let wifiText = NSTextField(labelWithString: "")
	private let batteryIcon = NSImageView()
	private let batteryText = NSTextField(labelWithString: "")
	private let percentage = NSTextField(labelWithString: "")
	private let battery = NSStackView()
	private let clock = NSTextField(labelWithString: "")
	private var clockFormatter = StatusSettings.dateFormatter(for: StatusSettings.dateFormat)
	private var clockTimer: Timer?
	private var systemTimer: Timer?
	private var isRefreshing = false

	init() {
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = 7
		edgeInsets = NSEdgeInsets(top: 0, left: 4, bottom: 0, right: 4)
		for label in [wifiText, batteryText, percentage, clock] {
			label.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
			label.textColor = .white
		}
		clock.lineBreakMode = .byTruncatingTail
		for icon in [wifi, batteryIcon] {
			icon.imageScaling = .scaleProportionallyDown
			icon.contentTintColor = .white
			icon.setAccessibilityElement(true)
		}
		battery.orientation = .horizontal
		battery.alignment = .centerY
		battery.spacing = 4
		for subview in [batteryIcon, batteryText, percentage] { battery.addArrangedSubview(subview) }
		for subview in [wifi, wifiText, battery, clock] { addArrangedSubview(subview) }
		clock.widthAnchor.constraint(lessThanOrEqualToConstant: 200).isActive = true
		NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: StatusSettings.didChange, object: nil)
		NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: .NSSystemTimeZoneDidChange, object: nil)
	}

	required init?(coder: NSCoder) { return nil }

	deinit {
		NotificationCenter.default.removeObserver(self)
		stopRefreshing()
	}

	func startRefreshing() {
		guard !isRefreshing else { return }
		isRefreshing = true
		reloadSettings()
	}

	func stopRefreshing() {
		isRefreshing = false
		clockTimer?.invalidate()
		systemTimer?.invalidate()
		clockTimer = nil
		systemTimer = nil
	}

	@objc private func settingsChanged(_ notification: Notification) {
		if Thread.isMainThread { reloadSettings() }
		else { DispatchQueue.main.async { [weak self] in self?.reloadSettings() } }
	}

	private func reloadSettings() {
		guard isRefreshing else { return }
		stopRefreshing()
		isRefreshing = true
		clock.isHidden = !StatusSettings.Display.clock.isEnabled
		if !clock.isHidden {
			clockFormatter = StatusSettings.dateFormatter(for: StatusSettings.dateFormat)
			refreshClock()
			clockTimer = makeTimer(interval: 1) { [weak self] in self?.refreshClock() }
		}
		refreshSystemStatus()
		if StatusSettings.Display.wifi.isEnabled || showsBattery {
			systemTimer = makeTimer(interval: 10) { [weak self] in self?.refreshSystemStatus() }
		}
	}

	private func makeTimer(interval: TimeInterval, refresh: @escaping () -> Void) -> Timer {
		let timer = Timer(timeInterval: interval, repeats: true) { _ in refresh() }
		timer.tolerance = interval / 10
		RunLoop.main.add(timer, forMode: .common)
		return timer
	}

	private func refreshClock() {
		let reading = clockFormatter.string(from: Date())
		if clock.stringValue != reading { clock.stringValue = reading }
	}

	private var showsBattery: Bool {
		StatusSettings.Display.battery.isEnabled &&
			(StatusSettings.Display.batteryIcon.isEnabled || StatusSettings.Display.batteryPercentage.isEnabled)
	}

	private func refreshSystemStatus() {
		refreshWiFi()
		refreshBattery()
	}

	private func refreshWiFi() {
		if StatusSettings.Display.wifi.isEnabled, let interface = CWWiFiClient.shared().interface() {
			let signal = interface.rssiValue()
			let powered = interface.powerOn()
			let strength = min(max(2 * (signal + 100), 0), 100)
			let symbol: String
			let description: String
			if !powered {
				symbol = "wifi.slash"
				description = "Wi-Fi off".localized
			} else if signal == 0 {
				symbol = "wifi.exclamationmark"
				description = "Wi-Fi disconnected".localized
			} else {
				symbol = "wifi"
				description = "Wi-Fi signal %d%%".localized(strength)
			}
			showIcon(wifi, fallback: wifiText, symbol: symbol, description: description,
				level: Double(strength) / 100)
		} else {
			wifi.isHidden = true
			wifiText.isHidden = true
		}
	}

	private func refreshBattery() {
		guard showsBattery, let reading = Self.readBattery() else {
			battery.isHidden = true
			return
		}
		battery.isHidden = false
		if StatusSettings.Display.batteryIcon.isEnabled {
			let level = ((reading.percent + 12) / 25) * 25
			let symbol = reading.charging ? "battery.100.bolt" : "battery.\(level)"
			let description = reading.charging ? "Battery charging".localized : "Battery".localized
			showIcon(batteryIcon, fallback: batteryText, symbol: symbol, description: description,
				fallbackText: reading.charging ? "⚡" : "🔋")
		} else {
			batteryIcon.isHidden = true
			batteryText.isHidden = true
		}
		percentage.isHidden = !StatusSettings.Display.batteryPercentage.isEnabled
		if !percentage.isHidden {
			percentage.stringValue = "\(reading.percent)%"
			percentage.setAccessibilityLabel("Battery %d%%".localized(reading.percent))
		}
	}

	private func showIcon(_ icon: NSImageView, fallback: NSTextField, symbol: String, description: String,
						  level: Double = 1, fallbackText: String? = nil) {
		let image: NSImage?
		if #available(macOS 13.0, *) {
			image = NSImage(systemSymbolName: symbol, variableValue: level, accessibilityDescription: description)
		} else if #available(macOS 11.0, *) {
			image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)
		} else {
			image = nil
		}
		if #available(macOS 11.0, *) {
			icon.image = image?.withSymbolConfiguration(.init(pointSize: 14, weight: .medium))
		}
		icon.isHidden = icon.image == nil
		icon.setAccessibilityLabel(description)
		fallback.isHidden = icon.image != nil
		fallback.stringValue = fallbackText ?? description
		fallback.setAccessibilityLabel(description)
	}

	private static func readBattery() -> (percent: Int, charging: Bool)? {
		guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
			  let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
		for source in sources {
			guard let details = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
				  details[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
				  let capacity = details[kIOPSCurrentCapacityKey] as? Int,
				  let maximum = details[kIOPSMaxCapacityKey] as? Int, maximum > 0 else { continue }
			let percent = Int((100 * Double(min(max(capacity, 0), maximum)) / Double(maximum)).rounded())
			return (percent, details[kIOPSIsChargingKey] as? Bool ?? false)
		}
		return nil
	}
}

internal final class StatusPreferencesView: NSStackView, NSTextFieldDelegate {
	private let dateFormat = NSTextField(string: StatusSettings.dateFormat)
	private let preview = NSTextField(labelWithString: "")
	private var buttons: [StatusSettings.Display: NSButton] = [:]

	init(organizeButton: NSButton) {
		super.init(frame: .zero)
		orientation = .vertical
		alignment = .leading
		spacing = 8
		for option in StatusSettings.Display.allCases {
			let button = NSButton(checkboxWithTitle: option.title, target: self, action: #selector(toggle(_:)))
			button.identifier = NSUserInterfaceItemIdentifier(option.rawValue)
			button.state = option.isEnabled ? .on : .off
			buttons[option] = button
			addArrangedSubview(button)
		}
		let formatLabel = NSTextField(labelWithString: "Date and time format".localized)
		dateFormat.delegate = self
		dateFormat.setAccessibilityLabel(formatLabel.stringValue)
		dateFormat.placeholderString = StatusSettings.defaultDateFormat
		let formatRow = NSStackView(views: [formatLabel, dateFormat])
		formatRow.alignment = .centerY
		formatRow.spacing = 8
		dateFormat.widthAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
		preview.textColor = .secondaryLabelColor
		preview.lineBreakMode = .byTruncatingTail
		addArrangedSubview(formatRow)
		addArrangedSubview(preview)
		addArrangedSubview(organizeButton)
		preview.widthAnchor.constraint(lessThanOrEqualToConstant: 290).isActive = true
		updateControls()
	}

	required init?(coder: NSCoder) { return nil }

	@objc private func toggle(_ sender: NSButton) {
		guard let key = sender.identifier?.rawValue else { return }
		UserDefaults.standard.set(sender.state == .on, forKey: key)
		updateControls()
		NotificationCenter.default.post(name: StatusSettings.didChange, object: nil)
	}

	func controlTextDidChange(_ notification: Notification) {
		updatePreview()
	}

	func controlTextDidEndEditing(_ notification: Notification) {
		let format = StatusSettings.dateFormatter(for: dateFormat.stringValue).dateFormat ?? StatusSettings.defaultDateFormat
		dateFormat.stringValue = format
		UserDefaults.standard.set(format, forKey: StatusSettings.dateFormatKey)
		updatePreview()
		NotificationCenter.default.post(name: StatusSettings.didChange, object: nil)
	}

	private func updateControls() {
		let batteryEnabled = StatusSettings.Display.battery.isEnabled
		buttons[.batteryIcon]?.isEnabled = batteryEnabled
		buttons[.batteryPercentage]?.isEnabled = batteryEnabled
		dateFormat.isEnabled = StatusSettings.Display.clock.isEnabled
		preview.isHidden = !dateFormat.isEnabled
		updatePreview()
	}

	private func updatePreview() {
		let formatted = StatusSettings.dateFormatter(for: dateFormat.stringValue).string(from: Date())
		preview.stringValue = "Preview: %@".localized(formatted)
	}
}
