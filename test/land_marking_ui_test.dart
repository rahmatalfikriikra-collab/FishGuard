// The map draws a point that sits on land as hollow and struck through. This
// pins the other half of that promise: the list row and the detail sheet must
// carry the same warning, or a fisherman who only ever reads the list takes in
// the distance and the ETA and sets out for a beach.
//
// The sheet is driven directly rather than through the map. PetaScreen embeds
// flutter_map, which pulls OpenStreetMap tiles over the network; under the test
// binding those requests fail slowly and keep the frame queue permanently busy,
// so anything that waits on the map's frames hangs the suite. DpiPointSheet is
// public for exactly this reason — it is the surface that carries the distance,
// the ETA and the departure button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fishguard_app/models/models.dart';
import 'package:fishguard_app/screens/peta_screen.dart';
import 'package:fishguard_app/services/app_state.dart';
import 'package:fishguard_app/theme/app_theme.dart';

/// KKP's own coordinate for WPP 573 #40, printed on the south Lombok coast.
DpiPoint _point({required bool onLand, String wpp = '573', int nomor = 40}) =>
    DpiPoint(
      nomor: nomor,
      lat: onLand ? -8.72639 : -5.1,
      lon: onLand ? 116.46583 : 119.4,
      lonDms: onLand ? "116°27'57\" BT" : "119°24'00\" BT",
      latDms: onLand ? "8°43'35\" LS" : "5°06'00\" LS",
      wpp: wpp,
      date: DateTime(2026, 11, 4),
      onLand: onLand,
    );

Future<AppState> _state(double lat, double lon) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final AppState s = AppState();
  await s.load();
  s.updatePosition(lat, lon);
  return s;
}

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.build(dark: false),
      home: Scaffold(body: child),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a land point warns before anything else on the sheet',
      (tester) async {
    final AppState s = await _state(-8.8, 116.5);
    await tester.pumpWidget(
      _host(
        DpiPointSheet(
          point: _point(onLand: true),
          state: s,
          onNavigate: () {},
          onStartTrip: () {},
        ),
      ),
    );
    await tester.pump();

    // The sheet leads with the reason, not with the distance.
    expect(find.textContaining('jatuh di darat'), findsOneWidget);
    // And the departure button no longer reads as a recommendation.
    expect(find.text('Tetap Berangkat ke Sini'), findsOneWidget);
    expect(find.text('Mulai Perjalanan ke Sini'), findsNothing);
  });

  testWidgets('an ordinary sea point keeps the plain recommendation',
      (tester) async {
    final AppState s = await _state(-5.1, 119.4);
    await tester.pumpWidget(
      _host(
        DpiPointSheet(
          point: _point(onLand: false, wpp: '713', nomor: 1),
          state: s,
          onNavigate: () {},
          onStartTrip: () {},
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('jatuh di darat'), findsNothing);
    expect(find.text('Mulai Perjalanan ke Sini'), findsOneWidget);
    expect(find.text('Tetap Berangkat ke Sini'), findsNothing);
  });

  testWidgets('a land point stays reachable — it is KKP\'s coordinate, not '
      'ours to delete', (tester) async {
    final AppState s = await _state(-8.8, 116.5);
    bool started = false;
    await tester.pumpWidget(
      _host(
        DpiPointSheet(
          point: _point(onLand: true),
          state: s,
          onNavigate: () {},
          onStartTrip: () => started = true,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Tetap Berangkat ke Sini'));
    await tester.pump();
    expect(started, isTrue, reason: 'the button must still work');
  });

  testWidgets('the bundled pack carries the land flag into AppState',
      (tester) async {
    final AppState s = await _state(-8.75, 116.47);

    final List<DpiPoint> land =
        s.dpiPoints.where((DpiPoint p) => p.onLand).toList();
    expect(land.length, 1);
    expect(land.single.wpp, '573');
    expect(land.single.nomor, 40);

    // …and it is never offered as somewhere to go.
    expect(s.nearestDpi(limit: 999).any((DpiPoint p) => p.onLand), isFalse);
  });
}
