//
//  EmptyTouchBarController.swift
//  Pock
//
//  Created by Pierluigi Galdi on 07/05/21.
//

import Cocoa
import PockKit

internal class EmptyTouchBarController: PKTouchBarMouseController {

	internal enum State {
		case empty, installDefault
	}
	
	internal var state: State = .empty
	
    // MARK: UI Elements
	@IBOutlet private weak var titleLabel: NSTextField?
	@IBOutlet private weak var subtitleLabel: NSTextField?
	@IBOutlet private weak var informativeLabel: NSTextField?
	@IBOutlet private weak var actionIconView: NSImageView?
	@IBOutlet private weak var actionButton: NSButton?
	
	// MARK: Mouse Support
	private var buttonWithMouseOver: NSButton?
	private var isHandlingAction = false
	private var touchBarView: NSView? {
		guard let views = NSFunctionRow._topLevelViews() as? [NSView], let view = views.last else {
			Roger.debug("Touch Bar is not available.")
			return nil
		}
		return view
	}
	public override var parentView: NSView? {
		get {
			return touchBarView
		} set {
			super.parentView = newValue
		}
	}
	
	override func present() {
		super.present()
		updateUIState()
	}

	override func reloadScreenEdgeController() {
		guard let parentView = parentView else {
			edgeController?.tearDown(invalidate: true)
			edgeController = nil
			return
		}
		edgeController = PKScreenEdgeController(mouseDelegate: self, parentView: parentView)
	}

	override var visibleRectWidth: CGFloat {
		get {
			return parentView?.visibleRect.width ?? 0
		}
		set {}
	}
	
	private func updateUIState() {
		guard let titleLabel = titleLabel,
			  let subtitleLabel = subtitleLabel,
			  let informativeLabel = informativeLabel,
			  let actionButton = actionButton else {
			Roger.error("[EmptyTouchBarController] Can't update UI because one or more outlets are not connected.")
			return
		}
		switch state {
		case .empty:
			informativeLabel.stringValue = "widgets.empty.add-widgets-to-pock".localized
			actionButton.tag = 0
			actionButton.title = "general.action.customize".localized

		case .installDefault:
			informativeLabel.stringValue = "widgets.defaults.tap-to-install".localized
			actionButton.tag = 1
			actionButton.title = "general.action.install".localized
		}
		titleLabel.stringValue = "general.welcome-to-pock".localized
		subtitleLabel.stringValue = "general.pock-widgets-manager".localized
		async(after: 0.5) { [weak self] in
			self?.addIconViewAnimation()
		}
	}

	@IBAction private func actionButtonPressed(_ button: NSButton) {
		guard !isHandlingAction else {
			return
		}
		isHandlingAction = true
		switch button.tag {
		case 0:
			dismiss()
			async(after: 0.1) { [weak self] in
				self?.isHandlingAction = false
				AppController.shared.openPockCustomizationPalette()
			}
		case 1:
			dismiss()
			isHandlingAction = false
			AppController.shared.reInstallDefaultWidgets()
		default:
			isHandlingAction = false
			return
		}
	}

	// MARK: Mouse stuff
	public override func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
		guard !isHandlingAction else {
			return
		}
		guard let button = button(at: location) else {
			return
		}
		actionButtonPressed(button)
	}

	public override func updateCursorLocation(_ location: NSPoint?) {
		guard !isHandlingAction, touchBarView != nil else {
			return
		}
		if let location = location {
			cursorView?.frame.origin = location
		}
		buttonWithMouseOver?.isHighlighted = false
		buttonWithMouseOver = nil
		buttonWithMouseOver = button(at: location)
		buttonWithMouseOver?.isHighlighted = true
	}

	private func button(at location: NSPoint?) -> NSButton? {
		guard !isHandlingAction,
			  let parentView = touchBarView,
			  let view = parentView.subview(in: parentView, at: location, of: "NSTouchBarItemContainerView") else {
			return nil
		}
		return view.findViews(subclassOf: NSButton.self).first
	}
	
}

// MARK: Icon bounce animation
extension EmptyTouchBarController {
	private func addIconViewAnimation() {
		guard let iconContainerView = actionIconView?.superview else {
			return
		}
		iconContainerView.layout()
		let slideAnimation = CABasicAnimation(keyPath: "position.x")
		slideAnimation.duration  = 0.475
		slideAnimation.fromValue = iconContainerView.frame.origin.x + 3.3525
		slideAnimation.toValue   = iconContainerView.frame.origin.x - 1.3525
		slideAnimation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
		slideAnimation.autoreverses = true
		slideAnimation.repeatCount = .greatestFiniteMagnitude
		iconContainerView.layer?.add(slideAnimation, forKey: "bounce_animation")
	}
	private func removeIconViewAnimation() {
		actionIconView?.superview?.layer?.removeAnimation(forKey: "bounce_animation")
	}
}
