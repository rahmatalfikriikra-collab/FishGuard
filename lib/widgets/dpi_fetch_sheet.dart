import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/kkp_pdpi_service.dart';
import '../services/table_ocr.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Opens the "Ambil data DPI hari ini" sheet and returns the number of points
/// that were read, or null when the sailor backed out.
Future<int?> showDpiFetchSheet(BuildContext context, AppState state) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.colors.cardBg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (BuildContext _) => _DpiFetchSheet(state: state),
  );
}

class _DpiFetchSheet extends StatefulWidget {
  const _DpiFetchSheet({required this.state});

  final AppState state;

  @override
  State<_DpiFetchSheet> createState() => _DpiFetchSheetState();
}

class _DpiFetchSheetState extends State<_DpiFetchSheet> {
  late DateTime _date;
  late WppZone _zone;
  bool _busy = false;
  DpiFetchResult? _result;

  @override
  void initState() {
    super.initState();
    _date = DateTime.now();
    _zone = widget.state.zoneHere ?? WppZone.all[5];
  }

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now(),
      helpText: 'Tanggal tabel DPI',
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _fetch() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    final DpiFetchResult? res = await widget.state.fetchDpi(
      zone: _zone,
      date: _date,
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _result = res;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    return SheetFrame(
      title: 'Data DPI dari KKP',
      subtitle: 'Portal Informasi KKP · WPP ${_zone.kode}',
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _FieldLabel('Zona WPP'),
            const SizedBox(height: 6),
            DropdownButtonFormField<WppZone>(
              initialValue: _zone,
              isExpanded: true,
              decoration: _decoration(c),
              items: <DropdownMenuItem<WppZone>>[
                for (final WppZone z in WppZone.all)
                  DropdownMenuItem<WppZone>(
                    value: z,
                    child: Text(
                      '${z.label} — ${z.nama}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (WppZone? z) {
                      if (z != null) setState(() => _zone = z);
                    },
            ),
            const SizedBox(height: 14),
            _FieldLabel('Tanggal'),
            const SizedBox(height: 6),
            InkWell(
              onTap: _busy ? null : _pickDate,
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
                decoration: BoxDecoration(
                  color: c.bgBody,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.calendar_today, size: 16, color: c.textMuted),
                    const SizedBox(width: 10),
                    Text(
                      formatTanggal(_date),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: c.textMain,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_busy) ...<Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.state.dpiProgress.isEmpty
                          ? 'Bekerja…'
                          : widget.state.dpiProgress,
                      style: TextStyle(fontSize: 13, color: c.textMuted),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            AppButton(
              label: _busy ? 'Sedang mengambil…' : 'Ambil & Baca Tabel DPI',
              icon: Icons.cloud_download_outlined,
              onPressed: _busy ? null : _fetch,
            ),
            if (_result != null) ...<Widget>[
              const SizedBox(height: 16),
              _ResultBlock(result: _result!, onDone: () {
                if (_result!.rows.isNotEmpty) {
                  Navigator.of(context).pop(_result!.rows.length);
                }
              }),
            ],
            const SizedBox(height: 14),
            Text(
              'Sumber: portal-informasi.kkp.go.id/pdpi. Tabel DPI diterbitkan '
              'sebagai gambar, jadi koordinat dibaca dengan OCR di perangkat '
              'ini. Periksa ulang titik sebelum dijadikan tujuan — data ini '
              'prakiraan, bukan jaminan lokasi ikan.',
              style: TextStyle(fontSize: 11.5, height: 1.45, color: c.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _decoration(AppColors c) => InputDecoration(
        isDense: true,
        filled: true,
        fillColor: c.bgBody,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c.border),
        ),
      );
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: context.colors.textMuted,
        ),
      );
}

class _ResultBlock extends StatelessWidget {
  const _ResultBlock({required this.result, required this.onDone});

  final DpiFetchResult result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool ok = result.rows.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        NoticeBox(
          text: ok
              ? '${result.rows.length} titik terbaca dari tabel WPP '
                  '${result.zone.kode} tanggal ${formatTanggal(result.date)}.'
              : (result.error ?? 'Tidak ada titik yang terbaca.'),
          icon: ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? c.accent : c.danger,
        ),
        if (result.error != null && ok)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: NoticeBox(
              text: result.error!,
              icon: Icons.warning_amber,
              color: c.warning,
            ),
          ),
        if (ok) ...<Widget>[
          const SizedBox(height: 10),
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
                  'Contoh 3 titik pertama',
                  style: TextStyle(fontSize: 11, color: c.textMuted),
                ),
                const SizedBox(height: 6),
                for (final DpiRowData r in result.rows.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      'Titik ${r.nomor}: ${r.latitude.toStringAsFixed(4)}, '
                      '${r.longitude.toStringAsFixed(4)}',
                      style: TextStyle(fontSize: 12.5, color: c.textMain),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          AppButton(
            label: 'Pakai ${result.rows.length} Titik Ini',
            icon: Icons.check,
            variant: ButtonVariant.success,
            onPressed: onDone,
          ),
        ],
      ],
    );
  }
}
