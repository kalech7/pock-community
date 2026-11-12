import AppKit
import Darwin

internal final class AgentActivityView: NSStackView {
	private enum Presentation: Equatable {
		case loading, unavailable, empty
		case page([AgentActivity], hasPrevious: Bool, hasNext: Bool)
	}

	private let pageSize = 3
	private let readQueue = DispatchQueue(label: "io.github.pock.agent-activity", qos: .utility)
	private var refreshTimer: Timer?
	private var refreshGeneration = 0
	private var isReading = false
	private var sessions: [AgentActivity]?
	private var page = 0
	private var presentation: Presentation?

	init() {
		super.init(frame: .zero)
		orientation = .horizontal
		alignment = .centerY
		spacing = 5
		render(.loading)
	}

	required init?(coder: NSCoder) {
		return nil
	}

	deinit {
		refreshTimer?.invalidate()
	}

	internal func startRefreshing() {
		guard refreshTimer == nil else { return }
		Self.prepareCodexHooks()
		let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
			self?.refresh()
		}
		timer.tolerance = 0.4
		refreshTimer = timer
		RunLoop.main.add(timer, forMode: .common)
		refresh()
	}

	private static let codexHookSetup: Void = {
		#if !DEBUG
		let bundle = Bundle.main
		guard !bundle.bundleURL.path.contains("/AppTranslocation/"),
			  let hook = bundle.url(forResource: "pock-agent-activity", withExtension: "rb") else { return }
		DispatchQueue.global(qos: .utility).async {
			let setup = Process()
			setup.executableURL = URL(fileURLWithPath: "/usr/bin/env")
			setup.arguments = ["-u", "RUBYOPT", "-u", "RUBYLIB", "/usr/bin/ruby", "--disable=gems", hook.path, "codex", "--install"]
			do {
				try setup.run()
			} catch {
				Roger.error("Could not start Codex hook setup")
			}
		}
		#endif
	}()

	private static func prepareCodexHooks() {
		_ = codexHookSetup
	}

	internal func stopRefreshing() {
		guard let refreshTimer = refreshTimer else { return }
		refreshTimer.invalidate()
		self.refreshTimer = nil
		refreshGeneration += 1
		isReading = false
		sessions = nil
		page = 0
		render(.loading)
	}

	private func refresh() {
		guard refreshTimer != nil, !isReading else { return }
		isReading = true
		let generation = refreshGeneration
		readQueue.async { [weak self] in
			guard self != nil else { return }
			let result = Result { try AgentActivityStore.runningSessions() }
			DispatchQueue.main.async { [weak self] in
				guard let self = self, self.refreshGeneration == generation else { return }
				self.isReading = false
				switch result {
				case .success(let sessions):
					guard self.sessions != sessions else { return }
					self.sessions = sessions
					self.page = min(self.page, max(0, (sessions.count - 1) / self.pageSize))
					self.renderPage(sessions)
				case .failure:
					self.sessions = nil
					self.page = 0
					self.render(.unavailable)
				}
			}
		}
	}

	private func renderPage(_ sessions: [AgentActivity]) {
		guard !sessions.isEmpty else {
			render(.empty)
			return
		}
		let first = page * pageSize
		let end = min(first + pageSize, sessions.count)
		render(.page(Array(sessions[first..<end]), hasPrevious: first > 0, hasNext: end < sessions.count))
	}

	private func render(_ newPresentation: Presentation) {
		guard presentation != newPresentation else { return }
		presentation = newPresentation
		for view in arrangedSubviews {
			removeArrangedSubview(view)
			view.removeFromSuperview()
		}
		switch newPresentation {
		case .loading: showStatus("Checking sessions…")
		case .unavailable: showStatus("Activity unavailable")
		case .empty: showStatus("No active sessions")
		case let .page(visibleSessions, hasPrevious, hasNext):
			let isPaged = hasPrevious || hasNext
			if isPaged {
				addPageButton(title: "‹", label: "Previous sessions", offset: -1, enabled: hasPrevious)
			}
			for session in visibleSessions {
				addArrangedSubview(AgentSessionButton(session: session, target: self, action: #selector(openSession(_:))))
			}
			if isPaged {
				for _ in visibleSessions.count..<pageSize {
					addView(NSView(), width: AgentSessionButton.width)
				}
				addPageButton(title: "›", label: "Next sessions", offset: 1, enabled: hasNext)
			}
		}
	}

	private func addPageButton(title: String, label: String, offset: Int, enabled: Bool) {
		let button = NSButton(title: title, target: self, action: #selector(changePage(_:)))
		button.tag = offset
		button.font = .systemFont(ofSize: 18, weight: .medium)
		button.toolTip = label
		button.setAccessibilityLabel(label)
		button.isEnabled = enabled
		addView(button, width: 28)
	}

	private func addView(_ view: NSView, width: CGFloat) {
		addArrangedSubview(view)
		view.widthAnchor.constraint(equalToConstant: width).isActive = true
	}

	private func showStatus(_ title: String) {
		let label = NSTextField(labelWithString: title)
		label.font = .systemFont(ofSize: 11, weight: .medium)
		label.textColor = NSColor(white: 0.76, alpha: 1)
		label.alignment = .center
		addView(label, width: 132)
	}

	@objc private func changePage(_ sender: NSButton) {
		let nextPage = page + sender.tag
		guard arrangedSubviews.contains(where: { $0 === sender }),
			  let sessions = sessions, nextPage >= 0, nextPage * pageSize < sessions.count else { return }
		page = nextPage
		renderPage(sessions)
	}

	@objc private func openSession(_ sender: AgentSessionButton) {
		guard arrangedSubviews.contains(where: { $0 === sender }) else { return }
		let session = sender.session
		sender.isEnabled = false
		readQueue.async { [weak self, weak sender] in
			guard self != nil, sender != nil else { return }
			let isRunning = AgentActivityStore.isRunning(session)
			DispatchQueue.main.async { [weak self, weak sender] in
				guard let self = self, let sender = sender,
					  self.arrangedSubviews.contains(where: { $0 === sender }) else { return }
				sender.isEnabled = true
				guard isRunning else {
					self.refresh()
					return
				}
				self.open(session, from: sender)
			}
		}
	}

	private func open(_ session: AgentActivity, from sender: AgentSessionButton) {
		let workspace = NSWorkspace.shared
		if let url = session.url, workspace.open(url) {
			return
		}
		if let bundleIdentifier = session.bundleIdentifier,
		   let application = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier),
		   workspace.open(application) {
			return
		}
		sender.showOpenFailure()
	}
}

private final class AgentSessionButton: NSButton {
	static let width: CGFloat = 118
	private static let surface = NSColor(white: 0.17, alpha: 1)
	private static let pressedSurface = NSColor(white: 0.26, alpha: 1)
	private static let symbolColor = NSColor(white: 0.72, alpha: 1)
	private static let runningColor = NSColor(srgbRed: 0.39, green: 0.78, blue: 0.46, alpha: 1)
	private static let titleAttributes: [NSAttributedString.Key: Any] = {
		let paragraph = NSMutableParagraphStyle()
		paragraph.lineBreakMode = .byTruncatingTail
		return [.font: NSFont.systemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor(white: 0.96, alpha: 1), .paragraphStyle: paragraph]
	}()
	// Product marks from ChatGPT's Codex resources, Anthropic's press kit and Gemini's site.
	private static let codexIcon = NSImage(named: "agent-codex")
	private static let claudeIcon = NSImage(named: "agent-claude")
	private static let geminiIcon = NSImage(named: "agent-gemini")

	let session: AgentActivity
	private let providerIcon: NSImage?
	private var feedback: DispatchWorkItem?
	private var cannotOpen = false
	private var hasDestination: Bool { return session.url != nil || session.bundleIdentifier != nil }

	init(session: AgentActivity, target: AnyObject, action: Selector) {
		self.session = session
		switch session.provider.lowercased() {
		case "codex": providerIcon = Self.codexIcon
		case "claude", "claude code": providerIcon = Self.claudeIcon
		case "gemini", "gemini cli": providerIcon = Self.geminiIcon
		default: providerIcon = nil
		}
		super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 30))
		title = ""
		isBordered = false
		setButtonType(.momentaryChange)
		isEnabled = hasDestination
		if hasDestination {
			self.target = target
			self.action = action
		} else {
			setAccessibilityRole(.staticText)
		}
		toolTip = "\(session.provider) · \(session.title)"
		setAccessibilityLabel("\(session.title), \(session.provider), running")
	}

	required init?(coder: NSCoder) { return nil }

	override var isFlipped: Bool { return true }
	override var intrinsicContentSize: NSSize { return NSSize(width: Self.width, height: 30) }

	override func highlight(_ flag: Bool) {
		super.highlight(flag)
		needsDisplay = true
	}

	override func draw(_ dirtyRect: NSRect) {
		let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 7, yRadius: 7)
		(cell?.isHighlighted == true ? Self.pressedSurface : Self.surface).setFill()
		shape.fill()
		drawProviderIcon()
		Self.runningColor.setFill()
		NSBezierPath(ovalIn: NSRect(x: 22, y: bounds.midY + 6, width: 3, height: 3)).fill()

		let textStart: CGFloat = 27
		let textWidth = max(0, bounds.width - textStart - 4)
		let textRect = NSRect(x: textStart, y: bounds.midY - 7, width: textWidth, height: 14)
		(cannotOpen ? "Can’t open" : session.title).draw(with: textRect,
			options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine], attributes: Self.titleAttributes)
	}

	private func drawProviderIcon() {
		if let providerIcon = providerIcon {
			providerIcon.draw(in: NSRect(x: 6, y: bounds.midY - 9, width: 18, height: 18),
							  from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
			return
		}
		let prompt = NSBezierPath(roundedRect: NSRect(x: 8, y: bounds.midY - 5.5, width: 14, height: 11),
								  xRadius: 3, yRadius: 3)
		prompt.move(to: NSPoint(x: 11, y: bounds.midY - 2))
		prompt.line(to: NSPoint(x: 13, y: bounds.midY))
		prompt.line(to: NSPoint(x: 11, y: bounds.midY + 2))
		prompt.move(to: NSPoint(x: 15, y: bounds.midY + 2))
		prompt.line(to: NSPoint(x: 18, y: bounds.midY + 2))
		prompt.lineCapStyle = .round
		prompt.lineJoinStyle = .round
		prompt.lineWidth = 1.2
		Self.symbolColor.setStroke()
		prompt.stroke()
	}

	func showOpenFailure() {
		feedback?.cancel()
		cannotOpen = true
		needsDisplay = true
		let work = DispatchWorkItem { [weak self] in
			self?.cannotOpen = false
			self?.needsDisplay = true
		}
		feedback = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
	}
}

private struct AgentActivity: Equatable {
	let id: String
	let provider: String
	let title: String
	let url: URL?
	let bundleIdentifier: String?
	let recordURL: URL
}

private enum AgentActivityStore {
	private struct Record: Decodable {
		let provider: String
		let id: String
		let title: String
		let pid: Int32
		let expiresAt: TimeInterval
		let url: String?
		let bundleIdentifier: String?
	}

	private static let directory = kWidgetsPathURL.deletingLastPathComponent()
		.appendingPathComponent("AgentActivity", isDirectory: true)

	static func runningSessions(in directory: URL = directory) throws -> [AgentActivity] {
		guard try canReadRecords(in: directory) else { return [] }
		let files: [URL]
		do {
			files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)
		} catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
			return []
		}
		let now = Date().timeIntervalSince1970
		let decoder = JSONDecoder()
		var sessions: [String: (session: AgentActivity, expiresAt: TimeInterval)] = [:]
		var runningProcesses: [Int32: Bool] = [:]
		for file in files where file.pathExtension == "json" {
			guard let record = readCurrentRecord(file, using: decoder, at: now) else { continue }
			if runningProcesses[record.pid] == nil {
				runningProcesses[record.pid] = kill(record.pid, 0) == 0
			}
			guard runningProcesses[record.pid] == true, let session = activity(from: record, at: file) else { continue }
			let key = "\(session.provider)\n\(session.id)"
			guard (sessions[key]?.expiresAt ?? 0) < record.expiresAt else { continue }
			sessions[key] = (session, record.expiresAt)
		}
		return sessions.values.map(\.session).sorted { left, right in
			if left.provider != right.provider { return left.provider < right.provider }
			if left.title != right.title { return left.title < right.title }
			return left.id < right.id
		}
	}

	static func isRunning(_ session: AgentActivity, in directory: URL = directory) -> Bool {
		let file = session.recordURL
		guard file.deletingLastPathComponent().standardizedFileURL.path == directory.standardizedFileURL.path,
			  (try? canReadRecords(in: directory)) == true,
			  let record = readCurrentRecord(file, using: JSONDecoder(), at: Date().timeIntervalSince1970),
			  kill(record.pid, 0) == 0 else { return false }
		return activity(from: record, at: file) == session
	}

	private static func canReadRecords(in directory: URL) throws -> Bool {
		var info = stat()
		guard lstat(directory.path, &info) == 0 else {
			if errno == ENOENT { return false }
			throw CocoaError(.fileReadNoPermission)
		}
		guard info.st_mode & S_IFMT == S_IFDIR, info.st_uid == getuid(), info.st_mode & 0o077 == 0 else {
			throw CocoaError(.fileReadNoPermission)
		}
		return true
	}

	private static func readCurrentRecord(_ url: URL, using decoder: JSONDecoder, at now: TimeInterval) -> Record? {
		guard let data = readRecord(url),
			  let record = try? decoder.decode(Record.self, from: data),
			  record.expiresAt.isFinite, record.expiresAt > now, record.pid > 1 else { return nil }
		return record
	}

	private static func activity(from record: Record, at file: URL) -> AgentActivity? {
		let provider = displayText(record.provider, limit: 32)
		let title = displayText(record.title, limit: 120)
		guard !provider.isEmpty, !title.isEmpty, !record.id.isEmpty, record.id.count <= 256,
			  record.id.rangeOfCharacter(from: .controlCharacters) == nil else { return nil }
		return AgentActivity(id: record.id, provider: provider, title: title, url: allowedURL(record.url),
							 bundleIdentifier: allowedBundleIdentifier(record.bundleIdentifier), recordURL: file)
	}

	private static func readRecord(_ url: URL) -> Data? {
		let file = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
		guard file >= 0 else { return nil }
		defer { close(file) }
		var info = stat()
		guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG,
			  info.st_uid == getuid(), info.st_size > 0, info.st_size <= 4_096 else { return nil }
		var data = Data(count: Int(info.st_size))
		let count = data.withUnsafeMutableBytes { Darwin.read(file, $0.baseAddress, $0.count) }
		return count == data.count ? data : nil
	}

	private static func displayText(_ string: String, limit: Int) -> String {
		return String(string.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(limit))
	}

	private static func allowedURL(_ string: String?) -> URL? {
		guard let string = string, let components = URLComponents(string: string),
			  components.user == nil, components.password == nil else { return nil }
		switch components.scheme?.lowercased() {
		case "https" where components.host?.isEmpty == false:
			return components.url
		case "codex" where components.host == "threads" && components.port == nil && components.query == nil && components.fragment == nil:
			let threadID = String(components.path.dropFirst())
			guard components.path.hasPrefix("/"), UUID(uuidString: threadID) != nil else { return nil }
			return URL(string: "codex://threads/\(threadID)")
		default:
			return nil
		}
	}

	private static func allowedBundleIdentifier(_ identifier: String?) -> String? {
		guard let identifier = identifier,
			  identifier.range(of: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9-]+)+$", options: .regularExpression) != nil else { return nil }
		return identifier
	}
}
