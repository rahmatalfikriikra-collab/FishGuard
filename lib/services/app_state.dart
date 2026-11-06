import 'dart:convert';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import 'background_sync.dart';
import 'bmkg_service.dart';
import 'claude_service.dart';
import 'fuel_calculator.dart';
import 'kkp_pdpi_service.dart';
import 'land_mask.dart';
import 'local_data.dart';
import 'prep_service.dart';

/// A named emergency contact (PRD SOS-2: at most 3).
class EmergencyContact {
  EmergencyContact({required this.nama, required this.hp});

  final String nama;
  final String hp;

  Map<String, dynamic> toJson() => <String, dynamic>{'nama': nama, 'hp': hp};

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        nama: j['nama'] as String? ?? '',
        hp: j['hp'] as String? ?? '',
      );
}

/// Profile fields from PRD 5.7 / AUTH-4.
class UserProfile {
  UserProfile({
    this.nama = 'Nelayan Tamu',
    this.hp = '',
    this.namaKapal = '',
    this.dayaMesinPk = 5.5,
    this.umurMesin = 0,
    this.pelabuhanAsal = MapConfig.defaultPortName,
    this.tankLiters = 20,
    this.isGuest = true,
    List<EmergencyContact>? kontak,
  }) : kontak = kontak ?? <EmergencyContact>[];

  String nama;
  String hp;
  String namaKapal;
  double dayaMesinPk;
  int umurMesin;
  String pelabuhanAsal;
  double tankLiters;
  bool isGuest;
  List<EmergencyContact> kontak;

  String get engineAgeLabel => switch (umurMesin) {
        0 => 'Mesin Baru (< 5 tahun)',
        1 => 'Mesin Sedang (5 - 10 tahun)',
        _ => 'Mesin Tua (> 10 tahun)',
      };

  double get engineFactor => switch (umurMesin) { 0 => 1.0, 1 => 1.2, _ => 1.4 };

  Map<String, dynamic> toJson() => <String, dynamic>{
        'nama': nama,
        'hp': hp,
        'namaKapal': namaKapal,
        'dayaMesinPk': dayaMesinPk,
        'umurMesin': umurMesin,
        'pelabuhanAsal': pelabuhanAsal,
        'tankLiters': tankLiters,
        'isGuest': isGuest,
        'kontak': kontak.map((EmergencyContact c) => c.toJson()).toList(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        nama: j['nama'] as String? ?? 'Nelayan Tamu',
        hp: j['hp'] as String? ?? '',
        namaKapal: j['namaKapal'] as String? ?? '',
        dayaMesinPk: (j['dayaMesinPk'] as num?)?.toDouble() ?? 5.5,
        umurMesin: (j['umurMesin'] as num?)?.toInt() ?? 0,
        pelabuhanAsal: j['pelabuhanAsal'] as String? ?? MapConfig.defaultPortName,
        tankLiters: (j['tankLiters'] as num?)?.toDouble() ?? 20,
        isGuest: j['isGuest'] as bool? ?? true,
        kontak: (j['kontak'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// A recorded trip (PRD PROF-2).
class Trip {
  Trip({
    required this.id,
    required this.mulai,
    this.selesai,
    required this.berangkatLat,
    required this.berangkatLon,
    this.jarakKm = 0,
    this.bbmEstimasiL = 0,
    this.bbmAktualL,
    this.track = const <List<double>>[],
    this.visited = const <int>[],
    this.selesaiNormal = true,
  });

  final String id;
  final DateTime mulai;
  DateTime? selesai;
  final double berangkatLat;
  final double berangkatLon;
  double jarakKm;
  double bbmEstimasiL;

  /// FUEL-4: what the sailor says the trip actually burned, once they have
  /// filled up. Null until they answer — never guessed, never filled in from
  /// the estimate, or the calibration would learn from itself.
  double? bbmAktualL;
  List<List<double>> track;
  List<int> visited;
  bool selesaiNormal;

  Duration get durasi => (selesai ?? DateTime.now()).difference(mulai);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'mulai': mulai.toIso8601String(),
        'selesai': selesai?.toIso8601String(),
        'lat': berangkatLat,
        'lon': berangkatLon,
        'jarakKm': jarakKm,
        'bbmL': bbmEstimasiL,
        'bbmAktualL': bbmAktualL,
        'track': track,
        'visited': visited,
        'normal': selesaiNormal,
      };

  factory Trip.fromJson(Map<String, dynamic> j) => Trip(
        id: j['id'] as String,
        mulai: DateTime.parse(j['mulai'] as String),
        selesai: j['selesai'] == null
            ? null
            : DateTime.parse(j['selesai'] as String),
        berangkatLat: (j['lat'] as num).toDouble(),
        berangkatLon: (j['lon'] as num).toDouble(),
        jarakKm: (j['jarakKm'] as num?)?.toDouble() ?? 0,
        bbmEstimasiL: (j['bbmL'] as num?)?.toDouble() ?? 0,
        bbmAktualL: (j['bbmAktualL'] as num?)?.toDouble(),
        track: (j['track'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => (e as List<dynamic>)
                .map((dynamic v) => (v as num).toDouble())
                .toList())
            .toList(),
        visited: (j['visited'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic e) => (e as num).toInt())
            .toList(),
        selesaiNormal: j['normal'] as bool? ?? true,
      );
}

/// One recorded catch (PRD v1.x: "Catatan hasil tangkapan per titik dan umpan
/// balik akurasi DPI"). Kept on the device; PREP-9's upload queue picks it up
/// once the backend exists.
class CatchLog {
  CatchLog({
    required this.id,
    required this.waktu,
    required this.jenis,
    required this.beratKg,
    this.jumlah = 1,
    this.dpiNomor,
    this.dpiWpp = '',
    this.lat,
    this.lon,
    this.catatan = '',
  });

  final String id;
  final DateTime waktu;
  final String jenis;
  final double beratKg;
  final int jumlah;

  /// Which DPI point produced the catch — null when none was picked.
  final int? dpiNomor;
  final String dpiWpp;
  final double? lat;
  final double? lon;
  final String catatan;

  String get lokasiLabel {
    final int? nomor = dpiNomor;
    if (nomor != null) {
      return dpiWpp.isEmpty
          ? 'Titik DPI $nomor'
          : 'Titik DPI $nomor · WPP $dpiWpp';
    }
    if (lat != null && lon != null) {
      return '${lat!.toStringAsFixed(4)}, ${lon!.toStringAsFixed(4)}';
    }
    return 'Lokasi tidak dicatat';
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'waktu': waktu.toIso8601String(),
        'jenis': jenis,
        'beratKg': beratKg,
        'jumlah': jumlah,
        'dpiNomor': dpiNomor,
        'dpiWpp': dpiWpp,
        'lat': lat,
        'lon': lon,
        'catatan': catatan,
      };

  factory CatchLog.fromJson(Map<String, dynamic> j) => CatchLog(
        id: j['id'] as String,
        waktu: DateTime.parse(j['waktu'] as String),
        jenis: j['jenis'] as String? ?? 'Ikan',
        beratKg: (j['beratKg'] as num?)?.toDouble() ?? 0,
        jumlah: (j['jumlah'] as num?)?.toInt() ?? 1,
        dpiNomor: (j['dpiNomor'] as num?)?.toInt(),
        dpiWpp: j['dpiWpp'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble(),
        lon: (j['lon'] as num?)?.toDouble(),
        catatan: j['catatan'] as String? ?? '',
      );
}

/// Global app state: profile, settings, trips, catches, cached data and the
/// live position. Persisted through `shared_preferences` so the app works
/// offline after the first launch.
class AppState extends ChangeNotifier {
  AppState({
    LocalDataSource? dataSource,
    BmkgService? bmkg,
    KkpPdpiService? kkp,
  })  : _data = dataSource ?? LocalDataSource(),
        bmkg = bmkg ?? BmkgService(),
        kkp = kkp ?? KkpPdpiService();

  /// Live BMKG marine forecasts.
  final BmkgService bmkg;

  /// Live KKP DPI tables (image + OCR).
  final KkpPdpiService kkp;

  static const String _kProfile = 'profile';
  static const String _kTrips = 'trips';
  static const String _kDark = 'darkMode';
  static const String _kApiKey = 'apiKey';
  static const String _kModel = 'aiModel';
  static const String _kUseAi = 'useAi';
  static const String _kOnboarded = 'onboarded';
  static const String _kLoggedIn = 'loggedIn';
  static const String _kLastSync = 'lastSync';
  // Shared with the background worker: a table it downloaded while the app was
  // closed has to count here as today's data.
  static const String _kDpiFetchedAt = kDpiFetchedAtKey;
  static const String _kDpiTableDate = kDpiTableDateKey;
  static const String _kWeatherFetchedAt = 'weatherFetchedAt';
  static const String _kPrep = 'prepDone';
  static const String _kCatches = 'catches';
  static const String _kDpiCache = kDpiCacheKey;
  static const String _kWeatherCache = 'weatherCache';
  static const String _kAreaId = 'bmkgAreaId';
  static const String _kQueue = 'outboxQueue';
  static const String _kCalibration = 'fuelCalibration';
  static const String _kReminder = 'subuhReminder';
  static const String _kBgSync = 'bgSyncEnabled';
  static const String _kLandPrompted = 'lastLandPromptDate';
  static const String _kOwnSpots = 'ownSpots';
  static const String _kMapPackAt = 'mapPackDownloadedAt';

  /// Keys for the six "Siap Melaut" items (PRD HOME-3).
  static const String prepDpi = 'dpi';
  static const String prepCuaca = 'cuaca';
  static const String prepPeta = 'peta';
  static const String prepKontak = 'kontak';
  static const String prepGps = 'gps';
  static const String prepBaterai = 'baterai';

  final LocalDataSource _data;
  final Battery _battery = Battery();

  /// Notifications + WorkManager (PRD PREP-3 / PREP-4).
  final PrepService prep = PrepService();

  SharedPreferences? _prefs;

  UserProfile profile = UserProfile();
  List<Trip> trips = <Trip>[];
  List<CatchLog> catches = <CatchLog>[];

  /// MAP-6: spots the sailor marked himself, kept apart from the KKP DPI.
  List<OwnSpot> ownSpots = <OwnSpot>[];

  /// MAP-9: when the offline map pack was last staged, so the app can say how
  /// old the offline copy is instead of implying it is current.
  DateTime? mapPackDownloadedAt;

  List<DpiPoint> dpiPoints = <DpiPoint>[];
  List<WeatherArea> weatherAreas = <WeatherArea>[];

  bool darkMode = false;
  bool loggedIn = false;
  bool onboarded = false;
  String apiKey = '';
  String aiModel = ClaudeClient.defaultModel;
  bool useAi = true;

  DateTime? lastSync;
  Set<String> prepDone = <String>{};

  /// When the KKP table currently on the phone was actually downloaded.
  ///
  /// Kept apart from [lastSync] on purpose. `markSynced()` stages the bundled
  /// pack with no network at all, so a single "last sync" timestamp let the
  /// app claim fresh data after a download that never happened — which is the
  /// one thing a fisherman must never be told. These two only move when a real
  /// HTTP fetch succeeded.
  DateTime? dpiFetchedAt;

  /// The date of the table itself, which is what the sailor cares about: KKP
  /// publishes roughly a day late, so "downloaded at 11.40" and "table dated
  /// yesterday" are both true and only the second one describes the data.
  DateTime? dpiTableDate;

  /// When the BMKG forecast on the phone was actually downloaded.
  DateTime? weatherFetchedAt;

  /// Position: a real GPS fix when available, else the home port.
  double lat = MapConfig.defaultLat;
  double lon = MapConfig.defaultLon;
  bool gpsLocked = false;
  bool usingFallbackPosition = true;
  String? gpsError;

  /// Live trip.
  Trip? activeTrip;
  double tripDistanceKm = 0;

  /// Device battery, read on demand — the checklist shows it as-is.
  int? batteryLevel;

  bool loading = true;

  /// PRD PREP-9: everything that needs uploading waits here and is retried
  /// whenever the app comes back online. Nothing leaves the phone until it is
  /// actually delivered, so the queue is the record of what is still owed.
  List<OutboxItem> outbox = <OutboxItem>[];

  /// True while [flushOutbox] is running, so the UI can show progress and a
  /// second call cannot double-send.
  bool flushingOutbox = false;

  /// How many times each queued item has been retried, surfaced so a sailor
  /// can see the app has not given up.
  String? outboxLastError;

  /// FUEL-4: the personal multiplier learned from real trips, 1.0 = untouched.
  double fuelCalibration = 1.0;

  /// Number of finished trips the calibration was computed from.
  int calibrationSamples = 0;

  /// PREP-4: subuh reminder setting, defaulting to 04.30.
  bool reminderEnabled = true;
  int reminderHour = PrepService.defaultReminderHour;
  int reminderMinute = PrepService.defaultReminderMinute;

  /// PREP-3: whether the periodic background sync is switched on.
  bool backgroundSyncEnabled = true;

  /// PREP-11: true when the boat looks like it is still on land — inside
  /// [landRadiusKm] of the home port. Combined with signal this decides
  /// whether the Siap Melaut card leads the Beranda.
  bool get likelyOnLand {
    final double d = _distanceKm(lat, lon, MapConfig.defaultLat, MapConfig.defaultLon);
    return d <= landRadiusKm;
  }

  /// How close counts as "still at the harbour" (PRD PREP-11).
  static const double landRadiusKm = 5;

  /// True when the checklist should lead the Beranda (PREP-11): on land and
  /// online. The connectivity check is deliberately conservative — with no
  /// signal there is nothing to sync, so the card is not urgent.
  bool get showPrepFirst => likelyOnLand;

  static double _distanceKm(double lat1, double lon1, double lat2, double lon2) {
    return DpiPoint(
      nomor: 0,
      lat: lat1,
      lon: lon1,
      lonDms: '',
      latDms: '',
      wpp: '',
      date: DateTime.now(),
    ).distanceKmTo(lat2, lon2);
  }

  /// The BMKG area resolved from the last GPS fix, e.g. `P.A.05`.
  String bmkgAreaId = '';

  /// Which WPP the DPI view is following. `null` = not chosen yet.
  String dpiWpp = '';

  /// Last live-fetch error per source, for the honesty banner.
  String? dpiError;
  String? weatherError;

  /// True while a live call is in flight.
  bool loadingWeather = false;
  bool loadingDpi = false;

  /// Progress text for the DPI OCR pipeline.
  String dpiProgress = '';

  /// PRD: the app shows the forecast for *the area the boat is in*. When the
  /// area has been resolved from a GPS fix that area wins; otherwise the first
  /// bundle entry is a placeholder, not a real prediction.
  WeatherArea? get currentArea {
    if (weatherAreas.isEmpty) return null;
    if (bmkgAreaId.isNotEmpty) {
      for (final WeatherArea a in weatherAreas) {
        if (a.code == bmkgAreaId) return a;
      }
    }
    return weatherAreas.first;
  }

  /// True when [currentArea] really belongs to the boat's position.
  bool get areaIsResolved =>
      bmkgAreaId.isNotEmpty && currentArea?.code == bmkgAreaId;

  SeaStatus get seaStatus => currentArea?.statusNow() ?? SeaStatus.waspada;

  RecommendationService get recommendationService => RecommendationService(
        client: useAi && apiKey.trim().isNotEmpty
            ? ClaudeClient(apiKey: apiKey, model: aiModel)
            : null,
      );

  /// PRD PREP-6 freshness, re-based on the data that is actually on the phone.
  ///
  /// The original version measured [lastSync], which `markSynced()` used to
  /// touch without downloading anything. This one counts from the newest real
  /// download of either source, so it cannot show green for a bundled pack.
  String get freshnessLabel {
    if (!readyForSea) return downloadStatusLabel;
    return 'Data hari ini siap · ${formatJam(nowMostRecentDownload!)}';
  }

  /// The download that is currently making the data fresh, for display.
  DateTime? get nowMostRecentDownload {
    final DateTime? d = dpiFetchedAt;
    final DateTime? w = weatherFetchedAt;
    if (d == null) return w;
    if (w == null) return d;
    return d.isAfter(w) ? d : w;
  }

  /// The older of the two freshness timestamps — the one that decides whether
  /// the phone is fully current. Null when either source was never downloaded.
  DateTime? get oldestFreshness {
    final DateTime? d = dpiFetchedAt;
    final DateTime? w = weatherFetchedAt;
    if (d == null || w == null) return null;
    return d.isBefore(w) ? d : w;
  }

  /// Kept for the screens that still show the PRD's three-colour freshness
  /// rule. Derived from the real downloads so it can never disagree with the
  /// departure gate.
  int get freshnessBand {
    final DateTime? t = oldestFreshness;
    if (t == null) return 2;
    final Duration age = DateTime.now().difference(t);
    if (age.inHours >= 24) return 2;
    if (age.inHours >= 12) return 1;
    return 0;
  }

  /// The PRD's three-colour rule, now driven by [freshnessBand] so the chip
  /// and the departure gate can never tell the sailor two different stories.
  int get freshnessLevel => freshnessBand;

  /// The same calendar day in the boat's own timezone (WITA), which is the
  /// clock the sailor reads everywhere else in the app.
  static bool _sameWitaDay(DateTime? a, DateTime b) {
    if (a == null) return false;
    final DateTime x = a.toUtc().add(const Duration(hours: 8));
    final DateTime y = b.toUtc().add(const Duration(hours: 8));
    return x.year == y.year && x.month == y.month && x.day == y.day;
  }

  /// Whether today's KKP table has actually been downloaded onto this phone.
  ///
  /// Deliberately strict: the bundled pack that ships inside the APK does not
  /// count, because it was read on a build machine weeks before this trip.
  bool get dpiDownloadedToday =>
      _sameWitaDay(dpiFetchedAt, DateTime.now()) && dpiPoints.isNotEmpty;

  /// Whether today's BMKG forecast has actually been downloaded.
  bool get weatherDownloadedToday =>
      _sameWitaDay(weatherFetchedAt, DateTime.now()) && weatherAreas.isNotEmpty;

  /// What still has to be downloaded before the boat leaves, in the order the
  /// sailor should deal with it. Empty means the phone is ready.
  ///
  /// This is the "wajib unduh sebelum melaut" rule. It exists because the app
  /// works offline from a bundled snapshot, and that snapshot is exactly the
  /// thing that goes stale without anyone noticing: the map still draws, the
  /// points still have numbers, and nothing on screen says the fish moved.
  List<String> get departureBlockers {
    final List<String> out = <String>[];
    if (!dpiDownloadedToday) {
      out.add(
        dpiFetchedAt == null
            ? 'Tabel DPI KKP belum pernah diunduh di ponsel ini.'
            : 'Tabel DPI KKP belum diunduh hari ini '
                '(terakhir ${formatTanggal(dpiFetchedAt!)}).',
      );
    }
    if (!weatherDownloadedToday) {
      out.add(
        weatherFetchedAt == null
            ? 'Prakiraan cuaca BMKG belum pernah diunduh di ponsel ini.'
            : 'Prakiraan cuaca BMKG belum diunduh hari ini '
                '(terakhir ${formatTanggal(weatherFetchedAt!)}).',
      );
    }
    return out;
  }

  bool get readyForSea => departureBlockers.isEmpty;

  /// True while [autoRefresh] has a check in flight, so two triggers (a resume
  /// and a timer) cannot both download the same table.
  bool autoRefreshing = false;

  /// The last time an auto-refresh actually looked at the portal.
  DateTime? lastAutoCheckAt;

  /// Fetches whatever is genuinely new, and does nothing when nothing is.
  ///
  /// This is the piece that makes the data *follow* KKP and BMKG rather than
  /// freeze at whatever the pack shipped with. It is called on every app
  /// resume, and by a periodic timer while the app is open, so a table KKP
  /// publishes mid-morning appears without the sailor doing anything.
  ///
  /// Cheap by design: `latestAvailableDate` answers "is there a newer table?"
  /// with one or two small JSON requests, and the ~330 KB image plus OCR pass
  /// only runs when the answer is yes. BMKG's forecast is a single small JSON
  /// file, so it is simply re-read whenever it is more than [weatherMaxAge]
  /// old.
  ///
  /// Never throws and never touches the user's session: a failure leaves the
  /// previous data in place and records why in [dpiError]/[weatherError].
  Future<void> autoRefresh({
    Duration weatherMaxAge = const Duration(hours: 6),
  }) async {
    if (autoRefreshing || loading || !readyToFetch) return;
    autoRefreshing = true;
    lastAutoCheckAt = DateTime.now();
    notifyListeners();
    try {
      await _autoRefreshWeather(weatherMaxAge);
      await _autoRefreshDpi();
    } finally {
      autoRefreshing = false;
      notifyListeners();
    }
  }

  /// Whether a fetch can run at all. The GPS does not have to be locked: the
  /// home-port fallback is a real position, and refusing to update because the
  /// phone is indoors would defeat the point.
  bool get readyToFetch => !loading;

  Future<void> _autoRefreshWeather(Duration maxAge) async {
    final DateTime? at = weatherFetchedAt;
    if (at != null && DateTime.now().difference(at) < maxAge) return;
    if (loadingWeather) return;
    if (_sameWitaDay(at, DateTime.now()) && weatherAreas.isNotEmpty) {
      // Already have today's forecast and it is fresh enough.
      return;
    }
    try {
      await fetchWeatherForPosition();
    } on Object {
      // fetchWeatherForPosition already turns failures into weatherError.
    }
  }

  Future<void> _autoRefreshDpi() async {
    if (loadingDpi) return;
    final WppZone? zone = zoneHere;
    if (zone == null) return;
    if (dpiDownloadedToday && dpiWpp == zone.kode) {
      // Today's table for this zone is already here. Nothing KKP could have
      // published since would be newer than today.
      return;
    }
    try {
      // fetchDpi walks back to the newest published table by itself, so this
      // is a "catch up" rather than a blind retry of today.
      await fetchDpi(zone: zone, date: DateTime.now());
    } on Object {
      // fetchDpi already records dpiError.
    }
  }

  /// One line describing the age of the data actually on the phone, for the
  /// screens that show a status chip.
  String get downloadStatusLabel {
    if (readyForSea) {
      final DateTime? d = dpiTableDate;
      return d == null
          ? 'Data hari ini siap'
          : 'Data hari ini siap (tabel KKP ${formatTanggal(d)})';
    }
    return departureBlockers.first;
  }

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final SharedPreferences p = _prefs!;

    final String? profileJson = p.getString(_kProfile);
    if (profileJson != null) {
      try {
        profile = UserProfile.fromJson(
            jsonDecode(profileJson) as Map<String, dynamic>);
      } catch (_) {}
    }

    final String? tripsJson = p.getString(_kTrips);
    if (tripsJson != null) {
      try {
        trips = (jsonDecode(tripsJson) as List<dynamic>)
            .map((dynamic e) => Trip.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final String? catchesJson = p.getString(_kCatches);
    if (catchesJson != null) {
      try {
        catches = (jsonDecode(catchesJson) as List<dynamic>)
            .map((dynamic e) => CatchLog.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    darkMode = p.getBool(_kDark) ?? false;
    loggedIn = p.getBool(_kLoggedIn) ?? false;
    onboarded = p.getBool(_kOnboarded) ?? false;
    apiKey = p.getString(_kApiKey) ?? '';
    aiModel = p.getString(_kModel) ?? ClaudeClient.defaultModel;
    useAi = p.getBool(_kUseAi) ?? true;
    final String? sync = p.getString(_kLastSync);
    lastSync = sync == null ? null : DateTime.tryParse(sync);
    dpiFetchedAt = DateTime.tryParse(p.getString(_kDpiFetchedAt) ?? '');
    dpiTableDate = DateTime.tryParse(p.getString(_kDpiTableDate) ?? '');
    weatherFetchedAt = DateTime.tryParse(p.getString(_kWeatherFetchedAt) ?? '');
    prepDone = (p.getStringList(_kPrep) ?? <String>[]).toSet();

    _restoreOutbox();
    _restoreOwnSpots();
    mapPackDownloadedAt =
        DateTime.tryParse(p.getString(_kMapPackAt) ?? '');
    fuelCalibration = (p.getDouble(_kCalibration) ?? 1.0).clamp(0.6, 1.8);
    calibrationSamples = p.getInt('${_kCalibration}Samples') ?? 0;
    reminderEnabled = p.getBool(_kReminder) ?? true;
    reminderHour = p.getInt('${_kReminder}H') ?? PrepService.defaultReminderHour;
    reminderMinute =
        p.getInt('${_kReminder}M') ?? PrepService.defaultReminderMinute;
    backgroundSyncEnabled = p.getBool(_kBgSync) ?? true;

    await refreshData();
    loading = false;
    notifyListeners();
  }

  /// Loads the bundled snapshot, then overlays anything cached from a previous
  /// live fetch. This is the "darat-dulu" path: it works with no signal.
  Future<void> refreshData() async {
    // The land mask decides whether a published point sits on a beach, so it
    // has to be in memory before any point is turned into a marker.
    await LandMask.instance();

    dpiPoints = await _data.loadDpi(forceReload: true);
    weatherAreas = await _data.loadWeather(forceReload: true);

    _restoreCachedDpi();
    _restoreCachedWeather();
    _stampLandFlags();

    notifyListeners();
  }

  /// Recomputes [DpiPoint.onLand] for every loaded point.
  ///
  /// The flag also comes from the asset, but a point cached by an older build
  /// (or one read before the mask finished loading) would carry a stale value.
  /// Recomputing is a handful of bitmap lookups, so it runs on every load.
  void _stampLandFlags() {
    final LandMask? mask = LandMask.loaded;
    if (mask == null) return;
    // Titik di daratan selalu difilter/dibuang demi akurasi nelayan.
    dpiPoints = dpiPoints
        .where((DpiPoint p) => !mask.isLand(p.lat, p.lon) && !p.onLand)
        .toList();
  }

  // ------------------------------------------------------------ live: BMKG

  /// Fetches the BMKG forecast for the area containing the current position.
  ///
  /// Resolves the area from the wilmetos polygons first, so the sailor never
  /// has to pick one; falls back to the nearest area when the fix lands
  /// outside every polygon (open sea).
  Future<bool> fetchWeatherForPosition({void Function(String)? onProgress}) async {
    loadingWeather = true;
    weatherError = null;
    notifyListeners();
    try {
      onProgress?.call('Mencari area perairan BMKG…');
      BmkgAreaRef? ref = await bmkg.areaForPosition(lat, lon);
      ref ??= await bmkg.nearestArea(lat, lon);
      if (ref == null) {
        weatherError = 'Tidak ada area perairan BMKG untuk posisi ini.';
        return false;
      }

      // The bulletin is what carries BMKG's own warning level per perairan.
      // A failure here must not sink the forecast, so it is best-effort: the
      // area simply stays without a bulletin warning and the wave/wind
      // thresholds in `statusNow` still decide the status.
      onProgress?.call('Memeriksa peringatan dini BMKG…');
      try {
        await bmkg.loadWarnings();
      } on BmkgException {
        // Ignored on purpose; see above.
      }

      onProgress?.call('Mengambil prakiraan ${ref.name}…');
      final WeatherArea area = await bmkg.loadArea(ref.id, fallbackName: ref.name);

      bmkgAreaId = ref.id;
      weatherAreas = <WeatherArea>[
        area,
        ...weatherAreas.where((WeatherArea a) => a.code != area.code),
      ];
      lastSync = DateTime.now();
      weatherFetchedAt = lastSync;
      await _prefs?.setString(_kAreaId, bmkgAreaId);
      await _prefs?.setString(_kLastSync, lastSync!.toIso8601String());
      await _prefs?.setString(
        _kWeatherFetchedAt,
        weatherFetchedAt!.toIso8601String(),
      );
      await _prefs?.setString(_kWeatherCache, jsonEncode(area.toJson()));
      return true;
    } on BmkgException catch (e) {
      weatherError = e.message;
      return false;
    } on Object catch (e) {
      weatherError = 'BMKG tidak bisa dihubungi. ($e)';
      return false;
    } finally {
      loadingWeather = false;
      notifyListeners();
    }
  }

  void _restoreCachedWeather() {
    final String? raw = _prefs?.getString(_kWeatherCache);
    if (raw == null) return;
    try {
      final WeatherArea cached = WeatherArea.fromJson(
          jsonDecode(raw) as Map<String, dynamic>);
      // Only trust the cache if it has hours that are still ahead of us.
      final bool useful = cached.hours
          .any((ForecastHour h) => h.time.isAfter(DateTime.now()));
      if (!useful) return;
      bmkgAreaId = _prefs?.getString(_kAreaId) ?? cached.code;
      weatherAreas = <WeatherArea>[
        cached,
        ...weatherAreas.where((WeatherArea a) => a.code != cached.code),
      ];
    } catch (_) {
      // A corrupt cache must never block start-up.
    }
  }

  // ------------------------------------------------------------- live: KKP

  /// Downloads the KKP DPI table for [zone] on [date] and reads it with OCR.
  ///
  /// KKP does not publish a table every day, and the current day is usually
  /// missing until they do. So when [date] has no table, this walks back to the
  /// newest date that does (see [KkpPdpiService.latestAvailableDate]) and reads
  /// that one instead — the sailor gets the most recent DPI rather than an
  /// error. The returned result's `date` says which day it actually used.
  ///
  /// On success the points are cached so the next offline launch still has
  /// them. On failure the previous points stay put and [dpiError] explains why.
  Future<DpiFetchResult?> fetchDpi({
    required WppZone zone,
    required DateTime date,
    bool replace = true,
  }) async {
    loadingDpi = true;
    dpiError = null;
    dpiProgress = '';
    notifyListeners();
    try {
      void progress(String m) {
        dpiProgress = m;
        notifyListeners();
      }

      DateTime target = date;
      try {
        await kkp.resolveImages(zone, date);
      } on PdpiException {
        // Nothing published for that day. Find the most recent one that is.
        final DateTime? latest = await kkp.latestAvailableDate(
          zone,
          from: date,
          onProgress: progress,
        );
        if (latest == null) {
          throw PdpiException(
            'Belum ada tabel DPI untuk WPP ${zone.kode} dalam 7 hari terakhir. '
            'Portal KKP biasanya menerbitkan tabel sehari setelahnya — '
            'coba lagi nanti atau pilih zona lain.',
          );
        }
        target = latest;
      }

      final DpiFetchResult result = await kkp.fetchAndOcr(
        zone,
        target,
        onProgress: progress,
      );

      if (result.rows.isNotEmpty) {
        // LandMask.loaded is populated by refreshData() at startup; if this is
        // the first thing the app ever does, make sure it is there.
        await LandMask.instance();
        final List<DpiPoint> fresh = result.toPoints();
        if (replace) {
          dpiPoints = <DpiPoint>[
            ...fresh,
            ...dpiPoints.where((DpiPoint p) => p.wpp != zone.kode),
          ];
        } else {
          dpiPoints = <DpiPoint>[...dpiPoints, ...fresh];
        }
        dpiWpp = zone.kode;
        // A real download of a real table: this is the only place the DPI
        // freshness timestamps may move.
        dpiFetchedAt = DateTime.now();
        dpiTableDate = result.date;
        await _prefs?.setString(
          _kDpiFetchedAt,
          dpiFetchedAt!.toIso8601String(),
        );
        await _prefs?.setString(
          _kDpiTableDate,
          dpiTableDate!.toIso8601String(),
        );
        await _persistDpi();
        // Tell the background worker which zone to keep fresh (PREP-3). It
        // runs in its own isolate with no AppState, so the answer lives in
        // shared_preferences.
        await _prefs?.setString(kBgZoneKey, zone.kode);
      }
      dpiError = result.error;
      return result;
    } on PdpiException catch (e) {
      dpiError = e.message;
      return null;
    } on Object catch (e) {
      dpiError = 'Gagal mengambil data DPI. ($e)';
      return null;
    } finally {
      loadingDpi = false;
      dpiProgress = '';
      notifyListeners();
    }
  }

  Future<void> _persistDpi() async {
    // Cap what we keep: the map only needs the current-day points.
    final List<DpiPoint> keep = dpiPoints.take(400).toList();
    await _prefs?.setString(
      _kDpiCache,
      jsonEncode(<String, dynamic>{
        'saved': DateTime.now().toIso8601String(),
        'points': keep.map((DpiPoint p) => p.toJson()).toList(),
      }),
    );
  }

  void _restoreCachedDpi() {
    final String? raw = _prefs?.getString(_kDpiCache);
    if (raw == null) return;
    try {
      final Map<String, dynamic> j = jsonDecode(raw) as Map<String, dynamic>;
      final List<DpiPoint> cached = (j['points'] as List<dynamic>)
          .map((dynamic e) => DpiPoint.fromJson(e as Map<String, dynamic>))
          .toList();
      if (cached.isEmpty) return;
      // Live OCR results replace the bundled WPP files they overlap, so the
      // map never shows two different point 7s at once.
      final Set<String> liveWpps = cached.map((DpiPoint p) => p.wpp).toSet();
      dpiPoints = <DpiPoint>[
        ...cached,
        ...dpiPoints.where((DpiPoint p) => !liveWpps.contains(p.wpp)),
      ];
      dpiWpp = liveWpps.length == 1 ? liveWpps.first : '';
    } catch (_) {
      // Ignore a corrupt cache.
    }
  }

  Future<void> _persistProfile() async {
    await _prefs?.setString(_kProfile, jsonEncode(profile.toJson()));
  }

  Future<void> saveProfile(UserProfile next) async {
    profile = next;
    await _persistProfile();
    notifyListeners();
  }

  Future<void> setDarkMode(bool value) async {
    darkMode = value;
    await _prefs?.setBool(_kDark, value);
    notifyListeners();
  }

  Future<void> setApiKey(String value) async {
    apiKey = value.trim();
    await _prefs?.setString(_kApiKey, apiKey);
    notifyListeners();
  }

  Future<void> setAiModel(String value) async {
    aiModel = value;
    await _prefs?.setString(_kModel, value);
    notifyListeners();
  }

  Future<void> setUseAi(bool value) async {
    useAi = value;
    await _prefs?.setBool(_kUseAi, value);
    notifyListeners();
  }

  Future<void> completeOnboarding() async {
    onboarded = true;
    await _prefs?.setBool(_kOnboarded, true);
    notifyListeners();
  }

  Future<void> login(UserProfile next) async {
    profile = next;
    loggedIn = true;
    onboarded = true;
    await _prefs?.setBool(_kLoggedIn, true);
    await _prefs?.setBool(_kOnboarded, true);
    await _persistProfile();
    notifyListeners();
  }

  Future<void> logout() async {
    loggedIn = false;
    activeTrip = null;
    tripDistanceKm = 0;
    await _prefs?.setBool(_kLoggedIn, false);
    notifyListeners();
  }

  /// Reads the device battery once and records whether it clears the 80 % mark.
  /// Failures are silent: an unreadable battery must not block the checklist.
  Future<void> readBattery() async {
    try {
      batteryLevel = await _battery.batteryLevel;
    } catch (_) {
      batteryLevel = null;
    }
    if (batteryLevel != null && batteryLevel! >= 80) {
      prepDone.add(prepBaterai);
    } else {
      prepDone.remove(prepBaterai);
    }
    notifyListeners();
  }

  /// A checklist item counts as ready only if the fact behind it still holds —
  /// a stored flag alone would let "Kontak darurat" stay green after the
  /// contact was deleted.
  bool prepReady(String key) {
    if (!prepDone.contains(key)) return false;
    return switch (key) {
      prepKontak => profile.kontak.any((EmergencyContact c) => c.hp.trim().isNotEmpty),
      prepGps => gpsLocked,
      prepBaterai => (batteryLevel ?? 0) >= 80,
      // Green means "today's data is on this phone", not "the APK shipped
      // with something to draw". The bundled pack alone is not ready for sea.
      prepDpi => dpiDownloadedToday,
      prepCuaca => weatherDownloadedToday,
      _ => true,
    };
  }

  /// "Siapkan Data": stages the bundled pack and re-evaluates the device items.
  ///
  /// No network call — the assets are already in the APK. That is exactly why
  /// it must not stamp [lastSync] or [dpiFetchedAt]: doing so once made the
  /// app report fresh data after a "sync" that downloaded nothing. The
  /// download timestamps belong to [fetchDpi] and [fetchWeatherForPosition]
  /// alone; this method only re-reads what is already on disk and re-runs the
  /// checklist.
  Future<void> markSynced() async {
    await refreshData();
    await readBattery();
    final Set<String> next = <String>{};
    if (dpiDownloadedToday) next.add(prepDpi);
    if (weatherDownloadedToday) next.add(prepCuaca);
    next.add(prepPeta);
    if (profile.kontak.any((EmergencyContact c) => c.hp.trim().isNotEmpty)) {
      next.add(prepKontak);
    }
    if (gpsLocked) next.add(prepGps);
    if ((batteryLevel ?? 0) >= 80) next.add(prepBaterai);
    prepDone = next;
    await _prefs?.setStringList(_kPrep, prepDone.toList());
    notifyListeners();
  }

  Future<void> setPrepItem(String key, bool done) async {
    if (done) {
      prepDone.add(key);
    } else {
      prepDone.remove(key);
    }
    await _prefs?.setStringList(_kPrep, prepDone.toList());
    notifyListeners();
  }

  void updatePosition(double newLat, double newLon, {bool locked = true}) {
    final bool wasLocked = gpsLocked;
    lat = newLat;
    lon = newLon;
    gpsLocked = locked;
    usingFallbackPosition = false;
    gpsError = null;
    if (locked && !wasLocked) {
      prepDone.add(prepGps);
      _prefs?.setStringList(_kPrep, prepDone.toList());
    }
    if (activeTrip != null) {
      final Trip t = activeTrip!;
      if (t.track.isNotEmpty) {
        final List<double> last = t.track.last;
        tripDistanceKm += _haversine(last[0], last[1], newLat, newLon);
      }
      t.track = <List<double>>[...t.track, <double>[newLat, newLon]];
      t.jarakKm = tripDistanceKm;
    }
    notifyListeners();
  }

  void setGpsError(String message) {
    gpsError = message;
    gpsLocked = false;
    usingFallbackPosition = true;
    notifyListeners();
  }

  /// The WPP zone this boat is in, resolved from the real published points.
  ///
  /// Falls back to the coarse box test only when nothing is loaded yet.
  WppZone? get zoneHere =>
      WppZone.nearestZone(lat, lon, dpiPoints) ??
      WppZone.forPosition(lat, lon);

  /// The closest published points, never including one that sits on land.
  ///
  /// A recommendation is a destination: the app must not tell a sailor to sail
  /// onto a beach. Land points stay visible on the chart, marked, so the data
  /// is still shown honestly — they are simply not offered as a place to go.
  List<DpiPoint> nearestDpi({int limit = 5, double? radiusKm}) =>
      LocalDataSource.nearby(
        dpiPoints.where((DpiPoint p) => !p.onLand).toList(),
        lat,
        lon,
        limit: limit,
        radiusKm: radiusKm,
      );

  void startTrip() {
    tripDistanceKm = 0;
    activeTrip = Trip(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      mulai: DateTime.now(),
      berangkatLat: lat,
      berangkatLon: lon,
      track: <List<double>>[
        <double>[lat, lon]
      ],
    );
    notifyListeners();
  }

  void markVisited(int nomor) {
    final Trip? t = activeTrip;
    if (t == null || t.visited.contains(nomor)) return;
    t.visited = <int>[...t.visited, nomor];
    notifyListeners();
  }

  Future<Trip?> finishTrip({required double bbmLiters}) async {
    final Trip? t = activeTrip;
    if (t == null) return null;
    t.selesai = DateTime.now();
    t.bbmEstimasiL = bbmLiters;
    t.jarakKm = tripDistanceKm;
    trips = <Trip>[t, ...trips];
    activeTrip = null;
    tripDistanceKm = 0;
    await _persistTrips();
    // PREP-9: the track is queued the moment it is closed. If the phone is
    // still at sea it waits in the outbox until there is a signal.
    await enqueue(OutboxKind.jejak, <String, dynamic>{
      'tripId': t.id,
      'mulai': t.mulai.toIso8601String(),
      'selesai': t.selesai?.toIso8601String(),
      'jarakKm': t.jarakKm,
      'bbmEstimasiL': t.bbmEstimasiL,
      'visited': t.visited,
      'track': t.track,
    });
    notifyListeners();
    return t;
  }

  Future<void> _persistTrips() async {
    await _prefs?.setString(
      _kTrips,
      jsonEncode(trips.map((Trip e) => e.toJson()).toList()),
    );
  }

  /// FUEL-4: records what a finished trip actually burned and folds it into
  /// the personal calibration.
  ///
  /// Returns the new multiplier. Nothing is learned when the trip had no
  /// estimate to compare against, so a trip recorded without fuel data never
  /// bends the model.
  Future<double> recordActualFuel(String tripId, double actualLiters) async {
    final int index = trips.indexWhere((Trip t) => t.id == tripId);
    if (index < 0) return fuelCalibration;
    final Trip t = trips[index];
    if (actualLiters <= 0) return fuelCalibration;
    t.bbmAktualL = actualLiters;
    await _persistTrips();

    final double estimate = FuelCalculator.estimate(
      powerPk: profile.dayaMesinPk,
      condition: profile.umurMesin,
      calibration: fuelCalibration,
      distanceKm: t.jarakKm > 0 ? t.jarakKm : null,
      hours: t.jarakKm > 0 ? null : t.durasi.inMinutes / 60.0,
    ).totalLiters;
    if (estimate <= 0) {
      notifyListeners();
      return fuelCalibration;
    }
    return calibrateFuel(
      actualLiters: actualLiters,
      estimatedLiters: estimate,
    );
  }

  // ---------------------------------------------------------------- catches

  /// Total weight recorded for a calendar day.
  double catchKgOn(DateTime day) => catches
      .where((CatchLog c) => samaHari(c.waktu, day))
      .fold<double>(0, (double sum, CatchLog c) => sum + c.beratKg);

  double get catchKgToday => catchKgOn(DateTime.now());

  double get catchKgTotal =>
      catches.fold<double>(0, (double sum, CatchLog c) => sum + c.beratKg);

  /// The DPI point with the best average catch, once at least two catches have
  /// been logged against it — the raw material for the accuracy feedback.
  MapEntry<int, double>? get bestDpiByCatch {
    final Map<int, List<double>> byPoint = <int, List<double>>{};
    for (final CatchLog c in catches) {
      final int? nomor = c.dpiNomor;
      if (nomor == null) continue;
      byPoint.putIfAbsent(nomor, () => <double>[]).add(c.beratKg);
    }
    MapEntry<int, double>? best;
    for (final MapEntry<int, List<double>> e in byPoint.entries) {
      if (e.value.length < 2) continue;
      final double avg =
          e.value.reduce((double a, double b) => a + b) / e.value.length;
      if (best == null || avg > best.value) {
        best = MapEntry<int, double>(e.key, avg);
      }
    }
    return best;
  }

  Future<void> addCatch(CatchLog entry) async {
    catches = <CatchLog>[entry, ...catches];
    await _persistCatches();
    // PREP-9: the catch report is queued as well, and carries the DPI point
    // it was logged against so the accuracy feedback survives the wait.
    await enqueue(OutboxKind.tangkapan, entry.toJson());
    notifyListeners();
  }

  Future<void> deleteCatch(String id) async {
    catches = catches.where((CatchLog c) => c.id != id).toList();
    await _persistCatches();
    notifyListeners();
  }

  Future<void> _persistCatches() async {
    await _prefs?.setString(
      _kCatches,
      jsonEncode(catches.map((CatchLog e) => e.toJson()).toList()),
    );
  }

  static double _haversine(double lat1, double lon1, double lat2, double lon2) {
    final DpiPoint probe = DpiPoint(
      nomor: 0,
      lat: lat1,
      lon: lon1,
      lonDms: '',
      latDms: '',
      wpp: '',
      date: DateTime.now(),
    );
    return probe.distanceKmTo(lat2, lon2);
  }

  // ------------------------------------------------------------- outbox (9)

  /// Queues something that needs uploading (PRD PREP-9). Called at the moment
  /// the data is recorded, so an app kill or a dead battery cannot lose it —
  /// the sea-side record is written to disk before the sailor sees "saved".
  Future<void> enqueue(OutboxKind kind, Map<String, dynamic> payload) async {
    final OutboxItem item = OutboxItem(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      kind: kind,
      createdAt: DateTime.now(),
      payload: payload,
    );
    outbox = <OutboxItem>[...outbox, item];
    await _persistOutbox();
    notifyListeners();
  }

  /// Items still owed to the server, oldest first.
  List<OutboxItem> get pendingOutbox =>
      outbox.where((OutboxItem i) => !i.delivered).toList();

  /// True when [flushOutbox] can do something useful.
  bool get hasPendingOutbox => outbox.any((OutboxItem i) => !i.delivered);

  /// Tries to deliver everything queued.
  ///
  /// There is no backend yet (PRD section 7 describes one, but none is
  /// deployed), so nothing here pretends to have sent anything: the items are
  /// marked [OutboxItem.attempts] and the error says plainly that delivery is
  /// not available. When a backend URL is configured this is the single place
  /// that changes.
  ///
  /// Returns the number of items delivered.
  Future<int> flushOutbox() async {
    if (flushingOutbox) return 0;
    final List<OutboxItem> pending = pendingOutbox;
    if (pending.isEmpty) return 0;

    flushingOutbox = true;
    outboxLastError = null;
    notifyListeners();

    int delivered = 0;
    try {
      for (final OutboxItem item in pending) {
        item.attempts += 1;
        // Honest failure: with no endpoint configured, the queue keeps the
        // data instead of dropping it. The UI states this rather than
        // showing a fake "terkirim".
        item.lastError = _outboxEndpoint.isEmpty
            ? 'Server FishGuard belum tersedia — data menunggu di HP.'
            : 'Gagal terkirim. Akan dicoba lagi.';
        if (_outboxEndpoint.isNotEmpty) {
          // Placeholder for the real POST once PRD section 7's backend ships.
          item.deliveredAt = null;
        }
      }
      outboxLastError = pending.first.lastError;
      await _persistOutbox();
    } finally {
      flushingOutbox = false;
      notifyListeners();
    }
    return delivered;
  }

  /// Empty until the FishGuard backend exists. Kept as one named constant so
  /// turning delivery on is a one-line change, not a hunt through the code.
  static const String _outboxEndpoint = '';

  // ------------------------------------------------ own fishing spots (MAP-6)

  /// Marks the boat's current position as a spot of the sailor's own.
  ///
  /// Kept in its own list on purpose: these are personal knowledge, not the
  /// government's daily recommendation, and the two are shown with different
  /// markers so neither is mistaken for the other.
  Future<OwnSpot> addOwnSpot({String name = '', String note = ''}) async {
    final OwnSpot spot = OwnSpot(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      lat: lat,
      lon: lon,
      createdAt: DateTime.now(),
      name: name,
      note: note,
    );
    ownSpots = <OwnSpot>[...ownSpots, spot];
    await _persistOwnSpots();
    notifyListeners();
    return spot;
  }

  Future<void> removeOwnSpot(String id) async {
    ownSpots = ownSpots.where((OwnSpot s) => s.id != id).toList();
    await _persistOwnSpots();
    notifyListeners();
  }

  /// How many of the sailor's own spots fall inside a radius — used by the map
  /// header so the count is visible without opening the list.
  List<OwnSpot> ownSpotsNear(double radiusKm) => ownSpots
      .where((OwnSpot s) => _distanceKm(s.lat, s.lon, lat, lon) <= radiusKm)
      .toList()
    ..sort((OwnSpot a, OwnSpot b) =>
        _distanceKm(a.lat, a.lon, lat, lon)
            .compareTo(_distanceKm(b.lat, b.lon, lat, lon)));

  Future<void> _persistOwnSpots() async {
    await _prefs?.setString(
      _kOwnSpots,
      jsonEncode(ownSpots.map((OwnSpot s) => s.toJson()).toList()),
    );
  }

  void _restoreOwnSpots() {
    final String? raw = _prefs?.getString(_kOwnSpots);
    if (raw == null) return;
    try {
      ownSpots = (jsonDecode(raw) as List<dynamic>)
          .map((dynamic e) => OwnSpot.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      // A corrupt list must not stop the app from starting; the sailor loses
      // only the saved spots, and the app keeps working.
      ownSpots = <OwnSpot>[];
    }
  }

  /// MAP-9: the offline pack is already inside the APK, so "downloading" it is
  /// staging what the device can already reach — the DPI rows for the WPP near
  /// the home port plus the forecast for the port's own area. Recording the
  /// moment tells the sailor how fresh the offline copy is.
  ///
  /// Returns whether anything beyond the bundled floor was actually fetched;
  /// with no signal the bundled pack still covers the 100 km around the port,
  /// and the return value says so rather than claiming a download.
  Future<bool> downloadOfflineArea() async {
    bool gotSomething = false;
    // The offline pack is for the home port, so resolve the zone from the
    // port's position — against the real published points when they are
    // loaded, and the coarse box test only as a last resort.
    final WppZone? zone =
        WppZone.nearestZone(MapConfig.defaultLat, MapConfig.defaultLon, dpiPoints) ??
            WppZone.forPosition(MapConfig.defaultLat, MapConfig.defaultLon);
    if (zone != null) {
      final DpiFetchResult? r =
          await fetchDpi(zone: zone, date: DateTime.now(), replace: false);
      gotSomething = r != null && r.rows.isNotEmpty;
    }
    // Only a fetch that actually brought back rows may move this timestamp.
    // Stamping it after a failed download made the map report "diperbarui
    // barusan" over data that was downloaded days ago — the same false
    // freshness the DPI and weather timestamps were fixed to stop claiming.
    // It also mattered beyond the label: _maybeAutoRefresh() skips the retry
    // for 24 hours once this is recent, so a failed attempt used to postpone
    // the next one by a day.
    if (gotSomething) {
      mapPackDownloadedAt = DateTime.now();
      await _prefs?.setString(
        _kMapPackAt,
        mapPackDownloadedAt!.toIso8601String(),
      );
    }
    notifyListeners();
    return gotSomething;
  }

  Future<void> _persistOutbox() async {
    await _prefs?.setString(
      _kQueue,
      jsonEncode(outbox.map((OutboxItem i) => i.toJson()).toList()),
    );
  }

  void _restoreOutbox() {
    final String? raw = _prefs?.getString(_kQueue);
    if (raw == null) return;
    try {
      outbox = (jsonDecode(raw) as List<dynamic>)
          .map((dynamic e) => OutboxItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } on Object {
      // A corrupt queue must not block start-up.
    }
  }

  // ------------------------------------------------------- calibration (4)

  /// FUEL-4: learns a personal multiplier from what the boat actually burned.
  ///
  /// [actualLiters] comes from the sailor after a trip; the estimate is
  /// recomputed with the same inputs so the ratio is like-for-like. The
  /// learning rate is deliberately slow (0.3) and the result is clamped to
  /// 0.6–1.8: one lucky or unlucky day must not swing the estimate wildly,
  /// and a fisherman who reports nonsense should not poison every later
  /// prediction.
  Future<double> calibrateFuel({
    required double actualLiters,
    required double estimatedLiters,
  }) async {
    if (actualLiters <= 0 || estimatedLiters <= 0) return fuelCalibration;
    final double ratio = (actualLiters / estimatedLiters).clamp(0.5, 2.0);
    const double rate = 0.3;
    final double next =
        (fuelCalibration * (1 - rate) + ratio * rate).clamp(0.6, 1.8);
    fuelCalibration = next;
    calibrationSamples += 1;
    await _prefs?.setDouble(_kCalibration, fuelCalibration);
    await _prefs?.setInt('${_kCalibration}Samples', calibrationSamples);
    notifyListeners();
    return fuelCalibration;
  }

  Future<void> resetCalibration() async {
    fuelCalibration = 1.0;
    calibrationSamples = 0;
    await _prefs?.setDouble(_kCalibration, 1.0);
    await _prefs?.setInt('${_kCalibration}Samples', 0);
    notifyListeners();
  }

  // --------------------------------------------------- reminder & sync (3/4)

  Future<void> setBackgroundSync(bool enabled) async {
    backgroundSyncEnabled = enabled;
    await _prefs?.setBool(_kBgSync, enabled);
    // The worker needs to know which zone to keep fresh; without one it has
    // nothing to fetch, so it is written whenever the setting is enabled.
    if (enabled && dpiWpp.isNotEmpty) {
      await _prefs?.setString(kBgZoneKey, dpiWpp);
      await prep.registerBackgroundSync();
    } else if (!enabled) {
      await prep.cancelBackgroundSync();
    }
    notifyListeners();
  }

  /// Stores the reminder time (PREP-4) and reschedules the notification.
  /// Returns false when the platform refused, so the UI can say so.
  Future<bool> setReminder({required bool enabled, int? hour, int? minute}) async {
    reminderEnabled = enabled;
    if (hour != null) reminderHour = hour;
    if (minute != null) reminderMinute = minute;
    await _prefs?.setBool(_kReminder, enabled);
    await _prefs?.setInt('${_kReminder}H', reminderHour);
    await _prefs?.setInt('${_kReminder}M', reminderMinute);
    final bool ok = await prep.scheduleSubuhReminder(
      hour: reminderHour,
      minute: reminderMinute,
      enabled: enabled,
    );
    notifyListeners();
    return ok;
  }

  /// Called once on the Beranda when the app opens on land (PREP-4:
  /// "Sinkronkan sebelum berangkat"). Returns true only the first time on a
  /// given day, so it is a nudge rather than a nag.
  Future<bool> shouldPromptLandSync() async {
    if (!likelyOnLand) return false;
    if (readyForSea) return false;
    final DateTime now = DateTime.now();
    final String today = '${now.year}-${now.month}-${now.day}';
    if (_prefs?.getString(_kLandPrompted) == today) return false;
    await _prefs?.setString(_kLandPrompted, today);
    return true;
  }

  bool get reminderStored => reminderEnabled;
}
