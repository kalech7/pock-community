//
//  OnBoardViewController.swift
//  Pock
//
//  Created by Pierluigi Galdi on 13/05/21.
//

import Cocoa
import ApplicationServices

class OnBoardViewController: NSViewController {

	// MARK: UI Elements
	
	@IBOutlet private weak var titleLabel: NSTextField!
	@IBOutlet private weak var subtitleLabel: NSTextField!
	@IBOutlet private weak var defaultWidgetsStackView: NSStackView!
	@IBOutlet private weak var defaultWidgetsInstallLabel: NSTextField!
	@IBOutlet private weak var openPreferencesButton: NSButton!
	@IBOutlet private weak var continueWithDefaultSettingsButton: NSButton!

	private let accessibilityStatusLabel = NSTextField(labelWithString: "")
	private let accessibilityButton = NSButton(
		title: "onboard.accessibility.open-settings".localized,
		target: nil,
		action: nil
	)
	private let launchAtLoginCheckbox = NSButton(
		checkboxWithTitle: "onboard.launch-at-login".localized,
		target: nil,
		action: nil
	)
	
	private var animatableViews: [NSTextField] {
		let substack: [NSStackView] = defaultWidgetsStackView.findViews()
		var views: [NSTextField] = []
		for stack in substack {
			views += stack.arrangedSubviews.filter({ $0 is NSTextField }) as? [NSTextField] ?? []
		}
		return views
	}
	
	// MARK: Overrides
	
	override var title: String? {
		get {
			return "general.welcome-to-pock".localized
		}
		set {
			view.window?.title = newValue ?? ""
		}
	}
	
    override func viewDidLoad() {
        super.viewDidLoad()
		Preferences[.didShowOnBoard] = true
		Preferences[.didCompleteSetupOnBoard] = true
		configureUIElements()
		configureSetupSection()
		enableLaunchAtLoginByDefault()
		requestAccessibilityPermissionIfNeeded()
		animate()
    }
	
	override func viewWillAppear() {
		super.viewWillAppear()
		NSApp.activate(ignoringOtherApps: true)
	}
	
	override func viewDidDisappear() {
		super.viewDidDisappear()
		NSApp.deactivate()
	}
	
	deinit {
		Roger.debug("[OnBoard][ViewController] - deinit")
	}
	
	// MARK: Methods
	
	private func configureUIElements() {
		titleLabel.stringValue = "onboard.title".localized
		subtitleLabel.stringValue = "onboard.body".localized
		defaultWidgetsInstallLabel.stringValue = "onboard.footer".localized
		openPreferencesButton.title = "onboard.open-preferences".localized
		continueWithDefaultSettingsButton.title = "onboard.continue-with-default-settings".localized
		continueWithDefaultSettingsButton.isHighlighted = true
	}

	private func configureSetupSection() {
		guard let mainStackView = view.subviews.first(where: { $0 is NSStackView }) as? NSStackView else { return }

		let setupTitleLabel = NSTextField(labelWithString: "onboard.setup.title".localized)
		setupTitleLabel.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
		setupTitleLabel.alignment = .center

		accessibilityStatusLabel.alignment = .center
		accessibilityStatusLabel.textColor = .secondaryLabelColor
		accessibilityStatusLabel.maximumNumberOfLines = 2

		accessibilityButton.target = self
		accessibilityButton.action = #selector(openAccessibilitySettings)
		accessibilityButton.bezelStyle = .rounded

		launchAtLoginCheckbox.target = self
		launchAtLoginCheckbox.action = #selector(toggleLaunchAtLogin(_:))
		launchAtLoginCheckbox.state = Preferences[.launchAtLogin] == true ? .on : .off

		let setupStackView = NSStackView(views: [
			setupTitleLabel,
			accessibilityStatusLabel,
			accessibilityButton,
			launchAtLoginCheckbox
		])
		setupStackView.orientation = .vertical
		setupStackView.alignment = .centerX
		setupStackView.spacing = 8
		setupStackView.edgeInsets = NSEdgeInsets(top: 0, left: 24, bottom: 0, right: 24)

		mainStackView.insertArrangedSubview(setupStackView, at: min(4, mainStackView.arrangedSubviews.count))
		updateAccessibilityStatus()
	}

	private func enableLaunchAtLoginByDefault() {
		guard Preferences[.launchAtLogin] == false else { return }
		Preferences[.launchAtLogin] = true
		launchAtLoginCheckbox.state = .on
	}

	private func requestAccessibilityPermissionIfNeeded() {
		guard !AXIsProcessTrusted() else {
			updateAccessibilityStatus()
			return
		}
		requestAccessibilityPermission()
	}

	private func requestAccessibilityPermission() {
		let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
		let options = [promptKey: true] as CFDictionary
		_ = AXIsProcessTrustedWithOptions(options)
		updateAccessibilityStatus()
	}

	private func updateAccessibilityStatus() {
		let isTrusted = AXIsProcessTrusted()
		accessibilityStatusLabel.stringValue = isTrusted
			? "onboard.accessibility.granted".localized
			: "onboard.accessibility.required".localized
		accessibilityButton.isHidden = isTrusted
	}
	
	private func animate() {
		for view in animatableViews {
			async(after: .random(in: 0...2)) { [weak view] in
				view?.animate(
					key: "kBounceAnimationKey",
					keyPath: "transform.scale",
					fromValue: .random(in: 0.56...0.88),
					toValue: 1.2,
					duration: .random(in: 2.25...2.75),
					autoreverse: true
				)
			}
		}
	}

	@objc private func openAccessibilitySettings() {
		requestAccessibilityPermission()
		if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
			NSWorkspace.shared.open(url)
		}
	}

	@objc private func toggleLaunchAtLogin(_ sender: NSButton) {
		Preferences[.launchAtLogin] = sender.state == .on
	}
	
	@IBAction private func didSelectButton(_ button: NSButton) {
		defer {
			view.window?.close()
		}
		switch button {
		case openPreferencesButton:
			AppController.shared.openController(PreferencesViewController())
		case continueWithDefaultSettingsButton:
			updateAccessibilityStatus()
		default:
			return
		}
	}
    
}

fileprivate extension NSView {
	func animate(
		key: String,
		keyPath: String,
		fromValue: CGFloat = 0.86,
		toValue: CGFloat = 1,
		duration: CFTimeInterval = 2.75,
		autoreverse: Bool = false,
		removeOnCompletion: Bool = false,
		repeatCount: Float = Float.infinity,
		timing: CAMediaTimingFunctionName = .easeInEaseOut,
		anchorPoint: CGPoint = CGPoint(x: 0.5, y: 0.5)
	) {
		wantsLayer = true
		let bounce                   = CABasicAnimation(keyPath: keyPath)
		bounce.fromValue             = fromValue
		bounce.toValue               = toValue
		bounce.duration              = duration
		bounce.autoreverses          = autoreverse
		bounce.repeatCount           = repeatCount
		bounce.isRemovedOnCompletion = removeOnCompletion
		bounce.timingFunction        = CAMediaTimingFunction(name: timing)
		let frame = self.layer?.frame
		self.layer?.anchorPoint = anchorPoint
		self.layer?.frame = frame ?? .zero
		self.layer?.add(bounce, forKey: "")
	}
}
