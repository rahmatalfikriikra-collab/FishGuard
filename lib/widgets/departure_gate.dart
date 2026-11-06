import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';

/// What the sailor chose at the pre-departure gate.
enum DepartureChoice { download, sailAnyway, cancel }

/// Asks the sailor to download today's KKP table and BMKG forecast before
/// going to sea.
///
/// Shared by every place that can start a trip — the Navigasi button and the
/// map's point sheet — so the rule is identical wherever it is triggered.
/// Returns null when the dialog was dismissed without an answer.
///
/// The gate never *forbids* departure. A fisherman with a dead signal and a
/// reason to sail must not be trapped by the app, and a boat already out has
/// no other choice. What it does forbid is leaving *while believing* the data
/// is current: the app's offline pack is read on a build machine days or weeks
/// before this trip, and nothing on the map shows that the fish have moved.
Future<DepartureChoice?> showDepartureGate(
  BuildContext context,
  AppState state,
) async {
  final List<String> blockers = state.departureBlockers;
  final bool canDownload = !state.loadingDpi && !state.loadingWeather;
  return showDialog<DepartureChoice>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext ctx) {
      final AppColors c = ctx.colors;
      return AlertDialog(
        title: const Text('Unduh data dulu'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (final String b in blockers)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Icon(Icons.error_outline, size: 16, color: c.warning),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        b,
                        style: const TextStyle(fontSize: 13.5, height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Di laut tidak ada internet. KKP menerbitkan tabel titik DPI '
              'baru setiap hari dan BMKG memperbarui prakiraan secara berkala '
              '— data kemarin bisa menyesatkan.',
              style: TextStyle(fontSize: 13.5, height: 1.45),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx, DepartureChoice.sailAnyway),
            child: const Text('Tetap berangkat'),
          ),
          FilledButton(
            onPressed: canDownload
                ? () => Navigator.pop(ctx, DepartureChoice.download)
                : null,
            child: const Text('Unduh sekarang'),
          ),
        ],
      );
    },
  );
}

/// The same gate, plus the download it offers, for callers that have no
/// dedicated "sync" routine of their own. Returns true when the boat may go:
/// either the data was downloaded on the spot, or the sailor chose to sail
/// regardless. Returns false when they cancelled or the download failed.
Future<bool> runDepartureGate(
  BuildContext context,
  AppState state, {
  Future<void> Function()? onDownload,
}) async {
  if (state.readyForSea) return true;
  final DepartureChoice? choice = await showDepartureGate(context, state);
  if (choice == null || choice == DepartureChoice.cancel) return false;
  if (choice == DepartureChoice.sailAnyway) return true;
  if (onDownload == null) return false;
  await onDownload();
  // The download may still have failed — that is what the return value is
  // for. Callers decide whether to insist or to show the error.
  return state.readyForSea;
}
