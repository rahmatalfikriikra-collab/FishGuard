// Reads the real KKP DPI table PNG the way the app does on a phone.
//
// The fixture is the table the portal published for WPPNRI 713 on 2 Nov 2026:
// https://portal-informasi.kkp.go.id/media/sync/peta-pdpi/tabel_dpi_713_20261102.png
//
// It deliberately contains the quirks the printed table really has:
//   * a south latitude printed with a leading minus as well as "LS"
//   * 60 seconds on point 44 (must normalise to +1 minute, not drop the row)
//   * latitude 0 with an explicit LU/LS hemisphere (points 3, 8, 12, 15, 16,
//     22, 25, 28, 30, 35, 37, 45, 46)
//   * the page printed as two side-by-side blocks (1-25 | 26-50)
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fishguard_app/services/table_ocr.dart';

const String _groundTruth = 'tool/probe/tabel_dpi_713_20261102.png';
const String _templates = 'assets/dpi/templates.json';

void main() {
  late GlyphTemplates tpl;
  late List<DpiRowData> rows;

  setUpAll(() {
    final GlyphTemplates? parsed =
        GlyphTemplates.fromJsonString(File(_templates).readAsStringSync());
    expect(parsed, isNotNull, reason: 'assets/dpi/templates.json must parse');
    tpl = parsed!;

    final Uint8List png = File(_groundTruth).readAsBytesSync();
    final List<DpiRowData>? read = readDpiTable(png, tpl);
    expect(read, isNotNull, reason: 'the table grid must be recognised');
    rows = read!;
  });

  group('KKP WPP 713, 2 Nov 2026', () {
    test('reads all 50 numbered points in order', () {
      expect(rows.length, 50);
      expect(validateDpiRows(rows), isTrue);
      expect(rows.map((DpiRowData r) => r.nomor).toList(),
          List<int>.generate(50, (int i) => i + 1));
    });

    test('no row carries a review note', () {
      // Every cell of this table is legible; a note here means the reader
      // mis-cut a column or the glyph library lost a shape.
      for (final DpiRowData r in rows) {
        expect(r.catatan, isEmpty, reason: 'nomor ${r.nomor}: ${r.catatan}');
      }
    });

    test('point 1 matches the published coordinates', () {
      final DpiRowData r = rows.firstWhere((DpiRowData r) => r.nomor == 1);
      expect(r.lonD, 118);
      expect(r.lonM, 34);
      expect(r.lonS, 33);
      expect(r.lonArah, 'BT');
      expect(r.latD, -3);
      expect(r.latM, 27);
      expect(r.latS, 56);
      expect(r.latArah, 'LS');
      expect(r.longitude, closeTo(118 + 34 / 60 + 33 / 3600, 1e-6));
      expect(r.latitude, closeTo(-(3 + 27 / 60 + 56 / 3600), 1e-6));
    });

    test('60 seconds on point 44 normalises instead of dropping the row', () {
      final DpiRowData r = rows.firstWhere((DpiRowData r) => r.nomor == 44);
      expect(r.lonD, 121);
      expect(r.lonM, 41);
      expect(r.lonS, 60);
      // 121 41 60 BT -> 121 42 00 BT -> 121.7
      expect(r.longitude, closeTo(121.7, 1e-6));
      // -8 8 37 LS is untouched.
      expect(r.latitude, closeTo(-(8 + 8 / 60 + 37 / 3600), 1e-6));
    });

    test('the "60" stays inside its own row', () {
      // A reader that treated 60" as a new number would lose the latitude of
      // 44 and then pair point 45 with the wrong hemisphere.
      final DpiRowData r45 = rows.firstWhere((DpiRowData r) => r.nomor == 45);
      expect(r45.lonD, 117);
      expect(r45.lonM, 55);
      expect(r45.lonS, 21);
      expect(r45.latD, 0);
      expect(r45.latArah, 'LS');
      expect(r45.latitude, closeTo(-(0 + 22 / 60 + 57 / 3600), 1e-6));
    });

    test('the minus sign does not double up with LS', () {
      final DpiRowData r = rows.firstWhere((DpiRowData r) => r.nomor == 20);
      expect(r.latitude, closeTo(-(8 + 9 / 60 + 15 / 3600), 1e-6));
    });

    test('0 degrees latitude keeps the hemisphere the table states', () {
      // 0 ... LU must be north, not read as "-0".
      final DpiRowData north = rows.firstWhere((DpiRowData r) => r.nomor == 8);
      expect(north.latArah, 'LU');
      expect(north.latitude, closeTo(6 / 60 + 6 / 3600, 1e-6));

      // 0 ... LS must be south. Point 35 prints the degree cell as a bare 0.
      final DpiRowData south = rows.firstWhere((DpiRowData r) => r.nomor == 35);
      expect(south.latArah, 'LS');
      expect(south.latitude, closeTo(-(0 + 17 / 60 + 2 / 3600), 1e-6));

      // And a south latitude that *also* carries a leading minus (point 10)
      // must not end up positive.
      final DpiRowData r10 = rows.firstWhere((DpiRowData r) => r.nomor == 10);
      expect(r10.latitude, closeTo(-(8 + 6 / 60 + 21 / 3600), 1e-6));
    });

    test('every point lands inside Indonesian waters', () {
      for (final DpiRowData r in rows) {
        expect(r.longitude, inInclusiveRange(94, 142), reason: 'nomor ${r.nomor}');
        expect(r.latitude, inInclusiveRange(-12, 8), reason: 'nomor ${r.nomor}');
      }
    });

    test('both table halves are read, not just the left one', () {
      // The right block holds 26-50; a reader that only walked the left
      // column would stop at 25.
      expect(rows.where((DpiRowData r) => r.nomor > 25).length, 25);
      final DpiRowData last = rows.last;
      expect(last.nomor, 50);
      expect(last.longitude, closeTo(119 + 24 / 60 + 55 / 3600, 1e-6));
    });

    test('the DMS text round-trips to the decimal value', () {
      final DpiRowData r = rows.firstWhere((DpiRowData r) => r.nomor == 1);
      expect(r.lonDms, '118°34\'33" BT');
      expect(r.latDms, '3°27\'56" LS');
    });
  });

  group('the reader refuses what it cannot trust', () {
    test('a PNG that is not a table yields nothing', () {
      // A 4x4 white PNG: no grid, so no rows.
      final Uint8List blank = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x04, 0x00, 0x00, 0x00, 0x04,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x26, 0x93, 0x09,
        0x29, 0x00, 0x00, 0x00, 0x18, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0xFC, 0xFF, 0xFF, 0x3F,
        0x00, 0x03, 0x03, 0x02, 0x00, 0xE9, 0x9C, 0x2B,
        0x76, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82,
      ]);
      expect(readDpiTable(blank, tpl), anyOf(isNull, isEmpty));
    });

    test('a truncated file yields nothing instead of throwing', () {
      final Uint8List cut =
          File(_groundTruth).readAsBytesSync().sublist(0, 512);
      expect(() => readDpiTable(cut, tpl), returnsNormally);
      expect(readDpiTable(cut, tpl), anyOf(isNull, isEmpty));
    });

    test('a gap in the numbering fails validation', () {
      final List<DpiRowData> holed = <DpiRowData>[
        rows[0],
        rows[2], // nomor 3, with 2 missing
      ];
      expect(validateDpiRows(holed), isFalse);
      expect(validateDpiRows(<DpiRowData>[]), isFalse);
    });
  });
}
