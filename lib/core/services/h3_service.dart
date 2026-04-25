import 'package:h3_flutter/h3_flutter.dart';

class H3Service {
  static H3? _h3;
  static bool _nativeLibLoaded = false;
  
  static void _init() {
    if (_h3 != null) return;
    try {
      _h3 = H3Factory().load();
      _nativeLibLoaded = true;
    } catch (e) {
      // Fallback for 16KB Page Size or other native library issues
      _h3 = null;
      _nativeLibLoaded = false;
    }
  }
  
  static const int defaultResolution = 12;

  /// Converts a latitude/longitude to an H3 Hexagon ID.
  static String getHex(double lat, double lng, {int resolution = defaultResolution}) {
    _init();
    if (!_nativeLibLoaded) {
      // Deterministic string-based fallback for demo stability
      return 'ZONE-${(lat * 1000).toInt()}-${(lng * 1000).toInt()}';
    }
    try {
      final h3Index = _h3!.geoToCell(GeoCoord(lat: lat, lon: lng), resolution);
      return h3Index.toRadixString(16);
    } catch (e) {
      return 'unknown_hex';
    }
  }

  /// Calculates the grid distance (number of hexagons) between two hex IDs.
  static int getDistance(String hex1, String hex2) {
    _init();
    if (!_nativeLibLoaded) return -1;
    try {
      if (hex1 == 'unknown_hex' || hex2 == 'unknown_hex') return -1;
      return _h3!.gridDistance(
        BigInt.parse(hex1, radix: 16),
        BigInt.parse(hex2, radix: 16),
      );
    } catch (e) {
      return -1;
    }
  }

  /// Returns a human-readable "Zone Name" based on the Hex ID.
  static String getZoneName(String hexId) {
    if (hexId == 'unknown_hex') return 'Finding Zone...';
    return 'HEX-${hexId.toUpperCase()}';
  }
}

