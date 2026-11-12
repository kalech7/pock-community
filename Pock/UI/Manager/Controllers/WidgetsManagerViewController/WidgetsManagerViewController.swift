//
//  WidgetsManagerViewController.swift
//  Pock
//
//  Created by Pierluigi Galdi on 30/04/21.
//

import Cocoa
import Combine
import EventKit
import PockKit
import TinyConstraints

class WidgetsManagerViewController: NSViewController {
	
	// MARK: Cell Identifiers
	
	private enum CellIdentifiers {
		static let widgetCell: NSUserInterfaceItemIdentifier = NSUserInterfaceItemIdentifier("widgetCellIdentifier")
	}
	
    // MARK: UI Elements
	///
	/// Common UI elements
	@IBOutlet private weak var tableView: NSTableView!
	/// Selected widget's UI elements
	@IBOutlet private weak var widgetNameLabel: NSTextField!
	@IBOutlet private weak var widgetAuthorLabel: NSTextField!
	@IBOutlet private weak var widgetVersionLabel: NSTextField!
	@IBOutlet private weak var widgetInstallButton: NSButton!
	@IBOutlet private weak var widgetUpdateButton: NSButton!
	@IBOutlet private weak var widgetUninstallButton: NSButton!
	@IBOutlet private weak var widgetUpdateStatusLabel: NSTextField!
	@IBOutlet private weak var widgetPreferencesContainer: NSView!
	@IBOutlet private weak var widgetPreferencesStatusLabel: NSTextField!
    @IBOutlet private weak var widgetPreferencesHorizontalLine: NSView!
    @IBOutlet private weak var widgetPreferencesResetButton: NSButton!
	
	@IBOutlet private weak var checkForWidgetsUpdateButton: NSButton!
	
	// MARK: Data

	private enum BuiltInWidget: CaseIterable {
		case weather, agentActivity, nextMeeting

		var name: String {
			switch self {
			case .weather: return "Weather".localized
			case .agentActivity: return "AI Activity".localized
			case .nextMeeting: return NextMeetingReminder.name
			}
		}

		var identifier: String {
			switch self {
			case .weather: return WeatherTouchBarItem.itemIdentifier.rawValue
			case .agentActivity: return PockTouchBarController.nativeTouchBarToggleIdentifier.rawValue
			case .nextMeeting: return NextMeetingReminder.identifier
			}
		}
	}

	private enum Entry {
		case builtIn(BuiltInWidget)
		case installed(PKWidgetInfo)

		var name: String {
			switch self {
			case .builtIn(let widget): return widget.name
			case .installed(let widget): return widget.name
			}
		}

		var identifier: String {
			switch self {
			case .builtIn(let widget): return "built-in:\(widget.identifier)"
			case .installed(let widget): return widget.bundleIdentifier
			}
		}

		var installedWidget: PKWidgetInfo? {
			if case .installed(let widget) = self { return widget }
			return nil
		}
	}

	private var entries: [Entry] = []
	private var isReloadingList = false
	private var selectedWidget: PKWidgetInfo? { return selectedEntry?.installedWidget }
	private var selectedEntry: Entry? {
		didSet {
			if let widget = selectedWidget {
				selectedWidgetNewVersion = Updater.newVersion(for: widget)
			} else {
				selectedWidgetNewVersion = nil
			}
			updateUIElementsForSelectedWidget()
			updatePreferencesContainerForSelectedPreferences()
		}
	}
	private var selectedPreferences: PKWidgetPreference?
	private var builtInPanel: NSView?
	private var selectedWidgetNewVersion: Updater.WidgetVersion?
	
	/// Set of disabled widget's `bundleIdentifier` to avoid user selection
	private var disabledWidgets: Set<String> = []
	
	// MARK: Overrides
	
	override var title: String? {
		get {
			return "widgets-manager.list.title".localized
		}
		set {
			view.window?.title = newValue ?? ""
		}
	}
	
	override func viewDidLoad() {
		super.viewDidLoad()
		self.tableView.register(NSNib(nibNamed: "PKWidgetCellView", bundle: .main), forIdentifier: CellIdentifiers.widgetCell)
		self.configureUIElements()
		reloadWidgetList()
		NotificationCenter.default.addObserver(self, selector: #selector(reload), name: .didLoadWidgets, object: nil)
		AppController.shared.reloadWidgets { }
	}
	
	override func viewWillAppear() {
		super.viewWillAppear()
		NSApp.activate(ignoringOtherApps: true)
	}
	
	override func viewWillDisappear() {
		super.viewWillDisappear()
		NSApp.deactivate()
	}
	
	private func configureUIElements() {
        widgetUpdateButton.title = "general.action.update".localized
        widgetUninstallButton.title = "general.action.remove".localized
		checkForWidgetsUpdateButton.title = "general.action.check-for-updates".localized
		widgetInstallButton.title = "menu.widgets.install-widget".localized
        widgetPreferencesResetButton.title = "widgets-manager.list.reset-preferences".localized
	}
	
	deinit {
		NotificationCenter.default.removeObserver(self)
		Roger.debug("[WidgetsManager][List] - deinit")
	}
	
}

// MARK: Methods

extension WidgetsManagerViewController {
	
	@objc private func reload() {
		async { [weak self] in
			self?.reloadWidgetList()
		}
	}

	private func reloadWidgetList() {
		let previouslySelected = selectedEntry?.identifier
		let builtIn = BuiltInWidget.allCases.map(Entry.builtIn)
		let installed = WidgetsLoader.installedWidgets.map(Entry.installed)
		entries = (builtIn + installed).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		let row = entries.firstIndex { $0.identifier == previouslySelected } ?? 0
		isReloadingList = true
		tableView.reloadData()
		tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
		isReloadingList = false
		selectedEntry = entries[row]
	}
	
	private func updatePreferredContentSize() {
		let frame = widgetPreferencesContainer.convert(widgetPreferencesContainer.visibleRect, to: view)
		self.preferredContentSize = NSSize(
			width: frame.origin.x + frame.size.width,
			height: frame.origin.y + frame.size.height
		)
		self.view.layout()
	}
	
	private func updateUIElementsForSelectedWidget() {
		let isBuiltIn: Bool
		if case .builtIn = selectedEntry {
			isBuiltIn = true
		} else {
			isBuiltIn = false
		}
		widgetUninstallButton.isHidden = isBuiltIn
		widgetUpdateButton.isHidden = isBuiltIn
		if case .builtIn(let widget) = selectedEntry {
			widgetNameLabel.stringValue = widget.name
			widgetAuthorLabel.stringValue = "Built into Pock".localized
			widgetVersionLabel.stringValue = Updater.fullAppVersion
			widgetUpdateStatusLabel.isHidden = true
			return
		}
		guard let widget = selectedWidget else {
			widgetNameLabel.stringValue = "widgets-manager.list.select-widget".localized
			widgetAuthorLabel.stringValue = "--"
			widgetVersionLabel.stringValue = "--"
			widgetUninstallButton.isEnabled = false
			widgetUpdateButton.isEnabled = false
			widgetUpdateButton.isHighlighted = false
			widgetUpdateStatusLabel.isHidden = true
			return
		}
		widgetNameLabel.stringValue = widget.name
		widgetAuthorLabel.stringValue = widget.author
		widgetVersionLabel.stringValue = widget.fullVersion
		widgetUninstallButton.isEnabled = true
		widgetUpdateButton.isEnabled = selectedWidgetNewVersion?.version != nil
		widgetUpdateButton.isHighlighted = widgetUpdateButton.isEnabled
		widgetUpdateStatusLabel.isHidden = selectedWidgetNewVersion?.error == nil
		widgetUpdateStatusLabel.stringValue = selectedWidgetNewVersion?.error?.description ?? "error.unknown".localized
	}
	
	private func updatePreferencesContainerForSelectedPreferences() {
		if case .builtIn(let widget) = selectedEntry {
			showBuiltInPreferences(widget)
			return
		}
		guard let widget = selectedWidget, let clss = widget.preferencesClass as? PKWidgetPreference.Type else {
			unloadPreferencesContainerWithTitle("widgets-manager.list.no-preferences".localized)
			selectedPreferences = nil
			return
		}
		if disabledWidgets.contains(where: { $0 == widget.bundleIdentifier }) {
			unloadPreferencesContainerWithTitle("widgets-manager.list.did-update".localized)
		} else {
			unloadPreferencesContainerWithTitle("widgets-manager.loading-preferences".localized)
			selectedPreferences = clss.init(nibName: clss.nibName, bundle: Bundle(for: clss))
			loadPreferencesContainerForSelectedPreferences()
		}
	}

	private func showBuiltInPreferences(_ widget: BuiltInWidget) {
		unloadPreferencesContainerWithTitle("")
		widgetPreferencesStatusLabel.isHidden = true
		let description: String
		let buttons: [NSButton]
		switch widget {
		case .weather:
			description = "Choose a city and temperature unit. Add Weather to your Touch Bar from Customize Pock.".localized
			buttons = [
				NSButton(title: "Configure Weather…".localized, target: self, action: #selector(configureWeather)),
				NSButton(title: "menu.customization.pock".localized, target: self, action: #selector(customizePock))
			]
		case .agentActivity:
			description = "See running agent sessions. Open AI Activity here or use the dot-and-arrow button on the Touch Bar.".localized
			buttons = [NSButton(title: "touchbar.show-ai-activity".localized, target: self, action: #selector(showAgentActivity))]
		case .nextMeeting:
			mountBuiltInPanel(NextMeetingPreferencesView())
			return
		}
		let label = NSTextField(wrappingLabelWithString: description)
		label.textColor = .secondaryLabelColor
		let actions = NSStackView(views: buttons)
		actions.orientation = .horizontal
		actions.spacing = 8
		let panel = NSStackView(views: [label, actions])
		panel.orientation = .vertical
		panel.alignment = .leading
		panel.spacing = 12
		label.widthAnchor.constraint(lessThanOrEqualTo: panel.widthAnchor).isActive = true
		mountBuiltInPanel(panel)
	}

	private func mountBuiltInPanel(_ panel: NSView) {
		panel.translatesAutoresizingMaskIntoConstraints = false
		widgetPreferencesContainer.addSubview(panel)
		NSLayoutConstraint.activate([
			panel.topAnchor.constraint(equalTo: widgetPreferencesContainer.topAnchor, constant: 20),
			panel.leadingAnchor.constraint(equalTo: widgetPreferencesContainer.leadingAnchor, constant: 20),
			panel.trailingAnchor.constraint(lessThanOrEqualTo: widgetPreferencesContainer.trailingAnchor, constant: -20)
		])
		builtInPanel = panel
	}

	@objc private func configureWeather() {
		WeatherTouchBarItem.openSettings()
	}

	@objc private func customizePock() {
		AppController.shared.openPockCustomizationPalette()
	}

	@objc private func showAgentActivity() {
		let controller = AppController.shared
		if !controller.isVisible { controller.showPockTouchBar() }
		controller.pockTouchBarController?.showAgentActivity()
	}
	
	private func loadPreferencesContainerForSelectedPreferences() {
		guard let preferences = selectedPreferences else {
			return
		}
		widgetPreferencesStatusLabel.stringValue = ""
		widgetPreferencesStatusLabel.isHidden = true
		addChild(preferences)
		widgetPreferencesContainer.addSubview(preferences.view)
		preferences.view.edgesToSuperview()
        widgetPreferencesHorizontalLine.isHidden = false
        widgetPreferencesResetButton.isHidden = false
		async { [weak self] in
			self?.updatePreferredContentSize()
		}
	}
	
	private func unloadPreferencesContainerWithTitle(_ title: String) {
        widgetPreferencesHorizontalLine.isHidden = true
        widgetPreferencesResetButton.isHidden = true
		builtInPanel?.removeFromSuperview()
		builtInPanel = nil
        selectedPreferences?.view.removeFromSuperview()
		selectedPreferences?.removeFromParent()
		selectedPreferences = nil
		widgetPreferencesStatusLabel.stringValue = title
		widgetPreferencesStatusLabel.isHidden = false
	}
	
	internal func presentWidgetInstallPanel(withInitialState state: WidgetsInstaller.State) {
		let controller = WidgetsInstallViewController()
		controller.state = state
		presentAsSheet(controller)
	}
	
	@IBAction internal func presentWidgetInstallerPanelFrom(_ button: NSButton) {
		let state: WidgetsInstaller.State
		switch button {
		case widgetInstallButton:
			state = .dragdrop
		case widgetUpdateButton:
			guard let widget = selectedWidget, let newVersion = selectedWidgetNewVersion?.version else {
				return
			}
			state = .update(widget: widget, version: newVersion)
		case widgetUninstallButton:
			guard let widget = selectedWidget else {
				return
			}
			state = .remove(widget: widget)
		default:
			return
		}
		presentWidgetInstallPanel(withInitialState: state)
	}
	
	@IBAction private func checkForWidgetsUpdates(_ sender: Any?) {
		checkForWidgetsUpdateButton.isEnabled = false
		checkForWidgetsUpdateButton.title = "general.action.checking".localized
		AppController.shared.fetchLatestVersions { [weak self] in
			async(after: 1) { [weak self] in
				self?.checkForWidgetsUpdateButton.isEnabled = true
				self?.checkForWidgetsUpdateButton.title = "general.action.check-for-updates".localized
				self?.reload()
			}
		}
	}
    
    @IBAction private func resetWidgetPreferences(_ sender: Any?) {
        guard let preferences = selectedPreferences else { return }
        preferences.reset()
        let identifier = selectedEntry?.identifier
        unloadPreferencesContainerWithTitle("Resetting preferences to default values…")
        async(after: 1.325) { [weak self] in
            guard let self = self, self.selectedEntry?.identifier == identifier else { return }
            self.updatePreferencesContainerForSelectedPreferences()
        }
    }
	
}

// MARK: Table - Data Source

extension WidgetsManagerViewController: NSTableViewDataSource {
	
	func numberOfRows(in tableView: NSTableView) -> Int {
		return entries.count
	}
	
	func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
		return 44
	}
	
	func tableView(_ tableView: NSTableView, sizeToFitWidthOfColumn column: Int) -> CGFloat {
		return 220
	}
	
}

// MARK: Table - Delegate

extension WidgetsManagerViewController: NSTableViewDelegate {
	
	/// View for cell in row
	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		/// Check for cell
		guard entries.indices.contains(row), let cell = tableView.makeView(withIdentifier: CellIdentifiers.widgetCell, owner: nil) as? PKWidgetCellView else {
			return nil
		}
		let entry = entries[row]
		let widget = entry.installedWidget
		let disabled = widget.map { disabledWidgets.contains($0.bundleIdentifier) } ?? false
		cell.status.image = NSImage(named: widget?.loaded == false ? NSImage.statusUnavailableName : NSImage.statusAvailableName)
		cell.name.stringValue = entry.name
		cell.name.alphaValue = disabled ? 0.475 : 1
		let newVersion = widget.map { Updater.newVersion(for: $0) }
		cell.badge.isHidden = disabled || (newVersion?.version == nil && newVersion?.error == nil)
		return cell
	}
	
	func tableViewSelectionDidChange(_ notification: Notification) {
		guard !isReloadingList else { return }
		let row = tableView.selectedRow
		selectedEntry = entries.indices.contains(row) ? entries[row] : nil
	}
	
}

private final class NextMeetingPreferencesView: NSStackView {
	private let calendar = MeetingCalendar.shared
	private let calendarMenu = NSPopUpButton(frame: .zero, pullsDown: false)
	private let accessButton = NSButton()
	private let status = NSTextField(wrappingLabelWithString: "")
	private var observations = Set<AnyCancellable>()
	private var lastAccess: MeetingCalendar.Access?
	private var revision = 0

	init() {
		super.init(frame: .zero)
		orientation = .vertical
		alignment = .leading
		spacing = 12

		let instructions = NSTextField(wrappingLabelWithString:
			"To sync Google, iCloud, or Exchange, open Calendar and choose Calendar > Add Account.".localized)
		instructions.textColor = .secondaryLabelColor
		instructions.maximumNumberOfLines = 0
		status.textColor = .secondaryLabelColor
		status.isHidden = true

		let reminders = NSButton(checkboxWithTitle: "Remind me 5 minutes before meetings".localized,
			target: self, action: #selector(toggleReminders(_:)))
		reminders.state = calendar.remindersEnabled ? .on : .off
		let calendarLabel = NSTextField(labelWithString: "Calendars for reminders".localized)
		calendarMenu.setAccessibilityLabel(calendarLabel.stringValue)
		calendarMenu.target = self
		calendarMenu.action = #selector(selectCalendar)
		calendarMenu.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		let selection = NSStackView(views: [calendarLabel, calendarMenu])
		selection.spacing = 8

		accessButton.bezelStyle = .rounded
		accessButton.target = self
		accessButton.action = #selector(openAccess)
		let actions = NSStackView(views: [
			accessButton,
			NSButton(title: "Open Calendar".localized, target: self, action: #selector(openCalendar))
		])
		actions.spacing = 8

		for row in [reminders, selection, status, instructions, actions] { addArrangedSubview(row) }
		NSLayoutConstraint.activate([
			instructions.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
			selection.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor),
			status.widthAnchor.constraint(lessThanOrEqualTo: widthAnchor)
		])
	}

	required init?(coder: NSCoder) { return nil }

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		revision += 1
		observations.removeAll()
		guard window != nil else { return }

		let center = NotificationCenter.default
		Publishers.MergeMany(center.publisher(for: .EKEventStoreChanged),
			center.publisher(for: MeetingCalendar.accessChanged))
			.debounce(for: .milliseconds(200), scheduler: RunLoop.main)
			.sink { [weak self] _ in self?.reloadCalendars() }
			.store(in: &observations)
		NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
			.receive(on: RunLoop.main)
			.sink { [weak self] _ in
				guard let self = self, self.lastAccess != self.calendar.access else { return }
				self.reloadCalendars()
			}
			.store(in: &observations)
		reloadCalendars()
	}

	private func reloadCalendars() {
		revision += 1
		let currentRevision = revision
		let access = calendar.access
		lastAccess = access
		accessButton.isHidden = access == .granted
		accessButton.title = access == .canRequest ? "Allow Calendar Access…".localized : "Calendar Privacy Settings…".localized
		guard access == .granted else {
			calendarMenu.removeAllItems()
			calendarMenu.addItem(withTitle: "Calendar access required".localized)
			calendarMenu.isEnabled = false
			status.isHidden = true
			return
		}
		if calendarMenu.numberOfItems == 0 || !calendarMenu.isEnabled {
			calendarMenu.removeAllItems()
			calendarMenu.addItem(withTitle: "Loading calendars…".localized)
			calendarMenu.isEnabled = false
		}
		calendar.loadCalendars { [weak self] calendars in
			guard let self = self, self.revision == currentRevision else { return }
			guard self.calendar.access == .granted else {
				self.reloadCalendars()
				return
			}
			self.showCalendars(calendars)
		}
	}

	private func showCalendars(_ calendars: [MeetingCalendar.CalendarOption]) {
		calendarMenu.removeAllItems()
		calendarMenu.addItem(withTitle: "All Calendars".localized)
		let groups = Dictionary(grouping: calendars, by: \.account)
		for account in groups.keys.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
			calendarMenu.menu?.addItem(.separator())
			for option in (groups[account] ?? []).sorted(by: { $0.title.localizedStandardCompare($1.title) == .orderedAscending }) {
				let title = account.isEmpty ? option.title : "\(option.title) — \(account)"
				let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
				item.representedObject = option.identifier
				calendarMenu.menu?.addItem(item)
			}
		}
		let selected = calendar.selectedCalendarIdentifier
		let missing = selected.map { identifier in !calendars.contains { $0.identifier == identifier } } ?? false
		if let selected = selected, missing {
			calendarMenu.addItem(withTitle: "Calendar unavailable".localized)
			calendarMenu.lastItem?.representedObject = selected
		}
		let item = calendarMenu.itemArray.first { !$0.isSeparatorItem && ($0.representedObject as? String) == selected }
		calendarMenu.select(item)
		calendarMenu.isEnabled = true
		status.stringValue = missing ? "Choose another calendar or reconnect its account.".localized : "No calendars are synced.".localized
		status.isHidden = !missing && !calendars.isEmpty
	}

	@objc private func selectCalendar() {
		calendar.selectedCalendarIdentifier = calendarMenu.selectedItem?.representedObject as? String
		if !status.isHidden { reloadCalendars() }
	}

	@objc private func toggleReminders(_ sender: NSButton) {
		calendar.remindersEnabled = sender.state == .on
	}

	@objc private func openAccess() { calendar.openAccess() }
	@objc private func openCalendar() { calendar.openCalendar() }
}
