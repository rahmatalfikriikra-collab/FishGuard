import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// One maritime forecast area (`perairan`) from BMKG.
class BmkgAreaRef {
  const BmkgAreaRef({required this.id, required this.name, required this.province});

  final String id;
  final String name;
  final String province;

  @override
  String toString() => '$id $name';
}

/// Live client for BMKG's marine forecast, `https://maritim.bmkg.go.id/marine2026-data/`.
///
/// Endpoints used (all GET, JSON, no auth):
///  - `meta/area_province.json`         -> the 375 perairan, grouped by province
///  - `perairan/{ID}.json`              -> hourly wave/wind for one area
///  - `meta/wilmetos.min.geojson`       -> polygons keyed by the same ID
///  - `warning/warnings.json`           -> active warnings, by perairan name
///
/// The GeoJSON is what makes automatic area selection possible: a GPS fix is
/// matched against the polygons, so the sailor never has to know which BMKG
/// area they are standing in.
class BmkgService {
  BmkgService({http.Client? client, this.baseUrl = defaultBase})
      : _client = client ?? http.Client();

  static const String defaultBase = 'https://maritim.bmkg.go.id/marine2026-data';

  final http.Client _client;
  final String baseUrl;

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json',
    'User-Agent': 'FishGuard/1.0 (Flutter; nelayan BMKG client)',
  };

  List<BmkgAreaRef>? _areaCache;
  List<BmkgZone>? _zoneCache;

  /// perairan name -> worst active warning level, refreshed with [loadWarnings].
  Map<String, WarningLevel> _warningByArea = <String, WarningLevel>{};

  /// True once a bulletin has been read this session, so callers can tell
  /// "no warning" apart from "never checked".
  bool warningsLoaded = false;

  /// All forecast areas, flattened out of the province grouping.
  Future<List<BmkgAreaRef>> loadAreas({bool forceReload = false}) async {
    if (_areaCache != null && !forceReload) return _areaCache!;
    final http.Response res = await _get('$baseUrl/meta/area_province.json');
    final Map<String, dynamic> body = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> data = body['data'] as List<dynamic>? ?? <dynamic>[];

    final List<BmkgAreaRef> out = <BmkgAreaRef>[];
    for (final dynamic prov in data) {
      final Map<String, dynamic> p = prov as Map<String, dynamic>;
      final String province = p['province'] as String? ?? '';
      for (final dynamic a in p['areas'] as List<dynamic>? ?? <dynamic>[]) {
        final Map<String, dynamic> area = a as Map<String, dynamic>;
        final String? id = area['id'] as String?;
        if (id == null || id.isEmpty) continue;
        out.add(BmkgAreaRef(
          id: id,
          name: area['name'] as String? ?? id,
          province: province,
        ));
      }
    }
    _areaCache = out;
    return out;
  }

  /// Reads BMKG's active-warning bulletin and indexes it by perairan name.
  ///
  /// `warning/warnings.json` is keyed by province, and each province lists its
  /// warned perairan under `data.warning.{sedang,tinggi,sangat_tinggi,ekstrem}`.
  /// The names there are exactly the `name` values in `area_province.json`
  /// (checked: 96 of 96 warning names resolve to a published area), so a plain
  /// name lookup is enough — no fuzzy matching needed.
  ///
  /// A province can appear under several buckets; the worst one wins. An area
  /// that is absent from the bulletin gets [WarningLevel.none], which is a real
  /// answer, not a failure — that is why [warningsLoaded] exists.
  ///
  /// Throws [BmkgException] only when the bulletin cannot be fetched at all.
  Future<void> loadWarnings({bool forceReload = false}) async {
    if (warningsLoaded && !forceReload) return;

    final http.Response res = await _get('$baseUrl/warning/warnings.json');
    final Map<String, dynamic> body =
        jsonDecode(res.body) as Map<String, dynamic>;

    final Map<String, WarningLevel> byArea = <String, WarningLevel>{};
    for (final dynamic raw in body.values) {
      if (raw is! Map<String, dynamic>) continue;
      final dynamic data = raw['data'];
      if (data is! Map<String, dynamic>) continue;
      final dynamic warn = data['warning'];
      if (warn is! Map<String, dynamic>) continue;

      for (final MapEntry<String, dynamic> bucket in warn.entries) {
        final WarningLevel level = WarningLevel.fromKey(bucket.key);
        if (level == WarningLevel.none) continue;
        final dynamic list = bucket.value;
        if (list is! List) continue;
        for (final dynamic name in list) {
          if (name is! String || name.isEmpty) continue;
          final WarningLevel? seen = byArea[name];
          if (seen == null || level.index > seen.index) byArea[name] = level;
        }
      }
    }

    _warningByArea = byArea;
    warningsLoaded = true;
  }

  /// The active warning level BMKG published for a perairan, by its name.
  ///
  /// Returns [WarningLevel.none] when the area is not named in the bulletin.
  /// Call [loadWarnings] first; until then this cannot know and says `none`.
  WarningLevel warningFor(String areaName) =>
      _warningByArea[areaName] ?? WarningLevel.none;

  /// Wave/wind forecast for one area, converted into the app's model.
  ///
  /// BMKG timestamps are UTC (`2026-11-02 00:00 UTC`); they are converted to
  /// local time here so the rest of the app can compare against `DateTime.now()`
  /// without worrying about offsets.
  Future<WeatherArea> loadArea(String areaId, {String? fallbackName}) async {
    final http.Response res = await _get('$baseUrl/perairan/$areaId.json');
    final Map<String, dynamic> j = jsonDecode(res.body) as Map<String, dynamic>;

    final String name = j['name'] as String? ?? fallbackName ?? areaId;
    final String issued = j['issued'] as String? ?? '';
    final List<ForecastHour> hours = <ForecastHour>[];

    void addAll(dynamic list) {
      if (list is! List) return;
      for (final dynamic raw in list) {
        final Map<String, dynamic> h = raw as Map<String, dynamic>;
        final DateTime? time = _parseUtc(h['time'] as String?);
        if (time == null) continue;
        final String weather = h['weather'] as String? ?? 'Cerah';
        hours.add(ForecastHour(
          time: time,
          waveM: (h['wave_height'] as num?)?.toDouble() ?? 0,
          windKt: (h['wind_speed'] as num?)?.toDouble() ?? 0,
          condition: weather,
          windDir: h['wind_from'] as String? ?? 'Timur',
          hasThunder: _isThunder(weather),
          warning: '',
        ));
      }
    }

    addAll(j['forecast_day1']);
    addAll(j['forecast_day2-4']);
    hours.sort((ForecastHour a, ForecastHour b) => a.time.compareTo(b.time));

    // Prefer BMKG's own bulletin for this perairan. When the bulletin does not
    // name it, fall back to the thunderstorm text the forecast itself carries.
    final WarningLevel level = warningFor(name);
    final String warningText = level == WarningLevel.none
        ? _thunderWarning(hours)
        : 'BMKG menetapkan peringatan gelombang ${level.label} '
            'untuk $name.';

    return WeatherArea(
      code: areaId,
      name: name,
      hours: hours,
      fetchedAt: DateTime.now(),
      warning: warningText,
      warningLevel: level,
      issuedLabel: issued,
    );
  }

  /// Resolves the forecast area containing a position, or null when the point
  /// falls outside every published polygon (open sea, or outside Indonesia).
  Future<BmkgAreaRef?> areaForPosition(double lat, double lon) async {
    final List<BmkgZone> zones = await loadZones();
    for (final BmkgZone z in zones) {
      if (z.contains(lat, lon)) {
        return z.ref;
      }
    }
    return null;
  }

  /// Nearest area by centroid, as a fallback when a position is not inside any
  /// polygon â€” better than showing an arbitrary area.
  Future<BmkgAreaRef?> nearestArea(double lat, double lon) async {
    final List<BmkgZone> zones = await loadZones();
    BmkgAreaRef? best;
    double bestKm = double.infinity;
    for (final BmkgZone z in zones) {
      final double km = z.centroidKmTo(lat, lon);
      if (km < bestKm) {
        bestKm = km;
        best = z.ref;
      }
    }
    return best;
  }

  Future<List<BmkgZone>> loadZones() async {
    if (_zoneCache != null) return _zoneCache!;
    final http.Response res = await _get('$baseUrl/meta/wilmetos.min.geojson');
    final Map<String, dynamic> j = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> features = j['features'] as List<dynamic>? ?? <dynamic>[];

    final Map<String, String> names = <String, String>{};
    for (final BmkgAreaRef a in await loadAreas()) {
      names[a.id] = a.name;
    }

    final List<BmkgZone> zones = <BmkgZone>[];
    for (final dynamic f in features) {
      final Map<String, dynamic> feat = f as Map<String, dynamic>;
      final Map<String, dynamic> props =
          feat['properties'] as Map<String, dynamic>? ?? <String, dynamic>{};
      final String id = props['ID_MAR'] as String? ?? '';
      if (id.isEmpty) continue;
      final List<List<double>> ring = _outerRing(feat['geometry']);
      if (ring.length < 3) continue;
      zones.add(BmkgZone(
        ref: BmkgAreaRef(
          id: id,
          name: names[id] ?? props['perairan'] as String? ?? id,
          province: props['provinsi'] as String? ?? '',
        ),
        ring: ring,
      ));
    }
    _zoneCache = zones;
    return zones;
  }

  Future<http.Response> _get(String url) async {
    final http.Response res;
    try {
      res = await _client.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 30));
    } on Object catch (e) {
      throw BmkgException('Tidak bisa menghubungi BMKG. Periksa sinyal. ($e)');
    }
    if (res.statusCode != 200) {
      throw BmkgException('BMKG menjawab ${res.statusCode}.');
    }
    return res;
  }

  /// `"2026-11-02 00:00 UTC"` -> local [DateTime].
  static DateTime? _parseUtc(String? raw) {
    if (raw == null) return null;
    final String cleaned =
        raw.replaceAll(' UTC', '').trim().replaceFirst(' ', 'T');
    final DateTime? parsed = DateTime.tryParse('${cleaned}Z');
    return parsed?.toLocal();
  }

  static bool _isThunder(String weather) {
    final String w = weather.toLowerCase();
    return w.contains('petir') || w.contains('thunder') || w.contains('kilat');
  }

  /// BMKG puts thunderstorms in the `weather` field rather than a warning
  /// flag. A day containing them is surfaced as the area's warning text.
  static String _thunderWarning(List<ForecastHour> hours) {
    final DateTime now = DateTime.now();
    final Iterable<ForecastHour> next = hours.where((ForecastHour h) =>
        h.time.isAfter(now) &&
        h.time.isBefore(now.add(const Duration(hours: 12))) &&
        h.hasThunder);
    if (next.isEmpty) return '';
    final ForecastHour first = next.first;
    return 'BMKG meramalkan hujan petir di ${first.condition.toLowerCase()} '
        'sekitar jam ${first.time.hour.toString().padLeft(2, '0')}.00.';
  }

  /// First ring of a Polygon or MultiPolygon, as [lat, lon] pairs.
  static List<List<double>> _outerRing(dynamic geometry) {
    if (geometry is! Map<String, dynamic>) return const <List<double>>[];
    final String type = geometry['type'] as String? ?? '';
    final dynamic coords = geometry['coordinates'];
    List<dynamic>? ring;

    if (type == 'Polygon' && coords is List && coords.isNotEmpty) {
      ring = coords.first as List<dynamic>?;
    } else if (type == 'MultiPolygon' && coords is List && coords.isNotEmpty) {
      final List<dynamic> firstPoly = coords.first as List<dynamic>;
      ring = firstPoly.isNotEmpty ? firstPoly.first as List<dynamic>? : null;
    }
    if (ring == null) return const <List<double>>[];

    final List<List<double>> out = <List<double>>[];
    for (final dynamic point in ring) {
      if (point is! List || point.length < 2) continue;
      final double lon = (point[0] as num).toDouble();
      final double lat = (point[1] as num).toDouble();
      out.add(<double>[lat, lon]);
    }
    return out;
  }

  void dispose() => _client.close();
}

/// One GeoJSON polygon with the forecast area it belongs to.
class BmkgZone {
  BmkgZone({required this.ref, required this.ring});

  final BmkgAreaRef ref;

  /// `[lat, lon]` pairs, closed or not.
  final List<List<double>> ring;

  /// Ray casting on the longitude axis. Good enough for the coarse wilmetos
  /// boundaries; the app only needs "which forecast should I show".
  bool contains(double lat, double lon) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final double yi = ring[i][0], xi = ring[i][1];
      final double yj = ring[j][0], xj = ring[j][1];
      final bool crosses = (yi > lat) != (yj > lat) &&
          lon < (xj - xi) * (lat - yi) / ((yj - yi) + 1e-12) + xi;
      if (crosses) inside = !inside;
    }
    return inside;
  }

  /// Distance from the polygon's vertex average â€” used only to rank areas when
  /// a position falls outside every polygon.
  double centroidKmTo(double lat, double lon) {
    double sy = 0, sx = 0;
    for (final List<double> p in ring) {
      sy += p[0];
      sx += p[1];
    }
    final double cy = sy / ring.length;
    final double cx = sx / ring.length;
    return _haversineKm(cy, cx, lat, lon);
  }

  static double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0088;
    const double rad = math.pi / 180;
    final double p1 = lat1 * rad, p2 = lat2 * rad;
    final double dp = (lat2 - lat1) * rad;
    final double dl = (lon2 - lon1) * rad;
    final double sdp = math.sin(dp / 2), sdl = math.sin(dl / 2);
    final double a = sdp * sdp + math.cos(p1) * math.cos(p2) * sdl * sdl;
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}

/// A BMKG failure worth showing to the user.
class BmkgException implements Exception {
  const BmkgException(this.message);

  final String message;

  @override
  String toString() => message;
}
