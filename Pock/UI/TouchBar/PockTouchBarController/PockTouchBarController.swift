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
	
	private var currentItems: [NSTouchBarItem.Identifier] {
		return touchBar?.itemIdentifiers ?? []
	}
	private var nativeTouchBarToggleEnabled: Bool {
		return Preferences[.nativeTouchBarToggleEnabled] as Bool
	}
	private var defaultItemIdentifiers: [NSTouchBarItem.Identifier] {
		var identifiers = Array(widgets.keys)
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
		TouchBarHelper.presentOnTop(touchBar, placement: configuration.placement)
		TouchBarHelper.setPresentationMode(to: configuration.mode)
		checkForBlankTouchBar()
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
		TouchBarHelper.dismissFromTop(touchBar)
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
		super.minimize()
	}
	
	override func dismiss() {
		cancelBlankTouchBarCheck()
		emptyTouchBarController?.dismiss()
		guard isVisible else {
			return
		}
		TouchBarHelper.setPresentationMode(to: Preferences[.userDefinedPresentationMode] as PresentationMode)
		super.dismiss()
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
		touchBar.customizationIdentifier = .pockTouchBarController
		touchBar.defaultItemIdentifiers = preferredItemIdentifiers
		touchBar.customizationAllowedItemIdentifiers = allowedCustomizationIdentifiers
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
			Roger.info("[\(identifier.rawValue)][item] - initializes")
			let item = makeNativeTouchBarToggleItem()
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

	internal func makeNativeTouchBarToggleItem() -> NSTouchBarItem {
		let item = NSCustomTouchBarItem(identifier: Self.nativeTouchBarToggleIdentifier)
		item.view = TouchBarSwapHandleView(
			width: 22,
			direction: .toNative,
			orientation: .vertical,
			target: AppController.shared,
			action: #selector(AppController.showNativeTouchBarFromHandle)
		)
		item.customizationLabel = "Native Touch Bar"
		return item
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
			if self.widgets.isEmpty {
				self.emptyTouchBarController = AppController.shared.showEmptyTouchBarController(with: .installDefault)
			} else {
				if self.currentItems.isEmpty {
					self.emptyTouchBarController = AppController.shared.showEmptyTouchBarController(with: .empty)
				}
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
		if Preferences[.mouseSupportEnabled], let parentView = parentView {
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
	internal enum Orientation {
		case horizontal
		case vertical
	}

	private let direction: Direction
	private let orientation: Orientation
	private let preferredWidth: CGFloat
	private var isCompact: Bool {
		return orientation == .horizontal && preferredWidth <= 24
	}

	override var intrinsicContentSize: NSSize {
		return NSSize(width: preferredWidth, height: 30)
	}

	internal init(
		width: CGFloat,
		direction: Direction,
		orientation: Orientation = .horizontal,
		target: AnyObject?,
		action: Selector?
	) {
		self.preferredWidth = width
		self.direction = direction
		self.orientation = orientation
		super.init(frame: NSRect(x: 0, y: 0, width: width, height: 30))
		self.target = target
		self.action = action
		setup()
		addDirectTouchGesture()
	}

	required init?(coder: NSCoder) {
		self.preferredWidth = 34
		self.direction = .toNative
		self.orientation = .horizontal
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
		if orientation == .vertical {
			drawVerticalHandle()
			return
		}
		drawHorizontalHandle()
	}

	private func drawHorizontalHandle() {
		let capsule = bounds.insetBy(dx: isCompact ? 2 : 3, dy: isCompact ? 8 : 7)
		let isPressed = cell?.isHighlighted == true
		let capsulePath = NSBezierPath(roundedRect: capsule, xRadius: capsule.height / 2, yRadius: capsule.height / 2)
		NSColor.white.withAlphaComponent(isPressed ? 0.2 : 0.12).setFill()
		capsulePath.fill()
		NSColor.white.withAlphaComponent(isPressed ? 0.34 : 0.24).setStroke()
		capsulePath.lineWidth = 0.75
		capsulePath.stroke()

		guard isCompact == false else {
			drawHorizontalChevron(in: capsule, isPressed: isPressed)
			return
		}
		drawDot(in: capsule, isPressed: isPressed)
		drawHorizontalChevron(in: capsule, isPressed: isPressed)
	}

	private func drawVerticalHandle() {
		let capsule = bounds.insetBy(dx: 5, dy: 3)
		let isPressed = cell?.isHighlighted == true
		let capsulePath = NSBezierPath(roundedRect: capsule, xRadius: capsule.width / 2, yRadius: capsule.width / 2)
		NSColor.white.withAlphaComponent(isPressed ? 0.2 : 0.12).setFill()
		capsulePath.fill()
		NSColor.white.withAlphaComponent(isPressed ? 0.34 : 0.24).setStroke()
		capsulePath.lineWidth = 0.75
		capsulePath.stroke()

		drawVerticalDot(in: capsule, isPressed: isPressed)
		drawVerticalChevron(in: capsule, isPressed: isPressed)
	}

	private func drawDot(in capsule: NSRect, isPressed: Bool) {
		let diameter: CGFloat = isPressed ? 7 : 6
		let centerX = direction == .toNative ? capsule.minX + 7 : capsule.maxX - 7
		let dot = NSRect(
			x: centerX - diameter / 2,
			y: capsule.midY - diameter / 2,
			width: diameter,
			height: diameter
		)
		NSColor.controlAccentColor.withAlphaComponent(isPressed ? 0.95 : 0.8).setFill()
		NSBezierPath(ovalIn: dot).fill()
	}

	private func drawVerticalDot(in capsule: NSRect, isPressed: Bool) {
		let diameter: CGFloat = isPressed ? 6 : 5
		let centerY = direction == .toNative ? capsule.maxY - 7 : capsule.minY + 7
		let dot = NSRect(
			x: capsule.midX - diameter / 2,
			y: centerY - diameter / 2,
			width: diameter,
			height: diameter
		)
		NSColor.controlAccentColor.withAlphaComponent(isPressed ? 0.95 : 0.8).setFill()
		NSBezierPath(ovalIn: dot).fill()
	}

	private func drawHorizontalChevron(in capsule: NSRect, isPressed: Bool) {
		let centerX = direction == .toNative ? capsule.maxX - 7 : capsule.minX + 7
		let centerY = capsule.midY
		let directionMultiplier: CGFloat = direction == .toNative ? 1 : -1
		let path = NSBezierPath()
		path.move(to: NSPoint(x: centerX - 2 * directionMultiplier, y: centerY + 3))
		path.line(to: NSPoint(x: centerX + 2 * directionMultiplier, y: centerY))
		path.line(to: NSPoint(x: centerX - 2 * directionMultiplier, y: centerY - 3))
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		path.lineWidth = 1.2
		NSColor.white.withAlphaComponent(isPressed ? 0.72 : 0.56).setStroke()
		path.stroke()
	}

	private func drawVerticalChevron(in capsule: NSRect, isPressed: Bool) {
		let centerX = capsule.midX
		let centerY = direction == .toNative ? capsule.minY + 7 : capsule.maxY - 7
		let directionMultiplier: CGFloat = direction == .toNative ? -1 : 1
		let path = NSBezierPath()
		path.move(to: NSPoint(x: centerX - 3, y: centerY - 2 * directionMultiplier))
		path.line(to: NSPoint(x: centerX, y: centerY + 2 * directionMultiplier))
		path.line(to: NSPoint(x: centerX + 3, y: centerY - 2 * directionMultiplier))
		path.lineCapStyle = .round
		path.lineJoinStyle = .round
		path.lineWidth = 1.2
		NSColor.white.withAlphaComponent(isPressed ? 0.72 : 0.56).setStroke()
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
