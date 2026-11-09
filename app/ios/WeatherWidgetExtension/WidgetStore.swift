import Foundation

/// Reads what the Flutter app saved through home_widget (`lib/store.dart`, class `Keys`) in the
/// shared App Group. All values are strings.
struct WidgetStore {
  static let appGroup = "group.io.rea.weatherWidget"

  private let defaults = UserDefaults(suiteName: WidgetStore.appGroup)

  struct Place {
    let name: String
    let lat: Double
    let lon: Double
  }

  var place: Place? {
    guard let raw = defaults?.string(forKey: "place"),
          let data = raw.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let name = j["name"] as? String,
          let lat = (j["lat"] as? NSNumber)?.doubleValue,
          let lon = (j["lon"] as? NSNumber)?.doubleValue
    else { return nil }
    return Place(name: name, lat: lat, lon: lon)
  }

  var forecastJSON: String? {
    get { defaults?.string(forKey: "forecast") }
    nonmutating set { defaults?.set(newValue, forKey: "forecast") }
  }

  var forecast: Forecast? { forecastJSON.flatMap(Forecast.parse) }
  var fahrenheit: Bool { defaults?.string(forKey: "unit") == "f" }
  var feelsLike: Bool { defaults?.string(forKey: "feels") == "1" }

  /// iOS gives widgets no stable id, so each size keeps its own time span.
  func span(family: String) -> Span {
    if let s = defaults?.string(forKey: "span_ios_\(family)").flatMap(Span.init(rawValue:)) { return s }
    return defaults?.string(forKey: "span").flatMap(Span.init(rawValue:)) ?? .medium
  }

  func setSpan(_ span: Span, family: String) {
    defaults?.set(span.rawValue, forKey: "span_ios_\(family)")
  }
}
