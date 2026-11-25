import AppKit

internal struct AWSStatusDisplay: Codable, Equatable {
	var ec2 = true
	var rds = true
	var job = false
	var cost = false
	var costMode = AWSCostMode.projected
	var costScope = AWSCostScope.account

	var hasServices: Bool { ec2 || rds }
	var hasStatus: Bool { hasServices || job }
}

internal struct AWSStatusConfiguration: Codable, Equatable {
	static let didChange = Notification.Name("pock.aws-status.configuration-changed")
	private static let key = "awsStatusConfiguration"

	var enabled = false
	var profile = "default"
	var region = "us-east-1"
	var interval = 120
	var jobPath = ""
	var costPath: String?
	var savedDisplay: AWSStatusDisplay?
	var display: AWSStatusDisplay { savedDisplay ?? AWSStatusDisplay() }

	static func load() -> Self {
		if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(Self.self, from: data) {
			return saved
		}
		return Self()
	}

	static func showSettings() {
		let saved = load()
		let enabled = NSButton(checkboxWithTitle: "Enable AWS Status".localized, target: nil, action: nil)
		enabled.state = saved.enabled ? .on : .off
		let profile = NSTextField(string: saved.profile)
		let region = NSTextField(string: saved.region)
		let interval = NSTextField(string: String(saved.interval))
		let jobPath = NSTextField(string: saved.jobPath)
		let costPath = NSTextField(string: saved.costPath ?? "")
		jobPath.widthAnchor.constraint(greaterThanOrEqualToConstant: 280).isActive = true
		func check(_ label: String, selected: Bool) -> NSButton {
			let button = NSButton(checkboxWithTitle: label, target: nil, action: nil)
			button.state = selected ? .on : .off
			return button
		}
		let ec2 = check("EC2", selected: saved.display.ec2)
		let rds = check("RDS", selected: saved.display.rds)
		let job = check("Last job".localized, selected: saved.display.job)
		let cost = check("Cost".localized, selected: saved.display.cost)
		let visibleItems = NSStackView(views: [ec2, rds, job, cost])
		visibleItems.spacing = 12
		let mode = NSPopUpButton(frame: .zero, pullsDown: false)
		let scope = NSPopUpButton(frame: .zero, pullsDown: false)
		mode.addItems(withTitles: AWSCostMode.allCases.map(\.title))
		scope.addItems(withTitles: AWSCostScope.allCases.map(\.title))
		mode.selectItem(at: AWSCostMode.allCases.firstIndex(of: saved.display.costMode) ?? 0)
		scope.selectItem(at: AWSCostScope.allCases.firstIndex(of: saved.display.costScope) ?? 0)
		let rows: [[NSView]] = [
			[NSTextField(labelWithString: "AWS CLI profile".localized), profile],
			[NSTextField(labelWithString: "AWS region".localized), region],
			[NSTextField(labelWithString: "Status refresh (seconds)".localized), interval],
			[NSTextField(labelWithString: "Job status file".localized), jobPath],
			[NSTextField(labelWithString: "Show in Touch Bar".localized), visibleItems],
			[NSTextField(labelWithString: "Local cost snapshot".localized), costPath],
			[NSTextField(labelWithString: "Cost display".localized), mode],
			[NSTextField(labelWithString: "Cost scope".localized), scope]
		]
		let grid = NSGridView(views: rows)
		grid.column(at: 1).xPlacement = .fill
		grid.rowAlignment = .firstBaseline
		grid.rowSpacing = 8
		let form = NSStackView(views: [enabled, grid])
		form.orientation = .vertical
		form.alignment = .leading
		form.spacing = 12
		form.frame.size = form.fittingSize

		let alert = NSAlert()
		alert.messageText = "AWS Status Settings".localized
		alert.informativeText = "EC2 and RDS use your local AWS CLI profile. The cost indicator reads a local JSON snapshot or an existing cached estimate.".localized
		alert.accessoryView = form
		alert.addButton(withTitle: "Save".localized)
		alert.addButton(withTitle: "Cancel".localized)
		NSApp.activate(ignoringOtherApps: true)

		while alert.runModal() == .alertFirstButtonReturn {
			let profileName = profile.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let regionName = region.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let path = jobPath.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			let billingPath = costPath.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard !profileName.isEmpty,
				  regionName.range(of: #"^[a-z0-9]+(-[a-z0-9]+)+-[0-9]+$"#, options: .regularExpression) != nil,
				  let seconds = Int(interval.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
				  (30...900).contains(seconds),
				  (job.state == .off || (path as NSString).expandingTildeInPath.hasPrefix("/")),
				  (billingPath.isEmpty || (billingPath as NSString).expandingTildeInPath.hasPrefix("/")) else {
				alert.informativeText = "Enter a profile, an AWS region and a 30–900 second interval. Use absolute or ~/ paths for local status files.".localized
				continue
			}
			let display = AWSStatusDisplay(ec2: ec2.state == .on, rds: rds.state == .on, job: job.state == .on,
				cost: cost.state == .on, costMode: AWSCostMode.allCases[max(0, mode.indexOfSelectedItem)],
				costScope: AWSCostScope.allCases[max(0, scope.indexOfSelectedItem)])
			guard enabled.state == .off || display.hasStatus || display.cost else {
				alert.informativeText = "Choose at least one item to show in the Touch Bar.".localized
				continue
			}
			let configuration = Self(enabled: enabled.state == .on, profile: profileName, region: regionName,
									 interval: seconds, jobPath: path, costPath: billingPath.isEmpty ? nil : billingPath, savedDisplay: display)
			if let data = try? JSONEncoder().encode(configuration) {
				UserDefaults.standard.set(data, forKey: key)
				NotificationCenter.default.post(name: didChange, object: nil)
			}
			return
		}
	}
}

private struct AWSStatusResource: Decodable {
	let id: String
	let name: String?
	let state: String

	var description: String { "\(name ?? id)  ·  \(state)" }
}

private enum AWSStatusService {
	case ec2, rds

	var arguments: [String] {
		switch self {
		case .ec2:
			return ["ec2", "describe-instances", "--filters", "Name=instance-state-name,Values=pending,running,stopping,stopped",
					"--query", "Reservations[].Instances[].{id:InstanceId,name:Tags[?Key==`Name`].Value|[0],state:State.Name}"]
		case .rds:
			return ["rds", "describe-db-instances", "--query", "DBInstances[].{id:DBInstanceIdentifier,state:DBInstanceStatus}"]
		}
	}
}

private struct AWSStatusReading {
	let instances: [AWSStatusResource]?
	let lastSuccess: Date?
	let error: String?

	static func resources(_ instances: [AWSStatusResource]) -> Self {
		Self(instances: instances, lastSuccess: Date(), error: nil)
	}

	static func unavailable(_ reason: String) -> Self {
		Self(instances: nil, lastSuccess: nil, error: reason)
	}

	func retaining(_ previous: Self?) -> Self {
		guard let error = error, let previous = previous else { return self }
		return Self(instances: previous.instances, lastSuccess: previous.lastSuccess, error: error)
	}

	func expired() -> Self {
		Self(instances: instances, lastSuccess: lastSuccess, error: error ?? "AWS reading is overdue for a refresh.".localized)
	}

	var badge: (symbol: String, color: NSColor) {
		guard let instances = instances else { return ("?", AWSStatusPalette.unavailable) }
		let state: (String, NSColor)
		if instances.contains(where: { ["running", "available"].contains($0.state) }) {
			state = ("●", AWSStatusPalette.active)
		} else if instances.contains(where: { $0.state != "stopped" }) {
			state = ("◐", AWSStatusPalette.changing)
		} else {
			state = ("○", AWSStatusPalette.inactive)
		}
		return (state.0, error == nil ? state.1 : AWSStatusPalette.changing)
	}

	func summary(formattedBy formatter: DateFormatter) -> String {
		guard let instances = instances else { return error ?? "AWS unavailable".localized }
		let resources = instances.isEmpty ? "No instances".localized
			: instances.sorted { ($0.name ?? $0.id) < ($1.name ?? $1.id) }.map(\.description).joined(separator: "\n")
		guard let reason = error, let date = lastSuccess else { return resources }
		return "\("Stale — last successful check".localized): \(formatter.string(from: date))\n\(reason)\n\(resources)"
	}
}

private struct AWSStatusSnapshot {
	let configuration: AWSStatusConfiguration
	let checkedAt: Date
	let ec2: AWSStatusReading
	let rds: AWSStatusReading

	var refreshInterval: TimeInterval {
		TimeInterval(configuration.interval)
	}

	func retaining(_ previous: Self?) -> Self {
		guard let previous = previous, previous.configuration == configuration else { return self }
		return Self(configuration: configuration, checkedAt: checkedAt, ec2: ec2.retaining(previous.ec2),
			rds: rds.retaining(previous.rds))
	}

	func displayed(at date: Date) -> Self {
		guard date.timeIntervalSince(checkedAt) > TimeInterval(configuration.interval * 2) else { return self }
		return Self(configuration: configuration, checkedAt: checkedAt, ec2: ec2.expired(), rds: rds.expired())
	}

	static func read(_ configuration: AWSStatusConfiguration) -> Self {
		let ec2 = configuration.display.ec2 ? readService(.ec2, configuration: configuration) : .unavailable("")
		let rds = configuration.display.rds ? readService(.rds, configuration: configuration) : .unavailable("")
		return Self(configuration: configuration, checkedAt: Date(), ec2: ec2, rds: rds)
	}

	private static func readService(_ service: AWSStatusService, configuration: AWSStatusConfiguration) -> AWSStatusReading {
		do {
			let data = try AWSCLI.run(profile: configuration.profile, region: configuration.region, arguments: service.arguments)
			let resources = try JSONDecoder().decode([AWSStatusResource].self, from: data)
			return .resources(resources)
		} catch let error as AWSCLI.Failure {
			return .unavailable(error.message)
		} catch {
			return .unavailable("AWS returned an unreadable response".localized)
		}
	}
}

internal enum AWSCLI {
	struct Failure: Error {
		let message: String
	}

	private final class ErrorOutput: @unchecked Sendable {
		var prefix = Data()

		func drain(_ handle: FileHandle) {
			while true {
				let chunk = handle.availableData
				guard !chunk.isEmpty else { return }
				let remaining = max(0, 16_384 - prefix.count)
				prefix.append(contentsOf: chunk.prefix(remaining))
			}
		}
	}

	static func run(profile: String, region: String, arguments: [String]) throws -> Data {
		let candidates = ["/usr/local/bin/aws", "/opt/homebrew/bin/aws", "/opt/local/bin/aws",
						  FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/aws").path]
		let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
			.filter { $0.hasPrefix("/") }.map { "\($0)/aws" }
		guard let executable = (candidates + pathCandidates).first(where: FileManager.default.isExecutableFile(atPath:)) else {
			throw Failure(message: "AWS CLI was not found. Install AWS CLI v2.".localized)
		}
		let process = Process()
		let output = Pipe()
		let errorPipe = Pipe()
		process.executableURL = URL(fileURLWithPath: executable)
		process.arguments = ["--profile", profile, "--region", region, "--no-cli-pager",
							 "--no-cli-auto-prompt", "--cli-connect-timeout", "8", "--cli-read-timeout", "16",
							 "--output", "json"] + arguments
		var environment = ProcessInfo.processInfo.environment
		environment["AWS_MAX_ATTEMPTS"] = "1"
		process.environment = environment
		process.standardOutput = output
		process.standardError = errorPipe
		do {
			try process.run()
		} catch {
			throw Failure(message: "Could not start the AWS CLI.".localized)
		}
		let errors = ErrorOutput()
		let drains = DispatchGroup()
		DispatchQueue.global(qos: .utility).async(group: drains) { errors.drain(errorPipe.fileHandleForReading) }
		let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
		// Credential resolution can take longer than the CLI's network timeouts.
		DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 45, execute: timeout)
		defer { timeout.cancel() }
		let data = output.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		drains.wait()
		guard process.terminationStatus == 0 else {
			if process.terminationReason == .uncaughtSignal, process.terminationStatus == SIGTERM {
				throw Failure(message: "AWS check timed out.".localized)
			}
			throw Failure(message: failureMessage(String(decoding: errors.prefix, as: UTF8.self)))
		}
		return data
	}

	static func failureMessage(_ output: String) -> String {
		let error = output.lowercased()
		if error.contains("could not be found"), error.contains("profile") {
			return "AWS CLI could not find the selected profile.".localized
		}
		if ["expiredtoken", "expired token", "token has expired", "sso session", "error loading sso token"]
			.contains(where: error.contains) {
			return "AWS credentials or SSO session expired. Renew the login for this profile.".localized
		}
		if ["unable to locate credentials", "invalidclienttokenid", "unrecognizedclientexception"]
			.contains(where: error.contains) {
			return "AWS CLI could not authenticate with the selected profile.".localized
		}
		if ["accessdenied", "unauthorizedoperation", "not authorized"]
			.contains(where: error.contains) {
			return "AWS denied access. Check the profile's EC2 or RDS read permissions.".localized
		}
		if ["could not connect to the endpoint", "ssl validation failed", "timed out", "proxy"]
			.contains(where: error.contains) {
			return "AWS endpoint unreachable. Check the region and network connection.".localized
		}
		if error.contains("unknown options") {
			return "The installed AWS CLI does not support the options used by Pock. Update AWS CLI v2.".localized
		}
		return "AWS CLI failed. Check the profile, region and connection.".localized
	}

}

private struct AWSJobRun: Decodable, Equatable {
	let status: String
	let finishedAt: String?
	let lastCompletedAt: String?

	var completion: Date? {
		guard let timestamp = finishedAt ?? lastCompletedAt else { return nil }
		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: timestamp) { return date }
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: timestamp)
	}

	var badge: (symbol: String, fallback: String, color: NSColor, description: String) {
		switch status {
		case "ok": return ("checkmark.circle", "✓", AWSStatusPalette.active, "Successful".localized)
		case "error": return ("exclamationmark.circle", "!", AWSStatusPalette.unavailable, "Failed".localized)
		case "running": return ("clock", "↻", AWSStatusPalette.changing, "Running".localized)
		default: return ("questionmark.circle", "?", AWSStatusPalette.inactive, "Unknown".localized)
		}
	}

	static func read(_ path: String) -> Self? {
		guard let data = try? AWSStatusFile.data(at: path) else { return nil }
		let decoder = JSONDecoder()
		decoder.keyDecodingStrategy = .convertFromSnakeCase
		return try? decoder.decode(Self.self, from: data)
	}
}

private enum AWSStatusPalette {
	static let inactive = NSColor(srgbRed: 0.63, green: 0.68, blue: 0.75, alpha: 1)
	static let active = NSColor(srgbRed: 0.41, green: 0.86, blue: 0.58, alpha: 1)
	static let changing = NSColor(srgbRed: 1.00, green: 0.73, blue: 0.38, alpha: 1)
	static let unavailable = NSColor(srgbRed: 1.00, green: 0.51, blue: 0.49, alpha: 1)
	static let cost = NSColor(srgbRed: 0.61, green: 0.85, blue: 1, alpha: 1)
	static let divider = NSColor(white: 1, alpha: 0.12)
}

internal final class AWSStatusView: NSButton {
	static let itemIdentifier = NSTouchBarItem.Identifier("io.github.pock.aws-status")
	private static let serviceWidth: CGFloat = 20
	private static let costWidth: CGFloat = 58
	private static let timeFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)
	private static let costFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
	private static let iconFont = NSFont.systemFont(ofSize: 8, weight: .semibold)
	private static let cpuIcon = symbol("cpu", color: AWSStatusPalette.inactive)
	private static let databaseIcon = symbol("cylinder", color: AWSStatusPalette.inactive)
	private let readQueue = DispatchQueue(label: "io.github.pock.aws-status", qos: .utility)
	private let jobQueue = DispatchQueue(label: "io.github.pock.aws-status.job", qos: .utility)
	private var configuration = AWSStatusConfiguration.load()
	private var snapshot: AWSStatusSnapshot?
	private var jobRun: AWSJobRun? {
		didSet {
			jobTimestamp = jobRun?.completion.map(Self.compactTime)
			guard oldValue?.status != jobRun?.status else { return }
			jobIcon = jobRun.flatMap { Self.symbol($0.badge.symbol, color: $0.badge.color) }
		}
	}
	private var jobIcon: NSImage?
	private var jobTimestamp: String?
	private var timer: Timer?
	private var active = false
	private var loading = false
	private var showAfterRefresh = false
	private var showingDetails = false

	private var statusWidth: CGFloat {
		let display = configuration.display
		if display.ec2 && display.rds { return 50 }
		if display.job { return 43 }
		return display.hasServices ? 35 : 0
	}
	private var costWidth: CGFloat { configuration.display.cost ? Self.costWidth : 0 }
	private var costEstimate: AWSCostEstimate?
	private var costFileUnavailable = false
	override var intrinsicContentSize: NSSize { NSSize(width: statusWidth + costWidth, height: 30) }
	override var isFlipped: Bool { true }

	init() {
		super.init(frame: .zero)
		frame.size = intrinsicContentSize
		target = self
		action = #selector(showDetails)
		isBordered = false
		setContentHuggingPriority(.required, for: .horizontal)
		let tap = NSClickGestureRecognizer(target: self, action: #selector(acceptDirectTouch(_:)))
		tap.allowedTouchTypes = .direct
		addGestureRecognizer(tap)
		render()
	}

	required init?(coder: NSCoder) { return nil }

	deinit {
		timer?.invalidate()
	}

	@objc private func acceptDirectTouch(_ gesture: NSClickGestureRecognizer) {
		guard gesture.state == .ended else { return }
		performClick(nil)
	}

	override func highlight(_ flag: Bool) {
		super.highlight(flag)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		let pressed = cell?.isHighlighted == true
		NSColor(srgbRed: pressed ? 0.24 : 0.14, green: pressed ? 0.28 : 0.17,
			blue: pressed ? 0.34 : 0.21, alpha: 1).setFill()
		NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7).fill()

		let display = configuration.display
		let left = bounds.midX - intrinsicContentSize.width / 2
		if display.hasStatus { drawStatus(left: left) }
		if display.cost {
			if display.hasStatus { drawDivider(NSRect(x: left + statusWidth, y: 5, width: 0.5, height: bounds.height - 10)) }
			drawCost(left: left + statusWidth)
		}
	}

	private func drawStatus(left: CGFloat) {
		let display = configuration.display
		let result = currentSnapshot
		let center = left + statusWidth / 2
		let split = display.hasServices && display.job
		let serviceY = bounds.midY - (split ? 6 : 0)
		let offset = display.ec2 && display.rds ? Self.serviceWidth / 2 : 0
		if display.ec2 {
			drawService(icon: Self.cpuIcon, fallback: "▣", reading: result?.ec2,
				centerX: center - offset, centerY: serviceY)
		}
		if display.rds {
			drawService(icon: Self.databaseIcon, fallback: "▤", reading: result?.rds,
				centerX: center + offset, centerY: serviceY)
		}
		if display.job { drawJob(centerX: center, centerY: bounds.midY + (split ? 6 : 0)) }
	}

	private func drawDivider(_ rect: NSRect) {
		AWSStatusPalette.divider.setFill()
		rect.fill()
	}

	private func drawService(icon: NSImage?, fallback: String, reading: AWSStatusReading?, centerX: CGFloat, centerY: CGFloat) {
		drawIcon(icon, fallback: fallback, color: AWSStatusPalette.inactive, x: centerX - 8, centerY: centerY)
		let badge = reading?.badge ?? ("·", AWSStatusPalette.inactive)
		let marker = Self.text(badge.0, font: Self.iconFont, color: badge.1)
		let markerX = centerX + 5
		marker.draw(at: NSPoint(x: markerX - marker.size().width / 2, y: centerY - marker.size().height / 2))
		if reading?.error != nil, reading?.lastSuccess != nil {
			badge.1.setFill()
			NSRect(x: markerX - 2, y: centerY + 4, width: 4, height: 0.75).fill()
		}
	}

	private func drawJob(centerX: CGFloat, centerY: CGFloat) {
		let badge = jobRun?.badge
		let timestamp = jobTimestamp ?? "Job —".localized
		let label = Self.text(timestamp, font: Self.timeFont, color: AWSStatusPalette.inactive)
		let size = label.size()
		let left = centerX - (size.width + 12) / 2
		drawIcon(jobIcon, fallback: badge?.fallback ?? "?", color: badge?.color ?? AWSStatusPalette.inactive,
			x: left, centerY: centerY)
		label.draw(at: NSPoint(x: left + 12, y: centerY - size.height / 2))
	}

	private func drawCost(left: CGFloat) {
		let color = costEstimate?.isStale == true ? AWSStatusPalette.changing : AWSStatusPalette.cost
		let amount = costAmount(compact: true) ?? "—"
		let maxWidth = costWidth - 10
		let width = Self.text(amount, font: Self.costFont, color: color).size().width
		let pointSize = max(8, Self.costFont.pointSize * min(1, maxWidth / max(1, width)))
		let font = NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .semibold)
		let paragraph = NSMutableParagraphStyle()
		paragraph.alignment = .center
		paragraph.lineBreakMode = .byTruncatingTail
		let label = NSAttributedString(string: amount, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: paragraph])
		label.draw(in: NSRect(x: left + 5, y: bounds.midY - label.size().height / 2, width: maxWidth, height: label.size().height))
	}

	private func drawIcon(_ icon: NSImage?, fallback: String, color: NSColor, x: CGFloat, centerY: CGFloat) {
		if let icon = icon {
			icon.draw(in: NSRect(x: x, y: centerY - 4.5, width: 9, height: 9), from: .zero,
				operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
		} else {
			let glyph = Self.text(fallback, font: Self.iconFont, color: color)
			glyph.draw(at: NSPoint(x: x, y: centerY - glyph.size().height / 2))
		}
	}

	private static func symbol(_ name: String, color: NSColor) -> NSImage? {
		guard #available(macOS 12, *) else { return nil }
		let configuration = NSImage.SymbolConfiguration(pointSize: 9, weight: .medium)
			.applying(.init(paletteColors: [color]))
		let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
		symbol?.isTemplate = false
		return symbol
	}

	private static func text(_ string: String, font: NSFont, color: NSColor) -> NSAttributedString {
		return NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
	}

	func startRefreshing() {
		guard !active else { return }
		let settings = AWSStatusConfiguration.load()
		if settings.jobPath != configuration.jobPath { jobRun = nil }
		if settings.costPath != configuration.costPath || settings.profile != configuration.profile {
			costEstimate = nil
			costFileUnavailable = false
		}
		configuration = settings
		invalidateIntrinsicContentSize()
		guard configuration.enabled else { return }
		active = true
		refresh()
	}

	func stopRefreshing() {
		active = false
		showAfterRefresh = false
		timer?.invalidate()
		timer = nil
	}

	private var currentSnapshot: AWSStatusSnapshot? {
		guard let snapshot = snapshot, snapshot.configuration == configuration else { return nil }
		return snapshot.displayed(at: Date())
	}

	private func refresh(force: Bool = false) {
		guard active else { return }
		timer?.invalidate()
		timer = nil
		render()
		if configuration.display.job || configuration.display.cost { refreshLocalIndicators() }
		guard configuration.display.hasServices else {
			scheduleRefresh(after: TimeInterval(configuration.interval))
			return
		}
		guard !loading else { return }
		if !force, let result = currentSnapshot {
			let remaining = result.refreshInterval + result.checkedAt.timeIntervalSinceNow
			if remaining > 0 {
				scheduleRefresh(after: remaining)
				return
			}
		}
		loading = true
		let configuration = configuration
		readQueue.async { [weak self] in
			guard self != nil else { return }
			let result = AWSStatusSnapshot.read(configuration)
			DispatchQueue.main.async { [weak self] in self?.didRefresh(result) }
		}
	}

	private func refreshLocalIndicators() {
		let settings = configuration
		jobQueue.async { [weak self] in
			let run = settings.display.job ? AWSJobRun.read(settings.jobPath) : nil
			let cost = Result { settings.display.cost ? try AWSCostEstimate.load(profile: settings.profile, path: settings.costPath) : nil }
			DispatchQueue.main.async { [weak self] in
				guard let self = self, self.active, self.configuration == settings else { return }
				self.jobRun = run
				switch cost {
				case .success(let estimate):
					self.costEstimate = estimate
					self.costFileUnavailable = false
				case .failure:
					self.costEstimate = nil
					self.costFileUnavailable = true
				}
				self.render()
				if !settings.display.hasServices { self.showDetailsAfterRefresh() }
			}
		}
	}

	private func didRefresh(_ result: AWSStatusSnapshot) {
		loading = false
		if result.configuration == configuration { snapshot = result.retaining(snapshot) }
		guard active else { return }
		guard result.configuration == configuration else {
			refresh()
			return
		}
		render()
		scheduleRefresh(after: result.refreshInterval)
		showDetailsAfterRefresh()
	}

	private func showDetailsAfterRefresh() {
		guard showAfterRefresh else { return }
		showAfterRefresh = false
		showDetails()
	}

	private func scheduleRefresh(after interval: TimeInterval) {
		let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in self?.refresh() }
		timer.tolerance = interval * 0.1
		self.timer = timer
		RunLoop.main.add(timer, forMode: .common)
	}

	private func render() {
		let result = currentSnapshot
		needsDisplay = true
		toolTip = "AWS Status".localized
		setAccessibilityLabel("AWS Status".localized)
		setAccessibilityValue(summary(snapshot: result, run: jobRun))
	}

	private func costAmount(compact: Bool = false) -> String? {
		guard let estimate = costEstimate else { return nil }
		let formatter = NumberFormatter()
		formatter.numberStyle = .currency
		formatter.currencyCode = estimate.unit
		if compact, estimate.unit == "USD" { formatter.currencySymbol = "$" }
		let display = configuration.display
		let amount = NSDecimalNumber(decimal: estimate.amount(display.costMode, scope: display.costScope))
		return formatter.string(from: amount).map { display.costMode == .projected ? "≈\($0)" : $0 }
	}

	private static func compactTime(_ date: Date) -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "HH:mm"
		return formatter.string(from: date)
	}

	private func summary(snapshot: AWSStatusSnapshot?, run: AWSJobRun?) -> String {
		let unavailable = "Waiting for a fresh AWS reading".localized
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .medium
		dateFormatter.timeStyle = .short
		let jobDate = run?.completion.map { dateFormatter.string(from: $0) } ?? "No completed run recorded".localized
		let jobStatus = run?.badge.description ?? "Status file unavailable".localized
		let lastChecked = snapshot.map { dateFormatter.string(from: $0.checkedAt) } ?? "—"
		let ec2 = snapshot?.ec2.summary(formattedBy: dateFormatter) ?? unavailable
		let rds = snapshot?.rds.summary(formattedBy: dateFormatter) ?? unavailable
		let display = configuration.display
		var sections = ["\(configuration.profile) / \(configuration.region)"]
		if display.cost { sections.append(costSummary()) }
		if display.ec2 { sections.append("EC2\n\(ec2)") }
		if display.rds { sections.append("RDS\n\(rds)") }
		if display.hasServices { sections.append("\("Last AWS check".localized): \(lastChecked)") }
		if display.job { sections.append("\("Last job completion".localized): \(jobDate)\n\("Job status".localized): \(jobStatus)") }
		return sections.joined(separator: "\n\n")
	}

	private func costSummary() -> String {
		let display = configuration.display
		var lines = ["\(display.costMode.title) · \(display.costScope.title)\n\(costAmount() ?? "—")"]
		if let estimate = costEstimate {
			let dates = DateFormatter()
			dates.dateStyle = .medium
			dates.timeZone = AWSCostEstimate.calendar.timeZone
			let lastDay = estimate.end.addingTimeInterval(-1)
			lines.append("\("Billing period (UTC)".localized): \(dates.string(from: estimate.start)) – \(dates.string(from: lastDay))")
			let update = DateFormatter.localizedString(from: estimate.checkedAt, dateStyle: .medium, timeStyle: .short)
			lines.append("\((estimate.isStale ? "Last successful cost update" : "Cost updated").localized): \(update)")
			if estimate.isStale { lines.append("Showing a previous estimate.".localized) }
			if display.costMode == .projected { lines.append("Projected at the average daily spend so far.".localized) }
		} else if costFileUnavailable {
			lines.append("The local cost snapshot is missing or invalid.".localized)
		} else {
			lines.append("Choose a local cost snapshot to show an estimate.".localized)
		}
		return lines.joined(separator: "\n")
	}

	@objc private func showDetails() {
		guard !showingDetails else { return }
		showingDetails = true
		defer { showingDetails = false }
		let alert = NSAlert()
		alert.messageText = "AWS Status".localized
		// A scrollable view keeps larger accounts from making the alert taller than the screen.
		let text = NSTextView(frame: NSRect(x: 0, y: 0, width: 390, height: 260))
		text.string = summary(snapshot: currentSnapshot, run: jobRun)
		text.font = .systemFont(ofSize: NSFont.systemFontSize)
		text.isEditable = false
		text.isVerticallyResizable = true
		text.autoresizingMask = [.width]
		let scroll = NSScrollView(frame: text.frame)
		scroll.hasVerticalScroller = true
		scroll.documentView = text
		alert.accessoryView = scroll
		alert.addButton(withTitle: "Close".localized)
		alert.addButton(withTitle: "Refresh status".localized)
		alert.addButton(withTitle: "Configure…".localized)
		NSApp.activate(ignoringOtherApps: true)
		switch alert.runModal() {
		case .alertSecondButtonReturn:
			showAfterRefresh = true
			refresh(force: true)
		case .alertThirdButtonReturn: AWSStatusConfiguration.showSettings()
		default: break
		}
	}
}
