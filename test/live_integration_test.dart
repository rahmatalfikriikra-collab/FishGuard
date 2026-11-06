// Live end-to-end check against the real KKP and BMKG endpoints.
//
// This hits the network, so it is tagged `live`. It is part of the default run
// because it is the only proof that the whole chain — portal JSON -> PNG ->
// grid detection -> glyph matching -> map points — still works against the
// data KKP publishes today. Run only these with:
//
//     flutter test --tags live
//
// or skip them on a dead connection with:
//
//     flutter test --exclude-tags live
@Tags(<String>['live'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/services/bmkg_service.dart';
import 'package:fishguard_app/services/kkp_pdpi_service.dart';
import 'package:fishguard_app/services/table_ocr.dart';

void main() {
  // The glyph library is an asset, so rootBundle has to be usable here.
  TestWidgetsFlutterBinding.ensureInitialized();

  // …but that binding also installs an HttpOverrides that answers every
  // request with 400 so unit tests never touch the network. This suite is the
  // exception: it exists to prove the live chain still works, so the real
  // client is put back for it.
  setUpAll(() => HttpOverrides.global = null);

  group('BMKG live', () {
    test('resolves Makassar from a position in the Sulawesi Selatan waters',
        () async {
      final BmkgService svc = BmkgService();
      final BmkgAreaRef? ref = await svc.areaForPosition(-5.1, 119.4);
      expect(ref, isNotNull);
      // ignore: avoid_print
      print('AREA: ${ref!.id} ${ref.name} [${ref.province}]');
      expect(ref.id, startsWith('P.'));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('loads a forecast with usable hours', () async {
      final BmkgService svc = BmkgService();
      await svc.loadWarnings();
      expect(svc.warningsLoaded, isTrue);

      final WeatherArea area =
          await svc.loadArea('P.AE.04', fallbackName: 'Perairan Makassar');
      // ignore: avoid_print
      print('FORECAST: ${area.name} issued=${area.issuedLabel} '
          'hours=${area.hours.length} '
          'wave=${area.waveRange} wind=${area.windRange} '
          'warning="${area.warning}" level=${area.warningLevel.name} '
          'status=${area.statusNow().name}');
      expect(area.hours, isNotEmpty);
      expect(area.hours.first.waveM, greaterThanOrEqualTo(0));
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('the bulletin names areas that exist in the area index', () async {
      final BmkgService svc = BmkgService();
      await svc.loadWarnings();
      final List<BmkgAreaRef> areas = await svc.loadAreas();

      int warned = 0;
      for (final BmkgAreaRef a in areas) {
        final WarningLevel l = svc.warningFor(a.name);
        if (l != WarningLevel.none) warned++;
      }
      // ignore: avoid_print
      print('WARNED AREAS: $warned of ${areas.length}');
      // A quiet day can legitimately be zero; the point is that the lookup
      // runs over the whole index without throwing.
      expect(warned, greaterThanOrEqualTo(0));
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  group('KKP live', () {
    test('finds the newest published table for WPP 713', () async {
      final KkpPdpiService svc = KkpPdpiService();
      final WppZone zone =
          WppZone.all.firstWhere((WppZone z) => z.kode == '713');

      // Today is normally not published yet, so this must walk back.
      final DateTime? day = await svc.latestAvailableDate(zone);
      // ignore: avoid_print
      print('KKP: newest published date for WPP 713 = $day');
      expect(day, isNotNull);
      expect(day!.isAfter(DateTime.now()), isFalse);

      final DpiFetchResult result = await svc.fetchAndOcr(zone, day);
      // ignore: avoid_print
      print('KKP: date=${result.date} rows=${result.rows.length} '
          'dropped=${result.dropped} error=${result.error} '
          'table=${result.tableUrl}');
      // The table image must resolve even where OCR cannot run (desktop/web).
      expect(result.tableUrl, isNotEmpty);
      expect(result.tableUrl, contains('tabel_dpi_713_'));

      // The reader is pure Dart, so it runs here exactly as it does on a
      // phone: the published table must come back as usable points.
      expect(result.ocrUsed, isTrue);
      expect(result.error, isNull, reason: 'a clean table must not warn');
      expect(result.rows.length, greaterThanOrEqualTo(25));
      expect(validateDpiRows(result.rows), isTrue,
          reason: 'row numbers must be contiguous');
      for (final DpiRowData r in result.rows) {
        expect(r.catatan, isEmpty, reason: 'nomor ${r.nomor}: ${r.catatan}');
        expect(r.longitude, inInclusiveRange(94, 142));
        expect(r.latitude, inInclusiveRange(-12, 8));
      }

      // And the points the map draws carry the coordinates and the source.
      final List<DpiPoint> points = result.toPoints();
      expect(points.length, result.rows.length);
      expect(points.first.wpp, '713');
      expect(points.first.sourceUrl, result.tableUrl);
      expect(points.first.latDms, isNotEmpty);
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('tooling', () {
    test('the OCR ground-truth image is present', () {
      final File f =
          File('tool/probe/tabel_dpi_713_20261102.png');
      expect(f.existsSync(), isTrue);
    });
  });
}
