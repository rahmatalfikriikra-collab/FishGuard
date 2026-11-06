// Locks the BMKG warning wiring to the shape `warning/warnings.json` really has.
//
// The fixtures below are trimmed copies of the live bulletin (3 Nov 2026):
// it is keyed by province, and each province lists its warned perairan by
// *name* under a severity bucket. Names match `area_province.json` exactly.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/services/bmkg_service.dart';

const String _warnings = '''
{
  "Indonesia": {
    "data": {
      "region": "Indonesia",
      "warning": {
        "sedang": ["Laut Jawa bagian timur", "Laut Bali"],
        "tinggi": ["Samudra Hindia selatan Jawa Timur"],
        "sangat_tinggi": [],
        "ekstrem": []
      }
    },
    "pdf": "indonesia.pdf"
  },
  "Jawa Timur": {
    "data": {
      "region": "Jawa Timur",
      "warning": {
        "sedang": ["Perairan Banyuwangi", "Perairan Jember"],
        "tinggi": [],
        "sangat_tinggi": [],
        "ekstrem": []
      }
    },
    "pdf": "jawa-timur.pdf"
  }
}
''';

/// Minimal perairan payload: two hourly slots, calm sea.
String _areaJson(String name) => jsonEncode(<String, dynamic>{
      'name': name,
      'issued': '2026-11-02 12:00 UTC',
      'forecast_day1': <Map<String, dynamic>>[
        <String, dynamic>{
          'time': '2026-11-03 06:00 UTC',
          'wave_height': 0.4,
          'wind_speed': 5,
          'weather': 'Cerah',
          'wind_from': 'Timur',
        },
        <String, dynamic>{
          'time': '2026-11-03 09:00 UTC',
          'wave_height': 0.5,
          'wind_speed': 6,
          'weather': 'Berawan',
          'wind_from': 'Timur',
        },
      ],
      'forecast_day2-4': <Map<String, dynamic>>[],
    });

BmkgService _service({String areaName = 'Perairan Banyuwangi'}) {
  final MockClient client = MockClient((http.Request req) async {
    final String url = req.url.toString();
    if (url.endsWith('warning/warnings.json')) {
      return http.Response(_warnings, 200);
    }
    if (url.contains('/perairan/')) {
      return http.Response(_areaJson(areaName), 200);
    }
    return http.Response('not found', 404);
  });
  return BmkgService(client: client);
}

void main() {
  group('BMKG warnings', () {
    test('indexes a warned perairan by name', () async {
      final BmkgService svc = _service();
      await svc.loadWarnings();

      expect(svc.warningsLoaded, isTrue);
      expect(svc.warningFor('Perairan Banyuwangi'), WarningLevel.sedang);
      expect(svc.warningFor('Samudra Hindia selatan Jawa Timur'),
          WarningLevel.tinggi);
      // Named nowhere in the bulletin.
      expect(svc.warningFor('Perairan Makassar'), WarningLevel.none);
    });

    test('the worst bucket wins when a name appears twice', () async {
      final MockClient client = MockClient((http.Request req) async {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'A': <String, dynamic>{
              'data': <String, dynamic>{
                'warning': <String, dynamic>{
                  'sedang': <String>['Perairan X'],
                },
              },
            },
            'B': <String, dynamic>{
              'data': <String, dynamic>{
                'warning': <String, dynamic>{
                  'ekstrem': <String>['Perairan X'],
                },
              },
            },
          }),
          200,
        );
      });
      final BmkgService svc = BmkgService(client: client);
      await svc.loadWarnings();
      expect(svc.warningFor('Perairan X'), WarningLevel.ekstrem);
    });

    test('warningsLoaded distinguishes "none" from "not checked"', () {
      final BmkgService svc = _service();
      expect(svc.warningsLoaded, isFalse);
      expect(svc.warningFor('Perairan Banyuwangi'), WarningLevel.none);
    });

    test('a warned area carries the level and BMKG text into the model',
        () async {
      final BmkgService svc = _service();
      await svc.loadWarnings();
      final WeatherArea area =
          await svc.loadArea('P.N.01', fallbackName: 'Perairan Banyuwangi');

      expect(area.warningLevel, WarningLevel.sedang);
      expect(area.warning, contains('Perairan Banyuwangi'));
      expect(area.warning.toLowerCase(), contains('sedang'));
    });

    test('an unwarned calm area stays LAYAK', () async {
      final BmkgService svc = _service(areaName: 'Perairan Makassar');
      await svc.loadWarnings();
      final WeatherArea area =
          await svc.loadArea('P.AE.04', fallbackName: 'Perairan Makassar');

      expect(area.warningLevel, WarningLevel.none);
      expect(area.warning, isEmpty);
      expect(area.statusNow(now: DateTime(2026, 11, 3, 5)), SeaStatus.layak);
    });

    test('a "sedang" bulletin warning raises the status to WASPADA', () async {
      final BmkgService svc = _service();
      await svc.loadWarnings();
      final WeatherArea area =
          await svc.loadArea('P.N.01', fallbackName: 'Perairan Banyuwangi');

      // The forecast alone is calm, so only the bulletin can move the status.
      expect(area.statusNow(now: DateTime(2026, 11, 3, 5)), SeaStatus.waspada);
    });

    test('a "tinggi" bulletin warning raises the status to TIDAK LAYAK',
        () async {
      final BmkgService svc = _service(
          areaName: 'Samudra Hindia selatan Jawa Timur');
      await svc.loadWarnings();
      final WeatherArea area = await svc.loadArea(
          'P.Q.01',
          fallbackName: 'Samudra Hindia selatan Jawa Timur');

      expect(area.statusNow(now: DateTime(2026, 11, 3, 5)),
          SeaStatus.tidakLayak);
    });
  });

  group('WarningLevel survives the cache round trip', () {
    test('level and text are restored', () {
      final WeatherArea original = WeatherArea(
        code: 'P.N.01',
        name: 'Perairan Banyuwangi',
        hours: <ForecastHour>[],
        fetchedAt: DateTime(2026, 11, 3, 6),
        warning: 'BMKG menetapkan peringatan gelombang sedang.',
        warningLevel: WarningLevel.sedang,
        issuedLabel: '2026-11-02 12:00 UTC',
        live: true,
      );
      final WeatherArea back =
          WeatherArea.fromJson(jsonDecode(jsonEncode(original.toJson()))
              as Map<String, dynamic>);

      expect(back.warningLevel, WarningLevel.sedang);
      expect(back.warning, original.warning);
      expect(back.live, isTrue);
    });

    test('an old cache without the level field still loads', () {
      final Map<String, dynamic> legacy = <String, dynamic>{
        'code': 'P.N.01',
        'name': 'Perairan Banyuwangi',
        'fetched': '2026-11-03T06:00:00.000',
        'warning': '',
        'issued': '',
        'live': false,
        'hours': <dynamic>[],
      };
      final WeatherArea back = WeatherArea.fromJson(legacy);
      expect(back.warningLevel, WarningLevel.none);
    });
  });
}
