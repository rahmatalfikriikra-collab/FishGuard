// Tests for the catch log model and its persistence helpers.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishguard_app/main.dart';
import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/services/app_state.dart';
import 'package:fishguard_app/widgets/catch_sheet.dart';

void main() {
  testWidgets('app builds', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await tester.pumpWidget(const FishGuardApp());
    await tester.pump();
    expect(find.text('FISHGUARD'), findsWidgets);
  });

  test('CatchLog survives a JSON round trip', () {
    final CatchLog entry = CatchLog(
      id: '42',
      waktu: DateTime(2026, 11, 2, 7, 30),
      jenis: 'Kembung',
      beratKg: 2.5,
      jumlah: 4,
      dpiNomor: 12,
      dpiWpp: '713',
      catatan: 'umpan udang',
    );
    final CatchLog back = CatchLog.fromJson(entry.toJson());

    expect(back.id, '42');
    expect(back.waktu, DateTime(2026, 11, 2, 7, 30));
    expect(back.jenis, 'Kembung');
    expect(back.beratKg, 2.5);
    expect(back.jumlah, 4);
    expect(back.dpiNomor, 12);
    expect(back.dpiWpp, '713');
    expect(back.catatan, 'umpan udang');
    expect(back.lokasiLabel, 'Titik DPI 12 · WPP 713');
  });

  test('CatchLog location label falls back to coordinates', () {
    final CatchLog gps = CatchLog(
      id: '1',
      waktu: DateTime(2026, 11, 2),
      jenis: 'Tuna',
      beratKg: 5,
      lat: -5.1234,
      lon: 119.4567,
    );
    expect(gps.lokasiLabel, '-5.1234, 119.4567');

    final CatchLog kosong = CatchLog(
      id: '2',
      waktu: DateTime(2026, 11, 2),
      jenis: 'Tuna',
      beratKg: 5,
    );
    expect(kosong.lokasiLabel, 'Lokasi tidak dicatat');
  });

  test('weights are formatted for the list', () {
    expect(formatKg(2.5), '2.5 kg');
    expect(formatKg(3), '3 kg');
    expect(formatKg(3.0), '3 kg');
    expect(formatKg(120), '120 kg');
  });

  // MAP-6: the sailor's own spots.
  test('OwnSpot survives a JSON round trip', () {
    final OwnSpot spot = OwnSpot(
      id: 'spot-1',
      lat: -5.5123,
      lon: 119.3456,
      createdAt: DateTime(2026, 11, 3, 5, 15),
      name: 'Karang Bosong',
      note: 'cakalang pagi',
    );
    final OwnSpot back = OwnSpot.fromJson(spot.toJson());

    expect(back.id, 'spot-1');
    expect(back.lat, -5.5123);
    expect(back.lon, 119.3456);
    expect(back.createdAt, DateTime(2026, 11, 3, 5, 15));
    expect(back.name, 'Karang Bosong');
    expect(back.note, 'cakalang pagi');
    expect(back.label, 'Karang Bosong');
  });

  test('a nameless OwnSpot is labelled by its coordinates', () {
    final OwnSpot spot = OwnSpot(
      id: 'spot-2',
      lat: -5.5123,
      lon: 119.3456,
      createdAt: DateTime(2026, 11, 3),
    );
    expect(spot.label, '-5.5123, 119.3456');
  });

  test('OwnSpot distance and bearing point back to the spot', () {
    final OwnSpot spot = OwnSpot(
      id: 'spot-3',
      lat: -5.5,
      lon: 119.5,
      createdAt: DateTime(2026, 11, 3),
    );
    // Due north of the boat, ~11.1 km away (0.1 degrees of latitude).
    final double km = spot.distanceKmTo(-5.6, 119.5);
    expect(km, closeTo(11.12, 0.15));
    expect(spot.bearingFrom(-5.6, 119.5), closeTo(0, 0.5));

    // Due east of the boat.
    final double east = spot.distanceKmTo(-5.5, 119.4);
    expect(spot.bearingFrom(-5.5, 119.4), closeTo(90, 0.5));
    expect(east, closeTo(11.07, 0.2));
  });
}
