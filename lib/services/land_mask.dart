import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

/// Answers "is this position on land?" from a bundled bitmap.
///
/// Why this exists: the KKP DPI table is a list of coordinates, not a chart.
/// A point can be printed slightly inland — one real table does exactly that,
/// putting point 40 of WPP 573 on the south coast of Lombok. Drawing such a
/// point as if it were fishing ground tells a sailor to steer into a beach.
/// The app cannot edit KKP's data, but it can refuse to present an inland
/// point as a fishing ground, and say why.
///
/// The mask is generated once by `tool/real/build_real_data.dart` from Natural
/// Earth's 1:10m and 1:50m land polygons, rasterised at 0.015° (~1.7 km) over
/// 90°E..145°E, 15°S..9°N. It ships as `assets/data/land_mask.bin` and costs
/// 733 KB — small enough for a phone, precise enough to catch a coastal point
/// without erasing the genuine offshore ones.
///
/// The grid is deliberately coarse relative to the coast: a point within a
/// couple of kilometres of the shoreline may fall on either side. That is the
/// right bias here, because a false "on land" only costs a warning, while a
/// false "at sea" is the failure being fixed.
class LandMask {
  LandMask._(this._width, this._height, this._bits);

  static const double minLat = -15.0;
  static const double maxLat = 9.0;
  static const double minLon = 90.0;
  static const double maxLon = 145.0;
  static const double cellDeg = 0.015;

  static const String assetPath = 'assets/data/land_mask.bin';

  final int _width;
  final int _height;
  final Uint8List _bits;

  static LandMask? _instance;
  static bool _tried = false;

  /// The shared mask, loaded on first use. Returns null when the asset is
  /// missing, in which case callers must behave as if no mask exists rather
  /// than guess.
  static Future<LandMask?> instance() async {
    if (_tried) return _instance;
    _tried = true;
    try {
      final ByteData data = await rootBundle.load(assetPath);
      final Uint8List bits = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      // Dimensions are derived, not stored: the asset is the raw bit array, so
      // a stale asset is caught by the size check below instead of silently
      // shifting every cell.
      final int w = ((maxLon - minLon) / cellDeg).ceil();
      final int h = ((maxLat - minLat) / cellDeg).ceil();
      if (bits.length < (w * h + 7) >> 3) return null;
      _instance = LandMask._(w, h, bits);
      return _instance;
    } catch (_) {
      return null;
    }
  }

  /// Synchronous lookup; only valid after [instance] has completed once.
  static LandMask? get loaded => _instance;

  /// True when the cell containing [lat]/[lon] is land.
  ///
  /// Positions outside the mask's box return false: the mask covers all
  /// Indonesian waters, so anything outside it is not a case the app handles.
  bool isLand(double lat, double lon) {
    if (lat < minLat || lat > maxLat || lon < minLon || lon > maxLon) {
      return false;
    }
    final int x = ((lon - minLon) / cellDeg).floor();
    final int y = ((maxLat - lat) / cellDeg).floor();
    if (x < 0 || y < 0 || x >= _width || y >= _height) return false;
    final int i = y * _width + x;
    final int byte = i >> 3;
    if (byte >= _bits.length) return false;
    return (_bits[byte] & (1 << (i & 7))) != 0;
  }

  /// True when the position is water, or when no mask is available to say
  /// otherwise. Use this for filtering; use [isLand] only when a missing mask
  /// must be reported.
  static bool isSea(double lat, double lon) {
    final LandMask? m = _instance;
    if (m == null) return true;
    return !m.isLand(lat, lon);
  }
}
