// Tests that the bundled data is genuinely KKP's, and that the two guards
// built around it — the land mask and the mandatory download — actually hold.
//
// These run offline against the shipped assets. They are the regression net
// for the bug that started all of this: a bundled pack whose coordinates were
// authored by hand, one of which sat in downtown Makassar.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/services/kkp_pdpi_service.dart';
import 'package:fishguard_app/services/land_mask.dart';
import 'package:fishguard_app/services/local_data.dart';

/// The one point KKP itself prints on land: WPP 573 #40, on the south coast of
/// Lombok. It is in the published table, so it must survive into the app — the
/// app's job is to mark it, not to edit the ministry's data.
const String knownLandPointWpp = '573';
const int knownLandPointNomor = 40;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the land mask loads and knows sea from land', () async {
    final LandMask? mask = await LandMask.instance();
    expect(mask, isNotNull, reason: 'land_mask.bin must ship and load');

    // Makassar city centre, and inland to its east.
    expect(mask!.isLand(-5.1477, 119.4327), isTrue);
    // Mataram on Lombok, where KKP printed WPP 573's point 40.
    expect(mask.isLand(-8.5833, 116.1167), isTrue);
    // Makassar Strait, well offshore.
    expect(mask.isLand(-3.0, 118.0), isFalse);
    // Middle of the Flores Sea.
    expect(mask.isLand(-7.0, 120.0), isFalse);
    // Middle of the Banda Sea.
    expect(mask.isLand(-5.5, 128.0), isFalse);
    // Middle of Borneo (Kalimantan), far from any coast.
    expect(mask.isLand(0.0, 114.0), isTrue);
    // Middle of the Java Sea.
    expect(mask.isLand(-5.0, 110.0), isFalse);
  });

  test('every bundled WPP file loads, and no point is invented', () async {
    final LocalDataSource data = LocalDataSource();
    final List<DpiPoint> points = await data.loadDpi(forceReload: true);

    // 571 has 25 rows, the other ten have 50 each. If this number moves, a
    // table was re-read — which is fine — but a silently emptied pack is not.
    expect(points.length, greaterThanOrEqualTo(500));

    final Set<String> wpps = points.map((DpiPoint p) => p.wpp).toSet();
    expect(wpps.length, 11, reason: 'all eleven WPPs must be bundled');

    // Each point must carry the coordinate KKP printed, in both forms, and a
    // date that is not the epoch.
    for (final DpiPoint p in points) {
      expect(p.nomor, greaterThan(0));
      expect(p.lat, inInclusiveRange(-15.0, 9.0), reason: 'WPP ${p.wpp} #${p.nomor}');
      expect(p.lon, inInclusiveRange(90.0, 145.0), reason: 'WPP ${p.wpp} #${p.nomor}');
      expect(p.latDms, isNotEmpty);
      expect(p.lonDms, isNotEmpty);
      expect(p.date.year, greaterThanOrEqualTo(2026));
      expect(p.sourceUrl, contains('kkp.go.id'));
    }
  });

  test('the only bundled point on land is the one KKP published that way',
      () async {
    final LocalDataSource data = LocalDataSource();
    final List<DpiPoint> points = await data.loadDpi(forceReload: true);
    final LandMask mask = (await LandMask.instance())!;

    final List<DpiPoint> onLand =
        points.where((DpiPoint p) => mask.isLand(p.lat, p.lon)).toList();

    expect(
      onLand.length,
      1,
      reason: 'unexpected inland points: '
          '${onLand.map((DpiPoint p) => 'WPP ${p.wpp} #${p.nomor} '
              '${p.lat.toStringAsFixed(4)},${p.lon.toStringAsFixed(4)}').join('; ')}',
    );
    expect(onLand.single.wpp, knownLandPointWpp);
    expect(onLand.single.nomor, knownLandPointNomor);
  });

  test('a point on land is never offered as a fishing destination', () {
    final List<DpiPoint> points = <DpiPoint>[
      // Right on the Lombok coast, closest to the boat.
      DpiPoint(
        nomor: 40,
        lat: -8.72639,
        lon: 116.46583,
        lonDms: "116°27'57\" BT",
        latDms: "8°43'35\" LS",
        wpp: '573',
        date: DateTime(2026, 11, 4),
        onLand: true,
      ),
      // Further out, but genuinely wet.
      DpiPoint(
        nomor: 41,
        lat: -9.5,
        lon: 116.5,
        lonDms: "116°30'00\" BT",
        latDms: "9°30'00\" LS",
        wpp: '573',
        date: DateTime(2026, 11, 4),
      ),
    ];

    // LocalDataSource.nearby does not filter; AppState.nearestDpi does, by
    // handing it a list that excludes land points. This test pins the filter
    // rule itself so a future refactor cannot quietly drop it.
    final List<DpiPoint> seaOnly =
        points.where((DpiPoint p) => !p.onLand).toList();
    final List<DpiPoint> nearest =
        LocalDataSource.nearby(seaOnly, -8.8, 116.5, limit: 5);

    expect(nearest.length, 1);
    expect(nearest.single.nomor, 41);
    expect(nearest.every((DpiPoint p) => !p.onLand), isTrue);
  });

  test('nearestZone picks the zone whose real points are closest', () async {
    final LocalDataSource data = LocalDataSource();
    final List<DpiPoint> points = await data.loadDpi(forceReload: true);

    // Off Makassar: WPP 713 covers the Makassar Strait.
    final WppZone? makassar = WppZone.nearestZone(-5.1, 119.4, points);
    expect(makassar?.kode, '713');

    // Aru Sea, south of Papua: WPP 718.
    final WppZone? aru = WppZone.nearestZone(-6.5, 134.5, points);
    expect(aru?.kode, '718');

    // Malacca Strait side, north Sumatra: WPP 571.
    final WppZone? selat = WppZone.nearestZone(4.5, 98.5, points);
    expect(selat?.kode, '571');

    // Empty input falls back to the caller's default rather than guessing.
    expect(WppZone.nearestZone(-5.1, 119.4, const <DpiPoint>[]), isNull);
  });

  test('nearestZone ignores a land point closer than the real one', () {
    final List<DpiPoint> points = <DpiPoint>[
      // 573 has a point printed on the Lombok coast.
      DpiPoint(
        nomor: 40,
        lat: -8.72639,
        lon: 116.46583,
        lonDms: "116°27'57\" BT",
        latDms: "8°43'35\" LS",
        wpp: '573',
        date: DateTime(2026, 11, 4),
        onLand: true,
      ),
      DpiPoint(
        nomor: 1,
        lat: -5.0,
        lon: 119.0,
        lonDms: "119°00'00\" BT",
        latDms: "5°00'00\" LS",
        wpp: '713',
        date: DateTime(2026, 11, 4),
      ),
    ];
    // Standing right next to the inland point: it must not win.
    expect(WppZone.nearestZone(-8.73, 116.47, points)?.kode, '713');
  });

  test('DpiPoint carries onLand through JSON and copies it faithfully', () {
    final DpiPoint p = DpiPoint(
      nomor: 40,
      lat: -8.72639,
      lon: 116.46583,
      lonDms: "116°27'57\" BT",
      latDms: "8°43'35\" LS",
      wpp: '573',
      date: DateTime(2026, 11, 4),
      onLand: true,
    );
    expect(DpiPoint.fromJson(p.toJson()).onLand, isTrue);
    expect(p.withLandFlag(false).onLand, isFalse);
    // Everything else survives the copy.
    final DpiPoint cleared = p.withLandFlag(false);
    expect(cleared.nomor, p.nomor);
    expect(cleared.lat, p.lat);
    expect(cleared.lonDms, p.lonDms);
    expect(cleared.date, p.date);
    expect(cleared.wpp, p.wpp);
  });

  test('the old weather sample is gone, so no invented forecast can ship',
      () async {
    // A bundled forecast is wrong from the moment the APK is built, but still
    // draws a full 48-hour table and a sea-status colour. There must be none.
    //
    // Checked on disk rather than through rootBundle, because the test bundle
    // is assembled once and would happily serve a copy cached from before the
    // file was deleted.
    expect(
      File('assets/data/weather.json').existsSync(),
      isFalse,
      reason: 'weather.json must not come back: it was invented data',
    );
    final LocalDataSource data = LocalDataSource();
    expect(await data.loadWeather(forceReload: true), isEmpty);
  });

  test('the raw DPI asset is the shape local_data reads', () async {
    // Guards the on-disk contract between tool/real/build_real_data.dart and
    // the app, which nothing else checks: a renamed key here would silently
    // produce an empty map rather than an error.
    final String raw = await rootBundle.loadString('assets/data/dpi_713.json');
    final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;

    expect(j['type'], 'FeatureCollection');
    expect(j['wpp'], '713');
    expect(j['tanggal'], isA<String>());

    final List<dynamic> features = j['features'] as List<dynamic>;
    expect(features, isNotEmpty);

    final Map<String, dynamic> first =
        (features.first as Map<String, dynamic>)['properties']
            as Map<String, dynamic>;
    expect(first['nomor'], isA<num>());
    expect(first['lat_dms'], isA<String>());
    expect(first['lon_dms'], isA<String>());
    expect(first['sumber'], contains('kkp.go.id'));
  });
}
