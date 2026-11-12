import AppKit
import Combine

internal final class WeatherTouchBarItem: NSCustomTouchBarItem {

	static let itemIdentifier = NSTouchBarItem.Identifier("io.github.pock.weather")

	static func openSettings() {
		WeatherSettingsWindowController.shared.present()
	}

	convenience init() {
		self.init(identifier: Self.itemIdentifier)
		customizationLabel = "Weather"
		viewController = WeatherButtonController()
	}

	static func makeCustomizationItem() -> NSTouchBarItem {
		let item = NSCustomTouchBarItem(identifier: itemIdentifier)
		item.customizationLabel = "Weather"
		let button = WeatherBadgeButton()
		let sample = WeatherObservation(temperature2m: 21, weatherCode: 2, isDay: 1, time: 0)
		button.update(city: "Quito", reading: "21°C", observation: sample)
		item.view = button
		return item
	}
}

private final class WeatherModel {

	struct State {
		enum Status {
			case idle, loading, failed
		}

		var place: WeatherPlace?
		var unit: WeatherUnit
		var observation: WeatherObservation?
		var status: Status = .idle
		var holiday: String?

		var displayObservation: WeatherObservation? {
			guard let observation = observation,
				(-15 * 60...6 * 60 * 60).contains(Date().timeIntervalSince(observation.date)) else {
				return nil
			}
			return observation
		}

		var isStale: Bool {
			guard let observation = displayObservation else { return false }
			return status == .failed || Date().timeIntervalSince(observation.date) > 45 * 60
		}
	}

	static let shared = WeatherModel()
	private static let placeKey = "weatherPlace"
	private static let unitKey = "weatherTemperatureUnit"

	@Published private(set) var state: State
	private let service = WeatherService()
	private var task: URLSessionDataTask?
	private var requestID: UUID?
	private var refreshAfter = Date.distantPast
	private var holidayKey: String?
	private var holidays: [WeatherHoliday]?
	private var holidayTask: URLSessionDataTask?
	private var holidayRequestID: UUID?
	private var holidayRetryAfter = Date.distantPast

	private init() {
		let defaults = UserDefaults.standard
		let storedPlace = defaults.data(forKey: Self.placeKey).flatMap { try? JSONDecoder().decode(WeatherPlace.self, from: $0) }
		let unit = defaults.string(forKey: Self.unitKey).flatMap(WeatherUnit.init(rawValue:)) ?? .celsius
		state = State(place: storedPlace?.hasValidCoordinates == true ? storedPlace : nil, unit: unit)
	}

	func setPlace(_ place: WeatherPlace) {
		if state.place != place {
			requestID = nil
			task?.cancel()
			task = nil
			if let data = try? JSONEncoder().encode(place) {
				UserDefaults.standard.set(data, forKey: Self.placeKey)
			}
			state = State(place: place, unit: state.unit)
		}
		refresh(force: true)
	}

	func setUnit(_ unit: WeatherUnit) {
		UserDefaults.standard.set(unit.rawValue, forKey: Self.unitKey)
		state.unit = unit
	}

	func refresh(force: Bool = false) {
		guard let place = state.place else { return }
		refreshHoliday()
		guard requestID == nil, force || Date() >= refreshAfter else { return }
		let id = UUID()
		requestID = id
		state.status = .loading
		task = service.current(at: place) { [weak self] result in
			guard let self = self, self.requestID == id else { return }
			self.requestID = nil
			self.task = nil
			var next = self.state
			switch result {
			case .success(let observation):
				next.observation = observation
				next.status = .idle
				self.refreshAfter = Date().addingTimeInterval(15 * 60)
			case .failure:
				next.status = .failed
				self.refreshAfter = Date().addingTimeInterval(2 * 60)
			}
			self.state = next
			self.refreshHoliday()
		}
	}

	private func refreshHoliday() {
		guard let place = state.place, let country = place.countryCode,
			  country.utf8.count == 2, country.utf8.allSatisfy({ (65...90).contains($0) }),
			  let timezone = state.observation?.timezone ?? place.timezone,
			  let zone = TimeZone(identifier: timezone) else { return }
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = zone
		let today = calendar.dateComponents([.year, .month, .day], from: Date())
		guard let year = today.year, let month = today.month, let day = today.day else { return }
		let key = "\(country)-\(year)"
		if holidayKey != key {
			holidayKey = key
			holidayTask?.cancel()
			holidayTask = nil
			holidayRequestID = nil
			holidayRetryAfter = .distantPast
			holidays = nil
			if state.holiday != nil { state.holiday = nil }
		}
		if let holidays = holidays {
			let date = String(format: "%04d-%02d-%02d", year, month, day)
			let holiday = holidays.lazy.filter { $0.applies(on: date, country: country, subdivision: place.holidaySubdivision) }
				.compactMap(\.displayName).first
			if state.holiday != holiday { state.holiday = holiday }
		}
		guard holidayRequestID == nil, Date() >= holidayRetryAfter else { return }
		let id = UUID()
		holidayRequestID = id
		holidayTask = service.publicHolidays(country: country, year: year) { [weak self] result in
			guard let self = self, self.holidayRequestID == id else { return }
			self.holidayTask = nil
			self.holidayRequestID = nil
			switch result {
			case .success(let records):
				self.holidays = records
				self.holidayRetryAfter = Date().addingTimeInterval(24 * 60 * 60)
				self.refreshHoliday()
			case .failure:
				self.holidayRetryAfter = Date().addingTimeInterval(60 * 60)
			}
		}
	}
}

private final class WeatherButtonController: NSViewController {

	private let model = WeatherModel.shared
	private var subscription: AnyCancellable?
	private var refreshTimer: Timer?
	private lazy var button = WeatherBadgeButton(target: self, action: #selector(openSettings))

	override func loadView() {
		view = button
		subscription = model.$state.sink { [weak self] state in self?.render(state) }
	}

	override func viewWillAppear() {
		super.viewWillAppear()
		button.setTickerVisible(true)
		model.refresh()
		refreshTimer?.invalidate()
		let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in self?.model.refresh() }
		timer.tolerance = 10
		RunLoop.main.add(timer, forMode: .common)
		refreshTimer = timer
	}

	override func viewWillDisappear() {
		super.viewWillDisappear()
		button.setTickerVisible(false)
		refreshTimer?.invalidate()
		refreshTimer = nil
	}

	deinit {
		refreshTimer?.invalidate()
	}

	@objc private func openSettings() {
		WeatherTouchBarItem.openSettings()
	}

	private func render(_ state: WeatherModel.State) {
		guard let place = state.place else {
			button.update(city: "Weather", reading: "", details: [WeatherDetail(text: "Set City", symbol: "location")])
			button.setAccessibilityLabel("Weather, set city")
			return
		}
		let holidayDetail = state.holiday.map { WeatherDetail(text: $0, symbol: "calendar", label: "Holiday: \($0)") }
		guard let observation = state.displayObservation else {
			let status = WeatherDetail(text: state.status == .loading ? "Updating…" : "Unavailable")
			button.update(city: place.name, reading: "",
						  details: [status] + [holidayDetail].compactMap { $0 })
			let summary = state.status == .loading ? "Loading weather for \(place.name)" : "Weather unavailable for \(place.name)"
			button.setAccessibilityLabel(([summary] + [holidayDetail?.description].compactMap { $0 }).joined(separator: ", "))
			return
		}
		let condition = observation.condition
		let temperature = state.unit.format(celsius: observation.temperature2m)
		var details = [WeatherDetail(text: condition.description)]
		if let holidayDetail = holidayDetail { details.append(holidayDetail) }
		if let apparent = observation.apparentTemperature, apparent.isFinite,
		   abs(apparent - observation.temperature2m) >= 2 {
			details.append(WeatherDetail(text: "Feels \(state.unit.format(celsius: apparent))", symbol: "thermometer"))
		}
		if let wind = observation.windSpeed, (0...400).contains(wind) {
			let speed = "\(Int(wind.rounded())) km/h"
			details.append(WeatherDetail(text: speed, symbol: "wind", label: "Wind \(speed)"))
		}
		if let humidity = observation.humidity, (0...100).contains(humidity) {
			let percentage = "\(Int(humidity.rounded()))%"
			details.append(WeatherDetail(text: percentage, symbol: "drop", label: "Humidity \(percentage)"))
		}
		button.update(city: place.name, reading: state.isStale ? "\(temperature)*" : temperature,
					  observation: observation, details: details)
		let description = ([place.name, temperature] + details.map(\.description)).joined(separator: ", ")
		button.setAccessibilityLabel(state.isStale ? "Last reading for \(description)" : description)
	}
}

private struct WeatherDetail: Equatable {
	let text: String
	var symbol: String? = nil
	var label: String? = nil
	var description: String { return label ?? text }
}

private final class WeatherBadgeButton: NSButton {
	private let cityFont = NSFont.systemFont(ofSize: 10, weight: .semibold)
	private let readingFont = NSFont.monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
	private let compactReadingFont = NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
	private let detailFont = NSFont.systemFont(ofSize: 9, weight: .medium)
	private let cityStart: CGFloat = 35
	private let readingInset: CGFloat = 2
	private var readingWidth: CGFloat { return cityStart - readingInset }
	private let rightInset: CGFloat = 6
	private var city = ""
	private var reading = ""
	private var usesCompactReadingFont = false
	private var details: [WeatherDetail] = []
	private var detailIndex = 0
	private var detailTextHeight: CGFloat = 0
	private var detailIcon: NSImage?
	private var tickerTimer: Timer?
	private var tickerVisible = false
	private var tickerOffset: CGFloat = 0
	private var icon: NSImage?
	private var symbolName: String?
	private var fallback = "☁︎"
	private var style: WeatherObservation.ConditionStyle = .unknown
	private var isDay = false
	private var palette = WeatherBadgePalette(style: .unknown, isDay: false)
	private var readingColor = NSColor.white

	init(target: AnyObject? = nil, action: Selector? = nil) {
		super.init(frame: NSRect(x: 0, y: 0, width: 104, height: 30))
		self.target = target
		self.action = action
		title = ""
		isBordered = false
		setButtonType(.momentaryChange)
	}

	required init?(coder: NSCoder) {
		return nil
	}

	deinit {
		tickerTimer?.invalidate()
	}

	override var isFlipped: Bool { return true }

	override var intrinsicContentSize: NSSize {
		return NSSize(width: 104, height: 30)
	}

	func update(city: String, reading: String, observation: WeatherObservation? = nil, details: [WeatherDetail] = []) {
		let condition = observation?.condition
		let newDetails = details.isEmpty ? condition.map { [WeatherDetail(text: $0.description)] } ?? [] : details
		let newStyle = condition?.style ?? .unknown
		let newDay = observation?.isDay == 1
		let newSymbol = condition?.symbol ?? "cloud.sun"
		let appearanceChanged = style != newStyle || isDay != newDay || symbolName != newSymbol
		if appearanceChanged {
			style = newStyle
			isDay = newDay
			symbolName = newSymbol
			palette = WeatherBadgePalette(style: newStyle, isDay: newDay)
			fallback = condition?.fallback ?? "☁︎"
			icon = Self.tintedSymbol(newSymbol, color: palette.icon)
		}
		let newReadingColor = palette.temperatureColor(observation?.temperature2m)
		let textChanged = self.city != city || self.reading != reading
		let detailsChanged = self.details != newDetails
		guard appearanceChanged || textChanged || detailsChanged || readingColor != newReadingColor else { return }
		readingColor = newReadingColor
		if textChanged {
			self.city = city
			self.reading = reading
			usesCompactReadingFont = (reading as NSString).size(withAttributes: [.font: readingFont]).width > readingWidth
		}
		if detailsChanged {
			self.details = newDetails
			detailIndex = 0
			prepareDetail()
		} else if appearanceChanged {
			updateDetailIcon()
		}
		toolTip = ([city, reading] + newDetails.map(\.description)).filter { !$0.isEmpty }.joined(separator: " · ")
		needsDisplay = true
	}

	override func highlight(_ flag: Bool) {
		super.highlight(flag)
		if flag {
			tickerTimer?.invalidate()
		} else {
			prepareDetail()
		}
		needsDisplay = true
	}

	func setTickerVisible(_ visible: Bool) {
		guard tickerVisible != visible else { return }
		tickerVisible = visible
		detailIndex = 0
		prepareDetail()
	}

	private var currentDetail: WeatherDetail? {
		return details.indices.contains(detailIndex) ? details[detailIndex] : nil
	}

	private var detailBounds: NSRect {
		let x = cityStart + (detailIcon == nil ? 0 : 12)
		return NSRect(x: x, y: 16, width: max(0, bounds.width - x - rightInset), height: 13)
	}

	private var detailDrawingRect: NSRect {
		return NSRect(x: cityStart, y: 16, width: max(0, bounds.width - cityStart), height: 14)
	}

	private func updateDetailIcon() {
		detailIcon = currentDetail?.symbol.flatMap { Self.tintedSymbol($0, color: palette.icon) }
	}

	private func prepareDetail() {
		tickerTimer?.invalidate()
		tickerTimer = nil
		tickerOffset = 0
		updateDetailIcon()
		setNeedsDisplay(detailDrawingRect)
		guard tickerVisible, cell?.isHighlighted != true, let detail = currentDetail else { return }
		let textSize = (detail.text as NSString).size(withAttributes: [.font: detailFont])
		detailTextHeight = textSize.height
		let distance = max(0, textSize.width - detailBounds.width)
		if distance > 1 && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
			scheduleTicker(after: 1.6) { $0.scrollDetail(distance: distance) }
		} else if details.count > 1 {
			scheduleTicker(after: 7) { $0.nextDetail() }
		}
	}

	private func scheduleTicker(after interval: TimeInterval, action: @escaping (WeatherBadgeButton) -> Void) {
		let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
			guard let self = self, self.tickerVisible else { return }
			action(self)
		}
		timer.tolerance = min(0.5, interval * 0.15)
		tickerTimer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	private func scrollDetail(distance: CGFloat) {
		let start = ProcessInfo.processInfo.systemUptime
		let duration = min(16, max(0.5, TimeInterval(distance) / 25))
		let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] timer in
			guard let self = self, self.tickerVisible else { timer.invalidate(); return }
			let fraction = min(1, (ProcessInfo.processInfo.systemUptime - start) / duration)
			self.tickerOffset = distance * CGFloat(fraction)
			self.setNeedsDisplay(self.detailBounds)
			if fraction == 1 {
				timer.invalidate()
				self.scheduleTicker(after: 1.5) { $0.nextDetail() }
			}
		}
		timer.tolerance = 0.01
		tickerTimer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	private func nextDetail() {
		guard !details.isEmpty else { return }
		detailIndex = (detailIndex + 1) % details.count
		prepareDetail()
	}

	override func draw(_ dirtyRect: NSRect) {
		let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 6, yRadius: 6)
		palette.background.setFill()
		shape.fill()
		if cell?.isHighlighted == true {
			palette.city.withAlphaComponent(0.12).setFill()
			shape.fill()
		}
		if !detailDrawingRect.contains(dirtyRect) {
			drawReading()
		}
		if detailDrawingRect.intersects(dirtyRect) {
			drawDetail()
		}
	}

	private func drawReading() {
		let iconRect = NSRect(x: 10, y: 2, width: 13, height: 13)
		if let icon = icon {
			icon.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		} else {
			drawText(fallback, font: .systemFont(ofSize: 14), color: palette.icon, x: iconRect.minX,
					 width: iconRect.width, centerY: iconRect.midY)
		}
		drawText(city, font: cityFont, color: palette.city, x: cityStart,
				 width: bounds.width - cityStart - rightInset, centerY: 9)
		drawText(reading, font: usesCompactReadingFont ? compactReadingFont : readingFont, color: readingColor,
				 x: readingInset, width: readingWidth,
				 centerY: 21.5, alignment: .center)
	}

	private func drawDetail() {
		guard let detail = currentDetail else { return }
		let area = detailBounds
		detailIcon?.draw(in: NSRect(x: cityStart, y: area.midY - 4.5, width: 9, height: 9),
						 from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		if tickerOffset == 0 {
			drawText(detail.text, font: detailFont, color: palette.city, x: area.minX, width: area.width, centerY: area.midY)
			return
		}
		let attributes: [NSAttributedString.Key: Any] = [.font: detailFont, .foregroundColor: palette.city]
		NSGraphicsContext.saveGraphicsState()
		NSBezierPath(rect: area).addClip()
		detail.text.draw(at: NSPoint(x: area.minX - tickerOffset, y: area.midY - detailTextHeight / 2), withAttributes: attributes)
		NSGraphicsContext.restoreGraphicsState()
	}

	private func drawText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, width: CGFloat,
						  centerY: CGFloat, alignment: NSTextAlignment = .left) {
		guard width > 0 else { return }
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		paragraph.alignment = alignment
		let attributedText = NSAttributedString(string: text, attributes: [
			.font: font, .foregroundColor: color, .paragraphStyle: paragraph
		])
		let lineHeight = ceil(attributedText.size().height)
		let rect = NSRect(x: x, y: centerY - lineHeight / 2, width: width, height: lineHeight)
		attributedText.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
	}

	private static func tintedSymbol(_ name: String, color: NSColor) -> NSImage? {
		guard #available(macOS 11.0, *),
			  let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?
				.withSymbolConfiguration(.init(pointSize: 16, weight: .medium)) else { return nil }
		return NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
			let scale = min(rect.width / symbol.size.width, rect.height / symbol.size.height)
			let width = symbol.size.width * scale
			let height = symbol.size.height * scale
			let fit = NSRect(x: rect.midX - width / 2, y: rect.midY - height / 2, width: width, height: height)
			symbol.draw(in: fit)
			color.setFill()
			rect.fill(using: .sourceIn)
			return true
		}
	}
}

private struct WeatherBadgePalette {
	let background: NSColor
	let icon: NSColor
	let city: NSColor
	private let isDay: Bool

	init(style: WeatherObservation.ConditionStyle, isDay: Bool) {
		self.isDay = isDay
		let colors: (background: UInt32, icon: UInt32)
		switch style {
		case .clear:
			colors = isDay ? (0xF3EEE3, 0x86531D) : (0x222A38, 0xDDC093)
		case .cloudy:
			colors = isDay ? (0xE9EFF4, 0x435B72) : (0x242E39, 0xB2C8DD)
		case .rain:
			colors = isDay ? (0xE4EEF3, 0x315873) : (0x1F2F3C, 0xA1CBE6)
		case .snow:
			colors = isDay ? (0xE8F1F0, 0x396267) : (0x213136, 0xA6D6D8)
		case .storm:
			colors = isDay ? (0xEEEAF2, 0x624B77) : (0x30293A, 0xCEB5E0)
		case .unknown:
			colors = isDay ? (0xECEFF1, 0x4D6174) : (0x252D37, 0xB4C5D7)
		}
		background = Self.color(colors.background)
		icon = Self.color(colors.icon)
		city = Self.color(isDay ? 0x323944 : 0xE0E5EC)
	}

	func temperatureColor(_ celsius: Double?) -> NSColor {
		guard let celsius = celsius else { return Self.color(isDay ? 0x18263B : 0xFFFFFF) }
		switch celsius {
		case ..<12: return Self.color(isDay ? 0x16446D : 0xAEE4FF)
		case 33...: return Self.color(isDay ? 0x831F29 : 0xFFACB0)
		case 25...: return Self.color(isDay ? 0x713714 : 0xFFCD9E)
		default: return Self.color(isDay ? 0x18263B : 0xFFFFFF)
		}
	}

	private static func color(_ rgb: UInt32) -> NSColor {
		return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
					   blue: CGFloat(rgb & 255) / 255, alpha: 1)
	}
}

private final class WeatherSettingsWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {

	static let shared = WeatherSettingsWindowController()
	private let model = WeatherModel.shared
	private let service = WeatherService()
	private let cityField = NSTextField()
	private let choices = NSPopUpButton(frame: .zero, pullsDown: false)
	private let conditions = NSTextField(labelWithString: "")
	private let detail = NSTextField(wrappingLabelWithString: "")
	private let searchStatus = NSTextField(wrappingLabelWithString: "")
	private lazy var searchButton = NSButton(title: "Search", target: self, action: #selector(search))
	private lazy var setCityButton = NSButton(title: "Set City", target: self, action: #selector(setCity))
	private lazy var refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refresh))
	private lazy var units = NSSegmentedControl(labels: ["°C", "°F"], trackingMode: .selectOne, target: self, action: #selector(changeUnit))
	private var candidates: [WeatherPlace] = []
	private var searchID: UUID?
	private var searchTask: URLSessionDataTask?
	private var subscription: AnyCancellable?

	private convenience init() {
		let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
			styleMask: [.titled, .closable], backing: .buffered, defer: false)
		self.init(window: window)
		window.title = "Weather"
		window.isReleasedWhenClosed = false
		window.delegate = self
		window.contentView = makeContentView()
		window.initialFirstResponder = cityField
		window.center()
		subscription = model.$state.sink { [weak self] state in self?.render(state) }
	}

	func present() {
		model.refresh()
		showWindow(nil)
		NSApp.activate(ignoringOtherApps: true)
		window?.makeKeyAndOrderFront(nil)
	}

	private func makeContentView() -> NSView {
		let container = NSView()
		conditions.font = .systemFont(ofSize: 15, weight: .semibold)
		conditions.lineBreakMode = .byTruncatingTail
		conditions.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		detail.textColor = .secondaryLabelColor
		searchStatus.textColor = .secondaryLabelColor
		cityField.placeholderString = "City or postal code"
		cityField.setAccessibilityLabel("City or postal code")
		cityField.delegate = self
		searchButton.keyEquivalent = "\r"
		searchButton.setContentHuggingPriority(.required, for: .horizontal)
		setCityButton.setContentHuggingPriority(.required, for: .horizontal)
		choices.setAccessibilityLabel("Matching cities")
		choices.autoenablesItems = false
		choices.cell?.truncatesLastVisibleLine = true
		choices.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
		cityField.setContentHuggingPriority(.defaultLow, for: .horizontal)
		choices.setContentHuggingPriority(.defaultLow, for: .horizontal)
		units.setAccessibilityLabel("Temperature unit")
		clearSearchResults()

		let attribution = NSTextField(labelWithString: "Weather and city data by")
		attribution.textColor = .secondaryLabelColor
		let provider = NSButton(title: "Open-Meteo (CC BY 4.0)", target: self, action: #selector(openProvider))
		provider.bezelStyle = .inline
		let geoNames = NSButton(title: "GeoNames", target: self, action: #selector(openGeoNames))
		geoNames.bezelStyle = .inline
		let holidayProvider = NSButton(title: "Nager.Date", target: self, action: #selector(openHolidayProvider))
		holidayProvider.bezelStyle = .inline
		holidayProvider.toolTip = "Public holiday data"

		let searchRow = row([cityField, searchButton])
		let resultsRow = row([choices, setCityButton])
		let settingsRow = row([NSTextField(labelWithString: "Temperature"), units, NSView(), refreshButton])
		let stack = NSStackView(views: [conditions, detail, searchRow, resultsRow, searchStatus, settingsRow,
									  row([attribution, provider, geoNames, holidayProvider])])
		stack.orientation = .vertical
		stack.alignment = .leading
		stack.spacing = 8
		stack.translatesAutoresizingMaskIntoConstraints = false
		container.addSubview(stack)
		NSLayoutConstraint.activate([
			stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
			stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
			stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
			stack.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -16),
			searchRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
			resultsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
			settingsRow.widthAnchor.constraint(equalTo: stack.widthAnchor),
			conditions.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
			detail.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor),
			searchStatus.widthAnchor.constraint(lessThanOrEqualTo: stack.widthAnchor)
		])
		return container
	}

	private func row(_ views: [NSView]) -> NSStackView {
		let row = NSStackView(views: views)
		row.orientation = .horizontal
		row.alignment = .centerY
		row.distribution = .fill
		row.spacing = 8
		return row
	}

	private func render(_ state: WeatherModel.State) {
		units.selectedSegment = state.unit == .celsius ? 0 : 1
		refreshButton.isEnabled = state.place != nil && state.status != .loading
		guard let place = state.place else {
			conditions.stringValue = "Choose a city to see its weather."
			conditions.toolTip = nil
			detail.stringValue = "Search by name or postal code, then select a match."
			return
		}
		conditions.stringValue = place.displayName
		conditions.toolTip = place.displayName
		if let observation = state.displayObservation {
			let date = DateFormatter.localizedString(from: observation.date, dateStyle: .short, timeStyle: .short)
			let reading = "\(state.unit.format(celsius: observation.temperature2m)) · \(observation.condition.description)"
			let timestamp = state.isStale ? "Last reading \(date)" : "Updated \(date)"
			detail.stringValue = "\(reading) · \(timestamp)"
		} else {
			detail.stringValue = state.status == .loading ? "Updating weather…" : "Weather unavailable. Try Refresh."
		}
		if let holiday = state.holiday {
			detail.stringValue += "\nHoliday: \(holiday)"
		}
	}

	private func clearSearchResults() {
		candidates.removeAll()
		choices.removeAllItems()
		choices.addItem(withTitle: "Matching cities")
		choices.isEnabled = false
		setCityButton.isEnabled = false
		searchStatus.stringValue = " "
	}

	private func cancelSearch() {
		searchID = nil
		searchTask?.cancel()
		searchTask = nil
		searchButton.isEnabled = true
	}

	func controlTextDidChange(_ obj: Notification) {
		cancelSearch()
		clearSearchResults()
	}

	func windowWillClose(_ notification: Notification) {
		cancelSearch()
		cityField.stringValue = ""
		clearSearchResults()
	}

	@objc private func search() {
		let query = cityField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
		guard query.count >= 2 else {
			searchStatus.stringValue = "Enter at least two characters."
			return
		}
		cancelSearch()
		clearSearchResults()
		searchStatus.stringValue = "Searching…"
		searchButton.isEnabled = false
		let id = UUID()
		searchID = id
		searchTask = service.search(query) { [weak self] result in
			guard let self = self, self.searchID == id else { return }
			self.cancelSearch()
			switch result {
			case .failure:
				self.searchStatus.stringValue = "City search is unavailable. Try again."
			case .success(let places):
				guard places.isEmpty == false else {
					self.searchStatus.stringValue = "No cities found. Try another name or postal code."
					return
				}
				self.candidates = places
				self.choices.removeAllItems()
				// Menu items may share a display name, so keep each result at its original index.
				for place in places {
					self.choices.menu?.addItem(NSMenuItem(title: place.displayName, action: nil, keyEquivalent: ""))
				}
				self.choices.selectItem(at: 0)
				self.choices.isEnabled = true
				self.setCityButton.isEnabled = true
				self.searchStatus.stringValue = "Select a match, then choose Set City."
			}
		}
	}

	@objc private func setCity() {
		let index = choices.indexOfSelectedItem
		guard candidates.indices.contains(index) else { return }
		model.setPlace(candidates[index])
		cityField.stringValue = ""
		clearSearchResults()
	}

	@objc private func changeUnit() {
		model.setUnit(units.selectedSegment == 1 ? .fahrenheit : .celsius)
	}

	@objc private func refresh() {
		model.refresh(force: true)
	}

	@objc private func openProvider() {
		if let url = URL(string: "https://open-meteo.com/") { NSWorkspace.shared.open(url) }
	}

	@objc private func openGeoNames() {
		if let url = URL(string: "https://www.geonames.org/") { NSWorkspace.shared.open(url) }
	}

	@objc private func openHolidayProvider() {
		if let url = URL(string: "https://nagerholidays.com/en/api") { NSWorkspace.shared.open(url) }
	}
}
