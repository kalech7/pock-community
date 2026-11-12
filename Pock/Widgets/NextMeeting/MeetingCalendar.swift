import AppKit
import EventKit

internal struct CalendarMeeting {
	let identifier: String
	let title: String
	let startsAt: Date
	let endsAt: Date
	let calendarTitle: String?
	let joinURL: URL?

	var occurrenceKey: String { "\(identifier)|\(startsAt.timeIntervalSinceReferenceDate)" }
}

internal struct MeetingSchedule {
	static let reminderLeadTime: TimeInterval = 5 * 60
	let due: [CalendarMeeting]
	let refreshAt: Date?

	static func nextMidnight(after now: Date, calendar: Calendar) -> Date {
		calendar.dateInterval(of: .day, for: now)?.end ?? now.addingTimeInterval(86_400)
	}

	static func upcoming(in events: [EKEvent], at now: Date, calendar: Calendar) -> MeetingSchedule {
		var due: [CalendarMeeting] = []
		var refreshAt = nextMidnight(after: now, calendar: calendar)
		for event in events {
			guard !event.isAllDay, event.status != .canceled,
				  let start = event.startDate, let end = event.endDate, start > now, end > start,
				  event.attendees?.contains(where: { $0.isCurrentUser && $0.participantStatus == .declined }) != true else { continue }
			let reminderAt = start.addingTimeInterval(-reminderLeadTime)
			if reminderAt > now {
				refreshAt = min(refreshAt, reminderAt)
				continue
			}
			let title = (event.title ?? "").split(whereSeparator: \.isWhitespace).joined(separator: " ")
			due.append(CalendarMeeting(identifier: event.calendarItemIdentifier,
				title: title.isEmpty ? "Untitled event".localized : title, startsAt: start, endsAt: end,
				calendarTitle: event.calendar?.title,
				joinURL: MeetingLink.find(in: event)))
		}
		return MeetingSchedule(due: due.sorted {
			if $0.startsAt != $1.startsAt { return $0.startsAt < $1.startsAt }
			if ($0.joinURL != nil) != ($1.joinURL != nil) { return $0.joinURL != nil }
			return $0.identifier < $1.identifier
		}, refreshAt: refreshAt)
	}
}

private enum MeetingLink {
	private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
	private static let conferenceHosts = [
		"meet.google.com", "zoom.us", "zoom.com", "teams.microsoft.com", "teams.live.com",
		"teams.cloud.microsoft", "webex.com", "whereby.com", "meet.jit.si", "facetime.apple.com"
	]

	static func find(in event: EKEvent) -> URL? {
		if let url = event.url, isConferenceLink(url) { return url }
		for text in [event.location, event.notes].compactMap({ $0 }) {
			let range = NSRange(text.startIndex..<text.endIndex, in: text)
			if let url = detector?.matches(in: text, range: range).compactMap(\.url).first(where: isConferenceLink) {
				return url
			}
		}
		return nil
	}

	private static func isConferenceLink(_ url: URL) -> Bool {
		guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
			  components.scheme?.lowercased() == "https", let host = components.host?.lowercased(),
			  components.user == nil, components.password == nil, !components.path.isEmpty, components.path != "/" else { return false }
		return conferenceHosts.contains { host == $0 || host.hasSuffix(".\($0)") }
	}
}

internal final class MeetingCalendar {
	enum Access: Equatable {
		case granted, canRequest, unavailable
	}

	struct CalendarOption {
		let identifier: String
		let title: String
		let account: String
	}

	static let shared = MeetingCalendar()
	static let accessChanged = Notification.Name("io.github.pock.meeting-calendar-access-changed")
	static let preferencesChanged = Notification.Name("io.github.pock.meeting-calendar-preferences-changed")
	private static let selectionKey = "nextMeetingCalendarIdentifier"
	private static let remindersKey = "nextMeetingRemindersEnabled"
	private let queue = DispatchQueue(label: "io.github.pock.meeting-calendar", qos: .utility)
	private lazy var store = EKEventStore()
	private var isRequesting = false

	private init() {}

	var selectedCalendarIdentifier: String? {
		get { UserDefaults.standard.string(forKey: Self.selectionKey) }
		set {
			guard newValue != selectedCalendarIdentifier else { return }
			UserDefaults.standard.set(newValue, forKey: Self.selectionKey)
			NotificationCenter.default.post(name: Self.preferencesChanged, object: self)
		}
	}

	var remindersEnabled: Bool {
		get { UserDefaults.standard.object(forKey: Self.remindersKey) as? Bool ?? true }
		set {
			guard newValue != remindersEnabled else { return }
			UserDefaults.standard.set(newValue, forKey: Self.remindersKey)
			NotificationCenter.default.post(name: Self.preferencesChanged, object: self)
		}
	}

	var access: Access {
		let status = EKEventStore.authorizationStatus(for: .event)
		if status == .notDetermined { return .canRequest }
		if #available(macOS 14, *) {
			if status == .fullAccess { return .granted }
			if status == .writeOnly { return .canRequest }
		} else if status == .authorized {
			return .granted
		}
		return .unavailable
	}

	func openAccess() {
		guard access == .canRequest else {
			if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
				NSWorkspace.shared.open(url)
			}
			return
		}
		guard !isRequesting else { return }
		isRequesting = true
		NSApp.activate(ignoringOtherApps: true)
		queue.async {
			let completion: (Bool, Error?) -> Void = { _, _ in
				DispatchQueue.main.async {
					self.isRequesting = false
					NotificationCenter.default.post(name: Self.accessChanged, object: self)
				}
			}
			if #available(macOS 14, *) {
				self.store.requestFullAccessToEvents(completion: completion)
			} else {
				self.store.requestAccess(to: .event, completion: completion)
			}
		}
	}

	func loadSchedule(_ completion: @escaping (MeetingSchedule?) -> Void) {
		let selection = selectedCalendarIdentifier
		queue.async {
			let schedule = self.access == .granted ? self.readSchedule(in: selection) : nil
			DispatchQueue.main.async { completion(schedule) }
		}
	}

	func loadCalendars(_ completion: @escaping ([CalendarOption]) -> Void) {
		queue.async {
			let calendars = self.access == .granted ? self.store.calendars(for: .event) : []
			let options = calendars.map {
				CalendarOption(identifier: $0.calendarIdentifier, title: $0.title, account: $0.source?.title ?? "")
			}
			DispatchQueue.main.async { completion(options) }
		}
	}

	func openCalendar() {
		let workspace = NSWorkspace.shared
		if let url = workspace.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
			workspace.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
		}
	}

	private func readSchedule(in identifier: String?) -> MeetingSchedule {
		let now = Date()
		let calendar = Calendar.autoupdatingCurrent
		let calendars: [EKCalendar]?
		if let identifier = identifier {
			guard let selected = store.calendar(withIdentifier: identifier), selected.allowedEntityTypes.contains(.event) else {
				return MeetingSchedule(due: [], refreshAt: nil)
			}
			calendars = [selected]
		} else {
			calendars = nil
		}
		// Refresh at local midnight, including reminders for events just after it.
		let end = MeetingSchedule.nextMidnight(after: now, calendar: calendar)
			.addingTimeInterval(MeetingSchedule.reminderLeadTime)
		let predicate = store.predicateForEvents(withStart: now, end: end, calendars: calendars)
		let events = store.events(matching: predicate)
		return MeetingSchedule.upcoming(in: events, at: now, calendar: calendar)
	}
}
