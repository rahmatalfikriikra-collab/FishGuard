import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/claude_service.dart';
import '../services/kkp_pdpi_service.dart';
import '../theme/app_theme.dart';
import '../widgets/catch_sheet.dart';
import '../widgets/common.dart';
import '../widgets/siap_melaut.dart';
import 'catch_log_screen.dart';

class BerandaScreen extends StatefulWidget {
  const BerandaScreen({
    super.key,
    required this.state,
    required this.onNavigate,
  });

  final AppState state;
  final ValueChanged<int> onNavigate;

  @override
  State<BerandaScreen> createState() => _BerandaScreenState();
}

class _BerandaScreenState extends State<BerandaScreen> {
  Recommendation? _rec;
  bool _loadingRec = false;
  String? _recError;

  /// PREP-4 / PREP-11: when the boat is still on land and the data is not
  /// fresh, nudge the sailor once per day to sync before going out.
  bool _landPromptShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _loadRecommendation();
      await _maybePromptLandSync();
    });
  }

  Future<void> _maybePromptLandSync() async {
    if (_landPromptShown) return;
    final AppState s = widget.state;
    final bool should = await s.shouldPromptLandSync();
    if (!mounted || !should) return;
    _landPromptShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Anda masih di darat. Sinkronkan data DPI dan cuaca sebelum berangkat.',
        ),
        action: SnackBarAction(
          label: 'Sinkron',
          onPressed: () async {
            await s.fetchWeatherForPosition();
            await s.fetchDpi(
              zone: s.zoneHere ?? WppZone.all[5],
              date: DateTime.now(),
            );
            await s.markSynced();
            if (mounted) _loadRecommendation();
          },
        ),
        duration: const Duration(seconds: 8),
      ),
    );
  }

  Future<void> _loadRecommendation() async {
    if (_loadingRec) return;
    setState(() {
      _loadingRec = true;
      _recError = null;
    });
    final AppState s = widget.state;
    final Recommendation rec = await s.recommendationService.recommend(
      area: s.currentArea,
      availablePoints: s.dpiPoints.length,
      portName: s.profile.pelabuhanAsal,
      enginePk: s.profile.dayaMesinPk.round(),
      tankLiters: s.profile.tankLiters,
    );
    if (!mounted) return;
    setState(() {
      _rec = rec;
      _loadingRec = false;
      _recError = rec.fromAi ? null : rec.error;
    });
  }

  Future<void> _openCatch() async {
    final bool saved = await showCatchSheet(context, widget.state);
    if (saved && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tangkapan tersimpan')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppState s = widget.state;
    final WeatherArea? area = s.currentArea;
    final ForecastHour hour = area?.currentHour() ??
        ForecastHour(
          time: DateTime.now(),
          waveM: 0,
          windKt: 0,
          condition: 'Data tidak tersedia',
        );

    return RefreshIndicator(
      onRefresh: () async {
        await s.refreshData();
        await _loadRecommendation();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
        children: <Widget>[
          _StatusCard(status: s.seaStatus, area: area, hour: hour),
          const SizedBox(height: 8),
          _FreshnessRow(state: s),
          const SizedBox(height: 18),
          // PREP-11: when the boat is still on land the checklist leads.
          SiapMelautCard(state: s),
          const SizedBox(height: 18),
          _RecommendationCard(
            rec: _rec,
            loading: _loadingRec,
            error: _recError,
            onRefresh: _loadRecommendation,
          ),
          const SizedBox(height: 18),
          _CatchCard(state: s),
          const SizedBox(height: 18),
          const SectionTitle('Menu Cepat'),
          _QuickMenu(onNavigate: widget.onNavigate, onCatat: _openCatch),
          const SizedBox(height: 55),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.status,
    required this.area,
    required this.hour,
  });

  final SeaStatus status;
  final WeatherArea? area;
  final ForecastHour hour;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Color tint = switch (status) {
      SeaStatus.layak => c.accent,
      SeaStatus.waspada => c.warning,
      SeaStatus.tidakLayak => c.danger,
    };

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tint.withValues(alpha: 0.16),
            c.cardBg,
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tint.withValues(alpha: 0.35)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: c.primary.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.waves, size: 18, color: c.primary),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  area?.name ?? 'Perairan tidak diketahui',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.primary,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          StatusBadge(status: status, large: true),
          const SizedBox(height: 14),
          Text(
            status.advice,
            style: TextStyle(fontSize: 15, height: 1.45, color: c.textMain),
          ),
          const SizedBox(height: 16),
          Divider(color: c.border),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _Metric(
                  icon: Icons.cloud,
                  label: 'Cuaca',
                  value: hour.condition,
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.waves,
                  label: 'Gelombang',
                  value: area?.waveRange ?? '-',
                ),
              ),
              Expanded(
                child: _Metric(
                  icon: Icons.air,
                  label: 'Angin',
                  value: area?.windRange ?? '-',
                ),
              ),
            ],
          ),
          if (area != null && area!.warning.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            NoticeBox(
              text: 'Peringatan BMKG: ${area!.warning}',
              icon: Icons.warning_amber_rounded,
              color: c.danger,
            ),
          ],
          if (area != null && area!.isStale()) ...<Widget>[
            const SizedBox(height: 10),
            NoticeBox(
              text:
                  'Prakiraan tersimpan, bukan data langsung. '
                  'Terakhir diperbarui ${formatJam(area!.fetchedAt)}.',
              icon: Icons.schedule,
              color: c.warning,
            ),
          ],
          if (area != null && area!.hours.isNotEmpty) ...<Widget>[
            const SizedBox(height: 16),
            Divider(color: c.border),
            const SizedBox(height: 12),
            _ForecastStrip(area: area!),
          ],
        ],
      ),
    );
  }
}

/// HOME-3: the next 24 h, one slot per 3 h, so a fisherman who leaves at dawn
/// can see what the afternoon looks like before he commits. BMKG publishes the
/// forecast at 3-hour steps already, so the slots are read straight from
/// [WeatherArea.hours] — nothing is interpolated.
class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.area});

  final WeatherArea area;

  /// The next 24 h in 3-hour steps, starting from the current slot.
  ///
  /// Hours are grouped by their own 3-hour bucket (00, 03, 06, …) and the
  /// first one at or after the current time is kept, so a forecast issued at
  /// 12:00 shows 12, 15, 18 … rather than repeating 09.
  List<ForecastHour> _slots() {
    final DateTime now = DateTime.now();
    final DateTime from = now.subtract(const Duration(minutes: 30));
    final DateTime until = now.add(const Duration(hours: 24));
    final Map<int, ForecastHour> byBucket = <int, ForecastHour>{};
    for (final ForecastHour h in area.hours) {
      if (h.time.isBefore(from) || h.time.isAfter(until)) continue;
      // Bucket on the absolute 3-hour boundary so two BMKG rows never collide.
      final int bucket = h.time.millisecondsSinceEpoch ~/
          const Duration(hours: 3).inMilliseconds;
      final ForecastHour? seen = byBucket[bucket];
      // Keep the row closest to the bucket's start (BMKG gives whole hours).
      if (seen == null || h.time.isBefore(seen.time)) byBucket[bucket] = h;
    }
    final List<ForecastHour> out = byBucket.values.toList()
      ..sort((ForecastHour a, ForecastHour b) => a.time.compareTo(b.time));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final List<ForecastHour> slots = _slots();
    if (slots.isEmpty) {
      return Text(
        'Prakiraan per 3 jam belum tersedia untuk area ini.',
        style: TextStyle(fontSize: 12.5, color: c.textMuted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.schedule, size: 13, color: c.textMuted),
            const SizedBox(width: 5),
            Text(
              '24 JAM KE DEPAN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: c.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: slots.length,
            separatorBuilder: (BuildContext _, int _) => const SizedBox(width: 8),
            itemBuilder: (BuildContext _, int i) => _ForecastChip(hour: slots[i]),
          ),
        ),
      ],
    );
  }
}

/// One 3-hour slot. The colour follows the same thresholds the status card
/// uses, so "orange at 15.00" means the same thing in both places.
class _ForecastChip extends StatelessWidget {
  const _ForecastChip({required this.hour});

  final ForecastHour hour;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final SeaStatus status = WeatherArea(
      code: '',
      name: '',
      hours: <ForecastHour>[hour],
      fetchedAt: DateTime.now(),
    ).statusNow(now: hour.time);

    final Color tint = switch (status) {
      SeaStatus.layak => c.accent,
      SeaStatus.waspada => c.warning,
      SeaStatus.tidakLayak => c.danger,
    };

    return Container(
      width: 74,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            '${dua(hour.time.hour)}.00',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: c.textMain,
            ),
          ),
          Icon(
            status == SeaStatus.tidakLayak
                ? Icons.warning_amber_rounded
                : hour.hasThunder
                    ? Icons.thunderstorm
                    : Icons.waves,
            size: 17,
            color: tint,
          ),
          Column(
            children: <Widget>[
              Text(
                '${hour.waveM.toStringAsFixed(1)} m',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: c.textMain,
                ),
              ),
              Text(
                '${hour.windKt.toStringAsFixed(0)} kt',
                style: TextStyle(fontSize: 10.5, color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 13, color: c.textMuted),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 11.5, color: c.textMuted),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: c.textMain,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _FreshnessRow extends StatefulWidget {
  const _FreshnessRow({required this.state});

  final AppState state;

  @override
  State<_FreshnessRow> createState() => _FreshnessRowState();
}

class _FreshnessRowState extends State<_FreshnessRow> {
  bool _busy = false;

  /// Pulls the live BMKG forecast for the area the boat is in. Falls back to
  /// the bundled pack when there is no signal, and says so either way.
  Future<void> _sync() async {
    if (_busy) return;
    setState(() => _busy = true);
    final AppState s = widget.state;
    final bool ok = await s.fetchWeatherForPosition();
    await s.readBattery();
    if (!mounted) {
      return;
    }
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Prakiraan BMKG terbaru dimuat'
                  '${s.currentArea == null ? '' : ' · ${s.currentArea!.name}'}'
              : (s.weatherError ?? 'BMKG tidak bisa dihubungi, memakai data lama'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState state = widget.state;
    final int level = state.freshnessLevel;
    final Color tint = switch (level) {
      0 => c.accent,
      1 => c.warning,
      _ => c.danger,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.update, size: 13, color: tint),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                state.freshnessLabel,
                style: TextStyle(
                    fontSize: 12.5, color: tint, fontWeight: FontWeight.w600),
              ),
            ),
            if (_busy || state.autoRefreshing)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
              )
            else ...<Widget>[
              // Sailing needs today's data, so when it is missing the chip
              // offers the download rather than a neutral "Sinkron" that
              // reads like an optional tidy-up.
              if (!state.readyForSea)
                Text(
                  'Wajib unduh',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: c.warning,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _sync,
                child: Text(
                  state.readyForSea ? 'Perbarui' : 'Unduh',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: c.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
        // Which perairan the forecast actually belongs to. Without this the
        // status card silently implies it covers wherever the boat is.
        Padding(
          padding: const EdgeInsets.only(left: 18, top: 3),
          child: Row(
            children: <Widget>[
              Icon(
                state.areaIsResolved ? Icons.place : Icons.help_outline,
                size: 11,
                color: c.textMuted,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  state.areaIsResolved
                      ? '${state.currentArea!.name} · BMKG'
                      : 'Area belum ditentukan dari GPS — memakai data contoh. '
                          'Tekan Sinkron.',
                  style: TextStyle(fontSize: 10.5, height: 1.3, color: c.textMuted),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RecommendationCard extends StatelessWidget {
  const _RecommendationCard({
    required this.rec,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final Recommendation? rec;
  final bool loading;
  final String? error;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.tips_and_updates_outlined, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Saran Hari Ini',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textMain,
                  ),
                ),
              ),
              if (rec != null)
                Chip2(
                  label: rec!.fromAi ? 'AI' : 'Lokal',
                  icon: rec!.fromAi ? Icons.auto_awesome : Icons.offline_bolt,
                  color: rec!.fromAi ? c.primary : c.textMuted,
                ),
              const SizedBox(width: 6),
              InkWell(
                onTap: loading ? null : onRefresh,
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: loading
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: c.primary,
                          ),
                        )
                      : Icon(Icons.refresh, size: 18, color: c.textMuted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rec == null && loading)
            Text(
              'Menyusun saran...',
              style: TextStyle(fontSize: 14, color: c.textMuted),
            )
          else if (rec != null) ...<Widget>[
            Text(
              rec!.body,
              style: TextStyle(fontSize: 15, height: 1.45, color: c.textMain),
            ),
            if (rec!.bullets.isNotEmpty) const SizedBox(height: 10),
            for (final String b in rec!.bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: c.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        b,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.4,
                          color: c.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (error != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                error!,
                style: TextStyle(fontSize: 12, color: c.warning, height: 1.35),
              ),
            ],
            if (rec!.fromAi && rec!.modelName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Disusun oleh ${rec!.modelName}',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Short summary of the day's catch with a tap-through to the full log.
class _CatchCard extends StatelessWidget {
  const _CatchCard({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final int today = state.catches
        .where((CatchLog e) => samaHari(e.waktu, DateTime.now()))
        .length;
    final MapEntry<int, double>? best = state.bestDpiByCatch;

    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(16),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (BuildContext _) => CatchLogScreen(state: state),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: c.primaryLight.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.set_meal, size: 22, color: c.primaryLight),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Hasil Tangkapan',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  today == 0
                      ? 'Belum ada catatan hari ini'
                      : 'Hari ini ${formatKg(state.catchKgToday)} · '
                          '$today catatan',
                  style: TextStyle(fontSize: 12.5, color: c.textMuted),
                ),
                if (best != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Titik ${best.key} paling produktif',
                      style: TextStyle(fontSize: 11.5, color: c.accent),
                    ),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: c.textMuted),
        ],
      ),
    );
  }
}

class _QuickMenu extends StatelessWidget {
  const _QuickMenu({required this.onNavigate, required this.onCatat});

  final ValueChanged<int> onNavigate;
  final VoidCallback onCatat;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final List<(IconData, String, int?, Color)> items =
        <(IconData, String, int?, Color)>[
      (Icons.local_gas_station, 'Hitung BBM', 3, const Color(0xFFF4A261)),
      (Icons.set_meal, 'Cari Ikan', 1, c.primaryLight),
      (Icons.explore, 'Navigasi', 2, c.primary),
      (Icons.person, 'Profil', 4, c.textMuted),
      (Icons.add_a_photo_outlined, 'Catat Ikan', null, c.accent),
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.45,
      children: <Widget>[
        for (final (IconData icon, String label, int? idx, Color tint) in items)
          InkWell(
            onTap: idx == null ? onCatat : () => onNavigate(idx),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: c.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Icon(icon, size: 26, color: tint),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.textMain,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
