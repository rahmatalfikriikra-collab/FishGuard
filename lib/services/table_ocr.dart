// =============================================================================
//  FishGuard - pembaca tabel DPI KKP (OCR murni Dart)
//
//  Peta PDPI KKP hanya menerbitkan tabel dalam bentuk gambar PNG. Modul ini
//  membaca gambarnya langsung di HP: deteksi grid, potong sel, lalu kenali
//  setiap angka dari pustaka bentuk (assets/dpi/templates.json).
//
//  Algoritma ini sama persis dengan tools/ocr/bin/extract.dart yang dipakai
//  saat membangun paket data awal, jadi hasil di HP dan di komputer konsisten.
// =============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

const int glyphW = 12;
const int glyphH = 16;
const double _inkThreshold = 0.30;
const int _darkLevel = 128;
const int _maxDistance = 34; // dari 192 bit (~18%)

class OcrGlyph {
  final List<int> bits;
  final int w;
  final int h;
  OcrGlyph(this.bits, this.w, this.h);
  String get key => bits.join();
}

class OcrCell {
  final int table;
  final int row;
  final int col;
  final List<OcrGlyph> glyphs;
  OcrCell(this.table, this.row, this.col, this.glyphs);
}

class OcrPage {
  final int w;
  final int h;
  final Uint8List dark;
  OcrPage(this.w, this.h, this.dark);

  bool at(int x, int y) =>
      x >= 0 && y >= 0 && x < w && y < h && dark[y * w + x] != 0;
}

class OcrGrid {
  final List<List<List<int>>> tablesV;
  final List<List<int>> rowRanges;
  OcrGrid(this.tablesV, this.rowRanges);
}

/// Hasil satu baris tabel.
class DpiRowData {
  final int nomor;
  final int lonD, lonM, lonS;
  final String lonArah;
  final int latD, latM, latS;
  final String latArah;
  final List<String> catatan;

  DpiRowData({
    required this.nomor,
    required this.lonD,
    required this.lonM,
    required this.lonS,
    required this.lonArah,
    required this.latD,
    required this.latM,
    required this.latS,
    required this.latArah,
    required this.catatan,
  });

  double get longitude => dmsToDecimal(lonD, lonM, lonS, lonArah);
  double get latitude => dmsToDecimal(latD, latM, latS, latArah);
  String get lonDms => dmsText(lonD, lonM, lonS, lonArah);
  String get latDms => dmsText(latD, latM, latS, latArah);
  bool get perluReview => catatan.isNotEmpty;
}

String dmsText(int d, int m, int s, String arah) =>
    '${d.abs()}°${m.toString().padLeft(2, '0')}\''
    '${s.toString().padLeft(2, '0')}" $arah';

double dmsToDecimal(int d, int m, int s, String arah) {
  if (s >= 60) {
    m += s ~/ 60;
    s %= 60;
  }
  if (m >= 60) {
    d += m ~/ 60;
    m %= 60;
  }
  final v = d.abs() + m / 60.0 + s / 3600.0;
  return double.parse(
      ((arah == 'LS' || arah == 'BB') ? -v : v).toStringAsFixed(6));
}

// ---------------------------------------------------------------------------
//  Pustaka bentuk glyph
// ---------------------------------------------------------------------------

class GlyphTemplates {
  final Map<String, List<List<int>>> _byChar;

  GlyphTemplates(this._byChar);

  static GlyphTemplates? fromJsonString(String s) {
    try {
      final raw = jsonDecode(s) as Map<String, dynamic>;
      final entries = raw['templates'] as List<dynamic>;
      final map = <String, List<List<int>>>{};
      for (final e in entries) {
        final m = e as Map<String, dynamic>;
        final ch = m['char'] as String;
        final bits =
            (m['bits'] as String).split('').map(int.parse).toList();
        map.putIfAbsent(ch, () => []).add(bits);
      }
      return GlyphTemplates(map);
    } catch (_) {
      return null;
    }
  }

  /// Karakter terdekat dari [allowed]; null bila tidak ada yang cukup mirip.
  String? classify(OcrGlyph g, Set<String> allowed) {
    String? best;
    var bestD = 1 << 30;
    _byChar.forEach((ch, list) {
      if (!allowed.contains(ch)) return;
      for (final t in list) {
        var d = 0;
        for (var i = 0; i < t.length && i < g.bits.length; i++) {
          if (t[i] != g.bits[i]) {
            d++;
            if (d >= bestD) break;
          }
        }
        if (d < bestD) {
          bestD = d;
          best = ch;
        }
      }
    });
    if (bestD > _maxDistance) return null;
    return best;
  }
}

const _digitChars = {'0', '1', '2', '3', '4', '5', '6', '7', '8', '9'};

// ---------------------------------------------------------------------------
//  Pembacaan gambar
// ---------------------------------------------------------------------------

OcrPage? decodePage(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final w = image.width;
  final h = image.height;
  final dark = Uint8List(w * h);
  var i = 0;
  for (final p in image) {
    final lum = 0.299 * p.r + 0.587 * p.g + 0.114 * p.b;
    dark[i++] = lum < _darkLevel ? 1 : 0;
  }
  return OcrPage(w, h, dark);
}

List<List<int>> _groupRanges(List<bool> mask) {
  final out = <List<int>>[];
  var start = -1;
  for (var i = 0; i < mask.length; i++) {
    if (mask[i] && start < 0) {
      start = i;
    } else if (!mask[i] && start >= 0) {
      out.add([start, i - 1]);
      start = -1;
    }
  }
  if (start >= 0) out.add([start, mask.length - 1]);
  return out;
}

List<List<int>> _darkRuns(bool Function(int) isDark, int length) {
  final out = <List<int>>[];
  var start = -1;
  for (var i = 0; i < length; i++) {
    if (isDark(i) && start < 0) {
      start = i;
    } else if (!isDark(i) && start >= 0) {
      out.add([start, i - 1]);
      start = -1;
    }
  }
  if (start >= 0) out.add([start, length - 1]);
  return out;
}

OcrGrid? detectGrid(OcrPage page) {
  final hFrac = List<double>.filled(page.h, 0);
  for (var y = 0; y < page.h; y++) {
    var c = 0;
    final row = y * page.w;
    for (var x = 0; x < page.w; x++) {
      if (page.dark[row + x] != 0) c++;
    }
    hFrac[y] = c / page.w;
  }

  final hMask = List<bool>.filled(page.h, false);
  for (var y = 0; y < page.h; y++) {
    hMask[y] = hFrac[y] > 0.45 && hFrac[y] < 0.96;
  }
  final hRanges = _groupRanges(hMask);
  if (hRanges.length < 5) return null;
  final hLines = hRanges.map((r) => (r[0] + r[1]) ~/ 2).toList();

  final probeY = hLines[hLines.length ~/ 2];
  final runs = _darkRuns((x) => page.at(x, probeY), page.w)
      .where((r) => (r[1] - r[0]) > page.w * 0.15)
      .toList();
  if (runs.isEmpty) return null;

  final yTop = hLines.first;
  final yBot = hLines.last;
  final tablesV = <List<List<int>>>[];

  for (final r in runs) {
    final xa = r[0];
    final xb = r[1];
    final width = xb - xa + 1;
    final frac = List<double>.filled(width, 0);
    for (var x = xa; x <= xb; x++) {
      var c = 0;
      for (var y = yTop; y <= yBot; y++) {
        if (page.dark[y * page.w + x] != 0) c++;
      }
      frac[x - xa] = c / (yBot - yTop + 1);
    }
    final mask = List<bool>.filled(width, false);
    for (var i = 0; i < width; i++) {
      mask[i] = frac[i] > 0.70;
    }
    tablesV.add(_groupRanges(mask).map((q) => [q[0] + xa, q[1] + xa]).toList());
  }

  final rowRanges = hRanges.sublist(2);
  return OcrGrid(tablesV, rowRanges);
}

List<OcrGlyph> _segmentCell(OcrPage page, int x0, int y0, int x1, int y1) {
  var minX = 1 << 30, minY = 1 << 30, maxX = -1, maxY = -1;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      if (!page.at(x, y)) continue;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
    }
  }
  if (maxX < 0) return const [];

  final colInk = List<int>.filled(maxX - minX + 1, 0);
  for (var x = minX; x <= maxX; x++) {
    var c = 0;
    for (var y = minY; y <= maxY; y++) {
      if (page.at(x, y)) c++;
    }
    colInk[x - minX] = c;
  }

  final spans = <List<int>>[];
  var start = -1;
  for (var i = 0; i < colInk.length; i++) {
    if (colInk[i] > 0 && start < 0) {
      start = i;
    } else if (colInk[i] == 0 && start >= 0) {
      spans.add([start, i - 1]);
      start = -1;
    }
  }
  if (start >= 0) spans.add([start, colInk.length - 1]);

  final out = <OcrGlyph>[];
  for (final sp in spans) {
    final gx0 = minX + sp[0];
    final gx1 = minX + sp[1];
    var gy0 = 1 << 30, gy1 = -1;
    for (var y = minY; y <= maxY; y++) {
      for (var x = gx0; x <= gx1; x++) {
        if (page.at(x, y)) {
          if (y < gy0) gy0 = y;
          if (y > gy1) gy1 = y;
          break;
        }
      }
    }
    if (gy1 < 0) continue;
    out.add(_normalize(page, gx0, gy0, gx1, gy1));
  }
  return out;
}

OcrGlyph _normalize(OcrPage page, int x0, int y0, int x1, int y1) {
  final bw = x1 - x0 + 1;
  final bh = y1 - y0 + 1;
  final vals = List<int>.filled(glyphW * glyphH, 0);
  for (var gy = 0; gy < glyphH; gy++) {
    final sy0 = y0 + (gy * bh) ~/ glyphH;
    var sy1 = y0 + ((gy + 1) * bh) ~/ glyphH;
    if (sy1 <= sy0) sy1 = sy0 + 1;
    for (var gx = 0; gx < glyphW; gx++) {
      final sx0 = x0 + (gx * bw) ~/ glyphW;
      var sx1 = x0 + ((gx + 1) * bw) ~/ glyphW;
      if (sx1 <= sx0) sx1 = sx0 + 1;
      var tot = 0, dk = 0;
      for (var y = sy0; y < sy1; y++) {
        for (var x = sx0; x < sx1; x++) {
          tot++;
          if (page.at(x, y)) dk++;
        }
      }
      if (tot > 0 && dk / tot > _inkThreshold) vals[gy * glyphW + gx] = 1;
    }
  }
  return OcrGlyph(vals, bw, bh);
}

List<OcrCell> _sliceCells(OcrPage page, OcrGrid grid) {
  final cells = <OcrCell>[];
  for (var t = 0; t < grid.tablesV.length; t++) {
    final v = grid.tablesV[t];
    if (v.length != 10) continue;
    for (var r = 0; r < grid.rowRanges.length - 1; r++) {
      final y0 = grid.rowRanges[r][1] + 3;
      final y1 = grid.rowRanges[r + 1][0] - 3;
      if (y1 <= y0) continue;
      for (var c = 0; c < 9; c++) {
        final x0 = v[c][1] + 3;
        final x1 = v[c + 1][0] - 3;
        if (x1 <= x0) continue;
        cells.add(OcrCell(t, r, c, _segmentCell(page, x0, y0, x1, y1)));
      }
    }
  }
  return cells;
}

class _NumberRead {
  final String text;
  final bool ok;
  _NumberRead(this.text, this.ok);
}

_NumberRead _readNumber(OcrCell cell, GlyphTemplates tpl) {
  var negative = false;
  final sb = StringBuffer();
  var ok = true;
  for (final g in cell.glyphs) {
    if (g.h <= 6 && g.w >= 4) {
      negative = true;
      continue;
    }
    final ch = tpl.classify(g, _digitChars);
    if (ch == null) {
      ok = false;
      sb.write('?');
    } else {
      sb.write(ch);
    }
  }
  if (sb.isEmpty) return _NumberRead('', false);
  return _NumberRead('${negative ? '-' : ''}$sb', ok);
}

String? _readDirection(OcrCell cell, GlyphTemplates tpl) {
  final chars = <String>[];
  for (final g in cell.glyphs) {
    final ch = tpl.classify(g, {'B', 'T', 'L', 'U', 'S', 'LS', 'LU'});
    if (ch == null) return null;
    chars.add(ch);
  }
  final s = chars.join();
  if (s == 'BT' || s == 'BB' || s == 'LU' || s == 'LS') return s;
  return null;
}

// ---------------------------------------------------------------------------
//  API modul
// ---------------------------------------------------------------------------

/// Baca tabel DPI dari gambar PNG. Mengembalikan null bila grid tidak dikenali.
List<DpiRowData>? readDpiTable(Uint8List pngBytes, GlyphTemplates templates) {
  final page = decodePage(pngBytes);
  if (page == null) return null;
  final grid = detectGrid(page);
  if (grid == null) return null;

  final cells = _sliceCells(page, grid);
  final rows = <DpiRowData>[];
  var i = 0;
  while (i < cells.length) {
    final first = cells[i];
    final group = <OcrCell>[];
    while (i < cells.length &&
        cells[i].table == first.table &&
        cells[i].row == first.row) {
      group.add(cells[i]);
      i++;
    }
    if (group.length != 9) continue;

    final catatan = <String>[];
    final nomor = _readNumber(group[0], templates);
    final lonD = _readNumber(group[1], templates);
    final lonM = _readNumber(group[2], templates);
    final lonS = _readNumber(group[3], templates);
    final lonArah = _readDirection(group[4], templates);
    final latD = _readNumber(group[5], templates);
    final latM = _readNumber(group[6], templates);
    final latS = _readNumber(group[7], templates);
    final latArah = _readDirection(group[8], templates);

    for (final n in [nomor, lonD, lonM, lonS, latD, latM, latS]) {
      if (!n.ok) catatan.add('angka tidak terbaca');
    }
    if (lonArah == null) catatan.add('arah bujur tidak terbaca');
    if (latArah == null) catatan.add('arah lintang tidak terbaca');

    int v(_NumberRead n) => int.tryParse(n.text) ?? 0;

    // KKP kadang menulis detik 60 (mis. 121°41'60") pada tabel sumbernya.
    // Nilai itu sah dan dinormalkan oleh [dmsToDecimal], jadi bukan alasan
    // menandai baris untuk ditinjau ulang.
    if (v(lonM) < 0 || v(lonM) > 60) catatan.add('menit bujur ${lonM.text}');
    if (v(lonS) < 0 || v(lonS) > 60) catatan.add('detik bujur ${lonS.text}');
    if (v(latM) < 0 || v(latM) > 60) catatan.add('menit lintang ${latM.text}');
    if (v(latS) < 0 || v(latS) > 60) catatan.add('detik lintang ${latS.text}');
    if (v(lonD) < 90 || v(lonD) > 145) catatan.add('derajat bujur ${lonD.text}');
    if (v(latD) < -15 || v(latD) > 15) catatan.add('derajat lintang ${latD.text}');

    rows.add(DpiRowData(
      nomor: v(nomor),
      lonD: v(lonD),
      lonM: v(lonM),
      lonS: v(lonS),
      lonArah: lonArah ?? 'BT',
      latD: v(latD),
      latM: v(latM),
      latS: v(latS),
      latArah: latArah ?? 'LS',
      catatan: catatan,
    ));
  }
  return rows;
}

/// Validasi: nomor harus 1..n berurutan tanpa bolong.
bool validateDpiRows(List<DpiRowData> rows) {
  if (rows.isEmpty) return false;
  for (var k = 0; k < rows.length; k++) {
    if (rows[k].nomor != k + 1) return false;
  }
  return true;
}
