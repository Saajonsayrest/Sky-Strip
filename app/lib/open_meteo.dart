import 'dart:convert';

import 'package:http/http.dart' as http;

import 'place.dart';

/// Place search with the free Open-Meteo geocoding API (GeoNames data, no key).
class PlaceSearch {
  PlaceSearch({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static Uri uri(String name) => Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
        'name': name,
        'count': '10',
        'format': 'json',
      });

  Future<List<Place>> search(String name) async {
    final res = await _client.get(uri(name)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw PlaceSearchException('Search failed (${res.statusCode})');
    }
    final results =
        (jsonDecode(res.body) as Map<String, dynamic>)['results'] as List? ?? const [];
    return [
      for (final r in results.cast<Map<String, dynamic>>())
        Place(
          name: r['name'] as String,
          region: [r['admin1'], r['country']]
              .whereType<String>()
              .where((s) => s.isNotEmpty)
              .join(', '),
          lat: (r['latitude'] as num).toDouble(),
          lon: (r['longitude'] as num).toDouble(),
        ),
    ];
  }
}

class PlaceSearchException implements Exception {
  PlaceSearchException(this.message);
  final String message;

  @override
  String toString() => message;
}
