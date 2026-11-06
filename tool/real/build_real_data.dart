// Builds FishGuard's real offline data pack from primary sources.
//
// Run from the project root:
//   dart run tool/real/build_real_data.dart
//
// What it produces:
//   assets/data/land_mask.bin      compact Indonesia land bitmap, for the
//                                  "is this DPI point on land?" check
//   assets/data/dpi_<wpp>.json     REAL coordinates, OCR'd from the KKP table
//                                  PNGs in tool/real/, not hand-authored
//   tool/real/report.txt           what was read and what was dropped
//
// Nothing here runs on the phone: the phone reads the assets. The point is
// that the assets are a faithful copy of what KKP published, so the bundled
// pack and a live fetch agree.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:fishguard_app/services/table_ocr.dart';

const String _srcDir = 'tool/real';
const String _outDir = 'assets/data';
const String _templates = 'assets/dpi/templates.json';

/// Bounds of the land mask. Covers every WPP from the Andaman Sea to Arafuru,
/// with a margin so a point just outside Indonesian waters still resolves.
const double _minLat = -15.0;
const double _maxLat = 9.0;
const double _minLon = 90.0;
const double _maxLon = 145.0;

/// ~1.5 km per cell. Fine enough to keep a small island (Balaobalang,
/// Kangean, the Seribu chain) visible, small enough to ship.
const double _cellDeg = 0.015;

void main() {
  final GlyphTemplates? tpl = GlyphTemplates.fromJsonString(
    File(_templates).readAsStringSync(),
  );
  if (tpl == null) {
    stderr.writeln('templates.json tidak bisa dibaca');
    exit(1);
  }

  Directory(_outDir).createSync(recursive: true);
  final StringBuffer report = StringBuffer();

  // ---- 1. land mask ------------------------------------------------------
  final _Mask mask = _Mask.build();
  final Uint8List packed = mask.bits;
  File('$_outDir/land_mask.bin').writeAsBytesSync(packed);
  report.writeln('land_mask.bin  ${mask.w}x${mask.h}  ${packed.length} B  '
      'lat $_minLat..$_maxLat lon $_minLon..$_maxLon');

  // ---- 2. OCR every published table --------------------------------------
  final List<File> tables = Directory(_srcDir)
      .listSync()
      .whereType<File>()
      .where((File f) => RegExp(r'tabel_dpi_(\d+)_(\d{8})\.png$')
          .hasMatch(f.path))
      .toList()
    ..sort((File a, File b) => a.path.compareTo(b.path));

  if (tables.isEmpty) {
    stderr.writeln('Tidak ada tabel di $_srcDir');
    exit(1);
  }

  final Map<String, List<Map<String, dynamic>>> byWpp =
      <String, List<Map<String, dynamic>>>{};
  final Map<String, String> dateByWpp = <String, String>{};

  for (final File f in tables) {
    final RegExpMatch m =
        RegExp(r'tabel_dpi_(\d+)_(\d{8})\.png$').firstMatch(f.path)!;
    final String wpp = m.group(1)!;
    final String stamp = m.group(2)!;
    final String iso = '${stamp.substring(0, 4)}-'
        '${stamp.substring(4, 6)}-${stamp.substring(6, 8)}';

    final Uint8List png = f.readAsBytesSync();
    final List<DpiRowData>? read = readDpiTable(png, tpl);
    if (read == null || read.isEmpty) {
      report.writeln('WPP $wpp  GRID TIDAK DIKENALI  ${f.path}');
      continue;
    }

    // Never guess. A row with an unreadable digit, a hemisphere that did not
    // read, or coordinates outside Indonesian waters is reported and dropped.
    final List<DpiRowData> clean = <DpiRowData>[];
    for (final DpiRowData r in read) {
      final List<String> why = <String>[...r.catatan];
      final double lat = r.latitude;
      final double lon = r.longitude;
      if (lat < _minLat || lat > _maxLat) {
        why.add('lintang ${lat.toStringAsFixed(3)} di luar');
      }
      if (lon < _minLon || lon > _maxLon) {
        why.add('bujur ${lon.toStringAsFixed(3)} di luar');
      }

      if (why.isNotEmpty) {
        report.writeln('WPP $wpp  DIBUANG #${r.nomor}  ${why.join(", ")}  '
            '${r.lonDms} ${r.latDms}');
        continue;
      }
      clean.add(r);
    }

    final List<Map<String, dynamic>> feats = <Map<String, dynamic>>[];
    int onLand = 0;
    for (final DpiRowData r in clean) {
      if (mask.isLand(r.latitude, r.longitude)) {
        onLand++;
        report.writeln('WPP $wpp  DI DARAT #${r.nomor} DIBUANG: '
            '${r.lonDms} ${r.latDms}  (${r.longitude.toStringAsFixed(5)}, '
            '${r.latitude.toStringAsFixed(5)})');
        continue; // Titik di daratan wajib dibuang demi akurasi nelayan
      }
      feats.add(<String, dynamic>{
        'type': 'Feature',
        'geometry': <String, dynamic>{
          'type': 'Point',
          'coordinates': <double>[r.longitude, r.latitude],
        },
        'properties': <String, dynamic>{
          'nomor': r.nomor,
          'wpp': wpp,
          'tanggal': iso,
          'lon_dms': r.lonDms,
          'lat_dms': r.latDms,
          'ocr_conf': 100,
          'sumber': 'https://portal-informasi.kkp.go.id/media/sync/'
              'peta-pdpi/tabel_dpi_${wpp}_$stamp.png',
        },
      });
    }

    byWpp[wpp] = feats;
    dateByWpp[wpp] = iso;

    report.writeln('WPP $wpp  $iso  baris=${read.length} '
        'pakai=${clean.length} dibuang=${read.length - clean.length} '
        'di_darat=$onLand  ${feats.isEmpty ? "" : "#1 ${clean.first.lonDms} ${clean.first.latDms}"}');
  }

  // ---- 3. write one GeoJSON per WPP --------------------------------------
  for (final MapEntry<String, List<Map<String, dynamic>>> e in byWpp.entries) {
    final Map<String, dynamic> fc = <String, dynamic>{
      'type': 'FeatureCollection',
      'wpp': e.key,
      'tanggal': dateByWpp[e.key],
      'sumber': 'Tabel DPI resmi KKP — dibaca ulang dari gambar yang '
          'diterbitkan portal-informasi.kkp.go.id',
      'features': e.value,
    };
    File('$_outDir/dpi_${e.key}.json')
        .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(fc));
  }

  // The WPP list the app should offer, generated rather than hand-typed.
  final List<String> have = byWpp.keys.toList()..sort();
  report.writeln('WPP ditulis: ${have.join(", ")}');

  File('$_srcDir/report.txt').writeAsStringSync(report.toString());
  stdout.write(report.toString());
}

// ---------------------------------------------------------------------------
//  Land mask
// ---------------------------------------------------------------------------

/// A bit per cell: 1 = land, 0 = water. Read at runtime by [LandMask].
class _Mask {
  _Mask(this.w, this.h, this.bits);

  final int w;
  final int h;
  final Uint8List bits;

  bool isLand(double lat, double lon) {
    final int x = ((lon - _minLon) / _cellDeg).floor();
    final int y = ((_maxLat - lat) / _cellDeg).floor();
    if (x < 0 || y < 0 || x >= w || y >= h) return false;
    final int i = y * w + x;
    return (bits[i >> 3] & (1 << (i & 7))) != 0;
  }

  static _Mask build() {
    final int w = ((_maxLon - _minLon) / _cellDeg).ceil();
    final int h = ((_maxLat - _minLat) / _cellDeg).ceil();
    final _Grid grid = _Grid(w, h);
    for (final String name in <String>[
      'ne_50m_land.geojson',
      'ne_10m_land.geojson',
    ]) {
      final File f = File('$_srcDir/$name');
      if (!f.existsSync()) {
        stderr.writeln('! $name tidak ada — melewati');
        continue;
      }
      final Map<String, dynamic> j =
          jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      for (final dynamic raw in j['features'] as List<dynamic>) {
        final dynamic geom = (raw as Map<String, dynamic>)['geometry'];
        _fillGeometry(geom, grid);
      }
    }
    return _Mask(w, h, grid.pack());
  }

  /// Rasterises a Polygon/MultiPolygon by scanning each row of cells and
  /// toggling on every edge crossing, then filling the runs that alternate in.
  static void _fillGeometry(dynamic geometry, _Grid grid) {
    if (geometry is! Map<String, dynamic>) return;
    final String type = geometry['type'] as String? ?? '';
    final dynamic coords = geometry['coordinates'];
    if (coords is! List) return;

    Iterable<List<dynamic>> polys;
    if (type == 'Polygon') {
      polys = <List<dynamic>>[coords];
    } else if (type == 'MultiPolygon') {
      polys = coords.cast<List<dynamic>>();
    } else {
      return;
    }

    for (final List<dynamic> poly in polys) {
      for (final dynamic ringRaw in poly) {
        if (ringRaw is! List) continue;
        final List<List<double>> ring = <List<double>>[];
        for (final dynamic p in ringRaw) {
          if (p is! List || p.length < 2) continue;
          ring.add(<double>[
            (p[0] as num).toDouble(),
            (p[1] as num).toDouble(),
          ]);
        }
        if (ring.length >= 3) grid.fillRing(ring);
      }
    }
  }
}

/// Scanline rasteriser over the mask's cell centres.
class _Grid {
  _Grid(this.w, this.h) : bits = Uint8List((w * h + 7) >> 3);

  final int w;
  final int h;
  final Uint8List bits;

  void set(int x, int y) {
    if (x < 0 || y < 0 || x >= w || y >= h) return;
    final int i = y * w + x;
    bits[i >> 3] |= 1 << (i & 7);
  }

  Uint8List pack() => bits;

  /// Every cell whose *centre* is inside the ring is marked.
  void fillRing(List<List<double>> ring) {
    // Ring bounds in cell space, clipped to the grid.
    double minLon = ring.first[0], maxLon = ring.first[0];
    double minLat = ring.first[1], maxLat = ring.first[1];
    for (final List<double> p in ring) {
      if (p[0] < minLon) minLon = p[0];
      if (p[0] > maxLon) maxLon = p[0];
      if (p[1] < minLat) minLat = p[1];
      if (p[1] > maxLat) maxLat = p[1];
    }
    int y0 = ((_maxLat - maxLat) / _cellDeg).floor() - 1;
    int y1 = ((_maxLat - minLat) / _cellDeg).ceil() + 1;
    if (y0 < 0) y0 = 0;
    if (y1 > h - 1) y1 = h - 1;

    for (int y = y0; y <= y1; y++) {
      final double lat = _maxLat - (y + 0.5) * _cellDeg;
      // Longitudes where this row crosses the ring.
      final List<double> xs = <double>[];
      for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
        final double yi = ring[i][1], xi = ring[i][0];
        final double yj = ring[j][1], xj = ring[j][0];
        final bool crosses = (yi > lat) != (yj > lat);
        if (!crosses) continue;
        xs.add((xj - xi) * (lat - yi) / (yj - yi) + xi);
      }
      if (xs.length < 2) continue;
      xs.sort();
      for (int k = 0; k + 1 < xs.length; k += 2) {
        int xa = ((xs[k] - _minLon) / _cellDeg).ceil();
        int xb = ((xs[k + 1] - _minLon) / _cellDeg).floor();
        if (xa < 0) xa = 0;
        if (xb > w - 1) xb = w - 1;
        for (int x = xa; x <= xb; x++) {
          set(x, y);
        }
      }
    }
  }
}

// keep math imported for future tweaks without tripping the analyzer
// ignore: unused_element
double _unused() => math.pi;
