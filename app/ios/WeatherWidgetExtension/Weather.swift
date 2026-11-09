import Foundation

// Swift twin of lib/weather.dart and lib/open_meteo.dart. Keep the two in sync.

struct Hour {
  let time: Int
  let temp: Double
  let feelsLike: Double
  let cloud: Double
  let rain: Double
  let snow: Double
  let wind: Double
  let isDay: Bool

  func temp(feels: Bool) -> Double { feels ? feelsLike : temp }
}

struct Day {
  let time: Int
  let min: Double
  let max: Double
  let precipitation: Double
}

struct Forecast {
  let utcOffset: Int
  let fetchedAt: Int
  let hours: [Hour]
  let days: [Day]

  private var calendar: Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(secondsFromGMT: utcOffset) ?? .gmt
    return c
  }

  /// Local hour (0-23) and weekday index (0 = Monday) of a UTC time.
  func local(_ utc: Int) -> (hour: Int, weekday: Int) {
    let parts = calendar.dateComponents([.hour, .weekday], from: Date(timeIntervalSince1970: TimeInterval(utc)))
    return (parts.hour ?? 0, ((parts.weekday ?? 2) + 5) % 7)
  }

  func from(_ nowUtc: Int) -> [Hour] {
    let start = hours.lastIndex { $0.time <= nowUtc } ?? 0
    return Array(hours[start...])
  }

  static func parse(_ raw: String) -> Forecast? {
    guard let data = raw.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let h = json["hourly"] as? [String: Any],
          let d = json["daily"] as? [String: Any],
          let times = h["time"] as? [NSNumber],
          let dayTimes = d["time"] as? [NSNumber]
    else { return nil }
    func at(_ m: [String: Any], _ key: String, _ i: Int) -> Double {
      guard let arr = m[key] as? [Any], i < arr.count, let n = arr[i] as? NSNumber else { return 0 }
      return n.doubleValue
    }
    let hours = times.indices.map { i in
      Hour(
        time: times[i].intValue,
        temp: at(h, "temperature_2m", i),
        feelsLike: at(h, "apparent_temperature", i),
        cloud: at(h, "cloud_cover", i),
        rain: at(h, "rain", i) + at(h, "showers", i),
        snow: at(h, "snowfall", i),
        wind: at(h, "wind_speed_10m", i),
        isDay: at(h, "is_day", i) > 0
      )
    }
    let days = dayTimes.indices.map { i in
      Day(
        time: dayTimes[i].intValue,
        min: at(d, "temperature_2m_min", i),
        max: at(d, "temperature_2m_max", i),
        precipitation: at(d, "precipitation_sum", i)
      )
    }
    return Forecast(
      utcOffset: (json["utc_offset_seconds"] as? NSNumber)?.intValue ?? 0,
      fetchedAt: (json["fetched_at"] as? NSNumber)?.intValue ?? Int(Date().timeIntervalSince1970),
      hours: hours,
      days: days
    )
  }

  /// Same request as `OpenMeteo.forecastUri` in Dart. Returns the JSON stamped with fetched_at.
  static func fetch(lat: Double, lon: Double) async throws -> String {
    var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    c.queryItems = [
      .init(name: "latitude", value: String(format: "%.4f", lat)),
      .init(name: "longitude", value: String(format: "%.4f", lon)),
      .init(name: "hourly", value: "temperature_2m,apparent_temperature,cloud_cover,rain,showers,snowfall,wind_speed_10m,is_day"),
      .init(name: "daily", value: "temperature_2m_max,temperature_2m_min,precipitation_sum"),
      .init(name: "wind_speed_unit", value: "ms"),
      .init(name: "timeformat", value: "unixtime"),
      .init(name: "timezone", value: "auto"),
      .init(name: "forecast_days", value: "8"),
      .init(name: "past_hours", value: "1"),
    ]
    var request = URLRequest(url: c.url!)
    request.timeoutInterval = 15
    let (data, response) = try await URLSession.shared.data(for: request)
    guard (response as? HTTPURLResponse)?.statusCode == 200,
          var json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { throw URLError(.badServerResponse) }
    json["fetched_at"] = Int(Date().timeIntervalSince1970)
    return String(data: try JSONSerialization.data(withJSONObject: json), encoding: .utf8) ?? ""
  }
}

private let beaufortFrom = [0.3, 1.6, 3.4, 5.5, 8.0, 10.8, 13.9, 17.2, 20.8, 24.5, 28.5, 32.7]

func beaufort(_ ms: Double) -> Int { beaufortFrom.filter { ms >= $0 }.count }

func windLabel(_ ms: Double) -> String {
  switch beaufort(ms) {
  case 0: return "Calm"
  case 1, 2: return "Light wind"
  case 3, 4: return "Breeze"
  case 5, 6: return "Strong wind"
  case 7, 8: return "Gale"
  default: return "Storm"
  }
}

func skyLabel(_ cloud: Double, _ isDay: Bool) -> String {
  if cloud < 20 { return isDay ? "Sunny" : "Clear" }
  if cloud < 50 { return "Partly cloudy" }
  if cloud < 85 { return "Cloudy" }
  return "Overcast"
}

func precipLabel(_ rain: Double, _ snow: Double) -> String? {
  if snow >= 0.1 { return snow < 1 ? "Light snow" : (snow < 3 ? "Snow" : "Heavy snow") }
  if rain < 0.1 { return nil }
  if rain < 1 { return "Light rain" }
  if rain < 4 { return "Rain" }
  if rain < 8 { return "Heavy rain" }
  return "Downpour"
}

func conditionLabel(_ h: Hour) -> String { precipLabel(h.rain, h.snow) ?? skyLabel(h.cloud, h.isDay) }

/// Rounds half away from zero, like Dart's round().
func displayTemp(_ celsius: Double, fahrenheit: Bool) -> Int {
  Int((fahrenheit ? celsius * 9 / 5 + 32 : celsius).rounded(.toNearestOrAwayFromZero))
}

enum Span: String, CaseIterable {
  case short, medium, long

  var hours: Int {
    switch self {
    case .short: return 12
    case .medium: return 36
    case .long: return 168
    }
  }

  var next: Span {
    let all = Span.allCases
    return all[(all.firstIndex(of: self)! + 1) % all.count]
  }
}

let weekdayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
