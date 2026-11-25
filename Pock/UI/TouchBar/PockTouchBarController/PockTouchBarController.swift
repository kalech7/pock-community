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
	private static let activityIdentifier = NSTouchBarItem.Identifier("io.github.pock.ai-activity")
	private static let backIdentifier = NSTouchBarItem.Identifier("io.github.pock.ai-activity.back")
	private static let nativeIdentifier = NSTouchBarItem.Identifier("io.github.pock.ai-activity.native")
	private static let navigationPriority = NSTouchBarItem.Priority(rawValue: NSTouchBarItem.Priority.high.rawValue + 1)

	internal static var layoutWidgets: [TouchBarLayoutEditor.Widget] {
		let builtIns = [
			(identifier: activityIdentifier, name: "AI Activity".localized, symbol: "sparkles"),
			(identifier: AudioOutputTouchBarItem.itemIdentifier, name: AudioOutputTouchBarItem.name, symbol: "speaker.wave.2"),
			(identifier: StatusTouchBarItem.itemIdentifier, name: StatusTouchBarItem.name, symbol: "gauge"),
			(identifier: WeatherTouchBarItem.itemIdentifier, name: "Weather".localized, symbol: "cloud.sun")
		]
		let menus: Set<TouchBarLayoutEditor.Menu> = [.primary, .secondary]
		let installed = WidgetsLoader.loadedWidgets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		return builtIns.map { .init(id: $0.identifier.rawValue, name: $0.name, symbol: $0.symbol, supportedMenus: menus) }
			+ installed.map { .init(id: $0.bundleIdentifier, name: $0.name, symbol: "app.dashed", supportedMenus: menus) }
	}

	internal static var widgetLayout: TouchBarWidgetLayout {
		return Preferences.touchBarWidgetLayout ?? .migrating(
			legacyPrimary: Preferences[.pockTouchBarItemIdentifiers],
			defaultPrimary: WidgetsLoader.loadedWidgets.map(\.bundleIdentifier).sorted() + [WeatherTouchBarItem.itemIdentifier.rawValue],
			defaultSecondary: [activityIdentifier, AudioOutputTouchBarItem.itemIdentifier].map(\.rawValue),
			navigation: nativeTouchBarToggleIdentifier.rawValue,
			spacer: NSTouchBarItem.Identifier.flexibleSpace.rawValue
		)
	}

	/// Data
	private(set) var widgets: [NSTouchBarItem.Identifier: PKWidgetInfo] = [:]
	private(set) var cachedItems: [NSTouchBarItem.Identifier: NSTouchBarItem] = [:]
	private var mouseMoveThrottler = MouseMoveThrottler(maximumFrequency: 30, locationTolerance: 0.75)
	private var activityView: AgentActivityView?
	private enum Panel { case activity, audio }
	private var panel: Panel?
	private var audioReturnPanel: Panel?
	private lazy var audioPanel = AudioOutputPanel { [weak self] in self?.returnFromAudioOutput() }

	private var currentItems: [NSTouchBarItem.Identifier] {
		return touchBar?.itemIdentifiers ?? []
	}
	private var nativeTouchBarToggleEnabled: Bool {
		return Preferences[.nativeTouchBarToggleEnabled] as Bool
	}
	private var availableItemIdentifiers: Set<NSTouchBarItem.Identifier> {
		return Set(Self.layoutWidgets.map { NSTouchBarItem.Identifier($0.id) })
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
		let secondary = Set(Self.widgetLayout.secondary)
		let available = availableItemIdentifiers
		let identifiers = Self.layoutWidgets.filter { !secondary.contains($0.id) }
			.map { NSTouchBarItem.Identifier($0.id) }.filter(available.contains)
		return identifiers + [.flexibleSpace] + requiredCustomizationIdentifiers
	}

	internal var requiredCustomizationIdentifiers: [NSTouchBarItem.Identifier] {
		return nativeTouchBarToggleEnabled ? [Self.nativeTouchBarToggleIdentifier] : []
	}

	internal var preferredItemIdentifiers: [NSTouchBarItem.Identifier] {
		let available = availableItemIdentifiers.union([.flexibleSpace])
		return Self.widgetLayout.primary.map { NSTouchBarItem.Identifier($0) }.filter(available.contains)
			+ requiredCustomizationIdentifiers
	}

	private var secondaryItemIdentifiers: [NSTouchBarItem.Identifier] {
		let available = availableItemIdentifiers
		return Self.widgetLayout.secondary.map { NSTouchBarItem.Identifier($0) }.filter(available.contains)
	}

	private var activeItemIdentifiers: [NSTouchBarItem.Identifier] {
		switch panel {
		case .activity: return secondaryItemIdentifiers
		case .audio: return []
		case nil: return preferredItemIdentifiers
		}
	}

	private var displayedItemIdentifiers: [NSTouchBarItem.Identifier] {
		switch panel {
		case .audio: return AudioOutputPanel.itemIdentifiers
		case nil: return preferredItemIdentifiers
		case .activity:
			var identifiers = secondaryItemIdentifiers
			if let center = identifiers.firstIndex(of: Self.activityIdentifier) {
				identifiers.insert(.flexibleSpace, at: center + 1)
				identifiers.insert(.flexibleSpace, at: center)
			} else if identifiers.isEmpty {
				identifiers = [.flexibleSpace]
			}
			return [Self.backIdentifier] + identifiers + [Self.nativeIdentifier]
		}
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
		NotificationCenter.default.removeObserver(self)
		Roger.info("Deinit")
		resetPanel()
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
		isVisible = true
		restorePresentation()
	}

	internal func restorePresentation() {
		guard AppController.shared.isLocked == false, isVisible else {
			return
		}
		let configuration = presentationConfiguration
		updateDisplayedItems()
		TouchBarHelper.presentOnTop(touchBar, placement: configuration.placement)
		TouchBarHelper.setPresentationMode(to: configuration.mode)
		if panel == nil {
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
		stopStatusWidgets()
		resetPanel()
		TouchBarHelper.dismissFromTop(touchBar)
	}

	internal func resumePresentation() {
		guard AppController.shared.isLocked == false, isVisible == false else {
			return
		}
		isVisible = true
		restorePresentation()
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
		stopStatusWidgets()
		resetPanel()
		super.minimize()
	}
	
	override func dismiss() {
		cancelBlankTouchBarCheck()
		stopStatusWidgets()
		resetPanel()
		emptyTouchBarController?.dismiss()
		guard isVisible else {
			return
		}
		TouchBarHelper.setPresentationMode(to: Preferences[.userDefinedPresentationMode] as PresentationMode)
		super.dismiss()
	}
	
	private func flushWidgetItems() {
		invalidateWidgetItems()
		widgets.removeAll()
	}

	private func invalidateWidgetItems() {
		stopStatusWidgets()
		cachedItems.removeAll()
		activityView = nil
	}

	internal func savePreferredItemIdentifiers(_ identifiers: [NSTouchBarItem.Identifier]) {
		let allowedIdentifiers = Set(allowedCustomizationIdentifiers).subtracting(requiredCustomizationIdentifiers)
		var seen = Set<NSTouchBarItem.Identifier>()
		let visibleIdentifiers = identifiers.filter {
			allowedIdentifiers.contains($0) && ($0 == .flexibleSpace || seen.insert($0).inserted)
		}
		Preferences.touchBarWidgetLayout = Self.widgetLayout.replacingPrimary(
			visibleIdentifiers.map(\.rawValue), editable: Set(allowedIdentifiers.map(\.rawValue))
		)
	}

	/// Setup Touch Bar
	override func makeTouchBar() -> NSTouchBar? {
		let touchBar = NSTouchBar()
		touchBar.delegate = self
		touchBar.templateItems = makeSecondaryNavigationItems().union(audioPanel.templateItems)
		// The separate customization palette saves its layout in Preferences.
		touchBar.defaultItemIdentifiers = displayedItemIdentifiers
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
		if identifier == StatusTouchBarItem.itemIdentifier {
			let item = StatusTouchBarItem()
			cachedItems[identifier] = item
			updateStatusWidgets()
			return item
		}
		if identifier == Self.activityIdentifier {
			let item = NSCustomTouchBarItem(identifier: identifier)
			let view = AgentActivityView()
			item.view = view
			activityView = view
			cachedItems[identifier] = item
			updateStatusWidgets()
			return item
		}
		if identifier == AudioOutputTouchBarItem.itemIdentifier {
			let item = AudioOutputTouchBarItem.make(target: self, action: #selector(showAudioOutput))
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
		return item
	}

	internal func makeBuiltInCustomizationItem(for identifier: NSTouchBarItem.Identifier) -> NSTouchBarItem? {
		if identifier == Self.nativeTouchBarToggleIdentifier { return makeSwitchItem(interactive: false) }
		if identifier == WeatherTouchBarItem.itemIdentifier { return WeatherTouchBarItem.makeCustomizationItem() }
		if identifier == AudioOutputTouchBarItem.itemIdentifier || identifier == Self.activityIdentifier
			|| identifier == StatusTouchBarItem.itemIdentifier,
			let label = Self.layoutWidgets.first(where: { $0.id == identifier.rawValue })?.name {
			let item = NSCustomTouchBarItem(identifier: identifier)
			item.view = NSButton(title: label, target: nil, action: nil)
			item.customizationLabel = label
			return item
		}
		return nil
	}

	internal func makeSwitchItem(interactive: Bool) -> NSTouchBarItem {
		let item = NSCustomTouchBarItem(identifier: Self.nativeTouchBarToggleIdentifier)
		item.view = TouchBarSwapHandleView(
			direction: .toNative,
			label: "Show AI Menu".localized,
			target: interactive ? self : nil,
			action: interactive ? #selector(showSecondaryMenu) : nil
		)
		item.customizationLabel = "touchbar.switch".localized
		item.visibilityPriority = Self.navigationPriority
		return item
	}

	private func resetPanel() {
		if panel == .audio { audioPanel.stop() }
		panel = nil
		audioReturnPanel = nil
	}

	@objc internal func showAgentActivity() {
		if secondaryItemIdentifiers.contains(Self.activityIdentifier) {
			showSecondaryMenu()
		} else if preferredItemIdentifiers.contains(Self.activityIdentifier) {
			showWidgets()
		} else {
			AppController.shared.openTouchBarLayoutEditor()
		}
	}

	@objc private func showSecondaryMenu() {
		showPanel(.activity)
	}

	@objc internal func showAudioOutput() {
		guard panel != .audio else { return }
		audioReturnPanel = panel
		showPanel(.audio)
	}

	private func returnFromAudioOutput() {
		guard panel == .audio else { return }
		showPanel(audioReturnPanel)
	}

	private func showPanel(_ nextPanel: Panel?) {
		guard isVisible, !AppController.shared.isLocked, panel != nextPanel else { return }
		cancelBlankTouchBarCheck()
		edgeController?.tearDown(invalidate: true)
		edgeController = nil
		if panel == .audio {
			audioPanel.stop()
			audioReturnPanel = nil
		}
		panel = nextPanel
		if nextPanel == .audio { audioPanel.start() }
		// Changing the modal bar for every menu leaves a gap while TouchBarServer updates its surfaces.
		updateDisplayedItems()
		if panel == nil { checkForBlankTouchBar() }
		refreshScreenEdgeAfterPresentation()
	}

	private func makeSecondaryNavigationItems() -> Set<NSTouchBarItem> {
		let back = NSCustomTouchBarItem(identifier: Self.backIdentifier)
		back.view = TouchBarSwapHandleView(
			direction: .toPock,
			label: "menu.show-pock".localized,
			target: self,
			action: #selector(returnFromAgentActivity)
		)
		back.visibilityPriority = Self.navigationPriority
		let native = NSCustomTouchBarItem(identifier: Self.nativeIdentifier)
		native.view = TouchBarSwapHandleView(
			direction: .toNative,
			label: "menu.show-native-touchbar".localized,
			target: AppController.shared,
			action: #selector(AppController.showNativeTouchBarFromHandle)
		)
		native.visibilityPriority = Self.navigationPriority
		return [back, native]
	}

	internal func reloadWidgetLayout() {
		emptyTouchBarController?.dismiss()
		emptyTouchBarController = nil
		guard isVisible, !AppController.shared.isLocked else { return }
		updateDisplayedItems()
		if panel == nil { checkForBlankTouchBar() }
		refreshScreenEdgeAfterPresentation()
	}

	private func updateDisplayedItems() {
		if let bar = touchBar {
			let identifiers = displayedItemIdentifiers
			if bar.defaultItemIdentifiers != identifiers { bar.defaultItemIdentifiers = identifiers }
		}
		updateStatusWidgets()
	}

	private func updateStatusWidgets() {
		guard isVisible else { return }
		let identifiers = activeItemIdentifiers
		if identifiers.contains(Self.activityIdentifier) { activityView?.startRefreshing() }
		else { activityView?.stopRefreshing() }
		let status = cachedItems[StatusTouchBarItem.itemIdentifier] as? StatusTouchBarItem
		if identifiers.contains(StatusTouchBarItem.itemIdentifier) { status?.startRefreshing() }
		else { status?.stopRefreshing() }
	}

	private func stopStatusWidgets() {
		activityView?.stopRefreshing()
		(cachedItems[StatusTouchBarItem.itemIdentifier] as? StatusTouchBarItem)?.stopRefreshing()
	}

	@objc private func returnFromAgentActivity() {
		guard panel == .activity else { return }
		showWidgets()
	}

	@objc internal func showWidgets() {
		guard panel != nil else {
			restorePresentation()
			return
		}
		showPanel(nil)
	}

	private func refreshScreenEdgeAfterPresentation() {
		async(after: 0.05) { [weak self] in
			guard let self = self, self.isVisible, self.panel != .audio else { return }
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
		return activeItemIdentifiers.compactMap { (cachedItems[$0] as? PKWidgetTouchBarItem)?.widget as? PKScreenEdgeMouseDelegate }
	}
	
	// MARK: Mouse Overrides
	override func reloadScreenEdgeController() {
		if panel != .audio, Preferences[.mouseSupportEnabled], let parentView = parentView {
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
