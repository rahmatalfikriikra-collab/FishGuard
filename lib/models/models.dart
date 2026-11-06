import 'dart:math' as math;

/// Sea-state status derived from BMKG maritime forecasts.
/// Rules (PRD 6): evaluated for the user's water area, taking the worst value
/// in the next 6 hours.
///  - TIDAK LAYAK : wave >= 1.25 m, or wind >= 15 kt, or an active BMKG warning
///  - WASPADA     : wave 0.75-1.25 m, or wind 10-15 kt, or thunderstorm forecast
///  - LAYAK        : everything else
enum SeaStatus { layak, waspada, tidakLayak }

extension SeaStatusX on SeaStatus {
  String get label => switch (this) {
        SeaStatus.layak => 'LAYAK MELAUT',
        SeaStatus.waspada => 'WASPADA',
        SeaStatus.tidakLayak => 'TIDAK LAYAK MELAUT',
      };

  String get shortLabel => switch (this) {
        SeaStatus.layak => 'LAYAK',
        SeaStatus.waspada => 'WASPADA',
        SeaStatus.tidakLayak => 'TIDAK LAYAK',
      };

  String get advice => switch (this) {
        SeaStatus.layak =>
          'Kondisi perairan relatif aman untuk perahu kecil. Tetap pantau langit dan informasi BMKG.',
        SeaStatus.waspada =>
          'Hati-hati. Gelombang atau angin mulai meningkat. Pertimbangkan jenis perahu dan pengalaman Anda.',
        SeaStatus.tidakLayak =>
          'Sebaiknya jangan melaut hari ini. Risiko gelombang/angin tinggi untuk perahu kecil.',
      };

  /// PRD: status must not be conveyed by colour alone.
  String get iconName => switch (this) {
        SeaStatus.layak => 'check_circle',
        SeaStatus.waspada => 'warning_amber',
        SeaStatus.tidakLayak => 'dangerous',
      };
}

/// One hour of the stored maritime forecast.
class ForecastHour {
  const ForecastHour({
    required this.time,
    required this.waveM,
    required this.windKt,
    required this.condition,
    this.windDir = 'Timur',
    this.hasThunder = false,
    this.warning = '',
  });

  final DateTime time;
  final double waveM;
  final double windKt;
  final String condition;
  final String windDir;
  final bool hasThunder;
  final String warning;

  Map<String, dynamic> toJson() => {
        't': time.toIso8601String(),
        'w': waveM,
        'k': windKt,
        'c': condition,
        'd': windDir,
        'th': hasThunder,
        'wn': warning,
      };

  factory ForecastHour.fromJson(Map<String, dynamic> j) => ForecastHour(
        time: DateTime.parse(j['t'] as String),
        waveM: (j['w'] as num).toDouble(),
        windKt: (j['k'] as num).toDouble(),
        condition: j['c'] as String? ?? 'Cerah',
        windDir: j['d'] as String? ?? 'Timur',
        hasThunder: j['th'] as bool? ?? false,
        warning: j['wn'] as String? ?? '',
      );
}

/// Severity buckets used by BMKG's `warning/warnings.json`.
///
/// BMKG publishes each active warning under one of `sedang`, `tinggi`,
/// `sangat_tinggi` or `ekstrem`. `none` means the area is not listed at all.
enum WarningLevel {
  none,
  sedang,
  tinggi,
  sangatTinggi,
  ekstrem;

  static WarningLevel fromKey(String key) => switch (key) {
        'sedang' => WarningLevel.sedang,
        'tinggi' => WarningLevel.tinggi,
        'sangat_tinggi' => WarningLevel.sangatTinggi,
        'ekstrem' => WarningLevel.ekstrem,
        _ => WarningLevel.none,
      };

  String get label => switch (this) {
        WarningLevel.none => '',
        WarningLevel.sedang => 'sedang',
        WarningLevel.tinggi => 'tinggi',
        WarningLevel.sangatTinggi => 'sangat tinggi',
        WarningLevel.ekstrem => 'ekstrem',
      };
}

/// A BMKG water area (perairan) with its stored forecast.
class WeatherArea {
  const WeatherArea({
    required this.code,
    required this.name,
    required this.hours,
    required this.fetchedAt,
    this.warning = '',
    this.warningLevel = WarningLevel.none,
    this.issuedLabel = '',
    this.live = false,
  });

  final String code;
  final String name;
  final List<ForecastHour> hours;
  final DateTime fetchedAt;
  final String warning;

  /// Severity of [warning] as BMKG published it. `none` when the area is not
  /// named in any active warning bulletin.
  final WarningLevel warningLevel;

  /// BMKG's own issue stamp, e.g. `2026-11-01 12:00 UTC`. Empty for the
  /// bundled snapshot, which carries no such field.
  final String issuedLabel;

  /// True when this came from a live BMKG call rather than `assets/data`.
  final bool live;

  /// Worst-case evaluation over the next [lookaheadHours] hours (PRD: 6 h).
  SeaStatus statusNow({DateTime? now, int lookaheadHours = 6}) {
    final DateTime t = now ?? DateTime.now();
    final List<ForecastHour> window = hours
        .where((ForecastHour h) =>
            h.time.isAfter(t.subtract(const Duration(hours: 1))) &&
            h.time.isBefore(t.add(Duration(hours: lookaheadHours))))
        .toList();
    final List<ForecastHour> use = window.isEmpty ? hours.take(2).toList() : window;
    if (use.isEmpty) return SeaStatus.waspada;

    for (final ForecastHour h in use) {
      if (h.waveM >= 1.25 || h.windKt >= 15 || h.warning.isNotEmpty) {
        return SeaStatus.tidakLayak;
      }
    }
    // BMKG's own bulletin outranks the numbers: a "sedang" (moderate) alert is
    // at least WASPADA, and "tinggi" upward is TIDAK LAYAK. A warning that is
    // present but carries no severity still blocks, as before.
    if (warningLevel == WarningLevel.tinggi ||
        warningLevel == WarningLevel.sangatTinggi ||
        warningLevel == WarningLevel.ekstrem) {
      return SeaStatus.tidakLayak;
    }
    if (warningLevel == WarningLevel.sedang) return SeaStatus.waspada;
    if (warning.isNotEmpty) return SeaStatus.tidakLayak;

    for (final ForecastHour h in use) {
      if (h.waveM >= 0.75 || h.windKt >= 10 || h.hasThunder) {
        return SeaStatus.waspada;
      }
    }
    return SeaStatus.layak;
  }

  /// The representative hour for "right now" (nearest forecast slot).
  ForecastHour currentHour({DateTime? now}) {
    final DateTime t = now ?? DateTime.now();
    if (hours.isEmpty) {
      return ForecastHour(
        time: t,
        waveM: 0,
        windKt: 0,
        condition: 'Tidak ada data',
      );
    }
    ForecastHour best = hours.first;
    int bestDelta = 1 << 30;
    for (final ForecastHour h in hours) {
      final int d = h.time.difference(t).inMinutes.abs();
      if (d < bestDelta) {
        bestDelta = d;
        best = h;
      }
    }
    return best;
  }

  String get waveRange {
    if (hours.isEmpty) return '-';
    final double lo = hours.map((ForecastHour h) => h.waveM).reduce(math.min);
    final double hi = hours.map((ForecastHour h) => h.waveM).reduce(math.max);
    if ((hi - lo).abs() < 0.05) return '${_fmt(lo)} m';
    return '${_fmt(lo)} - ${_fmt(hi)} m';
  }

  String get windRange {
    if (hours.isEmpty) return '-';
    final double lo = hours.map((ForecastHour h) => h.windKt).reduce(math.min);
    final double hi = hours.map((ForecastHour h) => h.windKt).reduce(math.max);
    if ((hi - lo).abs() < 0.5) return '${_fmt(lo)} knot';
    return '${_fmt(lo)} - ${_fmt(hi)} knot';
  }

  /// Data older than 6 h is labelled "data lama" (PRD HOME-4).
  bool isStale({DateTime? now}) =>
      (now ?? DateTime.now()).difference(fetchedAt).inHours >= 6;

  /// PRD PREP-6 freshness indicator thresholds.
  Duration get age => DateTime.now().difference(fetchedAt);

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'fetched': fetchedAt.toIso8601String(),
        'warning': warning,
        'warnLevel': warningLevel.name,
        'issued': issuedLabel,
        'live': live,
        'hours': hours.map((ForecastHour h) => h.toJson()).toList(),
      };

  factory WeatherArea.fromJson(Map<String, dynamic> j) => WeatherArea(
        code: j['code'] as String,
        name: j['name'] as String,
        fetchedAt: DateTime.parse(j['fetched'] as String),
        warning: j['warning'] as String? ?? '',
        warningLevel: WarningLevel.values.firstWhere(
          (WarningLevel l) => l.name == j['warnLevel'],
          orElse: () => WarningLevel.none,
        ),
        issuedLabel: j['issued'] as String? ?? '',
        live: j['live'] as bool? ?? false,
        hours: (j['hours'] as List<dynamic>)
            .map((dynamic e) => ForecastHour.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

String _fmt(double v) {
  final String s = v.toStringAsFixed(1);
  return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
}

String formatDecimal(double v) => v.toStringAsFixed(6);

/// A fishing spot the sailor marked himself (PRD MAP-6).
///
/// Deliberately separate from [DpiPoint]: a DPI point is the government's
/// recommendation for a day, this is the sailor's own memory of where the fish
/// were. They never overwrite each other and never share a marker style.
class OwnSpot {
  const OwnSpot({
    required this.id,
    required this.lat,
    required this.lon,
    required this.createdAt,
    this.name = '',
    this.note = '',
  });

  final String id;
  final double lat;
  final double lon;
  final DateTime createdAt;
  final String name;
  final String note;

  /// What the list and the marker call it. A spot with no name still needs
  /// something the sailor recognises, so the coordinates stand in.
  String get label => name.trim().isNotEmpty
      ? name.trim()
      : '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

  /// Distance in km from this spot to a position (haversine).
  double distanceKmTo(double lat2, double lon2) {
    const double r = 6371.0088;
    final double p1 = lat * math.pi / 180;
    final double p2 = lat2 * math.pi / 180;
    final double dp = (lat2 - lat) * math.pi / 180;
    final double dl = (lon2 - lon) * math.pi / 180;
    final double a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Compass bearing seen from another position looking at this spot
  /// (0 = north, clockwise) — the direction the sailor must steer.
  double bearingFrom(double fromLat, double fromLon) {
    final double p1 = fromLat * math.pi / 180;
    final double p2 = lat * math.pi / 180;
    final double dl = (lon - fromLon) * math.pi / 180;
    final double y = math.sin(dl) * math.cos(p2);
    final double x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'lat': lat,
        'lon': lon,
        'createdAt': createdAt.toIso8601String(),
        'name': name,
        'note': note,
      };

  factory OwnSpot.fromJson(Map<String, dynamic> j) => OwnSpot(
        id: j['id'] as String,
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        createdAt:
            DateTime.tryParse(j['createdAt'] as String? ?? '') ?? DateTime.now(),
        name: j['name'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

/// Extracted from the PDPI table image by the worker (see pdpi_worker.py).
/// The app never talks to the KKP portal: it reads the worker's GeoJSON.
class DpiPoint {
  const DpiPoint({
    required this.nomor,
    required this.lat,
    required this.lon,
    required this.lonDms,
    required this.latDms,
    required this.wpp,
    required this.date,
    this.ocrConf = 100,
    this.sourceUrl = '',
    this.onLand = false,
  });

  final int nomor;
  final double lat;
  final double lon;
  final String lonDms;
  final String latDms;
  final String wpp;
  final DateTime date;
  final double ocrConf;
  final String sourceUrl;

  /// True when the point KKP printed falls on land according to the bundled
  /// land mask. Such a point is still KKP's published coordinate — it is
  /// shown, but marked, never presented as ordinary fishing ground.
  final bool onLand;

  /// Distance in km to a position (haversine).
  double distanceKmTo(double lat2, double lon2) {
    const double r = 6371.0088;
    final double p1 = lat * math.pi / 180;
    final double p2 = lat2 * math.pi / 180;
    final double dp = (lat2 - lat) * math.pi / 180;
    final double dl = (lon2 - lon) * math.pi / 180;
    final double a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Initial bearing in degrees (0 = north, clockwise).
  double bearingTo(double lat2, double lon2) {
    final double p1 = lat * math.pi / 180;
    final double p2 = lat2 * math.pi / 180;
    final double dl = (lon2 - lon) * math.pi / 180;
    final double y = math.sin(dl) * math.cos(p2);
    final double x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  Map<String, dynamic> toGeoJson() => {
        'type': 'Feature',
        'geometry': {
          'type': 'Point',
          'coordinates': [lon, lat],
        },
        'properties': {
          'nomor': nomor,
          'wpp': wpp,
          'tanggal': date.toIso8601String().substring(0, 10),
          'lon_dms': lonDms,
          'lat_dms': latDms,
          'ocr_conf': ocrConf,
          'sumber': sourceUrl,
        },
      };

  factory DpiPoint.fromGeoJson(Map<String, dynamic> j) {
    final Map<String, dynamic> g = j['geometry'] as Map<String, dynamic>;
    final List<dynamic> coords = g['coordinates'] as List<dynamic>;
    final Map<String, dynamic> p = j['properties'] as Map<String, dynamic>;
    return DpiPoint(
      nomor: (p['nomor'] as num).toInt(),
      lon: (coords[0] as num).toDouble(),
      lat: (coords[1] as num).toDouble(),
      lonDms: p['lon_dms'] as String? ?? '',
      latDms: p['lat_dms'] as String? ?? '',
      wpp: p['wpp'] as String? ?? '713',
      date: DateTime.parse('${p['tanggal']}T00:00:00'),
      ocrConf: (p['ocr_conf'] as num?)?.toDouble() ?? 100,
      sourceUrl: p['sumber'] as String? ?? '',
      onLand: p['di_darat'] as bool? ?? false,
    );
  }

  factory DpiPoint.fromJson(Map<String, dynamic> j) => DpiPoint(
        nomor: (j['nomor'] as num).toInt(),
        lat: (j['lat'] as num).toDouble(),
        lon: (j['lon'] as num).toDouble(),
        lonDms: j['lonDms'] as String? ?? '',
        latDms: j['latDms'] as String? ?? '',
        wpp: j['wpp'] as String? ?? '713',
        date: DateTime.parse(j['date'] as String),
        ocrConf: (j['ocrConf'] as num?)?.toDouble() ?? 100,
        sourceUrl: j['sourceUrl'] as String? ?? '',
        onLand: j['onLand'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'nomor': nomor,
        'lat': lat,
        'lon': lon,
        'lonDms': lonDms,
        'latDms': latDms,
        'wpp': wpp,
        'date': date.toIso8601String(),
        'ocrConf': ocrConf,
        'sourceUrl': sourceUrl,
        'onLand': onLand,
      };

  /// Copy with a freshly computed [onLand], used when the mask becomes
  /// available after the points were already loaded from cache.
  DpiPoint withLandFlag(bool value) => DpiPoint(
        nomor: nomor,
        lat: lat,
        lon: lon,
        lonDms: lonDms,
        latDms: latDms,
        wpp: wpp,
        date: date,
        ocrConf: ocrConf,
        sourceUrl: sourceUrl,
        onLand: value,
      );
}

/// Bearing -> Indonesian compass label.
String bearingLabel(double deg) {
  const List<String> names = <String>[
    'Utara', 'Timur Laut', 'Timur', 'Tenggara',
    'Selatan', 'Barat Daya', 'Barat', 'Barat Laut',
  ];
  final int idx = (((deg % 360) + 360) % 360 / 45).round() % 8;
  return names[idx];
}

bool samaHari(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String dua(int v) => v.toString().padLeft(2, '0');

String formatTanggal(DateTime d) {
  const List<String> bulan = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun',
    'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
  ];
  return '${d.day} ${bulan[d.month - 1]} ${d.year}';
}

String formatJam(DateTime d) => '${dua(d.hour)}.${dua(d.minute)} WITA';

String formatJarak(double km) {
  if (km < 10) return '${km.toStringAsFixed(1)} km';
  return '${km.toStringAsFixed(0)} km';
}

String formatDurasi(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  if (h == 0) return '$m menit';
  if (m == 0) return '$h jam';
  return '$h jam $m menit';
}

/// What kind of thing is waiting to be uploaded (PRD PREP-9).
enum OutboxKind { jejak, tangkapan, umpanBalik }

extension OutboxKindX on OutboxKind {
  String get label => switch (this) {
        OutboxKind.jejak => 'Jejak pelayaran',
        OutboxKind.tangkapan => 'Laporan tangkapan',
        OutboxKind.umpanBalik => 'Umpan balik DPI',
      };

  String get key => switch (this) {
        OutboxKind.jejak => 'jejak',
        OutboxKind.tangkapan => 'tangkapan',
        OutboxKind.umpanBalik => 'umpan_balik',
      };

  static OutboxKind fromKey(String? k) => switch (k) {
        'jejak' => OutboxKind.jejak,
        'umpan_balik' => OutboxKind.umpanBalik,
        _ => OutboxKind.tangkapan,
      };
}

/// One item waiting to be uploaded once there is a signal (PRD PREP-9).
///
/// Persisted, so a queue survives the app closing or the phone dying — the
/// sailor can confirm that nothing recorded at sea was silently lost.
class OutboxItem {
  OutboxItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.payload,
    this.attempts = 0,
    this.lastError = '',
    this.deliveredAt,
  });

  final String id;
  final OutboxKind kind;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  int attempts;
  String lastError;
  DateTime? deliveredAt;

  bool get delivered => deliveredAt != null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'kind': kind.key,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        'attempts': attempts,
        'lastError': lastError,
        'deliveredAt': deliveredAt?.toIso8601String(),
      };

  factory OutboxItem.fromJson(Map<String, dynamic> j) => OutboxItem(
        id: j['id'] as String? ?? '',
        kind: OutboxKindX.fromKey(j['kind'] as String?),
        createdAt: DateTime.tryParse(j['createdAt'] as String? ?? '') ??
            DateTime.now(),
        payload: (j['payload'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        attempts: (j['attempts'] as num?)?.toInt() ?? 0,
        lastError: j['lastError'] as String? ?? '',
        deliveredAt: DateTime.tryParse(j['deliveredAt'] as String? ?? ''),
      );
}
