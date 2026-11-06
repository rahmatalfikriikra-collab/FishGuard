import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/kkp_pdpi_service.dart';
import '../services/local_data.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// "Siap Melaut" checklist (PRD HOME-3 / PREP-1..6).
///
/// The prototype had a one-tap "Siapkan Data" that implied a server fetch.
/// There is no server yet, so the button pulls what the device can actually
/// pull — the DPI table for the boat's WPP and the BMKG forecast for its area
/// — and reports exactly what succeeded. The bundled pack stays as the floor,
/// so a phone with no signal still has something to show.
class SiapMelautCard extends StatefulWidget {
  const SiapMelautCard({super.key, required this.state});

  final AppState state;

  @override
  State<SiapMelautCard> createState() => _SiapMelautCardState();
}

class _SiapMelautCardState extends State<SiapMelautCard> {
  bool _busy = false;

  /// PREP-2: human-readable progress for the staged download, empty when idle.
  String _stage = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.state.readBattery();
    });
  }

  List<_PrepItem> _items(AppState s) {
    final int? battery = s.batteryLevel;
    return <_PrepItem>[
      // "Terunduh" has to mean downloaded, not shipped inside the APK: the
      // detail line quotes the actual download so a green tick is checkable.
      _PrepItem(
        icon: Icons.pin_drop_outlined,
        label: 'Titik DPI terunduh',
        detail: !s.dpiDownloadedToday
            ? (s.dpiPoints.isEmpty
                ? 'Belum ada'
                : '${s.dpiPoints.length} titik — belum diunduh hari ini')
            : s.dpiTableDate == null
                ? '${s.dpiPoints.length} titik'
                : '${s.dpiPoints.length} titik · tabel ${formatTanggal(s.dpiTableDate!)}',
        ready: s.prepReady(AppState.prepDpi),
      ),
      _PrepItem(
        icon: Icons.cloud_outlined,
        label: 'Prakiraan cuaca BMKG',
        detail: !s.weatherDownloadedToday
            ? (s.weatherAreas.isEmpty
                ? 'Belum ada'
                : '${s.weatherAreas.length} area — belum diunduh hari ini')
            : '${s.weatherAreas.length} area · ${formatTanggal(s.weatherFetchedAt!)}',
        ready: s.prepReady(AppState.prepCuaca),
      ),
      _PrepItem(
        icon: Icons.map_outlined,
        label: 'Peta dasar offline',
        detail: '${MapConfig.packSizeMb.toStringAsFixed(1)} MB',
        ready: s.prepReady(AppState.prepPeta),
      ),
      _PrepItem(
        icon: Icons.contact_phone_outlined,
        label: 'Kontak darurat',
        detail: s.profile.kontak.isEmpty
            ? 'Belum diisi'
            : '${s.profile.kontak.length} kontak',
        ready: s.prepReady(AppState.prepKontak),
      ),
      _PrepItem(
        icon: Icons.satellite_alt_outlined,
        label: 'GPS terkunci',
        detail: s.gpsLocked ? 'Terkunci' : 'Belum',
        ready: s.prepReady(AppState.prepGps),
      ),
      _PrepItem(
        icon: Icons.battery_charging_full_outlined,
        label: 'Baterai ≥ 80%',
        detail: battery == null ? 'Tidak terbaca' : '$battery%',
        ready: s.prepReady(AppState.prepBaterai),
      ),
    ];
  }

  /// PREP-2: one button that downloads everything the phone can download.
  ///
  /// The download is staged and each stage names itself on the button, so a
  /// dropped signal shows where it stopped instead of leaving a spinner that
  /// looks broken. What already arrived stays — the next press picks up from
  /// there rather than starting over, which is what "bisa dilanjutkan bila
  /// sinyal putus" asks for.
  Future<void> _prepare() async {
    if (_busy) return;
    final AppState s = widget.state;

    // PREP-5: pressing this with stale data is fine — that is the point — but
    // the sailor should know what they are refreshing and why it matters.
    if (s.freshnessLevel >= 2) {
      final bool? go = await showDialog<bool>(
        context: context,
        builder: (BuildContext ctx) {
          final AppColors c = ctx.colors;
          return AlertDialog(
            title: const Text('Data sudah lama'),
            content: Text(
              '${s.freshnessLabel}. Titik DPI dan prakiraan cuaca yang lama '
              'bisa menyesatkan di laut. Siapkan data baru sekarang?',
              style: const TextStyle(fontSize: 13.5, height: 1.45),
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text('Siapkan', style: TextStyle(color: c.primary)),
              ),
            ],
          );
        },
      );
      if (go != true || !mounted) return;
    }

    setState(() {
      _busy = true;
      _stage = 'Menyiapkan paket…';
    });

    bool weatherOk = false;
    bool dpiOk = false;
    String? firstError;

    // Stage 1: the BMKG forecast for wherever the boat is.
    setState(() => _stage = 'Mengunduh prakiraan BMKG…');
    try {
      weatherOk = await s.fetchWeatherForPosition(
        onProgress: (String m) {
          if (mounted) setState(() => _stage = m);
        },
      );
      if (!weatherOk) firstError ??= s.weatherError;
    } on Object catch (e) {
      firstError ??= 'BMKG: $e';
    }

    // Stage 2: the DPI table for the boat's WPP.
    if (mounted) setState(() => _stage = 'Mengunduh tabel DPI KKP…');
    try {
      final WppZone zone = s.zoneHere ?? WppZone.all.first;
      final DpiFetchResult? r = await s.fetchDpi(
        zone: zone,
        date: DateTime.now(),
      );
      dpiOk = r != null && r.rows.isNotEmpty;
      if (!dpiOk) firstError ??= r?.error ?? s.dpiError;
    } on Object catch (e) {
      firstError ??= 'KKP: $e';
    }

    // Stage 3: the device-side items, which cost nothing but a moment.
    if (mounted) setState(() => _stage = 'Memeriksa GPS dan baterai…');
    await s.readBattery();
    if (weatherOk || dpiOk) await s.markSynced();

    if (!mounted) return;
    setState(() {
      _busy = false;
      _stage = '';
    });

    final String message = switch ((weatherOk, dpiOk)) {
      (true, true) => 'Data siap: DPI dan cuaca sudah diperbarui.',
      (true, false) =>
        'Cuaca diperbarui. Tabel DPI belum bisa diunduh — data lama tetap '
            'dipakai.',
      (false, true) =>
        'Tabel DPI diperbarui. Prakiraan cuaca belum bisa diunduh — data lama '
            'tetap dipakai.',
      (false, false) => 'Tidak ada sinyal. Data lama tetap bisa dipakai di laut.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          firstError == null || (weatherOk && dpiOk)
              ? message
              : '$message ($firstError)',
        ),
        duration: const Duration(seconds: 6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    final List<_PrepItem> items = _items(s);
    final int ready = items.where((_PrepItem i) => i.ready).length;
    final bool allReady = ready == items.length;

    return AppCard(
      padding: const EdgeInsets.all(18),
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                allReady ? Icons.verified : Icons.checklist_rtl,
                size: 18,
                color: allReady ? c.accent : c.primary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Siap Melaut',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textMain,
                  ),
                ),
              ),
              Chip2(
                label: '$ready/${items.length}',
                icon: allReady ? Icons.check : Icons.pending_outlined,
                color: allReady ? c.accent : c.warning,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            allReady
                ? 'Semua siap. Data aman dipakai tanpa sinyal.'
                : 'Lengkapi sebelum berangkat — di laut tidak ada sinyal.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textMuted),
          ),
          const SizedBox(height: 14),
          for (final _PrepItem item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: Row(
                children: <Widget>[
                  Icon(
                    item.ready ? Icons.check_circle : Icons.radio_button_unchecked,
                    size: 17,
                    color: item.ready ? c.accent : c.textMuted.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 9),
                  Icon(item.icon, size: 14, color: c.textMuted),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: item.ready ? FontWeight.w600 : FontWeight.w500,
                        color: item.ready ? c.textMain : c.textMuted,
                      ),
                    ),
                  ),
                  Text(
                    item.detail,
                    style: TextStyle(fontSize: 11.5, color: c.textMuted),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          AppButton(
            label: _busy
                ? (_stage.isEmpty ? 'Menyiapkan…' : _stage)
                : 'Siapkan Data (${MapConfig.packSizeMb.toStringAsFixed(1)} MB)',
            icon: allReady ? Icons.refresh : Icons.download_for_offline_outlined,
            dense: true,
            variant: allReady ? ButtonVariant.secondary : ButtonVariant.primary,
            onPressed: _busy ? null : _prepare,
          ),
        ],
      ),
    );
  }
}

class _PrepItem {
  const _PrepItem({
    required this.icon,
    required this.label,
    required this.detail,
    required this.ready,
  });

  final IconData icon;
  final String label;
  final String detail;
  final bool ready;
}
