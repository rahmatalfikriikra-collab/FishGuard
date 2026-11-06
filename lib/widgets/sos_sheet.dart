import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

Future<void> showSosSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    builder: (BuildContext ctx) => _SosSheet(state: state),
  );
}

/// SOS screen (PRD 5.6).
///
/// The prototype promised "lokasi dibagikan ke Tim SAR"; SOS-4 forbids that
/// until an official integration exists, so the copy here is literal about
/// what actually happens: SMS to your own contacts, plus call shortcuts.
class _SosSheet extends StatefulWidget {
  const _SosSheet({required this.state});

  final AppState state;

  @override
  State<_SosSheet> createState() => _SosSheetState();
}

class _SosSheetState extends State<_SosSheet> {
  static const Duration _holdDuration = Duration(seconds: 3);

  /// PREP-10: if the SMS composer could not be opened, try again every two
  /// minutes. Only an observable failure is retried — the app cannot see
  /// whether the sailor pressed send inside the SMS app, and pretending it
  /// did would be worse than saying so.
  static const Duration _retryEvery = Duration(minutes: 2);

  Timer? _holdTimer;
  Timer? _retryTimer;
  int _retries = 0;
  bool _retrying = false;
  double _progress = 0;
  bool _sent = false;
  String? _status;

  @override
  void dispose() {
    _holdTimer?.cancel();
    _retryTimer?.cancel();
    super.dispose();
  }

  void _startHold() {
    if (_sent) return;
    _holdTimer?.cancel();
    setState(() => _progress = 0);
    const int ticks = 30;
    int count = 0;
    _holdTimer = Timer.periodic(
      _holdDuration ~/ ticks,
      (Timer t) {
        count++;
        setState(() => _progress = count / ticks);
        if (count >= ticks) {
          t.cancel();
          _send();
        }
      },
    );
  }

  void _cancelHold() {
    if (_sent) return;
    _holdTimer?.cancel();
    setState(() => _progress = 0);
  }

  String get _message {
    final AppState s = widget.state;
    final String lat = s.lat.toStringAsFixed(6);
    final String lon = s.lon.toStringAsFixed(6);
    final String maps = 'https://maps.google.com/?q=$lat,$lon';
    return 'SOS FISHGUARD. Saya butuh bantuan. '
        'Posisi saya: $lat, $lon. '
        'Peta: $maps '
        '(dikirim ${formatJam(DateTime.now())}, ${formatTanggal(DateTime.now())})';
  }

  Future<void> _send() async {
    setState(() {
      _sent = true;
      _status = null;
    });
    final AppState s = widget.state;
    final List<EmergencyContact> contacts = s.profile.kontak
        .where((EmergencyContact c) => c.hp.trim().isNotEmpty)
        .take(3)
        .toList();

    if (contacts.isEmpty) {
      setState(() {
        _status =
            'Belum ada kontak darurat tersimpan. Tambahkan di Profil, lalu coba lagi. '
            'Untuk sekarang gunakan panggilan 115 / 112 di bawah.';
      });
      return;
    }

    final List<String> recipients =
        contacts.map((EmergencyContact c) => c.hp.trim()).toList();
    final Uri smsUri = Uri(
      scheme: 'sms',
      path: recipients.join(','),
      queryParameters: <String, String>{'body': _message},
    );

    setState(() {
      _status =
          'Membuka aplikasi SMS untuk ${recipients.length} kontak. Tekan kirim di sana.';
    });

    final bool ok = await _openComposer(smsUri, recipients.length);
    if (!ok) _scheduleRetry(smsUri, recipients.length);
  }

  /// Opens the SMS composer. Returns false when the phone refused, which is
  /// the only failure the app can actually observe.
  Future<bool> _openComposer(Uri smsUri, int contactCount) async {
    try {
      final bool ok = await launchUrl(smsUri);
      if (!mounted) return ok;
      if (!ok) {
        setState(() {
          _status =
              'Aplikasi SMS tidak bisa dibuka otomatis. Salin teks di bawah dan '
              'kirim manual ke kontak Anda.';
        });
      }
      return ok;
    } on Object catch (e) {
      if (!mounted) return false;
      setState(() {
        _status = 'SMS gagal dibuka ($e). Salin teks di bawah dan kirim manual.';
      });
      return false;
    }
  }

  /// PREP-10: retry every two minutes while the composer keeps refusing.
  ///
  /// The timer stops on success, on the retry limit (10 tries, ~20 minutes),
  /// and when the sheet closes. The coordinates stay large on screen the whole
  /// time, which is what the sailor reads out over the radio if the phone
  /// never manages an SMS.
  void _scheduleRetry(Uri smsUri, int contactCount) {
    _retryTimer?.cancel();
    _retryTimer = Timer.periodic(_retryEvery, (Timer t) async {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_retrying) return;
      if (_retries >= 10) {
        t.cancel();
        if (!mounted) return;
        setState(() {
          _status = 'SMS masih gagal setelah 10 percobaan. Gunakan '
              'panggilan 115 / 112 dan bacakan koordinat besar di atas.';
        });
        return;
      }
      _retrying = true;
      _retries++;
      final bool ok = await _openComposer(smsUri, contactCount);
      _retrying = false;
      if (ok) {
        t.cancel();
        if (!mounted) return;
        setState(() {
          _status = 'Aplikasi SMS terbuka lagi. Tekan kirim di sana.';
        });
      }
    });
  }

  Future<void> _call(String number) async {
    final Uri uri = Uri(scheme: 'tel', path: number);
    try {
      await launchUrl(uri);
    } catch (_) {
      setState(() => _status = 'Tidak bisa membuka panggilan ke $number.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;

    return SheetFrame(
      title: 'SOS DARURAT',
      subtitle: 'Tahan tombol 3 detik untuk mengirim',
      trailing: Icon(Icons.warning_amber_rounded, color: c.danger, size: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.bgBody,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.border),
            ),
            child: Column(
              children: <Widget>[
                Text(
                  'POSISI ANDA',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.textMuted,
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  '${s.lat.toStringAsFixed(6)}, ${s.lon.toStringAsFixed(6)}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: c.textMain,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.gpsLocked
                      ? 'Dari GPS'
                      : 'GPS mati — memakai ${s.profile.pelabuhanAsal}',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 12),
                AppButton(
                  label: 'Salin koordinat',
                  dense: true,
                  variant: ButtonVariant.secondary,
                  icon: Icons.copy,
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: '${s.lat.toStringAsFixed(6)}, ${s.lon.toStringAsFixed(6)}',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Koordinat disalin')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          GestureDetector(
            onTapDown: (_) => _startHold(),
            onTapUp: (_) => _cancelHold(),
            onTapCancel: _cancelHold,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                Container(
                  height: 62,
                  decoration: BoxDecoration(
                    color: _sent ? c.danger.withValues(alpha: 0.7) : c.danger,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      const Icon(Icons.sos, color: Colors.white, size: 24),
                      const SizedBox(width: 10),
                      Text(
                        _sent ? 'SOS DIKIRIM' : 'TAHAN UNTUK KIRIM SOS',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius:
                        const BorderRadius.vertical(bottom: Radius.circular(14)),
                    child: LinearProgressIndicator(
                      value: _progress,
                      minHeight: 6,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'FishGuard membuka aplikasi SMS dengan koordinat Anda untuk maksimal '
            '3 kontak darurat '
            '(${s.profile.kontak.where((EmergencyContact c) => c.hp.trim().isNotEmpty).length} tersimpan), '
            'lalu Anda menekan kirim di sana. SMS jalan tanpa paket data.',
            style: TextStyle(fontSize: 13, height: 1.4, color: c.textMuted),
          ),
          if (_retries > 0 && _status != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Percobaan ulang otomatis tiap 2 menit '
              '($_retries/10) selama aplikasi SMS belum terbuka.',
              style: TextStyle(fontSize: 11.5, color: c.textMuted),
            ),
          ],
          if (_status != null) ...<Widget>[
            const SizedBox(height: 12),
            NoticeBox(
              text: _status!,
              icon: Icons.info_outline,
              color: c.warning,
            ),
          ],
          if (_sent) ...<Widget>[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.bgBody,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Teks SOS (salin bila SMS gagal)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: c.textMuted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _message,
                    style: TextStyle(fontSize: 13, height: 1.4, color: c.textMain),
                  ),
                  const SizedBox(height: 8),
                  AppButton(
                    label: 'Salin teks SOS',
                    dense: true,
                    variant: ButtonVariant.secondary,
                    icon: Icons.copy_all,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: _message));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Teks SOS disalin')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          SectionTitle('Nomor darurat'),
          Row(
            children: <Widget>[
              Expanded(
                child: _CallTile(
                  number: '115',
                  label: 'Basarnas',
                  onTap: () => _call('115'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _CallTile(
                  number: '112',
                  label: 'Darurat',
                  onTap: () => _call('112'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          NoticeBox(
            text:
                'FishGuard belum terhubung otomatis ke tim SAR. Setelah menekan '
                'SOS, telepon juga 115 dan bacakan koordinat di atas lewat radio '
                'bila ada.',
            icon: Icons.campaign_outlined,
            color: c.danger,
          ),
        ],
      ),
    );
  }
}

class _CallTile extends StatelessWidget {
  const _CallTile({
    required this.number,
    required this.label,
    required this.onTap,
  });

  final String number;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: c.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.danger.withValues(alpha: 0.3)),
        ),
        child: Column(
          children: <Widget>[
            Icon(Icons.call, color: c.danger, size: 20),
            const SizedBox(height: 4),
            Text(
              number,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: c.danger,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 12, color: c.textMuted)),
          ],
        ),
      ),
    );
  }
}
