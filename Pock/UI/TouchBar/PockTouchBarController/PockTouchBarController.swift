//
//  PockTouchBarController.swift
//  Pock
//
//  Created by Pierluigi Galdi on 10/03/21.
//

import AppKit
import Foundation
import PockKit

/// Customization identifier
extension NSTouchBar.CustomizationIdentifier {
	static let pockTouchBarController = "PockTouchBarController"
}

/// Pock (main Touch Bar controller)
internal class PockTouchBarController: PKTouchBarMouseController {
	internal static let nativeTouchBarToggleIdentifier = NSTouchBarItem.Identifier("io.github.pock.native-touchbar-toggle")

	/// Data
	private(set) var widgets: [NSTouchBarItem.Identifier: PKWidgetInfo] = [:]
	private(set) var cachedItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
	private var cachedMouseDelegates: [PKScreenEdgeMouseDelegate] = []
	private var mouseMoveThrottler = MouseMoveThrottler(maximumFrequency: 30, locationTolerance: 0.75)
	private lazy var activityView = AgentActivityView()
	private lazy var activityTouchBar = makeAgentActivityTouchBar()
	private var isShowingAgentActivity = false
	
	private var currentItems: [NSTouchBarItem.Identifier] {
		return touchBar?.itemIdentifiers ?? []
	}
	private var nativeTouchBarToggleEnabled: Bool {
		return Preferences[.nativeTouchBarToggleEnabled] as Bool
	}
	private var defaultItemIdentifiers: [NSTouchBarItem.Identifier] {
		var identifiers = Array(widgets.keys)
		identifiers.append(WeatherTouchBarItem.itemIdentifier)
		if nativeTouchBarToggleEnabled {
			identifiers.append(Self.nativeTouchBarToggleIdentifier)
		}
		return identifiers
	}
	private var emptyTouchBarController: EmptyTouchBarController?
	private var blankTouchBarCheckGeneration = 0
	private var presentationConfiguration: (placement: Int64, mode: PresentationMode) {
		switch Preferences[.layoutStyle] as LayoutStyle {
		case .withControlStrip:
			return (0, .appWithControlStrip)
		case .fullWidth:
			return (1, .app)
		}
	}
	
	internal var allowedCustomizationIdentifiers: [NSTouchBarItem.Identifier] {
		var identifiers = Array(widgets.keys)
		identifiers.append(WeatherTouchBarItem.itemIdentifier)
		if nativeTouchBarToggleEnabled {
			identifiers.append(Self.nativeTouchBarToggleIdentifier)
		}
		identifiers.append(.flexibleSpace)
		return identifiers
	}

	internal var preferredItemIdentifiers: [NSTouchBarItem.Identifier] {
		let savedRawIdentifiers: [String] = Preferences[.pockTouchBarItemIdentifiers]
		let savedIdentifiers = savedRawIdentifiers.map({ NSTouchBarItem.Identifier($0) })
		let allowedIdentifiers = Set(allowedCustomizationIdentifiers)
		let savedVisibleIdentifiers = savedIdentifiers.filter({ allowedIdentifiers.contains($0) })
		guard savedVisibleIdentifiers.isEmpty == false else {
			return defaultItemIdentifiers
		}
		guard nativeTouchBarToggleEnabled else {
			return savedVisibleIdentifiers
		}
		guard savedVisibleIdentifiers.contains(Self.nativeTouchBarToggleIdentifier) == false else {
			return savedVisibleIdentifiers
		}
		return savedVisibleIdentifiers + [Self.nativeTouchBarToggleIdentifier]
	}
	
	// MARK: Mouse Support
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
	
	// MARK: Overrides
	override func didLoad() {
		super.didLoad()
		Roger.debug("[PockTouchBarController] Loaded.")
	}
	
	deinit {
		Roger.info("Deinit")
		dismissAgentActivity()
		flushWidgetItems()
		emptyTouchBarController = nil
		touchBar = nil
	}

	override func present() {
        guard AppController.shared.isLocked == false, isVisible == false else {
			return
		}
		flushWidgetItems()
		for widget in WidgetsLoader.loadedWidgets {
			widgets[NSTouchBarItem.Identifier(widget.bundleIdentifier)] = widget
		}
		touchBar = nil
		let configuration = presentationConfiguration
		isVisible = true
		TouchBarHelper.presentOnTop(touchBar, placement: configuration.placement)
		TouchBarHelper.setPresentationMode(to: configuration.mode)
		checkForBlankTouchBar()
	}

	internal func restorePresentation() {
		guard AppController.shared.isLocked == false, isVisible else {
			return
		}
		let configuration = presentationConfiguration
		TouchBarHelper.presentOnTop(isShowingAgentActivity ? activityTouchBar : touchBar, placement: configuration.placement)
		TouchBarHelper.setPresentationMode(to: configuration.mode)
		if !isShowingAgentActivity {
			checkForBlankTouchBar()
		}
	}

	internal func suspendPresentation() {
		cancelBlankTouchBarCheck()
		emptyTouchBarController?.dismiss()
		emptyTouchBarController = nil
		guard isVisible else {
			return
		}
		edgeController?.tearDown(invalidate: true)
		edgeController = nil
		isVisible = false
		if !dismissAgentActivity() {
			TouchBarHelper.dismissFromTop(touchBar)
		}
	}

	internal func resumePresentation() {
		guard AppController.shared.isLocked == false, isVisible == false else {
			return
		}
		let configuration = presentationConfiguration
		isVisible = true
		TouchBarHelper.presentOnTop(touchBar, placement: configuration.placement)
		TouchBarHelper.setPresentationMode(to: configuration.mode)
		checkForBlankTouchBar()
		async(after: 0.05) { [weak self] in
			guard self?.isVisible == true else {
				return
			}
			self?.reloadScreenEdgeController()
		}
	}
	
	override func minimize() {
		cancelBlankTouchBarCheck()
		emptyTouchBarController?.dismiss()
		if dismissAgentActivity() {
			isVisible = false
			touchBar = nil
		} else {
			super.minimize()
		}
	}
	
	override func dismiss() {
		cancelBlankTouchBarCheck()
		let dismissedActivity = dismissAgentActivity()
		emptyTouchBarController?.dismiss()
		guard isVisible else {
			return
		}
		TouchBarHelper.setPresentationMode(to: Preferences[.userDefinedPresentationMode] as PresentationMode)
		if dismissedActivity {
			isVisible = false
			touchBar = nil
		} else {
			super.dismiss()
		}
	}
	
	private func flushWidgetItems() {
		cachedItems.removeAll()
		cachedMouseDelegates.removeAll()
		widgets.removeAll()
	}

	internal func savePreferredItemIdentifiers(_ identifiers: [NSTouchBarItem.Identifier]) {
		let allowedIdentifiers = Set(allowedCustomizationIdentifiers)
		let visibleIdentifiers = identifiers.filter({ allowedIdentifiers.contains($0) })
		Preferences[.pockTouchBarItemIdentifiers] = visibleIdentifiers.map({ $0.rawValue })
	}

	/// Setup Touch Bar
	override func makeTouchBar() -> NSTouchBar? {
		let touchBar = NSTouchBar()
		touchBar.delegate = self
		// The separate customization palette saves its layout in Preferences.
		touchBar.defaultItemIdentifiers = preferredItemIdentifiers
		for key in widgets.keys {
			Roger.info("[\(key.rawValue)] - Allowed for customization")
		}
		return touchBar
	}

	/// Make Touch Bar item for given identifier
	func touchBar(_ touchBar: NSTouchBar, makeItemForIdentifier identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
		if let item = cachedItems[identifier] {
			Roger.info("[\(identifier.rawValue)][item] - cached")
			return item
		}
		if identifier == Self.nativeTouchBarToggleIdentifier {
			guard nativeTouchBarToggleEnabled else {
				return nil
			}
			let item = makeSwitchItem(interactive: true)
			cachedItems[identifier] = item
			return item
		}
		if identifier == WeatherTouchBarItem.itemIdentifier {
			let item = WeatherTouchBarItem()
			cachedItems[identifier] = item
			return item
		}
		guard let widget = widgets[identifier] else {
			Roger.error("Can't find `NSTouchBarItem` for given identifier: `\(identifier)`")
			return nil
		}
		Roger.info("[\(identifier.rawValue)][item] - initializes")
		let item = PKWidgetTouchBarItem(widget: widget)
		cachedItems[identifier] = item
		if let delegate = item?.widget as? PKScreenEdgeMouseDelegate {
			cachedMouseDelegates.append(delegate)
		}
		return item
	}

	internal func makeSwitchItem(interactive: Bool) -> NSTouchBarItem {
		let item = NSCustomTouchBarItem(identifier: Self.nativeTouchBarToggleIdentifier)
		item.view = TouchBarSwapHandleView(
			direction: .toNative,
			label: "touchbar.show-ai-activity".localized,
			target: interactive ? self : nil,
			action: interactive ? #selector(showAgentActivity) : nil
		)
		item.customizationLabel = "touchbar.switch".localized
		return item
	}

	@discardableResult
	private func dismissAgentActivity() -> Bool {
		guard isShowingAgentActivity else { return false }
		isShowingAgentActivity = false
		TouchBarHelper.dismissFromTop(activityTouchBar)
		activityView.stopRefreshing()
		return true
	}

	@objc private func showAgentActivity() {
		guard isVisible, !AppController.shared.isLocked, !isShowingAgentActivity else { return }
		cancelBlankTouchBarCheck()
		edgeController?.tearDown(invalidate: true)
		edgeController = nil
		isShowingAgentActivity = true
		TouchBarHelper.dismissFromTop(touchBar)
		restorePresentation()
		activityView.startRefreshing()
	}

	private func makeAgentActivityTouchBar() -> NSTouchBar {
		let back = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("io.github.pock.ai-activity.back"))
		back.view = TouchBarSwapHandleView(
			direction: .toPock,
			label: "menu.show-pock".localized,
			target: self,
			action: #selector(returnFromAgentActivity)
		)
		let activity = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("io.github.pock.ai-activity"))
		activity.view = activityView
		let native = NSCustomTouchBarItem(identifier: NSTouchBarItem.Identifier("io.github.pock.ai-activity.native"))
		native.view = TouchBarSwapHandleView(
			direction: .toNative,
			label: "menu.show-native-touchbar".localized,
			target: AppController.shared,
			action: #selector(AppController.showNativeTouchBarFromHandle)
		)
		let bar = NSTouchBar()
		bar.templateItems = [back, activity, native]
		bar.defaultItemIdentifiers = [back.identifier, .flexibleSpace, activity.identifier, .flexibleSpace, native.identifier]
		bar.principalItemIdentifier = activity.identifier
		return bar
	}

	@objc private func returnFromAgentActivity() {
		guard isShowingAgentActivity else { return }
		showWidgets()
	}

	@objc internal func showWidgets() {
		guard isShowingAgentActivity else {
			restorePresentation()
			return
		}
		guard !AppController.shared.isLocked else { return }
		dismissAgentActivity()
		restorePresentation()
		async(after: 0.05) { [weak self] in
			guard let self = self, self.isVisible, !self.isShowingAgentActivity else { return }
			self.reloadScreenEdgeController()
		}
	}
	
	// MARK: Blank Touch Bar
	private func checkForBlankTouchBar() {
		cancelBlankTouchBarCheck()
		let generation = blankTouchBarCheckGeneration
		emptyTouchBarController?.dismiss()
		emptyTouchBarController = nil
		guard Preferences[.allowBlankTouchBar] == false else {
			return
		}
		async(after: 0.225) { [weak self] in
			guard let self = self else {
				return
			}
			guard self.isVisible, self.blankTouchBarCheckGeneration == generation else {
				return
			}
			if self.currentItems.isEmpty && self.widgets.isEmpty {
				self.emptyTouchBarController = AppController.shared.showEmptyTouchBarController(with: .installDefault)
			} else if self.currentItems.isEmpty {
				self.emptyTouchBarController = AppController.shared.showEmptyTouchBarController(with: .empty)
			}
		}
	}

	private func cancelBlankTouchBarCheck() {
		blankTouchBarCheckGeneration += 1
	}
	
	// MARK: Mouse delegates
	
	private var mouseDelegates: [PKScreenEdgeMouseDelegate] {
		return cachedMouseDelegates
	}
	
	// MARK: Mouse Overrides
	override func reloadScreenEdgeController() {
		if !isShowingAgentActivity, Preferences[.mouseSupportEnabled], let parentView = parentView {
			let color: NSColor = Preferences[.showTrackingArea] ? .systemBlue : .clear
			self.edgeController = PKScreenEdgeController(mouseDelegate: self, parentView: parentView, barColor: color)
		} else {
			self.edgeController?.tearDown(invalidate: true)
			self.edgeController = nil
		}
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, mouseEnteredAtLocation location: NSPoint, in view: NSView) {
		mouseMoveThrottler.reset()
		super.screenEdgeController(controller, mouseEnteredAtLocation: location, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController(controller, mouseEnteredAtLocation: location, in: view)
		})
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, mouseMovedAtLocation location: NSPoint, in view: NSView) {
		guard mouseMoveThrottler.shouldForward(location) else {
			return
		}
		super.screenEdgeController(controller, mouseMovedAtLocation: location, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController(controller, mouseMovedAtLocation: location, in: view)
		})
	}
    
	override func screenEdgeController(_ controller: PKScreenEdgeController, mouseScrollWithDelta delta: CGFloat, atLocation location: NSPoint, in view: NSView) {
		super.screenEdgeController(controller, mouseScrollWithDelta: delta, atLocation: location, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController?(controller, mouseScrollWithDelta: delta, atLocation: location, in: view)
		})
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, mouseClickAtLocation location: NSPoint, in view: NSView) {
		super.screenEdgeController(controller, mouseClickAtLocation: location, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController(controller, mouseClickAtLocation: location, in: view)
		})
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, mouseExitedAtLocation location: NSPoint, in view: NSView) {
		mouseMoveThrottler.reset()
		super.screenEdgeController(controller, mouseExitedAtLocation: location, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController(controller, mouseExitedAtLocation: location, in: view)
		})
	}
	
	// MARK: Dragging Overrides
	override func screenEdgeController(_ controller: PKScreenEdgeController, draggingEntered info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
		var returnable: NSDragOperation?
		for delegate in mouseDelegates {
			guard let operation = delegate.screenEdgeController?(controller, draggingEntered: info, filepath: filepath, in: view) else {
				continue
			}
			returnable = operation
			self.showDraggingInfo(info, filepath: filepath)
			break
		}
		return returnable ?? super.screenEdgeController(controller, draggingEntered: info, filepath: filepath, in: view)
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, draggingUpdated info: NSDraggingInfo, filepath: String, in view: NSView) -> NSDragOperation {
		var returnable: NSDragOperation?
		for delegate in mouseDelegates {
			guard let operation = delegate.screenEdgeController?(controller, draggingUpdated: info, filepath: filepath, in: view) else {
				continue
			}
			returnable = operation
			self.updateCursorLocation(info.draggingLocation)
			self.updateDraggingInfoLocation(info.draggingLocation)
			break
		}
		return returnable ?? super.screenEdgeController(controller, draggingUpdated: info, filepath: filepath, in: view)
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, performDragOperation info: NSDraggingInfo, filepath: String, in view: NSView) -> Bool {
		var returnable: Bool?
		for delegate in mouseDelegates {
			guard let operation = delegate.screenEdgeController?(controller, performDragOperation: info, filepath: filepath, in: view) else {
				continue
			}
			returnable = operation
			break
		}
		return returnable ?? super.screenEdgeController(controller, performDragOperation: info, filepath: filepath, in: view)
	}
	
	override func screenEdgeController(_ controller: PKScreenEdgeController, draggingEnded info: NSDraggingInfo, in view: NSView) {
		super.screenEdgeController(controller, draggingEnded: info, in: view)
		mouseDelegates.forEach({
			$0.screenEdgeController?(controller, draggingEnded: info, in: view)
		})
	}

}

internal final class TouchBarSwapHandleView: NSButton {
	internal enum Direction {
		case toNative
		case toPock
	}
	private let direction: Direction
	private let preferredWidth: CGFloat

	override var intrinsicContentSize: NSSize {
		return NSSize(width: preferredWidth, height: 30)
	}

	internal init(
		width: CGFloat = 26,
		direction: Direction,
		label: String? = nil,
		target: AnyObject?,
		action: Selector?
	) {
		self.preferredWidth = width
		self.direction = direction
		super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
		self.target = target
		self.action = action
		setup()
		if let label = label {
			toolTip = label
			setAccessibilityLabel(label)
		}
		addDirectTouchGesture()
	}

	required init?(coder: NSCoder) {
		self.preferredWidth = 26
		self.direction = .toNative
		super.init(coder: coder)
		setup()
	}

	private func setup() {
		title = ""
		isBordered = false
		bezelStyle = .regularSquare
		setButtonType(.momentaryChange)
		focusRingType = .none
		wantsLayer = true
		layer?.backgroundColor = NSColor.clear.cgColor
		toolTip = direction == .toNative ? "Show native Touch Bar" : "Show Pock"
		setAccessibilityLabel(toolTip)
	}

	private func addDirectTouchGesture() {
		guard action != nil else {
			return
		}
		let clickGesture = NSClickGestureRecognizer(target: self, action: #selector(handleDirectTouchClick(_:)))
		clickGesture.allowedTouchTypes = .direct
		addGestureRecognizer(clickGesture)
	}

	@objc private func handleDirectTouchClick(_ recognizer: NSClickGestureRecognizer) {
		guard recognizer.state == .ended else {
			return
		}
		performClick(nil)
	}

	override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
		return true
	}

	override func highlight(_ flag: Bool) {
		super.highlight(flag)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		let capsule = NSRect(x: bounds.midX - 11, y: bounds.midY - 8, width: 22, height: 16)
		let isPressed = cell?.isHighlighted == true
		NSColor.white.withAlphaComponent(isPressed ? 0.23 : 0.14).setFill()
		NSBezierPath(roundedRect: capsule, xRadius: 6, yRadius: 6).fill()
		let directionMultiplier: CGFloat = direction == .toNative ? 1 : -1
		let dotCenter = capsule.midX - 4 * directionMultiplier
		NSColor.controlAccentColor.setFill()
		NSBezierPath(ovalIn: NSRect(x: dotCenter - 2, y: capsule.midY - 2, width: 4, height: 4)).fill()

		let centerX = capsule.midX + 4 * directionMultiplier
		let centerY = capsule.midY
		let path = NSBezierPath()
		path.move(to: NSPoint(x: centerX - 2 * directionMultiplier, y: centerY + 3))
		path.line(to: NSPoint(x: centerX + 2 * directionMultiplier, y: centerY))
		path.line(to: NSPoint(x: centerX - 2 * directionMultiplier, y: centerY - 3))
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		path.lineWidth = 1.3
		NSColor.white.withAlphaComponent(isPressed ? 1 : 0.82).setStroke()
		path.stroke()
	}
}

private struct MouseMoveThrottler {
	private let minimumInterval: TimeInterval
	private let locationTolerance: CGFloat
	private var lastForwardedTime: TimeInterval = 0
	private var lastForwardedLocation: NSPoint?

	init(maximumFrequency: Double, locationTolerance: CGFloat) {
		self.minimumInterval = 1.0 / max(maximumFrequency, 1)
		self.locationTolerance = locationTolerance
	}

	mutating func reset() {
		lastForwardedTime = 0
		lastForwardedLocation = nil
	}

	mutating func shouldForward(_ location: NSPoint) -> Bool {
		let now = ProcessInfo.processInfo.systemUptime
		if let lastLocation = lastForwardedLocation {
			guard hasMovedEnough(from: lastLocation, to: location) else {
				return false
			}
			guard now - lastForwardedTime >= minimumInterval else {
				return false
			}
		}
		lastForwardedTime = now
		lastForwardedLocation = location
		return true
	}

	private func hasMovedEnough(from lastLocation: NSPoint, to location: NSPoint) -> Bool {
		return abs(location.x - lastLocation.x) >= locationTolerance
			|| abs(location.y - lastLocation.y) >= locationTolerance
	}
}
