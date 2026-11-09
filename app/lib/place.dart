class Place {
  const Place({
    required this.name,
    required this.region,
    required this.lat,
    required this.lon,
    this.isDevice = false,
  });

  final String name;
  final String region;
  final double lat;
  final double lon;

  /// True for "my location": the app refreshes it from GPS each time it opens.
  final bool isDevice;

  Map<String, Object> toJson() => {
        'name': name,
        'region': region,
        'lat': lat,
        'lon': lon,
        'isDevice': isDevice,
      };

  factory Place.fromJson(Map<String, dynamic> json) => Place(
        name: json['name'] as String,
        region: json['region'] as String? ?? '',
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        isDevice: json['isDevice'] as bool? ?? false,
      );
}
