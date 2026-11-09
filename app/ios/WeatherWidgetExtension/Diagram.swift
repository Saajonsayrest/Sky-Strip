import SwiftUI

/// Colours from `Palette` in lib/diagram.dart.
enum Palette {
  static func hex(_ v: UInt32) -> Color {
    Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
  }

  static func card(_ dark: Bool) -> Color { dark ? hex(0x0F1420) : hex(0xF5F7FB) }
  static func text(_ dark: Bool) -> Color { dark ? .white : hex(0x121826) }
  static func muted(_ dark: Bool) -> Color { text(dark).opacity(0.6) }
  static func line(_ dark: Bool) -> Color { text(dark).opacity(0.12) }

  static let rain = hex(0x3D8BFF)
  static let snow = hex(0xF2F6FF)
  static let snowEdge = hex(0x9FB3D1)

  private typealias RGB = (Double, Double, Double)
  private static func rgb(_ v: UInt32) -> RGB {
    (Double((v >> 16) & 0xFF) / 255, Double((v >> 8) & 0xFF) / 255, Double(v & 0xFF) / 255)
  }
  private static func mix(_ a: RGB, _ b: RGB, _ t: Double) -> Color {
    Color(red: a.0 + (b.0 - a.0) * t, green: a.1 + (b.1 - a.1) * t, blue: a.2 + (b.2 - a.2) * t)
  }

  /// Temperature colour for text and lines; deeper scale on light cards (`Palette.ink` in Dart).
  static func ink(_ c: Double, _ dark: Bool) -> Color {
    let v = rampRGB(c, dark ? ramp : inkRamp)
    return Color(red: v.0, green: v.1, blue: v.2)
  }

  static func sky(_ cloud: Double, _ isDay: Bool) -> Color {
    mix(rgb(isDay ? 0x5BB4FF : 0x1E2C52), rgb(isDay ? 0x9AA7B8 : 0x353C4A), min(max(cloud / 100, 0), 1))
  }

  private static let rampAt: [Double] = [-10, 0, 10, 18, 26, 34]
  private static let ramp: [UInt32] = [0x6EA8FF, 0x7ED6E0, 0xA8E6A1, 0xFFE07A, 0xFFA45C, 0xFF5C7A]

  private static let inkRamp: [UInt32] = [0x2F6FE0, 0x1C9DB3, 0x3AA45A, 0xD99A00, 0xEB6F12, 0xDD2F4C]

  static func temp(_ c: Double) -> Color {
    let v = rampRGB(c, ramp)
    return Color(red: v.0, green: v.1, blue: v.2)
  }

  private static func rampRGB(_ c: Double, _ colors: [UInt32]) -> RGB {
    if c <= rampAt[0] { return rgb(colors[0]) }
    for i in 1..<rampAt.count where c <= rampAt[i] {
      let a = rgb(colors[i - 1]), b = rgb(colors[i])
      let t = (c - rampAt[i - 1]) / (rampAt[i] - rampAt[i - 1])
      return (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
    }
    return rgb(colors[colors.count - 1])
  }
}

/// Port of `HourlyDiagram` in lib/diagram.dart.
struct Diagram: View {
  let forecast: Forecast
  let now: Int
  let span: Span
  let fahrenheit: Bool
  let feels: Bool
  var compact = false
  @Environment(\.colorScheme) private var scheme

  var body: some View {
    Canvas { ctx, size in draw(&ctx, size) }
  }

  private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
    let dark = scheme == .dark
    let all = forecast.from(now)
    guard all.count >= 2, size.width > 20, size.height > 30 else { return }
    let hours = Array(all.prefix(span.hours + 1))
    let n = hours.count - 1
    let w = size.width
    let labelH: CGFloat = 14
    let skyH = size.height * 0.42
    let step = w / CGFloat(n)
    func x(_ i: Int) -> CGFloat { CGFloat(i) * step }

    // Sky band, one gradient stop per hour.
    let sky = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: skyH), cornerRadius: 10)
    var skyCtx = ctx
    skyCtx.clip(to: sky)
    let skyStops = hours.indices.map {
      Gradient.Stop(color: Palette.sky(hours[$0].cloud, hours[$0].isDay), location: CGFloat($0) / CGFloat(n))
    }
    skyCtx.fill(sky, with: .linearGradient(Gradient(stops: skyStops), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)))

    // Rain and snow hang from the top, full height at 6 mm/h.
    let barW = max(1.5, step * 0.55)
    for i in 0..<n {
      let h = hours[i + 1]
      let snow = h.snow >= 0.1
      let amount = snow ? h.snow * 2 : h.rain
      if amount < 0.1 { continue }
      let bh = CGFloat(min(max(amount, 0), 6) / 6) * (skyH - 6) + 3
      let rect = CGRect(x: x(i) + (step - barW) / 2, y: 0, width: barW, height: bh)
      let bar = Path(roundedRect: rect, cornerRadii: .init(bottomLeading: barW / 2, bottomTrailing: barW / 2))
      skyCtx.fill(bar, with: .color(snow ? Palette.snow : Palette.rain))
      if snow { skyCtx.stroke(bar, with: .color(Palette.snowEdge), lineWidth: 1) }
    }

    // Wind chevrons, only from a breeze up.
    let windEvery = max(1, Int((12 / step).rounded(.up)))
    for i in stride(from: 0, to: n, by: windEvery) {
      let force = beaufort(hours[i].wind)
      if force < 3 { continue }
      let count = min(max(Int((Double(force) / 3).rounded(.up)), 1), 4)
      for c in 0..<count {
        let cx = x(i) + 4 + CGFloat(c) * 3.5
        let cy = skyH - 6
        var p = Path()
        p.move(to: CGPoint(x: cx, y: cy - 2.5))
        p.addLine(to: CGPoint(x: cx + 2.5, y: cy))
        p.addLine(to: CGPoint(x: cx, y: cy + 2.5))
        skyCtx.stroke(p, with: .color(.white.opacity(0.75)), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
      }
    }

    // Temperature line with a soft fill under it.
    let temps = hours.map { $0.temp(feels: feels) }
    let lo = temps.min()!, hi = temps.max()!
    let top = skyH + 16
    let bottom = size.height - labelH - 20
    let mid = (hi + lo) / 2
    let range = max(hi - lo, 8)
    func y(_ t: Double) -> CGFloat {
      bottom - CGFloat((t - (mid - range / 2)) / range) * (bottom - top)
    }
    let pts = temps.indices.map { CGPoint(x: x($0), y: y(temps[$0])) }
    let curve = smooth(pts)
    let colors = temps.map { Palette.ink($0, dark) }
    var fill = curve
    fill.addLine(to: CGPoint(x: w, y: size.height - labelH))
    fill.addLine(to: CGPoint(x: 0, y: size.height - labelH))
    fill.closeSubpath()
    ctx.fill(fill, with: .linearGradient(
      Gradient(colors: [colors[0].opacity(0.28), colors[0].opacity(0)]),
      startPoint: CGPoint(x: 0, y: top), endPoint: CGPoint(x: 0, y: size.height - labelH)))
    let lineStops = colors.indices.map { Gradient.Stop(color: colors[$0], location: CGFloat($0) / CGFloat(n)) }
    ctx.stroke(curve, with: .linearGradient(Gradient(stops: lineStops), startPoint: .zero, endPoint: CGPoint(x: w, y: 0)),
               style: StrokeStyle(lineWidth: 3, lineCap: .round))

    // Time marks and day lines.
    let every = span == .short ? 3 : (span == .medium ? 6 : 24)
    for i in 0...n {
      let t = forecast.local(hours[i].time)
      let midnight = t.hour == 0
      if midnight && i > 0 {
        var l = Path()
        l.move(to: CGPoint(x: x(i), y: skyH + 4))
        l.addLine(to: CGPoint(x: x(i), y: size.height - labelH))
        ctx.stroke(l, with: .color(Palette.line(dark)), lineWidth: 1)
      }
      if i == 0 || i == n { continue }
      var label: String?
      if span == .long {
        if t.hour == 12 { label = weekdayNames[t.weekday] }
      } else if t.hour % every == 0 {
        label = midnight ? weekdayNames[t.weekday] : "\(t.hour)"
      }
      guard let label else { continue }
      let strong = midnight && span != .long
      let text = Text(label).font(.system(size: 10, weight: .medium))
        .foregroundColor(strong ? Palette.text(dark) : Palette.muted(dark))
      ctx.draw(text, at: CGPoint(x: x(i), y: size.height), anchor: .bottom)
    }

    // High and low marks.
    let hiI = temps.firstIndex(of: hi)!, loI = temps.firstIndex(of: lo)!
    mark(&ctx, pts[hiI], displayTemp(hi, fahrenheit: fahrenheit), colors[hiI], above: true, w: w, dark: dark)
    if hi - lo >= 2 && !compact {
      mark(&ctx, pts[loI], displayTemp(lo, fahrenheit: fahrenheit), colors[loI], above: false, w: w, dark: dark)
    }
  }

  private func mark(_ ctx: inout GraphicsContext, _ p: CGPoint, _ value: Int, _ color: Color,
                    above: Bool, w: CGFloat, dark: Bool) {
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 3.5, y: p.y - 3.5, width: 7, height: 7)), with: .color(color))
    ctx.fill(Path(ellipseIn: CGRect(x: p.x - 1.5, y: p.y - 1.5, width: 3, height: 3)), with: .color(Palette.card(dark)))
    let text = ctx.resolve(Text("\(value)°").font(.system(size: 11, weight: .semibold)).foregroundColor(Palette.text(dark)))
    let s = text.measure(in: CGSize(width: 100, height: 40))
    let cx = min(max(p.x, s.width / 2), w - s.width / 2)
    let cy = above ? p.y - 4 - s.height / 2 : p.y + 5 + s.height / 2
    ctx.draw(text, at: CGPoint(x: cx, y: cy), anchor: .center)
  }

  private func smooth(_ p: [CGPoint]) -> Path {
    var path = Path()
    path.move(to: p[0])
    for i in 0..<(p.count - 1) {
      let p0 = p[max(0, i - 1)], p1 = p[i], p2 = p[i + 1], p3 = p[min(p.count - 1, i + 2)]
      path.addCurve(
        to: p2,
        control1: CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6),
        control2: CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6))
    }
    return path
  }
}
