import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'land_mask.dart';
import 'table_ocr.dart';

/// A WPPNRI fishing zone the KKP portal publishes a DPI table for.
///
/// The `uuid` is the `category` query parameter used by
/// `GET /pdpi/result-search/?date=YYYY-M-D&category=<uuid>`.
class WppZone {
  const WppZone(this.kode, this.uuid, this.nama);

  final String kode;
  final String uuid;
  final String nama;

  String get label => 'WPP $kode';
  String get labelLong => 'WPPNRI $kode';

  /// The 11 zones published under `#select2-peta_category-results`.
  static const List<WppZone> all = <WppZone>[
    WppZone('571', '3e04bcd6-ecf1-45e6-b6e5-46d353664958',
        'Selat Malaka, Laut Andaman'),
    WppZone('572', 'dd636df1-3452-4c8c-a05e-f208f8e6a39b',
        'Samudera Hindia barat Sumatera, Selat Sunda'),
    WppZone('573', 'b0cc7704-2982-4d75-bfeb-a03873cdb6e0',
        'Samudera Hindia selatan Jawa hingga selatan Nusa Tenggara, Laut Sawu, Laut Timor bagian barat'),
    WppZone('711', 'ade406fb-5fa9-4df2-8f60-f5b353c3b7a8',
        'Selat Karimata, Laut Natuna, Laut China Selatan'),
    WppZone('712', '8361a41a-c140-47f3-837c-f714bc9ec7fc', 'Laut Jawa'),
    WppZone('713', '0b2544e4-0e59-4336-904b-ecd4c7f411d1',
        'Selat Makassar, Teluk Bone, Laut Flores, Laut Bali'),
    WppZone('714', '32e4d1bb-76df-4215-ba32-218e7d31487e', 'Teluk Tolo, Laut Banda'),
    WppZone('715', '7ac5ae0e-aa69-43ff-9ab0-75c4bfdabf2f',
        'Teluk Tomini, Laut Maluku, Laut Halmahera, Laut Seram, Teluk Berau'),
    WppZone('716', '514fb3c1-1a71-499c-928b-d0bd3a690de3',
        'Laut Sulawesi, utara Pulau Halmahera'),
    WppZone('717', '2e459cea-1661-453b-bcb9-2768155a967f',
        'Teluk Cendrawasih, Samudera Pasifik'),
    WppZone('718', '8824b5cf-f810-4cdc-903e-0efc5d259dbe',
        'Laut Aru, Laut Arafuru, Laut Timor bagian timur'),
  ];

  /// Looks a zone up by its three-digit code.
  static WppZone? byKode(String kode) {
    for (final WppZone z in all) {
      if (z.kode == kode) return z;
    }
    return null;
  }

  /// The zone whose published DPI points are nearest to a position.
  ///
  /// Earlier this was a chain of hand-drawn `if` boxes, and it was wrong often
  /// enough to matter: a boat off Makassar could be sent to WPP 716, and a
  /// boat in the Flores Sea to 714, so the app would fetch — and the sailor
  /// would read — the wrong ministry table.
  ///
  /// With real published points bundled for every zone there is no need to
  /// guess: the nearest actual fishing ground wins. [points] is the loaded set
  /// (all zones); a point on land is ignored, since it cannot be what the
  /// sailor is near.
  ///
  /// Returns null when [points] is empty, so callers keep their own default.
  static WppZone? nearestZone(
    double lat,
    double lon,
    Iterable<DpiPoint> points,
  ) {
    String? best;
    double bestKm = double.infinity;
    for (final DpiPoint p in points) {
      if (p.onLand) continue;
      final double km = p.distanceKmTo(lat, lon);
      if (km < bestKm) {
        bestKm = km;
        best = p.wpp;
      }
    }
    return best == null ? null : byKode(best);
  }

  /// Coarse fallback for when no points are loaded yet.
  ///
  /// Kept only for the first launch before [LocalDataSource] has read the
  /// bundled pack. Prefer [nearestZone]; this box test is approximate by
  /// design and says so.
  static WppZone? forPosition(double lat, double lon) {
    if (lat > 4) return byKode('711');
    if (lat > -1.5 && lon < 106) return byKode('571');
    if (lat > -1.5 && lon < 112) return byKode('711');
    if (lon < 106) return byKode('572');
    if (lon < 115) return byKode('573');
    if (lat < -3.5 && lon < 116) return byKode('573');
    if (lon < 120 && lat > -2.5) return byKode('716');
    if (lon < 119 && lat > -6) return byKode('713');
    if (lon < 121) return byKode('714');
    if (lat > -3) return byKode('715');
    if (lon < 127) return byKode('714');
    if (lon < 132) return byKode('715');
    if (lat < -5 && lon > 132) return byKode('718');
    return byKode('717');
  }
}

/// What a DPI fetch produced.
class DpiFetchResult {
  const DpiFetchResult({
    required this.zone,
    required this.date,
    required this.rows,
    this.tableUrl = '',
    this.mapUrl = '',
    this.error,
    this.ocrUsed = false,
    this.dropped = 0,
  });

  final WppZone zone;
  final DateTime date;
  final List<DpiRowData> rows;
  final String tableUrl;
  final String mapUrl;

  /// Set when the fetch failed outright; [rows] is then empty. It is also set
  /// when the read succeeded but something is worth telling the sailor about
  /// (a partial table, say) — check [rows] to tell the two apart.
  final String? error;

  /// True when the coordinates came from OCR of the KKP image rather than a
  /// bundled snapshot.
  final bool ocrUsed;

  /// Rows the reader threw away because a digit was unreadable or the
  /// coordinates fell outside Indonesian waters.
  final int dropped;

  bool get isEmpty => rows.isEmpty;

  List<DpiPoint> toPoints() {
    final LandMask? mask = LandMask.loaded;
    return rows
        .where((DpiRowData r) =>
            mask == null || !mask.isLand(r.latitude, r.longitude))
        .map((DpiRowData r) => DpiPoint(
              nomor: r.nomor,
              lat: r.latitude,
              lon: r.longitude,
              lonDms: r.lonDms,
              latDms: r.latDms,
              wpp: zone.kode,
              date: date,
              ocrConf: 100,
              sourceUrl: tableUrl,
              onLand: false,
            ))
        .toList();
  }
}

/// Talks to the public KKP portal that publishes the DPI (Daerah Penangkapan
/// Ikan) tables: `https://portal-informasi.kkp.go.id/pdpi/`.
///
/// The portal exposes no structured feed — `/pdpi/download/<uuid>/` returns
/// the very same PNG that `/media/sync/peta-pdpi/` serves — so the coordinates
/// have to be read out of the "TABEL DPI" image. That is what [readDpiTable]
/// does, entirely in Dart: it finds the printed grid, cuts every cell and
/// matches the digits against `assets/dpi/templates.json`. No ML Kit, no
/// platform plugin, so it behaves the same on Android, iOS, desktop and web.
class KkpPdpiService {
  KkpPdpiService({http.Client? client, this.baseUrl = defaultBase})
      : _client = client ?? http.Client();

  static const String defaultBase = 'https://portal-informasi.kkp.go.id';
  static const String _path = '/pdpi/result-search/';
  static const String templatesAsset = 'assets/dpi/templates.json';

  final http.Client _client;
  final String baseUrl;

  /// Loaded once per service instance: the file is ~40 KB and parsing it is
  /// far cheaper than keeping the JSON text around.
  GlyphTemplates? _templates;

  static const Map<String, String> _headers = <String, String>{
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
    'User-Agent': 'FishGuard/1.0 (Flutter; nelayan DPI client)',
  };

  /// The date format the portal expects in the `date` parameter: it echoes
  /// `2026-11-2`, i.e. no zero padding.
  static String dateParam(DateTime d) => '${d.year}-${d.month}-${d.day}';

  /// `yyyyMMdd`, as used in the published file names.
  static String dateStamp(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  Uri resultUri(WppZone zone, DateTime date) => Uri.parse(
        '$baseUrl$_path?date=${dateParam(date)}&category=${zone.uuid}',
      );

  /// The glyph library the reader matches digits against.
  Future<GlyphTemplates> loadTemplates() async {
    final GlyphTemplates? cached = _templates;
    if (cached != null) return cached;
    try {
      final String raw = await rootBundle.loadString(templatesAsset);
      final GlyphTemplates? parsed = GlyphTemplates.fromJsonString(raw);
      if (parsed == null) {
        throw const PdpiException(
          'Pustaka bentuk angka (templates.json) rusak. Pasang ulang aplikasi.',
        );
      }
      return _templates = parsed;
    } on PdpiException {
      rethrow;
    } on Object catch (e) {
      throw PdpiException(
        'Pustaka bentuk angka tidak bisa dimuat, jadi tabel tidak bisa '
        'dibaca. ($e)',
      );
    }
  }

  /// Asks the portal which images exist for [zone] on [date].
  ///
  /// Returns the absolute table/map PNG URLs, or throws [PdpiException] with
  /// a message worth showing to a fisherman rather than a stack trace.
  Future<({String tableUrl, String mapUrl})> resolveImages(
    WppZone zone,
    DateTime date,
  ) async {
    final Uri uri = resultUri(zone, date);
    final http.Response res;
    try {
      res = await _client.get(uri, headers: _headers).timeout(
            const Duration(seconds: 30),
          );
    } on Object catch (e) {
      throw PdpiException('Tidak bisa menghubungi portal KKP. ($e)');
    }

    if (res.statusCode != 200) {
      throw PdpiException(
        'Portal KKP menjawab ${res.statusCode} untuk WPP ${zone.kode} '
        'tanggal ${dateParam(date)}.',
      );
    }

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } on Object {
      throw const PdpiException('Jawaban portal KKP tidak bisa dibaca.');
    }

    if (body['status'] != 'success') {
      throw PdpiException(
        'Portal KKP: ${body['msg'] ?? 'status tidak dikenal'}.',
      );
    }

    final String render = body['render'] as String? ?? '';
    // The image paths are the only reliable anchors in the HTML fragment.
    final RegExp tableRe = RegExp(r'/media/sync/peta-pdpi/tabel_dpi_\d+_\d+\.png');
    final RegExp mapRe = RegExp(r'/media/sync/peta-pdpi/peta_dpi_\d+_\d+\.png');
    final String? table = tableRe.firstMatch(render)?.group(0);
    final String? map = mapRe.firstMatch(render)?.group(0);

    if (table == null) {
      throw PdpiException(
        'Tabel DPI untuk WPP ${zone.kode} pada ${dateParam(date)} belum '
        'tersedia di portal KKP. Coba tanggal lain atau zona lain.',
      );
    }
    return (tableUrl: '$baseUrl$table', mapUrl: map == null ? '' : '$baseUrl$map');
  }

  /// The most recent date, on or before [from], for which the portal actually
  /// publishes a table for [zone].
  ///
  /// KKP does not publish every day, and the current day is often missing
  /// until they do. Opening the app on "today" would otherwise always fail.
  /// Walks back at most [maxDaysBack] days; returns null when nothing is
  /// found, so the caller can show the portal's own message.
  Future<DateTime?> latestAvailableDate(
    WppZone zone, {
    DateTime? from,
    int maxDaysBack = 7,
    void Function(String message)? onProgress,
  }) async {
    final DateTime raw = from ?? DateTime.now();
    final DateTime start = DateTime(raw.year, raw.month, raw.day);
    for (int back = 0; back <= maxDaysBack; back++) {
      final DateTime day = start.subtract(Duration(days: back));
      onProgress?.call(
        'Mencari tabel DPI terbaru WPP ${zone.kode} '
        '(${dateParam(day)})…',
      );
      try {
        await resolveImages(zone, day);
        return day;
      } on PdpiException {
        // Nothing published that day — keep walking back.
        continue;
      }
    }
    return null;
  }

  /// Downloads the DPI table image bytes.
  Future<Uint8List> downloadTable(String url) async {
    try {
      final http.Response res = await _client.get(Uri.parse(url), headers: _headers)
          .timeout(const Duration(seconds: 60));
      if (res.statusCode != 200) {
        throw PdpiException('Gambar tabel gagal diunduh (${res.statusCode}).');
      }
      return res.bodyBytes;
    } on PdpiException {
      rethrow;
    } on Object catch (e) {
      throw PdpiException('Gambar tabel gagal diunduh. ($e)');
    }
  }

  /// Full pipeline: resolve -> download -> read.
  ///
  /// [onProgress] reports a short Indonesian status so the UI can show what
  /// is happening on a slow fishing-boat connection.
  Future<DpiFetchResult> fetchAndOcr(
    WppZone zone,
    DateTime date, {
    void Function(String message)? onProgress,
  }) async {
    onProgress?.call('Mencari tabel DPI WPP ${zone.kode}…');
    final ({String tableUrl, String mapUrl}) images =
        await resolveImages(zone, date);

    onProgress?.call('Mengunduh gambar tabel…');
    final Uint8List bytes = await downloadTable(images.tableUrl);

    onProgress?.call('Membaca tabel (OCR)…');
    return ocrBytes(
      zone: zone,
      date: date,
      bytes: bytes,
      tableUrl: images.tableUrl,
      mapUrl: images.mapUrl,
    );
  }

  /// Reads the rows out of an in-memory PNG of the KKP table.
  ///
  /// The grid detection plus glyph matching is pure Dart and takes roughly two
  /// seconds for a 3448x2457 table, so it runs on a worker isolate where one is
  /// available; the UI thread only waits.
  Future<DpiFetchResult> ocrBytes({
    required WppZone zone,
    required DateTime date,
    required Uint8List bytes,
    String tableUrl = '',
    String mapUrl = '',
  }) async {
    DpiFetchResult fail(String message, {int dropped = 0}) => DpiFetchResult(
          zone: zone,
          date: date,
          rows: const <DpiRowData>[],
          tableUrl: tableUrl,
          mapUrl: mapUrl,
          ocrUsed: true,
          dropped: dropped,
          error: message,
        );

    final GlyphTemplates templates;
    try {
      templates = await loadTemplates();
    } on PdpiException catch (e) {
      return fail(e.message);
    }

    final List<DpiRowData>? read = await _readOffThread(bytes, templates);
    if (read == null || read.isEmpty) {
      return fail(
        'Gambar tabel terunduh tetapi gridnya tidak dikenali. Format tabel '
        'KKP mungkin berubah — periksa gambar aslinya.',
      );
    }

    // Titik yang angka tidak terbaca atau jatuh di daratan langsung dibuang demi akurasi nelayan.
    final LandMask? mask = LandMask.loaded;
    final List<DpiRowData> clean = read
        .where((DpiRowData r) =>
            !r.perluReview &&
            (mask == null || !mask.isLand(r.latitude, r.longitude)))
        .toList();
    final int dropped = read.length - clean.length;

    if (clean.isEmpty) {
      return fail(
        'Semua ${read.length} baris tabel terbaca sebagian (ada angka yang '
        'tidak dikenali). Tabel tidak bisa dipakai.',
        dropped: dropped,
      );
    }

    final bool complete = validateDpiRows(clean);
    String? warning;
    if (!complete) {
      warning = 'Tabel terbaca sebagian: ${clean.length} titik, dan nomor '
          'urutnya tidak lengkap. Periksa kembali sebelum dipakai.';
    } else if (dropped > 0) {
      warning = '$dropped baris dilewati karena ada angka yang tidak terbaca.';
    }

    return DpiFetchResult(
      zone: zone,
      date: date,
      rows: clean,
      tableUrl: tableUrl,
      mapUrl: mapUrl,
      ocrUsed: true,
      dropped: dropped,
      error: warning,
    );
  }

  /// Runs [readDpiTable] off the UI thread.
  ///
  /// Falls back to a direct call when the platform refuses to spawn an isolate
  /// (web, or a restricted runtime) — the read is identical, only slower.
  Future<List<DpiRowData>?> _readOffThread(
    Uint8List bytes,
    GlyphTemplates templates,
  ) async {
    try {
      return await compute(_readTable, _OcrJob(bytes, templates));
    } on Object {
      return readDpiTable(bytes, templates);
    }
  }

  void dispose() => _client.close();
}

/// Input for the worker isolate. A plain object, so it can be copied across.
class _OcrJob {
  const _OcrJob(this.bytes, this.templates);

  final Uint8List bytes;
  final GlyphTemplates templates;
}

List<DpiRowData>? _readTable(_OcrJob job) =>
    readDpiTable(job.bytes, job.templates);

/// A failure worth showing to the user as-is.
class PdpiException implements Exception {
  const PdpiException(this.message);

  final String message;

  @override
  String toString() => message;
}
