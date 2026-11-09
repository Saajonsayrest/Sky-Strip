import AppIntents
import SwiftUI
import WidgetKit

struct WeatherEntry: TimelineEntry {
  let date: Date
  let forecast: Forecast?
  let placeName: String?
  let fahrenheit: Bool
  let feels: Bool
  let spans: [String: Span]
}

/// Uses the forecast the app saved; fetches a new one itself when it is older than 50 minutes.
struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> WeatherEntry { entry(Date(), forecast: nil) }

  func getSnapshot(in context: Context, completion: @escaping (WeatherEntry) -> Void) {
    completion(entry(Date(), forecast: WidgetStore().forecast))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<WeatherEntry>) -> Void) {
    Task {
      let store = WidgetStore()
      var forecast = store.forecast
      let now = Date()
      let stale = forecast.map { Int(now.timeIntervalSince1970) - $0.fetchedAt > 50 * 60 } ?? true
      if stale, let place = store.place, let raw = try? await Forecast.fetch(lat: place.lat, lon: place.lon) {
        store.forecastJSON = raw
        forecast = Forecast.parse(raw) ?? forecast
      }
      // One entry every 30 minutes, so the diagram moves on with the clock between fetches.
      let entries = (0..<4).map { entry(now.addingTimeInterval(Double($0) * 1800), forecast: forecast) }
      completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(45 * 60))))
    }
  }

  private func entry(_ date: Date, forecast: Forecast?) -> WeatherEntry {
    let store = WidgetStore()
    let families = ["systemSmall", "systemMedium", "systemLarge"]
    return WeatherEntry(
      date: date, forecast: forecast, placeName: store.place?.name,
      fahrenheit: store.fahrenheit, feels: store.feelsLike,
      spans: Dictionary(uniqueKeysWithValues: families.map { ($0, store.span(family: $0)) }))
  }
}

/// Tapping the diagram cycles 12 hours, 36 hours and 7 days for that widget size.
struct ToggleSpanIntent: AppIntent {
  static var title: LocalizedStringResource = "Switch time span"

  @Parameter(title: "Widget size") var family: String

  init() {}
  init(family: String) { self.family = family }

  func perform() async throws -> some IntentResult {
    let store = WidgetStore()
    store.setSpan(store.span(family: family).next, family: family)
    return .result()
  }
}

struct WeatherWidgetView: View {
  let entry: WeatherEntry
  @Environment(\.widgetFamily) private var family
  @Environment(\.colorScheme) private var scheme

  private var dark: Bool { scheme == .dark }
  private var familyKey: String {
    switch family {
    case .systemSmall: return "systemSmall"
    case .systemLarge: return "systemLarge"
    default: return "systemMedium"
    }
  }

  var body: some View {
    Group {
      if entry.placeName == nil {
        message("Open Sky Strip to choose a place")
      } else if let f = entry.forecast, f.from(now).count >= 13 {
        switch family {
        case .systemSmall: small(f)
        case .systemLarge: large(f)
        default: medium(f)
        }
      } else if entry.forecast == nil {
        message("Loading weather…")
      } else {
        message("Open Sky Strip to update")
      }
    }
    .containerBackground(Palette.card(dark), for: .widget)
  }

  private var now: Int { Int(entry.date.timeIntervalSince1970) }
  private var span: Span { entry.spans[familyKey] ?? .medium }

  private func message(_ s: String) -> some View {
    Text(s).font(.footnote).foregroundStyle(Palette.muted(dark)).multilineTextAlignment(.center)
  }

  private func temp(_ c: Double) -> String { "\(displayTemp(c, fahrenheit: entry.fahrenheit))°" }

  private func details(_ h: Hour) -> String {
    "\(entry.feels ? "Actual" : "Feels") \(temp(entry.feels ? h.temp : h.feelsLike)) · \(windLabel(h.wind))"
  }

  private func diagram(_ f: Forecast, span: Span, compact: Bool = false) -> some View {
    Diagram(forecast: f, now: now, span: span, fahrenheit: entry.fahrenheit, feels: entry.feels, compact: compact)
  }

  private func toggle<V: View>(_ content: V) -> some View {
    Button(intent: ToggleSpanIntent(family: familyKey)) { content }.buttonStyle(.plain)
  }

  private func small(_ f: Forecast) -> some View {
    let h = f.from(now)[0]
    let t = h.temp(feels: entry.feels)
    return VStack(alignment: .leading, spacing: 0) {
      Text(entry.placeName ?? "").font(.system(size: 11)).foregroundStyle(Palette.muted(dark)).lineLimit(1)
      Text(temp(t)).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.ink(t, dark))
      Text(conditionLabel(h)).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text(dark)).lineLimit(1)
      diagram(f, span: .short, compact: true).padding(.top, 6)
    }
  }

  private func medium(_ f: Forecast) -> some View {
    let h = f.from(now)[0]
    let t = h.temp(feels: entry.feels)
    return HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(temp(t)).font(.system(size: 38, weight: .light)).foregroundStyle(Palette.ink(t, dark))
        Text(conditionLabel(h)).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.text(dark))
        Text(details(h)).font(.system(size: 11)).foregroundStyle(Palette.muted(dark))
        Spacer(minLength: 0)
        Text(entry.placeName ?? "").font(.system(size: 11)).foregroundStyle(Palette.muted(dark))
      }
      .lineLimit(1)
      .frame(width: 104, alignment: .leading)
      toggle(diagram(f, span: span))
    }
  }

  private func large(_ f: Forecast) -> some View {
    let h = f.from(now)[0]
    let t = h.temp(feels: entry.feels)
    return VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .top, spacing: 12) {
        Text(temp(t)).font(.system(size: 44, weight: .light)).foregroundStyle(Palette.ink(t, dark))
        VStack(alignment: .leading, spacing: 2) {
          Text(conditionLabel(h)).font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.text(dark))
          Text(details(h)).font(.system(size: 11)).foregroundStyle(Palette.muted(dark))
        }
        .padding(.top, 8)
        Spacer(minLength: 0)
        Text(entry.placeName ?? "").font(.system(size: 11)).foregroundStyle(Palette.muted(dark)).padding(.top, 4)
      }
      .lineLimit(1)
      toggle(diagram(f, span: span)).frame(maxHeight: .infinity)
      days(f)
    }
  }

  private func days(_ f: Forecast) -> some View {
    let list = Array(f.days.prefix(5))
    let lo = list.map(\.min).min() ?? 0
    let hi = list.map(\.max).max() ?? 1
    return VStack(spacing: 6) {
      ForEach(list.indices, id: \.self) { i in
        let d = list[i]
        HStack(spacing: 8) {
          Text(i == 0 ? "Today" : weekdayNames[f.local(d.time).weekday])
            .font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.text(dark))
            .frame(width: 44, alignment: .leading)
          Text(d.precipitation >= 0.1 ? String(format: "%.1f mm", d.precipitation) : "")
            .font(.system(size: 11)).foregroundStyle(Palette.rain)
            .frame(width: 52, alignment: .leading)
          Text(temp(d.min)).font(.system(size: 12)).foregroundStyle(Palette.muted(dark))
            .frame(width: 32, alignment: .trailing)
          RangeBar(lo: lo, hi: hi, min: d.min, max: d.max, track: Palette.line(dark))
          Text(temp(d.max)).font(.system(size: 12)).foregroundStyle(Palette.text(dark))
            .frame(width: 32, alignment: .leading)
        }
      }
    }
  }
}

struct RangeBar: View {
  let lo, hi, min, max: Double
  let track: Color
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    GeometryReader { g in
      let span = hi - lo < 0.1 ? 1 : hi - lo
      let w = g.size.width
      let left = CGFloat((min - lo) / span) * w
      let width = Swift.max(6, CGFloat((max - min) / span) * w)
      ZStack(alignment: .leading) {
        Capsule().fill(track)
        Capsule()
          .fill(LinearGradient(colors: [Palette.ink(min, scheme == .dark), Palette.ink(max, scheme == .dark)], startPoint: .leading, endPoint: .trailing))
          .frame(width: Swift.min(width, w))
          .offset(x: Swift.min(left, w - Swift.min(width, w)))
      }
    }
    .frame(height: 6)
  }
}

@main
struct WeatherWidget: Widget {
  // Must match `iosWidgetKind` in lib/store.dart.
  let kind = "WeatherWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      WeatherWidgetView(entry: entry)
    }
    .configurationDisplayName("Sky Strip")
    .description("Your next hours of weather in one picture. Tap the picture to switch 12 h, 36 h or 7 days.")
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
  }
}
