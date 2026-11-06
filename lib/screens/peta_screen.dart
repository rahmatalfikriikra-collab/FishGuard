import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/local_data.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';
import '../widgets/departure_gate.dart';
import '../widgets/dpi_fetch_sheet.dart';
import '../widgets/sea_map.dart';

/// Peta DPI (PRD MAP-1..6).
///
/// Markers come from the bundled WPP 713/714 GeoJSON, the radius filter runs
/// on-device against the last GPS fix, and the detail sheet shows the decimal
/// and DMS coordinates exactly as the worker published them.
class PetaScreen extends StatefulWidget {
  const PetaScreen({super.key, required this.state, required this.onNavigate});

  final AppState state;
  final ValueChanged<int> onNavigate;

  @override
  State<PetaScreen> createState() => _PetaScreenState();
}

class _PetaScreenState extends State<PetaScreen> {
  double _radiusKm = 50;
  DpiPoint? _selected;
  String _wpp = 'semua';

  @override
  void initState() {
    super.initState();
    // MAP-9: opening the map is the clearest signal the sailor is about to
    // rely on the offline area, so that is when a stale copy is refreshed. It
    // runs once per visit, in the background, and a phone with no signal just
    // keeps the bundled pack — nothing to wait for, nothing to fail.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoRefresh());
  }

  Future<void> _maybeAutoRefresh() async {
    final AppState s = widget.state;
    if (!s.prepReady(AppState.prepPeta)) return;
    final DateTime? at = s.mapPackDownloadedAt;
    if (at != null &&
        DateTime.now().difference(at) < const Duration(hours: 24)) {
      return;
    }
    await s.downloadOfflineArea();
    if (!mounted) return;
    setState(() {});
  }

  List<DpiPoint> get _visible {
    final AppState s = widget.state;
    final List<DpiPoint> pool = _wpp == 'semua'
        ? s.dpiPoints
        : s.dpiPoints.where((DpiPoint p) => p.wpp == _wpp).toList();
    final List<DpiPoint> inRadius =
        LocalDataSource.nearby(pool, s.lat, s.lon, limit: 999, radiusKm: _radiusKm);
    return inRadius;
  }

  @override
  Widget build(BuildContext context) {
    final AppState s = widget.state;
    final List<DpiPoint> visible = _visible;
    final List<DpiPoint> nearest =
        LocalDataSource.nearby(visible, s.lat, s.lon, limit: 5);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Titik DPI',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: context.colors.textMain,
                      ),
                    ),
                    Text(
                      'Koordinat daerah penangkapan ikan',
                      style: TextStyle(
                        fontSize: 13,
                        color: context.colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Chip2(
                label: '${visible.length} titik',
                icon: Icons.pin_drop,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CoverageBanner(state: s),
          const SizedBox(height: 14),
          AppCard(
            padding: const EdgeInsets.all(12),
            margin: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 300,
                    child: ColoredBox(
                      color: context.colors.mapBg,
                      child: SeaMap(
                        points: visible,
                        ownSpots: s.ownSpotsNear(_radiusKm),
                        userLat: s.lat,
                        userLon: s.lon,
                        selected: _selected,
                        home: <double>[MapConfig.defaultLat, MapConfig.defaultLon],
                        interactive: true,
                        onMarkerTap: (DpiPoint p) => _openPoint(p),
                        onOwnSpotTap: (OwnSpot o) => _openOwnSpot(o),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Icon(Icons.info_outline, size: 12, color: context.colors.textMuted),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        'Sumber: PDPI KKP — skema peta, bukan untuk navigasi presisi.',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: context.colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const SectionTitle('Filter'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final double r in <double>[10, 25, 50, 100])
                _FilterPill(
                  label: '${r.toStringAsFixed(0)} km',
                  selected: _radiusKm == r,
                  onTap: () => setState(() => _radiusKm = r),
                ),
              for (final String w in <String>['semua', '713', '714'])
                _FilterPill(
                  label: w == 'semua' ? 'Semua WPP' : 'WPP $w',
                  selected: _wpp == w,
                  onTap: () => setState(() => _wpp = w),
                ),
            ],
          ),
          const SizedBox(height: 20),
          const SectionTitle('Spot Saya'),
          _OwnSpotsCard(state: s, radiusKm: _radiusKm, onChanged: () => setState(() {})),
          const SizedBox(height: 20),
          SectionTitle(
            'Terdekat',
            trailing: GestureDetector(
              onTap: () async {
                await s.refreshData();
                if (context.mounted) setState(() {});
              },
              child: Text(
                'Muat ulang',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: context.colors.primary,
                ),
              ),
            ),
          ),
          _LiveDpiCard(state: s, onFetched: () => setState(() {})),
          if (nearest.isEmpty)
            AppCard(
              margin: EdgeInsets.zero,
              child: Text(
                'Tidak ada titik DPI dalam radius ${_radiusKm.toStringAsFixed(0)} km. '
                'Perbesar radius atau muat ulang data.',
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: context.colors.textMuted,
                ),
              ),
            )
          else
            for (final DpiPoint p in nearest)
              _PointTile(
                point: p,
                distanceKm: p.distanceKmTo(s.lat, s.lon),
                // Bearing from the boat to the point — the same pair of numbers
                // the detail sheet shows, so the list and the sheet agree.
                bearingLabel: bearingLabel(p.bearingTo(s.lat, s.lon)),
                onTap: () => _openPoint(p),
              ),
          const SizedBox(height: 8),
          NoticeBox(
            text:
                'Titik DPI adalah area rekomendasi penangkapan dari portal KKP, '
                'bukan jaminan ikan. Periksa kondisi laut dan keselamatan dulu.',
            icon: Icons.policy_outlined,
            color: context.colors.warning,
          ),
        ],
      ),
    );
  }

  void _openPoint(DpiPoint p) {
    setState(() => _selected = p);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => DpiPointSheet(
        point: p,
        state: widget.state,
        onNavigate: () {
          Navigator.of(ctx).pop();
          widget.onNavigate(2);
        },
        onStartTrip: () async {
          Navigator.of(ctx).pop();
          // Same rule as the Navigasi button: the boat does not leave on a
          // bundled pack that was read days ago. The map can offer the
          // download sheet, so "Unduh sekarang" here opens it.
          final AppState s = widget.state;
          final bool go = await runDepartureGate(
            context,
            s,
            onDownload: () async {
              if (!mounted) return;
              await showDpiFetchSheet(context, s);
              await s.fetchWeatherForPosition();
            },
          );
          if (!go || !mounted) return;
          if (s.activeTrip == null) s.startTrip();
          s.markVisited(p.nomor);
          widget.onNavigate(2);
        },
      ),
    );
  }

  void _openOwnSpot(OwnSpot o) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) => _OwnSpotSheet(
        spot: o,
        state: widget.state,
        onChanged: () => setState(() {}),
        onNavigate: () {
          Navigator.of(ctx).pop();
          widget.onNavigate(2);
        },
      ),
    );
  }
}

/// MAP-6: "Tambah spot di posisi ini" plus the list of spots already marked.
///
/// The button uses the last GPS fix as-is — the sailor is standing where the
/// fish were, so re-prompting for a location would only get in the way. When
/// there is no fix yet the button says so instead of saving (0, 0).
class _OwnSpotsCard extends StatefulWidget {
  const _OwnSpotsCard({
    required this.state,
    required this.radiusKm,
    required this.onChanged,
  });

  final AppState state;
  final double radiusKm;
  final VoidCallback onChanged;

  @override
  State<_OwnSpotsCard> createState() => _OwnSpotsCardState();
}

class _OwnSpotsCardState extends State<_OwnSpotsCard> {
  bool _busy = false;

  Future<void> _add() async {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    if (!s.gpsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'GPS belum terkunci. Spot disimpan pada posisi terakhir yang '
            'diketahui aplikasi.',
          ),
        ),
      );
    }
    final TextEditingController name = TextEditingController();
    final TextEditingController note = TextEditingController();
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Tandai spot ini'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '${formatDecimal(s.lat)}, ${formatDecimal(s.lon)}',
              style: TextStyle(fontSize: 12, color: c.textMuted),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Nama spot (boleh kosong)',
                hintText: 'mis. Karang Bosong',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(
                labelText: 'Catatan (boleh kosong)',
                hintText: 'mis. banyak cakalang pagi',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Simpan', style: TextStyle(color: c.primary)),
          ),
        ],
      ),
    );
    if (ok != true) {
      name.dispose();
      note.dispose();
      return;
    }
    await s.addOwnSpot(name: name.text, note: note.text);
    name.dispose();
    note.dispose();
    if (!mounted) return;
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Spot disimpan di HP ini')),
    );
  }

  Future<void> _refreshArea() async {
    if (_busy) return;
    setState(() => _busy = true);
    final bool got = await widget.state.downloadOfflineArea();
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onChanged();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          got
              ? 'Area sekitar pelabuhan diperbarui dari KKP.'
              : 'Tidak ada sinyal. Area offline bawaan tetap bisa dipakai.',
        ),
      ),
    );
  }

  String _packAge(AppState s) {
    final DateTime? at = s.mapPackDownloadedAt;
    if (at == null) return 'belum pernah diperbarui';
    final Duration d = DateTime.now().difference(at);
    if (d.inMinutes < 60) return '${d.inMinutes} menit lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return '${d.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    final List<OwnSpot> near = s.ownSpotsNear(widget.radiusKm);

    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Spot tangkapan pribadi — terpisah dari titik DPI KKP dan hanya '
            'tersimpan di HP ini.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textMuted),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: AppButton(
                  label: 'Tandai Spot Ini',
                  icon: Icons.add_location_alt_outlined,
                  dense: true,
                  onPressed: _add,
                ),
              ),
              const SizedBox(width: 8),
              Chip2(
                label: '${near.length} di radius',
                icon: Icons.diamond_outlined,
                color: c.accent,
              ),
            ],
          ),
          if (near.isEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              s.ownSpots.isEmpty
                  ? 'Belum ada spot. Tandai saat Anda sedang di lokasi yang '
                      'biasanya ramai ikan.'
                  : 'Tidak ada spot dalam radius '
                      '${widget.radiusKm.toStringAsFixed(0)} km.',
              style: TextStyle(fontSize: 12.5, color: c.textMuted),
            ),
          ] else ...<Widget>[
            const SizedBox(height: 6),
            for (final OwnSpot o in near) _OwnSpotTile(spot: o),
          ],
          Divider(height: 22, color: c.border),
          // MAP-9: the offline area is staged here, and its age is stated so
          // the sailor knows whether the phone is carrying fresh coast data.
          Row(
            children: <Widget>[
              Icon(Icons.offline_pin_outlined, size: 15, color: c.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Peta offline 100 km dari pelabuhan asal · '
                  'diperbarui ${_packAge(s)}',
                  style: TextStyle(fontSize: 11.5, color: c.textMuted),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _refreshArea,
                child: Text(
                  _busy ? 'Mengunduh…' : 'Perbarui',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OwnSpotTile extends StatelessWidget {
  const _OwnSpotTile({required this.spot});

  final OwnSpot spot;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: <Widget>[
          Icon(Icons.diamond_outlined, size: 14, color: c.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  spot.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.textMain,
                  ),
                ),
                Text(
                  '${formatDecimal(spot.lat)}, ${formatDecimal(spot.lon)}'
                  '${spot.note.isEmpty ? '' : ' · ${spot.note}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Detail sheet for one of the sailor's own spots, with the two things they
/// can do with it: sail back to it, or delete it.
class _OwnSpotSheet extends StatelessWidget {
  const _OwnSpotSheet({
    required this.spot,
    required this.state,
    required this.onChanged,
    required this.onNavigate,
  });

  final OwnSpot spot;
  final AppState state;
  final VoidCallback onChanged;
  final VoidCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double distanceKm = spot.distanceKmTo(state.lat, state.lon);
    final double bearing = spot.bearingFrom(state.lat, state.lon);

    return SheetFrame(
      title: spot.label,
      subtitle: spot.note.isEmpty ? 'Spot pribadi' : spot.note,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Row(
            icon: Icons.straighten,
            label: 'Jarak dari posisi Anda',
            value: formatJarak(distanceKm),
          ),
          _Row(
            icon: Icons.explore_outlined,
            label: 'Arah (bearing)',
            value: '${bearing.toStringAsFixed(0)}° ${bearingLabel(bearing)}',
          ),
          _Row(
            icon: Icons.event_outlined,
            label: 'Ditandai',
            value: formatTanggal(spot.createdAt),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bgBody,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: SelectableText(
              '${spot.lat.toStringAsFixed(6)}, ${spot.lon.toStringAsFixed(6)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.textMain,
              ),
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            label: 'Buka Navigasi ke Sini',
            icon: Icons.explore,
            onPressed: onNavigate,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () async {
              final bool? del = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  title: const Text('Hapus spot ini?'),
                  content: Text(
                    '"${spot.label}" akan dihapus dari HP ini dan tidak bisa '
                    'dikembalikan.',
                    style: const TextStyle(fontSize: 13.5, height: 1.45),
                  ),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('Hapus', style: TextStyle(color: c.danger)),
                    ),
                  ],
                ),
              );
              if (del != true) return;
              await state.removeOwnSpot(spot.id);
              if (!context.mounted) return;
              onChanged();
              Navigator.of(context).pop();
            },
            icon: Icon(Icons.delete_outline, size: 18, color: c.danger),
            label: Text('Hapus spot', style: TextStyle(color: c.danger)),
          ),
        ],
      ),
    );
  }
}

/// Entry point for pulling today's table straight from the KKP portal.
class _LiveDpiCard extends StatelessWidget {
  const _LiveDpiCard({required this.state, required this.onFetched});

  final AppState state;
  final VoidCallback onFetched;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool busy = state.loadingDpi;

    return AppCard(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.cloud_download_outlined, size: 18, color: c.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Ambil DPI hari ini dari KKP',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Tabel DPI resmi diterbitkan per zona WPP dan per hari. Aplikasi '
            'mengunduh tabelnya lalu membaca koordinatnya dengan OCR.',
            style: TextStyle(fontSize: 12.5, height: 1.4, color: c.textMuted),
          ),
          if (busy && state.dpiProgress.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: c.primary),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    state.dpiProgress,
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                ),
              ],
            ),
          ],
          if (state.dpiError != null && !busy) ...<Widget>[
            const SizedBox(height: 10),
            NoticeBox(
              text: state.dpiError!,
              icon: Icons.error_outline,
              color: c.danger,
            ),
          ],
          const SizedBox(height: 12),
          AppButton(
            label: busy ? 'Mengambil…' : 'Pilih Zona & Tanggal',
            icon: Icons.tune,
            variant: ButtonVariant.secondary,
            dense: true,
            onPressed: busy
                ? null
                : () async {
                    await showDpiFetchSheet(context, state);
                    onFetched();
                  },
          ),
        ],
      ),
    );
  }
}

class _CoverageBanner extends StatelessWidget {
  const _CoverageBanner({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool empty = state.dpiPoints.isEmpty;
    if (empty) {
      return NoticeBox(
        text: 'Data DPI belum termuat. Buka Beranda lalu tekan "Siapkan Data".',
        icon: Icons.error_outline,
        color: c.danger,
      );
    }

    final Set<String> wpps =
        state.dpiPoints.map((DpiPoint p) => p.wpp).where((String w) => w.isNotEmpty).toSet();
    final String wppLabel = wpps.isEmpty
        ? 'tanpa kode WPP'
        : 'WPP ${(wpps.toList()..sort()).join(', ')}';
    // Points that came from a live KKP table carry the portal URL; the
    // bundled snapshot does not. Say which one the sailor is looking at.
    final bool live = state.dpiPoints.any((DpiPoint p) => p.sourceUrl.isNotEmpty);

    return NoticeBox(
      text: '${state.dpiPoints.length} titik dari $wppLabel, '
          'tanggal ${formatTanggal(state.dpiPoints.first.date)}. '
          '${live ? "Hasil unduhan langsung dari portal KKP." : "Data contoh yang dibawa di dalam aplikasi."} '
          'Tersimpan di HP, bisa dibuka tanpa sinyal.',
      icon: live ? Icons.cloud_done_outlined : Icons.offline_pin_outlined,
      color: c.primary,
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? c.primary : c.cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? c.primary : c.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : c.textMuted,
          ),
        ),
      ),
    );
  }
}

class _PointTile extends StatelessWidget {
  const _PointTile({
    required this.point,
    required this.distanceKm,
    required this.bearingLabel,
    required this.onTap,
  });

  final DpiPoint point;
  final double distanceKm;
  final String bearingLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      margin: const EdgeInsets.only(bottom: 10),
      onTap: onTap,
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            alignment: Alignment.center,
            child: Text(
              '${point.nomor}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: c.primary,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Titik ${point.nomor} · WPP ${point.wpp}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${point.lat.toStringAsFixed(3)}, ${point.lon.toStringAsFixed(3)}',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                // The marker on the map is hollow and struck through; the row
                // that lists it has to carry the same warning.
                if (point.onLand) ...<Widget>[
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Icon(Icons.terrain_outlined,
                          size: 12, color: c.warning),
                      const SizedBox(width: 4),
                      Text(
                        'di darat',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: c.warning,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                formatJarak(distanceKm),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: c.primary,
                ),
              ),
              Text(
                bearingLabel,
                style: TextStyle(fontSize: 11, color: c.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Detail sheet for one KKP DPI point.
///
/// Public so it can be built directly in tests: the map below it embeds
/// flutter_map, whose tile fetches keep the frame queue busy under the test
/// binding, and this sheet is the surface that actually carries the distance,
/// the ETA and the departure button. It is where a land point would send
/// someone somewhere, so it is worth testing without the map in the way.
class DpiPointSheet extends StatelessWidget {
  const DpiPointSheet({
    super.key,
    required this.point,
    required this.state,
    required this.onNavigate,
    required this.onStartTrip,
  });

  final DpiPoint point;
  final AppState state;
  final VoidCallback onNavigate;
  final VoidCallback onStartTrip;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final double distanceKm = point.distanceKmTo(state.lat, state.lon);
    final double bearing = point.bearingTo(state.lat, state.lon);
    final double speed = 6.5;
    final Duration eta = Duration(
      minutes: ((distanceKm / (speed * 1.852)) * 60).round(),
    );

    return SheetFrame(
      title: 'Titik DPI ${point.nomor}',
      subtitle: 'WPP ${point.wpp} · ${formatTanggal(point.date)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // The map already draws this marker hollow and struck through. The
          // sheet has to say why, or a fisherman reads the distance and ETA
          // and sets out for a beach.
          if (point.onLand) ...<Widget>[
            NoticeBox(
              text: 'Koordinat ini jatuh di darat menurut peta garis pantai. '
                  'KKP tetap mencetaknya di tabel, tetapi FishGuard tidak '
                  'menyarankannya sebagai tujuan melaut — pilih titik lain.',
              icon: Icons.terrain_outlined,
              color: c.warning,
            ),
            const SizedBox(height: 12),
          ],
          _Row(
            icon: Icons.straighten,
            label: 'Jarak dari posisi Anda',
            value: formatJarak(distanceKm),
          ),
          _Row(
            icon: Icons.explore_outlined,
            label: 'Arah (bearing)',
            value: '${bearing.toStringAsFixed(0)}° ${bearingLabel(bearing)}',
          ),
          _Row(
            icon: Icons.schedule,
            label: 'Perkiraan tiba (6,5 knot)',
            value: formatDurasi(eta),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bgBody,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'KOORDINAT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${point.lat.toStringAsFixed(6)}, ${point.lon.toStringAsFixed(6)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
                if (point.latDms.isNotEmpty || point.lonDms.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  SelectableText(
                    '${point.latDms}  ${point.lonDms}',
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),
          AppButton(
            // Only the departure button needs the warning wording; marking a
            // visited point is a log entry, not a recommendation.
            label: state.activeTrip != null
                ? 'Tandai Sudah Dikunjungi'
                : point.onLand
                    ? 'Tetap Berangkat ke Sini'
                    : 'Mulai Perjalanan ke Sini',
            icon: state.activeTrip == null ? Icons.play_arrow : Icons.flag,
            // Still enabled: the coordinate is KKP's, and the app does not get
            // to decide the sailor is wrong. The wording just stops it reading
            // as a recommendation.
            variant: point.onLand && state.activeTrip == null
                ? ButtonVariant.secondary
                : ButtonVariant.primary,
            onPressed: onStartTrip,
          ),
          const SizedBox(height: 10),
          AppButton(
            label: 'Buka Navigasi',
            variant: ButtonVariant.secondary,
            icon: Icons.explore,
            onPressed: onNavigate,
          ),
          if (point.sourceUrl.isNotEmpty) ...<Widget>[
            const SizedBox(height: 12),
            AppButton(
              label: 'Lihat Tabel Asli di Portal KKP',
              variant: ButtonVariant.secondary,
              icon: Icons.open_in_new,
              onPressed: () => launchUrl(
                Uri.parse(point.sourceUrl),
                mode: LaunchMode.externalApplication,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Text(
            'Sumber: PDPI KKP. Koordinat dipakai apa adanya dari portal; '
            'periksa ulang sebelum dipakai sebagai tujuan.',
            style: TextStyle(fontSize: 12, height: 1.4, color: c.textMuted),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 16, color: c.textMuted),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: c.textMuted),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: c.textMain,
            ),
          ),
        ],
      ),
    );
  }
}
