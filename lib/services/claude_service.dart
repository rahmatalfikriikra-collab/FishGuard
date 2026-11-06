import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/models.dart';

/// Errors the UI can tell apart, so the sailor gets a useful message instead of
/// a generic "gagal".
class ClaudeApiException implements Exception {
  ClaudeApiException(this.message, {this.statusCode, this.retryable = false});

  final String message;
  final int? statusCode;
  final bool retryable;

  @override
  String toString() => message;

  String get userMessage {
    if (statusCode == 401 || statusCode == 403) {
      return 'Kunci API tidak valid atau tidak punya akses. Periksa di Profil → Asisten AI.';
    }
    if (statusCode == 429) {
      return 'Terlalu banyak permintaan ke AI. Coba lagi beberapa saat.';
    }
    if (statusCode != null && statusCode! >= 500) {
      return 'Server AI sedang bermasalah. Saran lokal tetap dipakai.';
    }
    return message;
  }
}

/// Recognition of the shape returned by POST /v1/messages.
class ClaudeReply {
  const ClaudeReply({
    required this.text,
    required this.model,
    this.stopReason = 'end_turn',
    this.inputTokens = 0,
    this.outputTokens = 0,
  });

  final String text;
  final String model;
  final String stopReason;
  final int inputTokens;
  final int outputTokens;

  bool get isRefusal => stopReason == 'refusal';
}

/// Thin Messages API client for Flutter.
///
/// Dart has no official Anthropic SDK, so this speaks the REST API directly
/// with `package:http`:
///   POST https://api.anthropic.com/v1/messages
///   headers: content-type, x-api-key, anthropic-version
///
/// Non-streaming is deliberate: a recommendation here is a handful of
/// sentences, and one buffered response keeps the screen logic trivial.
/// Flip [stream] on if the answer ever grows long enough to need progressive
/// rendering.
class ClaudeClient {
  ClaudeClient({
    required this.apiKey,
    this.model = defaultModel,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  static const String endpoint = 'https://api.anthropic.com/v1/messages';
  static const String apiVersion = '2026-10-21';

  /// Current Opus-tier model; see the model table in the app's settings screen.
  static const String defaultModel = 'claude-opus-5-5';
  static const List<String> knownModels = <String>[
    'claude-opus-5-5',
    'claude-opus-5',
    'claude-sonnet-5-5',
    'claude-haiku-5-5',
  ];

  final String apiKey;
  final String model;
  final http.Client _http;

  bool get hasKey => apiKey.trim().isNotEmpty;

  Map<String, String> get _headers => <String, String>{
        'content-type': 'application/json',
        'x-api-key': apiKey.trim(),
        'anthropic-version': apiVersion,
      };

  /// One Messages API round trip.
  ///
  /// [system] carries the stable instructions, [userMessage] the per-request
  /// data. Thinking is adaptive (never `budget_tokens`, which is rejected by
  /// current models) and `effort` is set explicitly because the default is
  /// model-dependent.
  Future<ClaudeReply> send({
    required String userMessage,
    String? system,
    int maxTokens = 1600,
    String effort = 'medium',
    Duration timeout = const Duration(seconds: 60),
  }) async {
    if (!hasKey) {
      throw ClaudeApiException('Kunci API belum diisi.', statusCode: 401);
    }

    final Map<String, dynamic> body = <String, dynamic>{
      'model': model,
      'max_tokens': maxTokens,
      'thinking': <String, dynamic>{'type': 'adaptive', 'display': 'summarized'},
      'output_config': <String, dynamic>{'effort': effort},
      if (system != null && system.isNotEmpty) 'system': system,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'user', 'content': userMessage},
      ],
    };

    http.Response response;
    try {
      response = await _http
          .post(
            Uri.parse(endpoint),
            headers: _headers,
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw ClaudeApiException('Koneksi ke AI habis waktu.', retryable: true);
    } on SocketException {
      throw ClaudeApiException('Tidak ada internet.', retryable: true);
    } on http.ClientException catch (e) {
      throw ClaudeApiException('Gagal menghubungi AI: ${e.message}', retryable: true);
    }

    return _parse(response);
  }

  ClaudeReply _parse(http.Response response) {
    Map<String, dynamic>? json;
    try {
      json = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      json = null;
    }

    if (response.statusCode != 200) {
      final String detail = json?['error'] is Map<String, dynamic>
          ? ((json!['error'] as Map<String, dynamic>)['message'] as String? ?? '')
          : '';
      final int code = response.statusCode;
      throw ClaudeApiException(
        detail.isEmpty ? 'AI menolak permintaan (HTTP $code).' : detail,
        statusCode: code,
        retryable: code == 429 || code >= 500,
      );
    }

    if (json == null) {
      throw ClaudeApiException('Balasan AI tidak bisa dibaca.', retryable: true);
    }

    final String stopReason = json['stop_reason'] as String? ?? 'end_turn';
    final List<dynamic> content = json['content'] as List<dynamic>? ?? <dynamic>[];
    final StringBuffer text = StringBuffer();
    for (final dynamic block in content) {
      if (block is Map<String, dynamic> &&
          block['type'] == 'text' &&
          block['text'] is String) {
        text.write(block['text'] as String);
      }
    }

    final Map<String, dynamic> usage =
        json['usage'] as Map<String, dynamic>? ?? <String, dynamic>{};
    return ClaudeReply(
      text: text.toString().trim(),
      model: json['model'] as String? ?? model,
      stopReason: stopReason,
      inputTokens: (usage['input_tokens'] as num?)?.toInt() ?? 0,
      outputTokens: (usage['output_tokens'] as num?)?.toInt() ?? 0,
    );
  }

  void close() => _http.close();
}

/// One recommendation shown on Beranda.
class Recommendation {
  const Recommendation({
    required this.headline,
    required this.body,
    required this.bullets,
    required this.source,
    this.modelName = '',
    this.generatedAt,
    this.error,
  });

  final String headline;
  final String body;
  final List<String> bullets;

  /// 'ai' when Claude produced it, 'lokal' when the offline rules did.
  final String source;
  final String modelName;
  final DateTime? generatedAt;
  final String? error;

  bool get fromAi => source == 'ai';

  factory Recommendation.local({
    required String headline,
    required String body,
    required List<String> bullets,
    String? error,
  }) {
    return Recommendation(
      headline: headline,
      body: body,
      bullets: bullets,
      source: 'lokal',
      generatedAt: DateTime.now(),
      error: error,
    );
  }
}

/// Builds the prompt from the same values the dashboard shows, then falls back
/// to the on-device rules whenever Claude is unreachable or unkeyed.
class RecommendationService {
  // A named parameter cannot be private, so the field cannot be an
  // initializing formal here.
  // ignore: prefer_initializing_formals
  RecommendationService({ClaudeClient? client}) : _client = client;

  final ClaudeClient? _client;

  static const String _system = '''
Anda adalah asisten keselamatan nelayan untuk aplikasi FishGuard, dipakai nelayan
perahu kecil (sampan sampai katir, 5,5-40 PK) di pesisir Sulawesi Selatan.
Tugas Anda: memberi rekomendasi singkat "hari ini melaut atau tidak" dalam
Bahasa Indonesia yang sederhana, kalimat pendek, mudah dibaca orang berusia
sekitar 50 tahun.

Aturan:
- Jangan pernah menjanjikan keselamatan. FishGuard alat bantu keputusan, bukan
  pengganti informasi resmi BMKG, Basarnas, atau syahbandar.
- Ambil status LAYAK/WASPADA/TIDAK LAYAK dari data yang diberikan sebagai dasar;
  jangan mengubahnya menjadi lebih longgar.
- Sebut angka gelombang dan angin yang diberikan, jangan mengarang angka baru.
- Keluarkan maksimal 3 baris poin, tiap poin diawali "- " dan maksimal 18 kata.
- Jangan pakai markdown tebal, judul, atau tabel. Hanya teks biasa.''';

  Future<Recommendation> recommend({
    required WeatherArea? area,
    required int availablePoints,
    required String portName,
    required int enginePk,
    required double tankLiters,
  }) async {
    final SeaStatus status = area?.statusNow() ?? SeaStatus.waspada;
    final ForecastHour now = area?.currentHour() ??
        ForecastHour(
          time: DateTime.now(),
          waveM: 0,
          windKt: 0,
          condition: 'Data tidak tersedia',
        );

    final Recommendation fallback = _local(
      status: status,
      hour: now,
      area: area,
      availablePoints: availablePoints,
      portName: portName,
      enginePk: enginePk,
      tankLiters: tankLiters,
    );

    final ClaudeClient? client = _client;
    if (client == null || !client.hasKey) return fallback;

    final String user = '''
Data hari ini untuk ${area?.name ?? 'perairan anda'}:
- Status FishGuard: ${status.shortLabel}
- Cuaca: ${now.condition}
- Tinggi gelombang: ${now.waveM.toStringAsFixed(1)} m
- Kecepatan angin: ${now.windKt.toStringAsFixed(0)} knot (arah ${now.windDir})
- Peringatan BMKG: ${(area?.warning.isNotEmpty ?? false) ? area!.warning : 'tidak ada'}
- Jumlah titik DPI tersimpan: $availablePoints
- Pelabuhan asal: $portName
- Mesin: ${enginePk.toString().replaceAll('.0', '')} PK, tangki ${tankLiters.toStringAsFixed(0)} liter

Tuliskan: satu kalimat keputusan, lalu maksimal 3 poin saran praktis.''';

    try {
      final ClaudeReply reply = await client.send(userMessage: user, system: _system);
      if (reply.isRefusal) {
        return Recommendation.local(
          headline: fallback.headline,
          body: fallback.body,
          bullets: fallback.bullets,
          error: 'AI menolak menjawab; saran lokal ditampilkan.',
        );
      }
      final List<String> lines = reply.text
          .split('\n')
          .map((String l) => l.trim())
          .where((String l) => l.isNotEmpty)
          .toList();
      final List<String> bullets = lines
          .where((String l) => l.startsWith('- ') || l.startsWith('• '))
          .map((String l) => l.substring(2).trim())
          .toList();
      final String body = lines
          .where((String l) => !l.startsWith('- ') && !l.startsWith('• '))
          .join(' ')
          .trim();

      if (reply.text.isEmpty) return fallback;

      return Recommendation(
        headline: status.shortLabel,
        body: body.isEmpty ? reply.text : body,
        bullets: bullets,
        source: 'ai',
        modelName: reply.model,
        generatedAt: DateTime.now(),
      );
    } on ClaudeApiException catch (e) {
      return Recommendation.local(
        headline: fallback.headline,
        body: fallback.body,
        bullets: fallback.bullets,
        error: e.userMessage,
      );
    } catch (e) {
      return Recommendation.local(
        headline: fallback.headline,
        body: fallback.body,
        bullets: fallback.bullets,
        error: 'AI tidak tersedia: $e',
      );
    }
  }

  Recommendation _local({
    required SeaStatus status,
    required ForecastHour hour,
    required WeatherArea? area,
    required int availablePoints,
    required String portName,
    required int enginePk,
    required double tankLiters,
  }) {
    final String headline = status.shortLabel;
    final String body = switch (status) {
      SeaStatus.layak =>
        'Gelombang ${hour.waveM.toStringAsFixed(1)} m dan angin '
            '${hour.windKt.toStringAsFixed(0)} knot masih bersahabat untuk perahu kecil. '
            'Tetap cek langit sebelum berangkat.',
      SeaStatus.waspada =>
        'Gelombang ${hour.waveM.toStringAsFixed(1)} m atau angin '
            '${hour.windKt.toStringAsFixed(0)} knot mulai naik. Kurangi jarak dan '
            'awasi perubahan cuaca.',
      SeaStatus.tidakLayak =>
        'Gelombang ${hour.waveM.toStringAsFixed(1)} m atau angin '
            '${hour.windKt.toStringAsFixed(0)} knot berisiko untuk perahu kecil. '
            'Sebaiknya tunda melaut.',
    };

    final List<String> bullets = <String>[
      if (availablePoints == 0)
        'Belum ada titik DPI tersimpan. Unduh dulu di darat.'
      else
        '$availablePoints titik DPI tersimpan, pilih yang terdekat dari $portName.',
      if (enginePk > 0)
        'Dengan mesin ${enginePk.toString().replaceAll('.0', '')} PK dan tangki '
            '${tankLiters.toStringAsFixed(0)} liter, hitung BBM sebelum berangkat.',
      if (status == SeaStatus.tidakLayak)
        'Pantau terus informasi BMKG dan syahbandar sebelum memutuskan.'
      else
        'Bawa cadangan solar 10% dan kontak darurat yang sudah terisi.',
    ];

    return Recommendation.local(headline: headline, body: body, bullets: bullets);
  }
}
