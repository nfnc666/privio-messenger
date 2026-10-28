import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/geo_point.dart';

/// What came back from asking the phone where it is.
///
/// A sealed set, like the address book's, because each answer calls for a
/// different sentence: a place to show before sending, the way to the system
/// settings, or "not right now".
@immutable
sealed class LocationRead {
  const LocationRead();
}

/// One position, measured now.
class LocationFix extends LocationRead {
  const LocationFix(this.point);

  final GeoPoint point;
}

/// The person said no, or the system had already recorded a no.
class LocationDenied extends LocationRead {
  const LocationDenied();
}

/// Allowed, but no position came: location is switched off for the whole
/// phone, or nothing answered in time.
class LocationUnavailable extends LocationRead {
  const LocationUnavailable();
}

/// This build has no way to ask: the web build, or a channel that is not there.
class LocationUnsupported extends LocationRead {
  const LocationUnsupported();
}

/// Where the phone is, behind an interface, for the same reason the address
/// book has one: every answer, the refusal included, has to be reachable in a
/// test, and none of it can be exercised on a machine with no phone attached.
abstract interface class DeviceLocation {
  /// Asks the operating system for one position, now.
  ///
  /// **The permission is requested at the moment this is called**, which is
  /// the moment somebody chose to share a place. Never at start, never on a
  /// settings screen. Only while the app is in use, never in the background,
  /// and one position rather than a stream: there is no live location here.
  Future<LocationRead> current();
}

/// What a build with no location integration reports.
class NoDeviceLocation implements DeviceLocation {
  const NoDeviceLocation();

  @override
  Future<LocationRead> current() async => const LocationUnsupported();
}

/// Asks the platform over a method channel.
///
/// The native halves are `LocationReader.kt` and `LocationReader.swift`, on
/// the platform's own location API: no Google Play services, so the Libre
/// build can carry it.
class ChannelDeviceLocation implements DeviceLocation {
  const ChannelDeviceLocation([
    this._channel = const MethodChannel('app.privio/location'),
  ]);

  final MethodChannel _channel;

  @override
  Future<LocationRead> current() async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>('current');
      final latitude = raw?['latitude'];
      final longitude = raw?['longitude'];
      if (latitude is! num || longitude is! num) return const LocationUnavailable();
      final accuracy = raw?['accuracy'];
      final point = GeoPoint(
        latitude: latitude.toDouble(),
        longitude: longitude.toDouble(),
        accuracyMeters: accuracy is num ? accuracy.round() : null,
      );
      return point.isValid ? LocationFix(point) : const LocationUnavailable();
    } on MissingPluginException {
      return const LocationUnsupported();
    } on PlatformException catch (error) {
      // The two codes the native halves raise on purpose. Anything else is a
      // phone that could not answer, which must not be reported as a refusal:
      // a refusal sends somebody to a settings switch that is already on.
      return error.code == 'permission_denied'
          ? const LocationDenied()
          : const LocationUnavailable();
    }
  }
}
