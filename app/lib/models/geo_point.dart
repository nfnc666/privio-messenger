import 'package:flutter/foundation.dart';

/// A place, as coordinates and nothing else.
///
/// No address, no place name, no map: those would have to come from a service
/// that is told the coordinates first. What travels is the pair of numbers the
/// phone measured, sealed like any message, and what the other side does with
/// them is its own choice.
@immutable
class GeoPoint {
  const GeoPoint({required this.latitude, required this.longitude, this.accuracyMeters});

  final double latitude;
  final double longitude;

  /// How far off the phone said it might be, when it said.
  final int? accuracyMeters;

  /// On the planet. Anything else is not a place, and a payload that carries
  /// one is filed as its text. NaN and infinity fail the comparisons too, so
  /// they need no rule of their own.
  bool get isValid =>
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180 &&
      (accuracyMeters == null || accuracyMeters! >= 0);

  /// Six decimals, about ten centimetres: more than any phone measures, so
  /// nothing real is lost, and nothing past the measurement is sent.
  GeoPoint rounded() => GeoPoint(
        latitude: _round(latitude),
        longitude: _round(longitude),
        accuracyMeters: accuracyMeters,
      );

  static double _round(double value) => double.parse(value.toStringAsFixed(6));

  /// The two numbers as people write them, with a point for the decimals in
  /// every language, because this is also what gets copied and pasted into a
  /// maps app, and those all read a point.
  String get coordinates => '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';

  Map<String, Object> toJson() => {
        'la': latitude,
        'lo': longitude,
        if (accuracyMeters != null) 'ac': accuracyMeters!,
      };

  /// Null for anything that is not a valid place.
  static GeoPoint? fromJson(Object? json) {
    if (json is! Map) return null;
    final latitude = json['la'];
    final longitude = json['lo'];
    if (latitude is! num || longitude is! num) return null;
    final accuracy = json['ac'];
    final point = GeoPoint(
      latitude: latitude.toDouble(),
      longitude: longitude.toDouble(),
      accuracyMeters: accuracy is int ? accuracy : null,
    );
    return point.isValid ? point : null;
  }

  @override
  bool operator ==(Object other) =>
      other is GeoPoint &&
      other.latitude == latitude &&
      other.longitude == longitude &&
      other.accuracyMeters == accuracyMeters;

  @override
  int get hashCode => Object.hash(latitude, longitude, accuracyMeters);
}
