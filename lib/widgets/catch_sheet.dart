import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Bottom sheet for recording one catch (PRD v1.x: "Catatan hasil tangkapan per
/// titik dan umpan balik akurasi DPI").
///
/// Everything is filled in on the boat without a signal, so the form stays
/// short: species, weight, how many, and where. The location defaults to the
/// target DPI point when one was picked in Navigasi, otherwise to the current
/// GPS fix, so the sailor usually only types the weight.
Future<bool> showCatchSheet(
  BuildContext context,
  AppState state, {
  DpiPoint? titik,
}) async {
  final bool? saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (BuildContext ctx) => _CatchSheet(state: state, titik: titik),
  );
  return saved ?? false;
}

class _CatchSheet extends StatefulWidget {
  const _CatchSheet({required this.state, this.titik});

  final AppState state;
  final DpiPoint? titik;

  @override
  State<_CatchSheet> createState() => _CatchSheetState();
}

class _CatchSheetState extends State<_CatchSheet> {
  static const List<String> _jenisUmum = <String>[
    'Kembung',
    'Tongkol',
    'Cakalang',
    'Tuna',
    'Bandeng',
    'Terbang',
    'Layang',
    'Kerapu',
    'Udang',
    'Cumi-cumi',
  ];

  final TextEditingController _berat = TextEditingController();
  final TextEditingController _jumlah = TextEditingController(text: '1');
  final TextEditingController _catatan = TextEditingController();

  String _jenis = _jenisUmum.first;
  bool _pakaiTitik = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    // With no DPI target the catch is pinned to the boat's position instead.
    _pakaiTitik = widget.titik != null;
  }

  @override
  void dispose() {
    _berat.dispose();
    _jumlah.dispose();
    _catatan.dispose();
    super.dispose();
  }

  Future<void> _simpan() async {
    final double? berat = double.tryParse(_berat.text.trim().replaceAll(',', '.'));
    if (berat == null || berat <= 0) {
      setState(() => _error = 'Isi berat tangkapan dalam kg, misalnya 2.5.');
      return;
    }
    final int jumlah = int.tryParse(_jumlah.text.trim()) ?? 1;
    if (jumlah < 1) {
      setState(() => _error = 'Jumlah ikan minimal 1.');
      return;
    }

    final AppState s = widget.state;
    final DpiPoint? titik = _pakaiTitik ? widget.titik : null;
    await s.addCatch(CatchLog(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      waktu: DateTime.now(),
      jenis: _jenis,
      beratKg: berat,
      jumlah: jumlah,
      dpiNomor: titik?.nomor,
      dpiWpp: titik?.wpp ?? '',
      lat: titik == null ? s.lat : null,
      lon: titik == null ? s.lon : null,
      catatan: _catatan.text.trim(),
    ));
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    final DpiPoint? titik = widget.titik;

    return SheetFrame(
      title: 'Catat Hasil Tangkapan',
      subtitle: 'Tersimpan di HP ini, terkirim otomatis saat ada sinyal.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DropdownButtonFormField<String>(
            initialValue: _jenis,
            decoration: const InputDecoration(
              labelText: 'Jenis ikan',
              prefixIcon: Icon(Icons.set_meal),
            ),
            items: <DropdownMenuItem<String>>[
              for (final String j in _jenisUmum)
                DropdownMenuItem<String>(value: j, child: Text(j)),
            ],
            onChanged: (String? v) {
              if (v != null) setState(() => _jenis = v);
            },
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _berat,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Berat (kg)',
                    hintText: '2.5',
                    prefixIcon: Icon(Icons.scale_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _jumlah,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Ekor'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _catatan,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
              hintText: 'Umpan, kondisi, atau hal lain',
              prefixIcon: Icon(Icons.notes_outlined),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Lokasi tangkapan',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          if (titik != null)
            RadioListTile<bool>(
              value: true,
              // ignore: deprecated_member_use
              groupValue: _pakaiTitik,
              contentPadding: EdgeInsets.zero,
              activeColor: c.primary,
              title: Text(
                'Titik DPI ${titik.nomor} · WPP ${titik.wpp}',
                style: const TextStyle(fontSize: 14),
              ),
              // ignore: deprecated_member_use
              onChanged: (bool? v) => setState(() => _pakaiTitik = v ?? true),
            ),
          RadioListTile<bool>(
            value: false,
            // ignore: deprecated_member_use
            groupValue: _pakaiTitik,
            contentPadding: EdgeInsets.zero,
            activeColor: c.primary,
            title: Text(
              s.gpsLocked
                  ? 'Posisi kapal sekarang '
                      '(${s.lat.toStringAsFixed(4)}, ${s.lon.toStringAsFixed(4)})'
                  : 'Posisi kapal (GPS belum terkunci, memakai '
                      '${s.profile.pelabuhanAsal})',
              style: const TextStyle(fontSize: 14),
            ),
            // ignore: deprecated_member_use
            onChanged: (bool? v) => setState(() => _pakaiTitik = v ?? false),
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: 13, color: c.danger),
            ),
          ],
          const SizedBox(height: 14),
          AppButton(
            label: 'Simpan Tangkapan',
            icon: Icons.save,
            onPressed: _simpan,
          ),
          const SizedBox(height: 10),
          NoticeBox(
            text: 'Catatan ini dipakai untuk melihat titik mana yang paling '
                'banyak hasilnya. Data DPI tetap prakiraan, bukan jaminan.',
            icon: Icons.info_outline,
            color: c.primary,
          ),
        ],
      ),
    );
  }
}

/// Formats a weight the way the catch list shows it.
String formatKg(double kg) {
  if (kg >= 100) return '${kg.toStringAsFixed(0)} kg';
  if (kg == kg.roundToDouble()) return '${kg.toStringAsFixed(0)} kg';
  return '${kg.toStringAsFixed(1)} kg';
}

/// Shared row widget for one catch, used by the history screen and the
/// dashboard summary.
class CatchTile extends StatelessWidget {
  const CatchTile({
    super.key,
    required this.entry,
    this.onDelete,
  });

  final CatchLog entry;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.set_meal, size: 20, color: c.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.jenis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: c.textMain,
                        ),
                      ),
                    ),
                    Text(
                      formatKg(entry.beratKg),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: c.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.jumlah} ekor · ${formatTanggal(entry.waktu)} '
                  '${formatJam(entry.waktu)}',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Icon(
                      entry.dpiNomor != null
                          ? Icons.pin_drop_outlined
                          : Icons.my_location,
                      size: 12,
                      color: c.textMuted,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        entry.lokasiLabel,
                        style: TextStyle(fontSize: 12, color: c.textMuted),
                      ),
                    ),
                  ],
                ),
                if (entry.catatan.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    entry.catatan,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      fontStyle: FontStyle.italic,
                      color: c.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              icon: Icon(Icons.delete_outline, size: 20, color: c.danger),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}
