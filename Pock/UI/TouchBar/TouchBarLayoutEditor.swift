import AppKit

internal final class TouchBarLayoutEditor: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
	enum Menu: Hashable {
		case primary, secondary
	}

	struct Widget {
		let id: String
		let name: String
		let symbol: String
		let supportedMenus: Set<Menu>
	}

	private enum Section: String, CaseIterable {
		case primary, secondary, available

		var title: String {
			switch self {
			case .primary: return "Main menu".localized
			case .secondary: return "Second menu".localized
			case .available: return "Available widgets".localized
			}
		}

		var detail: String {
			switch self {
			case .primary: return "Shown when you open Pock.".localized
			case .secondary: return "Opened with the AI button.".localized
			case .available: return "Drop a widget here to hide it.".localized
			}
		}

		var menu: Menu? {
			switch self {
			case .primary: return .primary
			case .secondary: return .secondary
			case .available: return nil
			}
		}
	}

	private struct Layout: Equatable {
		var primary: [String]
		var secondary: [String]
	}

	private static var currentEditor: TouchBarLayoutEditor?
	private static let dragType = NSPasteboard.PasteboardType("io.github.pock.touchbar-layout-widget")
	private let widgets: [Widget]
	private let widgetsByID: [String: Widget]
	private let onApply: ([String], [String]) -> Void
	private var saved: Layout
	private var draft: Layout
	private var panels: [Section: LayoutEditorPanel] = [:]
	private var refreshingSelection = false

	private let moveButton = NSPopUpButton(frame: .zero, pullsDown: true)
	private let upButton = NSButton()
	private let downButton = NSButton()
	private let closeButton = NSButton()
	private let applyButton = NSButton()

	static func show(widgets: [Widget], primary: [String], secondary: [String],
					 onApply: @escaping (_ primary: [String], _ secondary: [String]) -> Void) {
		let editor = currentEditor ?? TouchBarLayoutEditor(widgets: widgets, layout: Layout(primary: primary, secondary: secondary), onApply: onApply)
		currentEditor = editor
		NSApp.activate(ignoringOtherApps: true)
		editor.showWindow(nil)
		editor.window?.makeKeyAndOrderFront(nil)
	}

	private init(widgets: [Widget], layout: Layout, onApply: @escaping ([String], [String]) -> Void) {
		self.widgets = widgets.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
		self.widgetsByID = Dictionary(widgets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
		self.onApply = onApply
		self.saved = layout
		self.draft = layout

		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 710, height: 584),
							  styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
		window.title = "Touch Bar Layout".localized
		window.contentMinSize = NSSize(width: 575, height: 480)
		window.isReleasedWhenClosed = false
		super.init(window: window)
		window.delegate = self
		window.contentView = makeContentView()
		window.center()
		window.initialFirstResponder = panels[.primary]?.table
		updateControls()
	}

	required init?(coder: NSCoder) { return nil }

	func windowWillClose(_ notification: Notification) {
		Self.currentEditor = nil
	}

	private func makeContentView() -> NSView {
		let content = NSView()
		let instructions = NSTextField(wrappingLabelWithString: "Drag widgets between menus to choose what appears and in which order.".localized)
		instructions.font = .systemFont(ofSize: 13)
		instructions.textColor = .secondaryLabelColor

		for section in Section.allCases {
			let placeholder = section == .available ? "All widgets are in a menu.".localized : "Drop widgets here".localized
			let panel = LayoutEditorPanel(title: section.title, detail: section.detail, placeholder: placeholder)
			panel.table.dataSource = self
			panel.table.delegate = self
			panel.table.registerForDraggedTypes([Self.dragType])
			panel.table.setDraggingSourceOperationMask(.move, forLocal: true)
			panels[section] = panel
		}
		let main = panels[.primary]!
		let secondary = panels[.secondary]!
		let menus = NSStackView(views: [main, secondary])
		menus.orientation = .horizontal
		menus.alignment = .centerY
		menus.distribution = .fillEqually
		menus.spacing = 14
		menus.setContentHuggingPriority(.defaultLow, for: .vertical)
		let available = panels[.available]!
		available.heightAnchor.constraint(equalToConstant: 143).isActive = true
		let footer = makeFooter()

		let sections = [instructions, menus, available, footer]
		let stack = NSStackView(views: sections)
		stack.translatesAutoresizingMaskIntoConstraints = false
		stack.orientation = .vertical
		stack.alignment = .centerX
		stack.spacing = 14
		content.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
			stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
			stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 20),
			stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20),
			menus.heightAnchor.constraint(greaterThanOrEqualToConstant: 178),
			main.heightAnchor.constraint(equalTo: menus.heightAnchor),
			secondary.heightAnchor.constraint(equalTo: menus.heightAnchor)
		] + sections.map { $0.widthAnchor.constraint(equalTo: stack.widthAnchor) })
		refreshPanels()
		return content
	}

	private func makeFooter() -> NSView {
		moveButton.target = self
		moveButton.action = #selector(moveSelected(_:))
		moveButton.setAccessibilityLabel("Move selected widget".localized)
		closeButton.target = self
		closeButton.action = #selector(closeEditor)
		closeButton.keyEquivalent = "\u{1b}"
		applyButton.title = "Apply Layout".localized
		applyButton.target = self
		applyButton.action = #selector(applyLayout)
		applyButton.keyEquivalent = "\r"
		for (button, direction, label) in [(upButton, "↑", "Move selected widget up"), (downButton, "↓", "Move selected widget down")] {
			button.title = direction
			button.target = self
			button.action = #selector(reorderSelected(_:))
			button.bezelStyle = .rounded
			button.toolTip = label.localized
			button.setAccessibilityLabel(label.localized)
			button.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
		}
		for button in [applyButton, closeButton] { button.bezelStyle = .rounded }

		let spacer = NSView()
		spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
		let footer = NSStackView(views: [moveButton, upButton, downButton, spacer, closeButton, applyButton])
		footer.orientation = .horizontal
		footer.alignment = .centerY
		footer.spacing = 7
		return footer
	}

	private func identifiers(in section: Section) -> [String] {
		switch section {
		case .primary: return draft.primary.filter { widgetsByID[$0] != nil }
		case .secondary: return draft.secondary.filter { widgetsByID[$0] != nil }
		case .available:
			let placed = Set(draft.primary + draft.secondary)
			return widgets.map(\.id).filter { !placed.contains($0) }
		}
	}

	private func section(for table: NSTableView) -> Section? {
		Section.allCases.first { panels[$0]?.table === table }
	}

	private var selection: (section: Section, row: Int, id: String)? {
		for section in Section.allCases {
			guard let row = panels[section]?.table.selectedRow, row >= 0 else { continue }
			let ids = identifiers(in: section)
			if ids.indices.contains(row) { return (section, row, ids[row]) }
		}
		return nil
	}

	private func refreshPanels(select id: String? = nil, in target: Section? = nil) {
		refreshingSelection = true
		for section in Section.allCases {
			guard let panel = panels[section] else { continue }
			let ids = identifiers(in: section)
			panel.table.deselectAll(nil)
			panel.table.reloadData()
			panel.emptyHint.isHidden = !ids.isEmpty
			if section == target, let id = id, let row = ids.firstIndex(of: id) {
				panel.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
				panel.table.scrollRowToVisible(row)
			}
		}
		refreshingSelection = false
		updateControls()
	}

	private func canPlace(_ id: String, in section: Section) -> Bool {
		guard let widget = widgetsByID[id] else { return false }
		return section.menu.map { widget.supportedMenus.contains($0) } ?? true
	}

	private func updateControls() {
		moveButton.removeAllItems()
		moveButton.addItem(withTitle: "Move to…".localized)
		let selected = selection
		if let selected = selected {
			for section in Section.allCases where section != selected.section && canPlace(selected.id, in: section) {
				moveButton.addItem(withTitle: section.title)
				moveButton.lastItem?.representedObject = section.rawValue
			}
		}
		moveButton.isEnabled = moveButton.numberOfItems > 1
		if let selected = selected, selected.section != .available {
			upButton.isEnabled = selected.row > 0
			downButton.isEnabled = selected.row + 1 < identifiers(in: selected.section).count
		} else {
			upButton.isEnabled = false
			downButton.isEnabled = false
		}
		applyButton.isEnabled = draft != saved
		closeButton.title = (draft == saved ? "Close" : "Cancel").localized
	}

	@objc private func moveSelected(_ sender: NSPopUpButton) {
		guard let selected = selection, let rawValue = sender.selectedItem?.representedObject as? String,
			  let destination = Section(rawValue: rawValue) else { return }
		move(selected.id, into: destination, before: nil)
	}

	@objc private func reorderSelected(_ sender: NSButton) {
		guard let selected = selection, selected.section != .available else { return }
		let ids = identifiers(in: selected.section)
		let nextRow = selected.row + (sender === upButton ? -1 : 2)
		move(selected.id, into: selected.section, before: ids.indices.contains(nextRow) ? ids[nextRow] : nil)
	}

	@objc private func applyLayout() {
		guard draft != saved else { return }
		onApply(draft.primary, draft.secondary)
		saved = draft
		updateControls()
	}

	@objc private func closeEditor() {
		window?.close()
	}

	private func move(_ id: String, into destination: Section, before nextID: String?) {
		guard canPlace(id, in: destination), id != nextID else { return }
		func insert(into ids: inout [String]) {
			let insertion = nextID.flatMap { ids.firstIndex(of: $0) } ?? ids.endIndex
			ids.insert(id, at: insertion)
		}
		draft.primary.removeAll { $0 == id }
		draft.secondary.removeAll { $0 == id }
		switch destination {
		case .primary: insert(into: &draft.primary)
		case .secondary: insert(into: &draft.secondary)
		case .available: break
		}
		refreshPanels(select: id, in: destination)
	}

	func numberOfRows(in tableView: NSTableView) -> Int {
		section(for: tableView).map { identifiers(in: $0).count } ?? 0
	}

	func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
		guard let section = section(for: tableView) else { return nil }
		let ids = identifiers(in: section)
		guard ids.indices.contains(row), let widget = widgetsByID[ids[row]] else { return nil }
		return LayoutEditorWidgetRow(name: widget.name, symbol: widget.symbol)
	}

	func tableViewSelectionDidChange(_ notification: Notification) {
		guard !refreshingSelection, let table = notification.object as? NSTableView else { return }
		if table.selectedRow >= 0 {
			refreshingSelection = true
			for panel in panels.values where panel.table !== table { panel.table.deselectAll(nil) }
			refreshingSelection = false
		}
		updateControls()
	}

	func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
		guard let section = section(for: tableView) else { return nil }
		let ids = identifiers(in: section)
		guard ids.indices.contains(row) else { return nil }
		let item = NSPasteboardItem()
		item.setString(ids[row], forType: Self.dragType)
		return item
	}

	func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int,
				   proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
		guard let source = info.draggingSource as? NSTableView, let origin = section(for: source),
			  let destination = section(for: tableView), origin != .available || destination != .available,
			  let id = info.draggingPasteboard.string(forType: Self.dragType), canPlace(id, in: destination) else { return [] }
		if destination == .available {
			tableView.setDropRow(-1, dropOperation: .on)
		} else {
			let count = identifiers(in: destination).count
			tableView.setDropRow(row < 0 ? count : min(row, count), dropOperation: .above)
		}
		return .move
	}

	func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int,
				   dropOperation: NSTableView.DropOperation) -> Bool {
		guard let destination = section(for: tableView), let id = info.draggingPasteboard.string(forType: Self.dragType),
			  canPlace(id, in: destination) else { return false }
		let ids = identifiers(in: destination)
		let nextID = destination != .available && ids.indices.contains(row) ? ids[row] : nil
		move(id, into: destination, before: nextID)
		return true
	}
}

private final class LayoutEditorPanel: NSBox {
	let table = NSTableView()
	let emptyHint: NSTextField

	init(title: String, detail: String, placeholder: String) {
		emptyHint = LayoutEditorEmptyHint(labelWithString: placeholder)
		super.init(frame: .zero)
		boxType = .custom
		borderWidth = 1
		cornerRadius = 12
		borderColor = .separatorColor
		fillColor = .controlBackgroundColor
		contentViewMargins = .zero

		let titleLabel = NSTextField(labelWithString: title)
		titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
		let detailLabel = NSTextField(labelWithString: detail)
		detailLabel.font = .systemFont(ofSize: 11)
		detailLabel.textColor = .secondaryLabelColor
		let header = NSStackView(views: [titleLabel, detailLabel])
		header.orientation = .vertical
		header.alignment = .leading
		header.spacing = 3

		let divider = NSBox()
		divider.boxType = .separator
		table.headerView = nil
		table.rowHeight = 34
		table.intercellSpacing = NSSize(width: 0, height: 2)
		table.backgroundColor = .clear
		table.usesAlternatingRowBackgroundColors = false
		table.allowsMultipleSelection = false
		table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
		table.setAccessibilityLabel(title)
		if #available(macOS 11.0, *) { table.style = .inset }
		let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("widget"))
		column.resizingMask = .autoresizingMask
		table.addTableColumn(column)
		let scroll = NSScrollView()
		scroll.drawsBackground = false
		scroll.hasVerticalScroller = true
		scroll.autohidesScrollers = true
		scroll.documentView = table

		emptyHint.font = .systemFont(ofSize: 12)
		emptyHint.textColor = .secondaryLabelColor
		let content = NSView()
		contentView = content
		for view in [header, divider, scroll, emptyHint] {
			view.translatesAutoresizingMaskIntoConstraints = false
			content.addSubview(view)
		}
		NSLayoutConstraint.activate([
			header.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 14),
			header.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -14),
			header.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
			divider.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 9),
			divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
			divider.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
			scroll.topAnchor.constraint(equalTo: divider.bottomAnchor, constant: 4),
			scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 4),
			scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -4),
			scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -5),
			emptyHint.centerXAnchor.constraint(equalTo: scroll.centerXAnchor),
			emptyHint.centerYAnchor.constraint(equalTo: scroll.centerYAnchor)
		])
	}

	required init?(coder: NSCoder) { return nil }
}

private final class LayoutEditorEmptyHint: NSTextField {
	override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private final class LayoutEditorWidgetRow: NSTableCellView {
	init(name: String, symbol: String) {
		super.init(frame: .zero)
		let icon = NSImageView()
		icon.image = Self.image(symbol, fallback: NSImage.actionTemplateName, size: 12)
		icon.contentTintColor = .controlAccentColor
		icon.setAccessibilityElement(false)
		let grip = NSImageView()
		grip.image = Self.image("line.3.horizontal", fallback: NSImage.listViewTemplateName, size: 10)
		grip.contentTintColor = .tertiaryLabelColor
		grip.setAccessibilityElement(false)
		let nameLabel = NSTextField(labelWithString: name)
		nameLabel.font = .systemFont(ofSize: 12, weight: .medium)
		nameLabel.lineBreakMode = .byTruncatingTail
		nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		textField = nameLabel
		imageView = icon
		for view in [icon, nameLabel, grip] {
			view.translatesAutoresizingMaskIntoConstraints = false
			addSubview(view)
		}
		NSLayoutConstraint.activate([
			icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
			icon.centerYAnchor.constraint(equalTo: centerYAnchor),
			icon.widthAnchor.constraint(equalToConstant: 18),
			nameLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 9),
			nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
			nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: grip.leadingAnchor, constant: -8),
			grip.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -9),
			grip.centerYAnchor.constraint(equalTo: centerYAnchor),
			grip.widthAnchor.constraint(equalToConstant: 13)
		])
	}

	required init?(coder: NSCoder) { return nil }

	private static func image(_ symbol: String, fallback: NSImage.Name, size: CGFloat) -> NSImage? {
		if #available(macOS 11.0, *), let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
			return image.withSymbolConfiguration(.init(pointSize: size, weight: .semibold))
		}
		return NSImage(named: fallback)
	}
}
