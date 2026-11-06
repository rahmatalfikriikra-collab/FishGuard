import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'kkp_pdpi_service.dart';

/// Keys the background worker reads. The worker runs in its own isolate with
/// no `AppState`, so the storage contract lives here, in one place, instead of
/// being duplicated in two files that could drift apart.
const String kDpiCacheKey = 'dpiCache';
const String kBgZoneKey = 'bgSyncZone';
const String kLastSyncKey = 'lastSync';

/// When the KKP table in [kDpiCacheKey] was downloaded, and the date of the
/// table itself. Written by whoever performs the download — the foreground
/// [AppState] or the headless worker below — and read by both, so a table that
/// arrived while the app was closed still counts as today's data.
const String kDpiFetchedAtKey = 'dpiFetchedAt';
const String kDpiTableDateKey = 'dpiTableDate';

/// What the on-disk DPI cache looks like: `{saved, points[]}`.
///
/// Shared by the foreground [AppState] and the background worker so a table
/// written by one is read correctly by the other.
class DpiCache {
  const DpiCache({required this.saved, required this.points});

  final DateTime saved;
  final List<DpiPoint> points;

  static DpiCache? parse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      final List<DpiPoint> points = (j['points'] as List<dynamic>)
          .map((dynamic e) => DpiPoint.fromJson(e as Map<String, dynamic>))
          .toList();
      if (points.isEmpty) return null;
      return DpiCache(
        saved: DateTime.tryParse(j['saved'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        points: points,
      );
    } on Object {
      // A corrupt cache must never block the app or the worker.
      return null;
    }
  }

  String encode() => jsonEncode(<String, dynamic>{
        'saved': saved.toIso8601String(),
        'points': points.map((DpiPoint p) => p.toJson()).toList(),
      });

  /// Newest table date stored for [wpp], or null when nothing is stored.
  DateTime? newestDateFor(String wpp) {
    DateTime? newest;
    for (final DpiPoint p in points) {
      if (p.wpp != wpp) continue;
      if (newest == null || p.date.isAfter(newest)) newest = p.date;
    }
    return newest;
  }
}

/// Result of one background sync attempt.
class BgSyncOutcome {
  const BgSyncOutcome({required this.changed, required this.points, this.error});

  /// True when a newer table was downloaded and written to the cache.
  final bool changed;

  /// How many points the cache holds after the run.
  final int points;

  final String? error;

  static const BgSyncOutcome nothing = BgSyncOutcome(changed: false, points: 0);
}

/// Downloads today's KKP DPI table when it is newer than the one on disk
/// (PRD PREP-3: "dimulai begitu data DPI hari itu terbit, tanpa menunggu
/// aplikasi dibuka").
///
/// Runs headless from the WorkManager isolate, so it builds its own service
/// and reads/writes `shared_preferences` directly rather than touching
/// [AppState] — which belongs to the UI isolate.
///
/// Cost control matters here: the job fires every six hours, and KKP publishes
/// roughly once a day. [KkpPdpiService.latestAvailableDate] answers "is there
/// something newer?" with one or two cheap JSON requests, and the expensive
/// part (a ~330 KB image plus a ~2 s OCR pass) only runs when the answer is
/// yes — so most runs cost a few kilobytes and a couple of seconds.
Future<BgSyncOutcome> backgroundSync({KkpPdpiService? service}) async {
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final String zoneCode = prefs.getString(kBgZoneKey) ?? '';
  if (zoneCode.isEmpty) return BgSyncOutcome.nothing;

  final WppZone? zone = WppZone.byKode(zoneCode);
  if (zone == null) {
    return BgSyncOutcome(changed: false, points: 0, error: 'Zona $zoneCode tidak dikenal.');
  }

  final KkpPdpiService kkp = service ?? KkpPdpiService();
  try {
    final DateTime? latest = await kkp.latestAvailableDate(zone);
    if (latest == null) return BgSyncOutcome.nothing;

    final DpiCache? cached = DpiCache.parse(prefs.getString(kDpiCacheKey));
    final DateTime? stored = cached?.newestDateFor(zone.kode);
    if (stored != null && !latest.isAfter(stored)) {
      // Already have today's table: nothing to download, nothing to notify.
      return BgSyncOutcome(changed: false, points: cached?.points.length ?? 0);
    }

    final DpiFetchResult result = await kkp.fetchAndOcr(zone, latest);
    if (result.rows.isEmpty) {
      return BgSyncOutcome(
        changed: false,
        points: cached?.points.length ?? 0,
        error: result.error ?? 'Tabel kosong.',
      );
    }

    // Replace this zone's points, keep whatever other zones are stored — the
    // same merge rule the foreground fetch uses, so the map never shows two
    // different point 7s at once.
    final List<DpiPoint> merged = <DpiPoint>[
      ...result.toPoints(),
      ...?cached?.points.where((DpiPoint p) => p.wpp != zone.kode),
    ];

    final DateTime now = DateTime.now();
    final DpiCache next = DpiCache(saved: now, points: merged);
    await prefs.setString(kDpiCacheKey, next.encode());
    await prefs.setString(kLastSyncKey, now.toIso8601String());
    // Record the download so the app, on its next launch, knows today's table
    // is already on the phone and does not ask the sailor to fetch it again.
    await prefs.setString(kDpiFetchedAtKey, now.toIso8601String());
    await prefs.setString(kDpiTableDateKey, latest.toIso8601String());
    return BgSyncOutcome(changed: true, points: merged.length);
  } on PdpiException catch (e) {
    return BgSyncOutcome(
      changed: false,
      points: 0,
      error: e.message,
    );
  } on Object catch (e) {
    // No signal, DNS failure, portal down: WorkManager retries on backoff.
    return BgSyncOutcome(changed: false, points: 0, error: '$e');
  } finally {
    kkp.dispose();
  }
}
