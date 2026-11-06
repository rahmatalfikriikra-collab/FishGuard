// The "wajib unduh sebelum melaut" rule.
//
// What went wrong before: `markSynced()` set `lastSync = DateTime.now()` with
// no network call at all, and the freshness chip measured that timestamp. The
// app could therefore report "Data per 11.40, hari ini" after a "sync" that
// downloaded nothing, because the bundled pack was already on disk. A
// fisherman trusted that. These tests pin the fix.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/services/app_state.dart';
import 'package:fishguard_app/services/background_sync.dart';

/// A position with plenty of published points around it.
const double boatLat = -5.1;
const double boatLon = 119.4;

/// A cached BMKG forecast with hours still ahead of "now", which is the same
/// condition [AppState._restoreCachedWeather] applies before trusting it.
String _weatherCacheJson({DateTime? fetchedAt}) {
  final DateTime now = DateTime.now();
  final WeatherArea area = WeatherArea(
    code: 'P.AE.04',
    name: 'Perairan Makassar',
    fetchedAt: fetchedAt ?? now,
    live: true,
    hours: <ForecastHour>[
      for (int i = 0; i < 12; i++)
        ForecastHour(
          time: now.add(Duration(hours: i)),
          waveM: 0.4,
          windKt: 5,
          condition: 'Berawan',
        ),
    ],
  );
  return jsonEncode(area.toJson());
}

/// Everything a completed download leaves behind, and nothing else.
Map<String, Object> _downloaded({DateTime? at}) {
  final DateTime when = at ?? DateTime.now();
  return <String, Object>{
    kDpiFetchedAtKey: when.toIso8601String(),
    kDpiTableDateKey: when.toIso8601String(),
    'weatherFetchedAt': when.toIso8601String(),
    'bmkgAreaId': 'P.AE.04',
    'weatherCache': _weatherCacheJson(fetchedAt: when),
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  Future<AppState> freshState() async {
    final AppState s = AppState();
    await s.load();
    s.updatePosition(boatLat, boatLon);
    return s;
  }

  test('a fresh install is not ready for sea — nothing was downloaded',
      () async {
    final AppState s = await freshState();

    // The bundled pack is loaded and has real points in it...
    expect(s.dpiPoints, isNotEmpty);
    // ...and that is exactly why it used to look fine. It must not now.
    expect(s.dpiFetchedAt, isNull);
    expect(s.weatherFetchedAt, isNull);
    expect(s.readyForSea, isFalse);
    expect(s.departureBlockers.length, 2);
    expect(s.departureBlockers.first, contains('belum pernah diunduh'));
  });

  test('markSynced does not make undownloaded data look downloaded', () async {
    final AppState s = await freshState();
    expect(s.readyForSea, isFalse);

    await s.markSynced();

    // The checklist stages what is on disk; it must not move the download
    // timestamps, because it performs no download.
    expect(s.dpiFetchedAt, isNull);
    expect(s.weatherFetchedAt, isNull);
    expect(s.readyForSea, isFalse);
    // And the checklist must not claim the DPI item is done either.
    expect(s.prepReady(AppState.prepDpi), isFalse);
    expect(s.prepReady(AppState.prepCuaca), isFalse);
  });

  test('stale downloads are reported with their real date', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      ..._downloaded(at: DateTime.now().subtract(const Duration(days: 2))),
    });
    final AppState s = AppState();
    await s.load();
    s.updatePosition(boatLat, boatLon);

    expect(s.readyForSea, isFalse);
    expect(s.departureBlockers.length, 2);
    for (final String b in s.departureBlockers) {
      expect(b, contains('belum diunduh hari ini'));
    }
    // The three-colour rule must agree with the gate, not contradict it.
    expect(s.freshnessLevel, 2);
  });

  test("a background sync's download counts as today's data", () async {
    // The worker runs while the app is closed, so it writes the same keys the
    // foreground reads. A table it fetched must not be demanded again.
    SharedPreferences.setMockInitialValues(_downloaded());
    final AppState s = AppState();
    await s.load();
    s.updatePosition(boatLat, boatLon);

    expect(s.readyForSea, isTrue);
    expect(s.departureBlockers, isEmpty);
    expect(s.freshnessLevel, 0);
    expect(s.freshnessLabel, contains('siap'));

    // The checklist only goes green once it has been evaluated — and now it
    // can, because the underlying facts are true. Before the fix, markSynced()
    // made it green on a bundled pack with no download behind it.
    await s.markSynced();
    expect(s.prepReady(AppState.prepDpi), isTrue);
    expect(s.prepReady(AppState.prepCuaca), isTrue);
  });

  test('"hari ini" is judged on the WITA calendar, not the phone clock',
      () async {
    // A download made at 02:00 WITA today is today's, whatever the phone's
    // own zone is. Construct the UTC instant that is 02:00 WITA on the current
    // WITA date, so the assertion holds whenever the suite is run.
    final DateTime witaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final DateTime twoAmWita = DateTime.utc(
      witaNow.year,
      witaNow.month,
      witaNow.day,
      2,
    ).subtract(const Duration(hours: 8)); // WITA 02:00 == UTC previous 18:00

    SharedPreferences.setMockInitialValues(_downloaded(at: twoAmWita));
    final AppState s = AppState();
    await s.load();
    s.updatePosition(boatLat, boatLon);

    expect(
      s.dpiDownloadedToday,
      isTrue,
      reason: '02:00 WITA on the current WITA date is "today"',
    );
    expect(s.weatherDownloadedToday, isTrue);
    expect(s.readyForSea, isTrue);
  });

  test('a download from the previous WITA day does not count', () async {
    final DateTime witaNow = DateTime.now().toUtc().add(const Duration(hours: 8));
    final DateTime lateYesterdayWita = DateTime.utc(
      witaNow.year,
      witaNow.month,
      witaNow.day,
      0,
    ).subtract(const Duration(hours: 9)); // 23:00 WITA yesterday

    SharedPreferences.setMockInitialValues(_downloaded(at: lateYesterdayWita));
    final AppState s = AppState();
    await s.load();
    s.updatePosition(boatLat, boatLon);

    expect(s.dpiDownloadedToday, isFalse);
    expect(s.weatherDownloadedToday, isFalse);
    expect(s.readyForSea, isFalse);
  });

  test('zoneHere resolves from the real points, not the box heuristic',
      () async {
    final AppState s = await freshState();
    expect(s.zoneHere, isNotNull);
    expect(s.zoneHere!.kode, '713');
  });

  test('readiness flips the moment both downloads land', () async {
    final AppState s = await freshState();
    expect(s.readyForSea, isFalse);

    // Simulate the two fetches succeeding, which is what the real ones do on
    // their success paths.
    s.dpiFetchedAt = DateTime.now();
    s.weatherFetchedAt = DateTime.now();
    // A bare timestamp is not enough for weather — there must be a usable
    // forecast behind it, or the app would claim ready with nothing to show.
    expect(s.weatherDownloadedToday, isFalse);

    s.weatherAreas = <WeatherArea>[
      WeatherArea(
        code: 'P.AE.04',
        name: 'Perairan Makassar',
        fetchedAt: DateTime.now(),
        live: true,
        hours: <ForecastHour>[
          ForecastHour(
            time: DateTime.now().add(const Duration(hours: 1)),
            waveM: 0.4,
            windKt: 5,
            condition: 'Berawan',
          ),
        ],
      ),
    ];
    expect(s.readyForSea, isTrue);

    // Either one alone is still not enough.
    s.weatherFetchedAt = null;
    expect(s.readyForSea, isFalse);
    expect(s.departureBlockers.single, contains('BMKG'));
  });
}
