import 'dart:convert';

import 'package:flutter/services.dart';

import 'place.dart';

enum Span { short, medium, long }

enum LocationMode { automatic, manual }

/// One widget's settings. Same JSON as `WidgetStore.Settings` in Kotlin.
class WidgetSettings {
  const WidgetSettings({
    this.span = Span.medium,
    this.fahrenheit = false,
    this.feelsLike = false,
    this.alsoOtherUnit = false,
    this.mode = LocationMode.manual,
    this.place,
  });

  final Span span;
  final bool fahrenheit;
  final bool feelsLike;
  final bool alsoOtherUnit;
  final LocationMode mode;
  final Place? place;

  /// Ready to save: automatic, or manual with a place picked.
  bool get complete => mode == LocationMode.automatic || place != null;

  WidgetSettings copyWith({
    Span? span,
    bool? fahrenheit,
    bool? feelsLike,
    bool? alsoOtherUnit,
    LocationMode? mode,
    Place? place,
    bool clearPlace = false,
  }) =>
      WidgetSettings(
        span: span ?? this.span,
        fahrenheit: fahrenheit ?? this.fahrenheit,
        feelsLike: feelsLike ?? this.feelsLike,
        alsoOtherUnit: alsoOtherUnit ?? this.alsoOtherUnit,
        mode: mode ?? this.mode,
        place: clearPlace ? null : place ?? this.place,
      );

  String encode() => jsonEncode({
        'span': span.name,
        'unit': fahrenheit ? 'f' : 'c',
        'feelsLike': feelsLike,
        'alsoOtherUnit': alsoOtherUnit,
        'mode': mode.name,
        'place': place == null ? null : {'name': place!.name, 'lat': place!.lat, 'lon': place!.lon},
      });

  factory WidgetSettings.decode(String raw) {
    final j = jsonDecode(raw) as Map<String, dynamic>;
    final p = j['place'] as Map<String, dynamic>?;
    return WidgetSettings(
      span: Span.values.asNameMap()[j['span']] ?? Span.medium,
      fahrenheit: j['unit'] == 'f',
      feelsLike: j['feelsLike'] == true,
      alsoOtherUnit: j['alsoOtherUnit'] == true,
      mode: j['mode'] == 'automatic' ? LocationMode.automatic : LocationMode.manual,
      place: p == null
          ? null
          : Place(
              name: p['name'] as String,
              region: '',
              lat: (p['lat'] as num).toDouble(),
              lon: (p['lon'] as num).toDouble(),
            ),
    );
  }
}

enum LocationAccess { none, foreground, background }

/// How the app was opened: normally, by the launcher to set up a new widget, or by a widget tap.
class Launch {
  const Launch(this.widgetId, this.mode);
  final int? widgetId;
  final String? mode; // null, "configure" or "edit"
}

/// Talks to the native widget code (`MainActivity.kt`).
class Bridge {
  Bridge() {
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openWidget':
          onOpenWidget?.call(call.arguments as int);
        case 'resumed':
          onResumed?.call();
      }
    });
  }

  static const _channel = MethodChannel('io.rea.weather_widget/widgets');

  void Function(int widgetId)? onOpenWidget;
  void Function()? onResumed;

  Future<Launch> launch() async {
    final m = await _channel.invokeMapMethod<String, Object?>('launch') ?? const {};
    return Launch(m['widgetId'] as int?, m['mode'] as String?);
  }

  Future<WidgetSettings?> settings(int id) async {
    final raw = await _channel.invokeMethod<String>('settings', {'id': id});
    return raw == null ? null : WidgetSettings.decode(raw);
  }

  Future<void> save(int id, WidgetSettings s) =>
      _channel.invokeMethod('saveSettings', {'id': id, 'json': s.encode()});

  Future<void> finishConfigure(int id, {required bool ok}) =>
      _channel.invokeMethod('finishConfigure', {'id': id, 'ok': ok});

  Future<bool> canPin() async => await _channel.invokeMethod<bool>('canPin') ?? false;

  Future<bool> pin(WidgetSettings s) async =>
      await _channel.invokeMethod<bool>('pin', {'json': s.encode()}) ?? false;

  Future<LocationAccess> locationAccess() async =>
      _access(await _channel.invokeMethod<String>('locationAccess'));

  Future<LocationAccess> requestLocation() async =>
      _access(await _channel.invokeMethod<String>('requestLocation'));

  Future<LocationAccess> requestBackgroundLocation() async =>
      _access(await _channel.invokeMethod<String>('requestBackgroundLocation'));

  Future<Uint8List?> preview({
    required double width,
    required double height,
    required bool dark,
    required bool fahrenheit,
  }) =>
      _channel.invokeMethod<Uint8List>(
          'preview', {'width': width, 'height': height, 'dark': dark, 'fahrenheit': fahrenheit});

  Future<void> refreshAll() => _channel.invokeMethod('refreshAll');

  Future<bool> flag(String name) async =>
      await _channel.invokeMethod<bool>('getFlag', {'name': name}) ?? false;

  Future<void> setFlag(String name, bool value) =>
      _channel.invokeMethod('setFlag', {'name': name, 'value': value});

  /// Android share sheet with a short note about the app.
  Future<void> share() => _channel.invokeMethod('share');

  static LocationAccess _access(String? s) =>
      LocationAccess.values.asNameMap()[s] ?? LocationAccess.none;
}
