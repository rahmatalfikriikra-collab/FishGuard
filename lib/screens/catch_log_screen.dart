import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/catch_sheet.dart';
import '../widgets/common.dart';

/// Catatan Hasil Tangkapan (PRD v1.x).
///
/// Lists every catch the sailor recorded, grouped by day, with a running total
/// and the DPI point that has produced the best average so far. Everything is
/// read from the device — no network.
class CatchLogScreen extends StatelessWidget {
  const CatchLogScreen({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final List<CatchLog> entries = state.catches;
    final MapEntry<int, double>? best = state.bestDpiByCatch;

    return Scaffold(
      backgroundColor: c.bgApp,
      appBar: AppBar(
        title: const Text(
          'Hasil Tangkapan',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: c.primary,
        foregroundColor: Colors.white,
        onPressed: () async {
          await showCatchSheet(context, state);
        },
        icon: const Icon(Icons.add),
        label: const Text('Catat'),
      ),
      body: entries.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(Icons.set_meal, size: 56, color: c.textMuted),
                    const SizedBox(height: 14),
                    Text(
                      'Belum ada catatan tangkapan',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: c.textMain,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Tekan "Catat" setiap kali menarik hasil. Catatan ini '
                      'membantu melihat titik mana yang paling banyak ikan.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.45,
                        color: c.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
              children: <Widget>[
                AppCard(
                  margin: EdgeInsets.zero,
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Total tercatat',
                        style: TextStyle(fontSize: 12.5, color: c.textMuted),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        formatKg(state.catchKgTotal),
                        style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: c.primary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${entries.length} catatan · hari ini '
                        '${formatKg(state.catchKgToday)}',
                        style: TextStyle(fontSize: 12.5, color: c.textMuted),
                      ),
                      if (best != null) ...<Widget>[
                        const SizedBox(height: 10),
                        Divider(color: c.border),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            Icon(Icons.emoji_events_outlined,
                                size: 16, color: c.accent),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Titik DPI ${best.key} rata-rata '
                                '${formatKg(best.value)} per catatan.',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  height: 1.35,
                                  color: c.textMain,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                for (final CatchLog entry in entries) ...<Widget>[
                  if (_showDayHeader(entries, entry))
                    SectionTitle(
                      '${formatTanggal(entry.waktu)} · '
                      '${formatKg(state.catchKgOn(entry.waktu))}',
                    ),
                  CatchTile(
                    entry: entry,
                    onDelete: () => _confirmDelete(context, state, entry),
                  ),
                ],
              ],
            ),
    );
  }

  /// A day heading appears above the first catch of each day.
  bool _showDayHeader(List<CatchLog> all, CatchLog entry) {
    final int i = all.indexOf(entry);
    if (i <= 0) return true;
    return !samaHari(all[i - 1].waktu, entry.waktu);
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppState state,
    CatchLog entry,
  ) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Hapus catatan?'),
        content: Text(
          '${entry.jenis} ${formatKg(entry.beratKg)} pada '
          '${formatTanggal(entry.waktu)} akan dihapus.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true) await state.deleteCatch(entry.id);
  }
}
