import Foundation

internal struct WeatherPlace: Codable, Equatable {

	let id: Int
	let name: String
	let latitude: Double
	let longitude: Double
	let admin1: String?
	let admin2: String?
	let country: String?
	let countryCode: String?
	let timezone: String?
	let admin1ID: Int?

	private enum CodingKeys: String, CodingKey {
		case id, name, latitude, longitude, admin1, admin2, country, timezone
		case countryCode = "country_code"
		case admin1ID = "admin1_id"
	}

	var displayName: String {
		var parts = [name]
		for part in [admin2, admin1, country ?? countryCode].compactMap({ $0 }) {
			if parts.contains(where: { $0.localizedCaseInsensitiveCompare(part) == .orderedSame }) == false {
				parts.append(part)
			}
		}
		return parts.joined(separator: ", ")
	}

	var hasValidCoordinates: Bool {
		return (-90...90).contains(latitude) && (-180...180).contains(longitude)
	}

	var holidaySubdivision: String? {
		guard countryCode == "CA" else { return nil }
		let region = admin1?.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
		return admin1ID == 6115047 || region == "quebec" ? "CA-QC" : nil
	}
}

internal enum WeatherUnit: String {
	case celsius, fahrenheit

	var symbol: String {
		return self == .celsius ? "°C" : "°F"
	}

	func format(celsius: Double) -> String {
		let temperature = self == .celsius ? celsius : celsius * 9 / 5 + 32
		let rounded = temperature.rounded()
		return String(format: "%.0f%@", locale: Locale.current, rounded == 0 ? Double.zero : rounded, symbol)
	}
}

internal struct WeatherObservation: Decodable {

	enum ConditionStyle {
		case clear, cloudy, rain, snow, storm, unknown
	}

	let temperature2m: Double
	let weatherCode: Int
	let isDay: Int
	let time: TimeInterval
	let apparentTemperature: Double?
	let humidity: Double?
	let windSpeed: Double?
	var timezone: String? = nil

	private enum CodingKeys: String, CodingKey {
		case temperature2m = "temperature_2m"
		case weatherCode = "weather_code"
		case isDay = "is_day"
		case time
		case apparentTemperature = "apparent_temperature"
		case humidity = "relative_humidity_2m"
		case windSpeed = "wind_speed_10m"
	}

	init(temperature2m: Double, weatherCode: Int, isDay: Int, time: TimeInterval,
		 apparentTemperature: Double? = nil, humidity: Double? = nil, windSpeed: Double? = nil) {
		self.temperature2m = temperature2m
		self.weatherCode = weatherCode
		self.isDay = isDay
		self.time = time
		self.apparentTemperature = apparentTemperature
		self.humidity = humidity
		self.windSpeed = windSpeed
	}

	var date: Date {
		return Date(timeIntervalSince1970: time)
	}

	var condition: (description: String, symbol: String, fallback: String, style: ConditionStyle) {
		switch weatherCode {
		case 0:
			return isDay == 0 ? ("Clear", "moon.stars", "☾", .clear) : ("Clear", "sun.max", "☀︎", .clear)
		case 1:
			return isDay == 0 ? ("Mainly clear", "cloud.moon", "☾", .clear) : ("Mainly clear", "cloud.sun", "⛅︎", .clear)
		case 2:
			return isDay == 0 ? ("Partly cloudy", "cloud.moon", "☁︎", .cloudy) : ("Partly cloudy", "cloud.sun", "⛅︎", .cloudy)
		case 3:
			return ("Overcast", "cloud", "☁︎", .cloudy)
		case 45, 48:
			return ("Fog", "cloud.fog", "☁︎", .cloudy)
		case 51, 53, 55:
			return ("Drizzle", "cloud.drizzle", "☂︎", .rain)
		case 56, 57:
			return ("Freezing drizzle", "cloud.sleet", "❄︎", .snow)
		case 61, 63, 65, 80, 81, 82:
			return ("Rain", "cloud.rain", "☂︎", .rain)
		case 66, 67:
			return ("Freezing rain", "cloud.sleet", "❄︎", .snow)
		case 71, 73, 75, 77, 85, 86:
			return ("Snow", "cloud.snow", "❄︎", .snow)
		case 95, 96, 99:
			return ("Thunderstorms", "cloud.bolt.rain", "ϟ", .storm)
		default:
			return ("Conditions unavailable", "cloud", "☁︎", .unknown)
		}
	}
}

internal struct WeatherHoliday: Decodable {
	let date: String
	let localName: String?
	let name: String?
	let countryCode: String
	let global: Bool
	let counties: [String]?
	let types: [String]

	var displayName: String? {
		for title in [localName, name].compactMap({ $0 }) {
			let text = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
			if !text.isEmpty { return String(text.prefix(120)) }
		}
		return nil
	}

	func applies(on date: String, country: String, subdivision: String?) -> Bool {
		return self.date == date && countryCode == country && types.contains("Public") &&
			(global || subdivision.map({ counties?.contains($0) == true }) == true)
	}
}

internal struct WeatherService {

	private struct SearchResponse: Decodable {
		let results: [WeatherPlace]?
	}

	private struct ForecastResponse: Decodable {
		let current: WeatherObservation
		let timezone: String?
	}

	private static let session: URLSession = {
		let configuration = URLSessionConfiguration.ephemeral
		configuration.httpShouldSetCookies = false
		configuration.urlCache = nil
		configuration.timeoutIntervalForRequest = 15
		configuration.timeoutIntervalForResource = 20
		return URLSession(configuration: configuration)
	}()

	private let session: URLSession

	init(session: URLSession? = nil) {
		self.session = session ?? Self.session
	}

	@discardableResult
	func search(_ query: String, completion: @escaping (Result<[WeatherPlace], Error>) -> Void) -> URLSessionDataTask? {
		let language = Locale.preferredLanguages.first?.prefix(while: { $0.isLetter }) ?? "en"
		return request(host: "geocoding-api.open-meteo.com", path: "/v1/search", parameters: [
			"name": query,
			"count": "8",
			"language": String(language)
		], response: SearchResponse.self) { result in
			completion(result.map { ($0.results ?? []).filter { $0.hasValidCoordinates } })
		}
	}

	@discardableResult
	func current(at place: WeatherPlace, completion: @escaping (Result<WeatherObservation, Error>) -> Void) -> URLSessionDataTask? {
		return request(host: "api.open-meteo.com", path: "/v1/forecast", parameters: [
			"latitude": String(place.latitude),
			"longitude": String(place.longitude),
			"current": "temperature_2m,weather_code,is_day,apparent_temperature,relative_humidity_2m,wind_speed_10m",
			"timezone": "auto",
			"timeformat": "unixtime"
		], response: ForecastResponse.self) { result in
			completion(result.map { forecast in
				var reading = forecast.current
				reading.timezone = forecast.timezone
				return reading
			})
		}
	}

	@discardableResult
	func publicHolidays(country: String, year: Int, completion: @escaping (Result<[WeatherHoliday], Error>) -> Void) -> URLSessionDataTask? {
		return request(host: "nagerholidays.com", path: "/api/v3/PublicHolidays/\(year)/\(country)",
					   parameters: [:], response: [WeatherHoliday].self, completion: completion)
	}

	private func request<Response: Decodable>(host: String, path: String, parameters: [String: String],
		response: Response.Type, completion: @escaping (Result<Response, Error>) -> Void) -> URLSessionDataTask? {
		var components = URLComponents()
		components.scheme = "https"
		components.host = host
		components.path = path
		if !parameters.isEmpty {
			components.queryItems = parameters.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
		}
		// A literal plus would otherwise be decoded as a space by form-style query parsers.
		components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
		guard let url = components.url else {
			DispatchQueue.main.async { completion(.failure(URLError(.badURL))) }
			return nil
		}
		let task = session.dataTask(with: url) { data, response, error in
			let result = Result<Response, Error> {
				if let error = error {
					throw error
				}
				guard let data = data, let response = response as? HTTPURLResponse,
					(200..<300).contains(response.statusCode) else {
					throw URLError(.badServerResponse)
				}
				return try JSONDecoder().decode(Response.self, from: data)
			}
			DispatchQueue.main.async { completion(result) }
		}
		task.resume()
		return task
	}
}
