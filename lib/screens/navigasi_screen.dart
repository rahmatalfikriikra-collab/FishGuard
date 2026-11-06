import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/fuel_calculator.dart';
import '../services/kkp_pdpi_service.dart';
import '../services/local_data.dart';
import '../theme/app_theme.dart';
import '../widgets/catch_sheet.dart';
import '../widgets/common.dart';
import '../widgets/departure_gate.dart';
import '../widgets/sea_map.dart';

/// Navigasi (PRD NAV-1..NAV-6).
///
/// A live compass, bearing and distance to the chosen target, plus the trip
/// recorder. GPS is sampled every 10 m so an eight-hour day stays inside the
/// battery budget (PREP-4); the same stream moves the vessel on the map and
/// extends the recorded track.
class NavigasiScreen extends StatefulWidget {
  const NavigasiScreen({super.key, required this.state});

  final AppState state;

  @override
  State<NavigasiScreen> createState() => _NavigasiScreenState();
}

class _NavigasiScreenState extends State<NavigasiScreen> {
  StreamSubscription<Position>? _posSub;
  DpiPoint? _target;
  bool _guideHome = false;

  /// NAV-5: the status the sailor last saw, so a change to TIDAK LAYAK while
  /// they are already out there is announced instead of quietly displayed.
  SeaStatus? _lastSeenStatus;
  bool _weatherAlertOpen = false;

  /// NAV-1: the track is sampled every 30 s even when the boat barely moves,
  /// so a slow drift or a drift at anchor still shows up on the map. The
  /// distance-based stream fires sooner when the boat is actually moving.
  Timer? _sampleTimer;

  @override
  void initState() {
    super.initState();
    _startGps();
    widget.state.addListener(_onStateChanged);
    _sampleTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (widget.state.activeTrip == null) return;
      Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.best,
          timeLimit: Duration(seconds: 20),
        ),
      ).then(
        (Position p) => widget.state.updatePosition(p.latitude, p.longitude),
        onError: (Object _) {},
      );
    });
  }

  /// Watches the forecast while a trip is running (PRD NAV-5).
  ///
  /// Only fires on a transition into TIDAK LAYAK, never on every rebuild and
  /// never for a status that was already dangerous when the trip began — at
  /// that point the "Tetap berangkat" dialog has already said its piece.
  void _onStateChanged() {
    if (!mounted) return;
    final AppState s = widget.state;
    final SeaStatus now = s.seaStatus;
    final SeaStatus? before = _lastSeenStatus;
    _lastSeenStatus = now;
    if (s.activeTrip == null) return;
    if (before == null || before == SeaStatus.tidakLayak) return;
    if (now != SeaStatus.tidakLayak || _weatherAlertOpen) return;

    _weatherAlertOpen = true;
    final WeatherArea? area = s.currentArea;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final AppColors c = ctx.colors;
        return AlertDialog(
          title: Row(
            children: <Widget>[
              Icon(Icons.warning_amber_rounded, color: c.danger),
              const SizedBox(width: 8),
              const Expanded(child: Text('Cuaca memburuk')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Status perairan berubah menjadi TIDAK LAYAK.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: c.danger,
                ),
              ),
              const SizedBox(height: 8),
              if (area != null)
                Text(
                  '${area.name} — gelombang ${area.waveRange}, angin '
                  '${area.windRange}.',
                  style: const TextStyle(fontSize: 13.5, height: 1.4),
                ),
              const SizedBox(height: 8),
              const Text(
                'Pertimbangkan kembali ke pelabuhan. Arahkan pulang lewat '
                'tombol "Pandu Pulang".',
                style: TextStyle(fontSize: 13.5, height: 1.4),
              ),
              if (area != null && area.warning.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  'Peringatan BMKG: ${area.warning}',
                  style: TextStyle(fontSize: 12.5, color: c.textMuted),
                ),
              ],
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Mengerti'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _startGuideHome();
              },
              child: const Text('Pandu pulang'),
            ),
          ],
        );
      },
    ).whenComplete(() => _weatherAlertOpen = false);
  }

  @override
  void dispose() {
    _sampleTimer?.cancel();
    widget.state.removeListener(_onStateChanged);
    _posSub?.cancel();
    super.dispose();
  }

  void _startGps() {
    _posSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 10,
      ),
    ).listen(
      (Position p) {
        widget.state.updatePosition(p.latitude, p.longitude);
        if (mounted) setState(() {});
      },
      onError: (Object e) {
        widget.state.setGpsError(e.toString());
        if (mounted) setState(() {});
      },
    );
    Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        timeLimit: Duration(seconds: 20),
      ),
    ).then(
      (Position p) => widget.state.updatePosition(p.latitude, p.longitude),
      onError: (Object _) {},
    );
  }

  // ---------------------------------------------------------------- fuel math

  double get _tankLiters {
    final double tank = widget.state.profile.tankLiters;
    return tank > 0 ? tank : 20;
  }

  double get _usedFuel {
    if (widget.state.tripDistanceKm <= 0) return 0;
    return FuelCalculator.estimate(
      powerPk: widget.state.profile.dayaMesinPk,
      condition: widget.state.profile.umurMesin,
      distanceKm: widget.state.tripDistanceKm,
      // FUEL-4: once the sailor has corrected the formula with real fill-ups,
      // the live "solar terpakai" follows their own boat.
      calibration: widget.state.fuelCalibration,
    ).totalLiters;
  }

  double get _remainingFuel =>
      (_tankLiters - _usedFuel).clamp(0, double.infinity);

  // ------------------------------------------------------------------- trips

  /// PREP-5: "Mulai" warns when the data on the phone is not fresh, because the
  /// sailor is about to rely on it with no signal. Sailing anyway is allowed —
  /// the app advises, it does not gatekeep — but the warning has to be seen.
  Future<void> _startTrip() async {
    if (widget.state.activeTrip != null) return;
    final AppState s = widget.state;

    // The rule the sailor asked for: no going to sea on data that was never
    // downloaded today. The dialog offers to download right now, and only
    // sailing with no signal at all gets past it — with the reason shown.
    if (!s.readyForSea) {
      final DepartureChoice? choice = await showDepartureGate(context, s);
      if (choice == null || choice == DepartureChoice.cancel) return;
      if (choice == DepartureChoice.download) {
        if (!mounted) return;
        await _syncBeforeDeparture();
        if (!mounted || !s.readyForSea) return;
      }
      // choice == sailAnyway falls through to departure below.
    }
    if (!mounted) return;
    s.startTrip();
    _lastSeenStatus = s.seaStatus;
    setState(() {});
  }

  /// The "Sinkron dulu" branch: refresh both feeds, and report honestly when
  /// the phone has no signal instead of leaving the button looking dead.
  Future<void> _syncBeforeDeparture() async {
    final AppState s = widget.state;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(content: Text('Menyinkronkan DPI dan cuaca…')),
    );
    final bool weather = await s.fetchWeatherForPosition();
    final WppZone zone = s.zoneHere ?? WppZone.all.first;
    final DpiFetchResult? dpi = await s.fetchDpi(
      zone: zone,
      date: DateTime.now(),
    );
    final bool dpiOk = dpi != null && dpi.rows.isNotEmpty;
    // markSynced() re-reads the bundled pack and refreshes the checklist; it
    // deliberately no longer stamps the download timestamps, so calling it
    // cannot make failed downloads look successful.
    await s.markSynced();
    if (!mounted) return;
    final bool ok = weather && dpiOk;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Data hari ini sudah diunduh. Selamat melaut.'
              : 'Unduhan belum lengkap — periksa sinyal, lalu coba lagi.',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
    setState(() {});
  }

  /// Records a catch against the current target point, so the DPI accuracy
  /// feedback knows which point produced it.
  Future<void> _catatTangkapan() async {
    final bool saved = await showCatchSheet(context, widget.state, titik: _target);
    if (!mounted) return;
    if (saved) {
      final DpiPoint? t = _target;
      if (t != null) widget.state.markVisited(t.nomor);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tangkapan tersimpan')),
      );
    }
  }

  void _startGuideHome() {
    final AppState s = widget.state;
    if (s.activeTrip == null) return;
    setState(() {
      _target = null;
      _guideHome = true;
    });
  }

  Future<void> _stopTrip() async {
    final Trip? t = await widget.state.finishTrip(bbmLiters: _usedFuel);
    if (!mounted || t == null) return;
    setState(() {
      _guideHome = false;
    });
    _showSummary(t);
  }

  void _showSummary(Trip t) {
    final AppColors c = context.colors;
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Ringkasan Pelayaran'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _sumRow('Mulai', formatJam(t.mulai)),
              _sumRow('Selesai', formatJam(t.selesai ?? DateTime.now())),
              _sumRow('Durasi', formatDurasi(t.durasi)),
              _sumRow('Jarak tempuh', _fmtJarak(t.jarakKm)),
              _sumRow('Estimasi solar', '${t.bbmEstimasiL.toStringAsFixed(1)} L'),
              _sumRow('Titik dikunjungi', '${t.visited.length} titik'),
              const SizedBox(height: 10),
              Text(
                'Perjalanan tersimpan di Profil → Riwayat Pelayaran.',
                style: TextStyle(fontSize: 12, color: c.textMuted),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Tutup', style: TextStyle(color: c.primary)),
          ),
        ],
      ),
    );
  }

  String _fmtJarak(double km) {
    if (km < 10) return '${km.toStringAsFixed(1)} km';
    return '${km.toStringAsFixed(0)} km';
  }

  Widget _sumRow(String a, String b) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(a, style: const TextStyle(fontSize: 14)),
          Text(b, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ target picker

  void _pickTarget() {
    final AppState s = widget.state;
    final List<DpiPoint> nearest = s.nearestDpi(limit: 5);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => SheetFrame(
        title: 'Pilih Tujuan',
        subtitle: '5 titik DPI terdekat dari posisi Anda',
        child: nearest.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Text(
                  'Belum ada titik DPI dalam radius 50 km. Buka tab Peta untuk '
                  'memperbesar radius.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    color: ctx.colors.textMuted,
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final DpiPoint p in nearest)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundColor: ctx.colors.primary.withValues(alpha: 0.12),
                        child: Text(
                          '${p.nomor}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: ctx.colors.primary,
                          ),
                        ),
                      ),
                      title: Text('Titik ${p.nomor} · WPP ${p.wpp}'),
                      subtitle: Text(
                        '${_fmtJarak(p.distanceKmTo(s.lat, s.lon))} · '
                        '${bearingLabel(p.bearingTo(s.lat, s.lon))}',
                        style: TextStyle(fontSize: 12, color: ctx.colors.textMuted),
                      ),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        setState(() {
                          _target = p;
                          _guideHome = false;
                        });
                      },
                    ),
                ],
              ),
      ),
    );
  }

  // ------------------------------------------------------------------- build

  /// Where "home" is: the trip's departure point while recording.
  List<double>? get _homePoint {
    final Trip? t = widget.state.activeTrip;
    if (t == null) return null;
    return <double>[t.berangkatLat, t.berangkatLon];
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    final bool recording = s.activeTrip != null;

    final List<double>? dest = _guideHome
        ? _homePoint
        : (_target == null ? null : <double>[_target!.lat, _target!.lon]);

    double? distanceKm;
    double? bearing;
    if (dest != null) {
      final DpiPoint probe = DpiPoint(
        nomor: 0,
        lat: s.lat,
        lon: s.lon,
        lonDms: '',
        latDms: '',
        wpp: '',
        date: DateTime.now(),
      );
      distanceKm = probe.distanceKmTo(dest[0], dest[1]);
      bearing = probe.bearingTo(dest[0], dest[1]);
    }

    final List<double>? home = _homePoint;
    final double? distanceHomeKm = home == null
        ? null
        : DpiPoint(
            nomor: 0,
            lat: s.lat,
            lon: s.lon,
            lonDms: '',
            latDms: '',
            wpp: '',
            date: DateTime.now(),
          ).distanceKmTo(home[0], home[1]);

    final bool canReachHome = distanceHomeKm == null
        ? true
        : FuelCalculator.canReachHome(
            remainingLiters: _remainingFuel,
            distanceHomeKm: distanceHomeKm,
            powerPk: s.profile.dayaMesinPk,
            condition: s.profile.umurMesin,
            calibration: s.fuelCalibration,
          );

    final DpiPoint? bearingMarker = dest == null
        ? null
        : DpiPoint(
            nomor: -1,
            lat: dest[0],
            lon: dest[1],
            lonDms: '',
            latDms: '',
            wpp: '',
            date: DateTime.now(),
          );

    return Column(
      children: <Widget>[
        SizedBox(
          height: 240,
          child: Stack(
            children: <Widget>[
              ColoredBox(
                color: c.mapBg,
                child: SeaMap(
                  points: const <DpiPoint>[],
                  userLat: s.lat,
                  userLon: s.lon,
                  track: recording ? s.activeTrip!.track : const <List<double>>[],
                  bearingTo: bearingMarker,
                  home: home,
                ),
              ),
              Positioned(
                top: 12,
                left: 12,
                right: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: c.cardBg.withValues(alpha: 0.92),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.border),
                  ),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        s.gpsLocked ? Icons.gps_fixed : Icons.gps_not_fixed,
                        size: 14,
                        color: s.gpsLocked ? c.accent : c.warning,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s.gpsLocked
                              ? '${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}'
                              : 'Menunggu GPS — memakai ${MapConfig.defaultPortName}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: c.textMain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Chip2(
                        label: 'BBM ${_remainingFuel.toStringAsFixed(1)} L',
                        icon: Icons.local_gas_station,
                        color: _remainingFuel < 3 ? c.danger : c.warning,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (recording)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Chip2(
                      label: 'MEREKAM PERJALANAN',
                      icon: Icons.fiber_manual_record,
                      color: c.danger,
                      filled: true,
                    ),
                  ),
                _Compass(bearing: bearing, distanceKm: distanceKm),
                const SizedBox(height: 16),
                if (!canReachHome)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: NoticeBox(
                      text: 'Sisa BBM ${_remainingFuel.toStringAsFixed(1)} L '
                          'tidak cukup untuk pulang ke titik berangkat '
                          '(${_fmtJarak(distanceHomeKm)}) plus cadangan 10%. '
                          'Pertimbangkan pulang sekarang.',
                      icon: Icons.warning_amber_rounded,
                      color: c.danger,
                    ),
                  ),
                AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    children: <Widget>[
                      _InfoTile(
                        icon: Icons.directions_boat,
                        label: 'Kapal Saya',
                        value: s.gpsLocked
                            ? '${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)}'
                            : 'GPS belum terkunci',
                        tint: c.primary,
                      ),
                      const SizedBox(height: 10),
                      _InfoTile(
                        icon: Icons.pin_drop_outlined,
                        label: 'Tujuan',
                        value: _guideHome
                            ? 'Titik berangkat'
                            : (_target == null
                                ? 'Belum dipilih'
                                : 'Titik DPI ${_target!.nomor} · WPP ${_target!.wpp}'),
                        tint: c.accent,
                      ),
                      const SizedBox(height: 10),
                      _InfoTile(
                        icon: Icons.local_gas_station_outlined,
                        label: 'BBM: tangki ${_tankLiters.toStringAsFixed(0)} L',
                        value: 'Terpakai ${_usedFuel.toStringAsFixed(1)} L · '
                            'sisa ${_remainingFuel.toStringAsFixed(1)} L',
                        tint: c.warning,
                      ),
                    ],
                  ),
                ),
                if (recording) ...<Widget>[
                  const SizedBox(height: 12),
                  AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: <Widget>[
                        _stat(
                          'Waktu',
                          formatDurasi(
                            DateTime.now().difference(s.activeTrip!.mulai),
                          ),
                          c,
                        ),
                        _stat('Jarak', _fmtJarak(s.tripDistanceKm), c),
                        _stat('Solar', '${_usedFuel.toStringAsFixed(1)} L', c),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                AppButton(
                  label: _target == null ? 'Pilih Tujuan DPI' : 'Ganti Tujuan DPI',
                  icon: Icons.pin_drop,
                  variant: ButtonVariant.secondary,
                  dense: true,
                  onPressed: _pickTarget,
                ),
                const SizedBox(height: 10),
                AppButton(
                  label: _target == null
                      ? 'Catat Hasil Tangkapan'
                      : 'Catat Tangkapan di Titik ${_target!.nomor}',
                  icon: Icons.set_meal,
                  variant: ButtonVariant.success,
                  dense: true,
                  onPressed: _catatTangkapan,
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: AppButton(
                        label: 'Mulai',
                        icon: Icons.play_arrow,
                        dense: true,
                        variant: recording
                            ? ButtonVariant.secondary
                            : ButtonVariant.success,
                        onPressed: recording ? null : _startTrip,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Pandu Pulang',
                        icon: Icons.home,
                        dense: true,
                        variant: ButtonVariant.warning,
                        onPressed: recording ? () => _startGuideHome() : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppButton(
                        label: 'Selesai',
                        icon: Icons.flag,
                        dense: true,
                        variant: ButtonVariant.danger,
                        onPressed: recording ? _stopTrip : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                NoticeBox(
                  text: 'Kompas memakai arah tujuan, bukan arah pandang HP. '
                      'Periksa jarum magnet dulu sebelum membelok.',
                  icon: Icons.explore_outlined,
                  color: c.primary,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stat(String label, String value, AppColors c) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: c.textMain,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 11.5, color: c.textMuted)),
      ],
    );
  }
}

class _Compass extends StatelessWidget {
  const _Compass({required this.bearing, required this.distanceKm});

  final double? bearing;
  final double? distanceKm;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool hasTarget = bearing != null && distanceKm != null;

    return Column(
      children: <Widget>[
        Container(
          width: 158,
          height: 158,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c.cardBg,
            border: Border.all(color: c.primary, width: 3),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: c.primary.withValues(alpha: 0.14),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              Positioned(
                top: 8,
                child: Text(
                  'U',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.danger,
                  ),
                ),
              ),
              Transform.rotate(
                angle: (bearing ?? 0) * math.pi / 180,
                child: Icon(
                  Icons.navigation,
                  size: 62,
                  color: hasTarget
                      ? c.primary
                      : c.textMuted.withValues(alpha: 0.35),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (hasTarget) ...<Widget>[
          Text(
            '${distanceKm!.toStringAsFixed(1)} km',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w800,
              color: c.textMain,
            ),
          ),
          Text(
            '${bearing!.toStringAsFixed(0)}° ${bearingLabel(bearing!)}',
            style: TextStyle(fontSize: 15, color: c.textMuted),
          ),
        ] else ...<Widget>[
          Text(
            'Pilih tujuan navigasi',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: c.textMain,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Tekan "Pilih Tujuan DPI", atau mulai perjalanan lalu "Pandu Pulang".',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, height: 1.35, color: c.textMuted),
          ),
        ],
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.tint,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bgBody,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.border),
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: tint),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: TextStyle(fontSize: 11.5, color: c.textMuted),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
