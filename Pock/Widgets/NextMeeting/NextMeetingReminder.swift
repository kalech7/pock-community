import AppKit
import Combine
import EventKit

internal final class NextMeetingReminder {
	static let identifier = "io.github.pock.next-meeting"
	static let name = "Next Meeting".localized
	private static let displayDuration: TimeInterval = 30

	private let calendar = MeetingCalendar.shared
	private let canPresent: () -> Bool
	private let didDismiss: () -> Void
	private lazy var badge = MeetingBadgeView()
	private lazy var openButton = MeetingReminderButton(width: 54, target: self, action: #selector(openMeeting))
	private lazy var touchBar = makeTouchBar()
	private var observations = Set<AnyCancellable>()
	private var refreshTimer: Timer?
	private var dismissTimer: Timer?
	private var revision = 0
	private var lastAccess: MeetingCalendar.Access?
	private var presentedMeeting: CalendarMeeting?
	private var delivered: [String: Date] = [:]

	var isPresented: Bool { presentedMeeting != nil }

	init(canPresent: @escaping () -> Bool, didDismiss: @escaping () -> Void) {
		self.canPresent = canPresent
		self.didDismiss = didDismiss
	}

	func start() {
		let center = NotificationCenter.default
		let workspace = NSWorkspace.shared.notificationCenter
		Publishers.MergeMany(center.publisher(for: .EKEventStoreChanged),
			center.publisher(for: .NSSystemClockDidChange), center.publisher(for: .NSSystemTimeZoneDidChange),
			workspace.publisher(for: NSWorkspace.didWakeNotification),
			workspace.publisher(for: NSWorkspace.screensDidWakeNotification),
			workspace.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification))
			.receive(on: RunLoop.main)
			.sink { [weak self] _ in self?.calendarDidChange() }
			.store(in: &observations)
		Publishers.Merge(center.publisher(for: MeetingCalendar.accessChanged), center.publisher(for: MeetingCalendar.preferencesChanged))
			.receive(on: RunLoop.main)
			.sink { [weak self] _ in
				self?.dismiss()
				self?.refresh()
			}
			.store(in: &observations)
		Publishers.MergeMany(workspace.publisher(for: NSWorkspace.willSleepNotification),
			workspace.publisher(for: NSWorkspace.screensDidSleepNotification),
			workspace.publisher(for: NSWorkspace.sessionDidResignActiveNotification))
			.receive(on: RunLoop.main)
			.sink { [weak self] _ in self?.suspend() }
			.store(in: &observations)
		workspace.publisher(for: NSWorkspace.didActivateApplicationNotification)
			.receive(on: RunLoop.main)
			.sink { [weak self] _ in
				guard let self = self, self.lastAccess != self.calendar.access else { return }
				self.refresh()
			}
			.store(in: &observations)
		refresh()
	}

	deinit {
		refreshTimer?.invalidate()
		dismissTimer?.invalidate()
	}

	func suspend() {
		revision += 1
		refreshTimer?.invalidate()
		refreshTimer = nil
		dismiss()
	}

	func refresh() {
		refreshTimer?.invalidate()
		refreshTimer = nil
		revision += 1
		let currentRevision = revision
		let access = calendar.access
		lastAccess = access
		guard access == .granted, calendar.remindersEnabled, canPresent() else {
			dismiss()
			return
		}
		calendar.loadSchedule { [weak self] schedule in
			guard let self = self, self.revision == currentRevision else { return }
			guard let schedule = schedule, self.calendar.access == .granted,
				  self.calendar.remindersEnabled, self.canPresent() else {
				self.dismiss()
				return
			}
			self.apply(schedule)
		}
	}

	private func calendarDidChange() {
		guard calendar.remindersEnabled, calendar.access == .granted else {
			if isPresented || refreshTimer != nil { suspend() }
			return
		}
		revision += 1
		// Coalesce notifications from a calendar sync before fetching events again.
		scheduleRefresh(at: Date().addingTimeInterval(0.25))
	}

	private func scheduleRefresh(at date: Date) {
		refreshTimer?.invalidate()
		let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in self?.refresh() }
		refreshTimer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	private func apply(_ schedule: MeetingSchedule) {
		let now = Date()
		delivered = delivered.filter { $0.value > now }
		if let presented = presentedMeeting {
			if let updated = schedule.due.first(where: { $0.occurrenceKey == presented.occurrenceKey }) {
				presentedMeeting = updated
				updateView(for: updated)
			} else {
				dismiss()
			}
		}
		if !isPresented, let meeting = schedule.due.first(where: {
			$0.startsAt > now && delivered[$0.occurrenceKey] == nil
		}) {
			// Present one alert for simultaneous events, preferring a meeting with a join link.
			for event in schedule.due where event.startsAt == meeting.startsAt {
				delivered[event.occurrenceKey] = event.startsAt
			}
			presentedMeeting = meeting
			updateView(for: meeting)
			let placement: Int64 = TouchBarHelper.isSystemControlStripVisible ? 0 : 1
			TouchBarHelper.presentOnTop(touchBar, placement: placement)
			let timer = Timer(timeInterval: Self.displayDuration, repeats: false) { [weak self] _ in self?.closeReminder() }
			dismissTimer = timer
			RunLoop.main.add(timer, forMode: .common)
		}
		if let date = schedule.refreshAt { scheduleRefresh(at: date) }
	}

	func dismiss() {
		guard isPresented else { return }
		presentedMeeting = nil
		dismissTimer?.invalidate()
		dismissTimer = nil
		TouchBarHelper.dismissFromTop(touchBar)
		didDismiss()
	}

	@objc private func closeReminder() {
		dismiss()
		refresh()
	}

	@objc private func openMeeting() {
		guard let meeting = presentedMeeting, calendar.access == .granted,
			  calendar.remindersEnabled, canPresent(), meeting.endsAt > Date() else {
			closeReminder()
			return
		}
		closeReminder()
		if let url = meeting.joinURL {
			NSWorkspace.shared.open(url)
		} else {
			calendar.openCalendar()
		}
	}

	private func makeTouchBar() -> NSTouchBar {
		let details = NSCustomTouchBarItem(identifier: .init("\(Self.identifier).details"))
		details.view = badge
		let close = NSCustomTouchBarItem(identifier: .init("\(Self.identifier).dismiss"))
		let closeButton = MeetingReminderButton(width: 38, target: self, action: #selector(closeReminder))
		closeButton.isBordered = false
		closeButton.contentTintColor = .secondaryLabelColor
		closeButton.setIcon(.close, label: "Dismiss meeting reminder".localized)
		close.view = closeButton
		let open = NSCustomTouchBarItem(identifier: .init("\(Self.identifier).open"))
		open.view = openButton
		let bar = NSTouchBar()
		bar.templateItems = [close, details, open]
		bar.defaultItemIdentifiers = [.flexibleSpace, close.identifier, details.identifier, open.identifier, .flexibleSpace]
		return bar
	}

	private func updateView(for meeting: CalendarMeeting) {
		badge.update(for: meeting)
		let canJoin = meeting.joinURL != nil
		openButton.bezelColor = canJoin ? .systemBlue : nil
		if canJoin {
			openButton.setIcon(.video, label: "Join meeting".localized)
		} else {
			openButton.setIcon(.calendar, label: "Open Calendar".localized)
		}
	}
}

private final class MeetingReminderButton: NSButton {
	private let size: NSSize

	enum Icon {
		case close, video, calendar

		private var names: (symbol: String, template: NSImage.Name) {
			switch self {
			case .close: return ("xmark", NSImage.stopProgressTemplateName)
			case .video: return ("video", NSImage.touchBarCommunicationVideoTemplateName)
			case .calendar: return ("calendar", NSImage.touchBarOpenInBrowserTemplateName)
			}
		}

		var image: NSImage? {
			let names = names
			if #available(macOS 11, *), let symbol = NSImage(systemSymbolName: names.symbol, accessibilityDescription: nil) {
				let pointSize: CGFloat = self == .close ? 11 : 14
				return symbol.withSymbolConfiguration(.init(pointSize: pointSize, weight: .medium)) ?? symbol
			}
			return NSImage(named: names.template)
		}
	}

	init(width: CGFloat, target: AnyObject, action: Selector) {
		size = NSSize(width: width, height: 30)
		super.init(frame: NSRect(origin: .zero, size: size))
		self.target = target
		self.action = action
		title = ""
		imagePosition = .imageOnly
		bezelStyle = .rounded
		setContentHuggingPriority(.required, for: .horizontal)
	}

	required init?(coder: NSCoder) { return nil }

	override var intrinsicContentSize: NSSize { size }

	func setIcon(_ icon: Icon, label: String) {
		image = icon.image
		setAccessibilityLabel(label)
		toolTip = label
	}
}

private final class MeetingBadgeView: NSView {
	private let titleLabel = NSTextField(labelWithString: "")
	private let detailLabel = NSTextField(labelWithString: "")

	init() {
		super.init(frame: NSRect(x: 0, y: 0, width: 96, height: 30))
		let labels = NSStackView(views: [titleLabel, detailLabel])
		labels.orientation = .vertical
		labels.alignment = .leading
		labels.spacing = 0
		labels.translatesAutoresizingMaskIntoConstraints = false
		for label in [titleLabel, detailLabel] {
			label.lineBreakMode = .byTruncatingTail
			label.maximumNumberOfLines = 1
			label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
			label.widthAnchor.constraint(equalTo: labels.widthAnchor).isActive = true
		}
		titleLabel.font = .systemFont(ofSize: 11, weight: .semibold)
		titleLabel.textColor = .labelColor
		detailLabel.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
		detailLabel.textColor = .secondaryLabelColor
		addSubview(labels)
		NSLayoutConstraint.activate([
			labels.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 5),
			labels.centerYAnchor.constraint(equalTo: centerYAnchor),
			labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -5)
		])
	}

	required init?(coder: NSCoder) { return nil }

	override var intrinsicContentSize: NSSize {
		let textWidth = max(titleLabel.intrinsicContentSize.width, detailLabel.intrinsicContentSize.width)
		return NSSize(width: min(236, max(96, ceil(textWidth) + 10)), height: 30)
	}

	func update(for meeting: CalendarMeeting) {
		let time = DateFormatter.localizedString(from: meeting.startsAt, dateStyle: .none, timeStyle: .short)
		let detail = "Starts at %@".localized(time)
		titleLabel.stringValue = meeting.title
		detailLabel.stringValue = [detail, meeting.calendarTitle].compactMap { $0 }.joined(separator: " · ")
		toolTip = "\(meeting.title) · \(detail)"
		invalidateIntrinsicContentSize()
	}
}
