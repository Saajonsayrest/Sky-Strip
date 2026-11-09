import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:weather_widget/bridge.dart';
import 'package:weather_widget/open_meteo.dart';
import 'package:weather_widget/place.dart';
import 'package:weather_widget/settings_sheet.dart';

void main() {
  test('widget settings keep every field through the native JSON', () {
    const s = WidgetSettings(
      span: Span.long,
      fahrenheit: true,
      feelsLike: true,
      alsoOtherUnit: true,
      mode: LocationMode.manual,
      place: Place(name: 'Oslo', region: '', lat: 59.91, lon: 10.75),
    );
    final back = WidgetSettings.decode(s.encode());
    expect(back.span, Span.long);
    expect(back.fahrenheit, isTrue);
    expect(back.feelsLike, isTrue);
    expect(back.alsoOtherUnit, isTrue);
    expect(back.place?.name, 'Oslo');
    expect(back.place?.lat, 59.91);
    // Same keys and values as WidgetStore.Settings in Kotlin.
    final j = jsonDecode(s.encode()) as Map<String, dynamic>;
    expect(j['span'], 'long');
    expect(j['unit'], 'f');
    expect(j['mode'], 'manual');
  });

  test('a manual widget is only complete with a place', () {
    expect(const WidgetSettings().complete, isFalse);
    expect(const WidgetSettings(mode: LocationMode.automatic).complete, isTrue);
  });

  test('new widgets use °F only where people use it', () {
    expect(defaultSettings(const Locale('en', 'US')).fahrenheit, isTrue);
    expect(defaultSettings(const Locale('en', 'GB')).fahrenheit, isFalse);
    expect(defaultSettings(const Locale('ne', 'NP')).fahrenheit, isFalse);
  });

  test('place search asks the free geocoding service', () {
    final u = PlaceSearch.uri('Kathmandu');
    expect(u.host, 'geocoding-api.open-meteo.com');
    expect(u.queryParameters['name'], 'Kathmandu');
  });
}
