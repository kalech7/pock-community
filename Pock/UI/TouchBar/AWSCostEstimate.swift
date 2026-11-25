import Foundation

internal enum AWSCostMode: String, CaseIterable, Codable {
	case projected, monthToDate

	var title: String {
		switch self {
		case .projected: return "Projected month".localized
		case .monthToDate: return "Month to date".localized
		}
	}
}

internal enum AWSCostScope: String, CaseIterable, Codable {
	case account, ec2AndRds

	var title: String {
		switch self {
		case .account: return "All services".localized
		case .ec2AndRds: return "EC2 and RDS only".localized
		}
	}

	func includes(_ service: String) -> Bool {
		return self == .account || ["Amazon Elastic Compute Cloud - Compute", "EC2 - Other",
			"Amazon Relational Database Service"].contains(service)
	}
}

internal struct AWSCostEstimate: Codable, Equatable {
	struct Line: Codable, Equatable {
		let service: String
		let amount: Decimal
	}

	private struct CachedReading: Decodable {
		let estimate: AWSCostEstimate?
	}

	static let calendar: Calendar = {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = TimeZone(secondsFromGMT: 0)!
		return calendar
	}()

	let start: Date
	let end: Date
	let checkedAt: Date
	let unit: String
	let lines: [Line]

	func amount(_ mode: AWSCostMode, scope: AWSCostScope) -> Decimal {
		let total = lines.filter { scope.includes($0.service) }.reduce(Decimal(0)) { $0 + $1.amount }
		guard mode == .projected, let days = Self.calendar.range(of: .day, in: .month, for: start)?.count,
			  let elapsed = Self.calendar.dateComponents([.day], from: start, to: end).day, elapsed > 0 else { return total }
		return total * Decimal(days) / Decimal(elapsed)
	}

	var isStale: Bool {
		!Self.calendar.isDate(start, equalTo: Date(), toGranularity: .month) ||
			Date().timeIntervalSince(checkedAt) > 24 * 60 * 60
	}

	static func load(profile: String, path: String?) throws -> Self? {
		guard let path = path, !path.isEmpty else {
			guard let data = UserDefaults.standard.data(forKey: "awsCostCache") else { return nil }
			return try? JSONDecoder().decode([String: CachedReading].self, from: data)[profile]?.estimate
		}
		let data = try AWSStatusFile.data(at: path)
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .iso8601
		let estimate = try decoder.decode(Self.self, from: data)
		guard let month = calendar.dateInterval(of: .month, for: estimate.start),
			  estimate.start < estimate.end, estimate.end <= month.end,
			  estimate.unit.range(of: #"^[A-Z]{3}$"#, options: .regularExpression) != nil else {
			throw CocoaError(.fileReadCorruptFile)
		}
		return estimate
	}
}

internal enum AWSStatusFile {
	static func data(at path: String) throws -> Data {
		guard !path.isEmpty else { throw CocoaError(.fileNoSuchFile) }
		let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
		let file = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
		guard file.isRegularFile == true, let size = file.fileSize, size < 1_048_576 else {
			throw CocoaError(.fileReadCorruptFile)
		}
		let handle = try FileHandle(forReadingFrom: url)
		defer { handle.closeFile() }
		let data = handle.readData(ofLength: 1_048_576)
		guard data.count < 1_048_576 else { throw CocoaError(.fileReadCorruptFile) }
		return data
	}
}
