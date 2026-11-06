import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../services/fuel_calculator.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Hitung BBM (PRD FUEL-1 / FUEL-2), ported from the prototype form and
/// extended with the PRD's distance input and 10% reserve.
class FuelScreen extends StatefulWidget {
  const FuelScreen({super.key, required this.state});

  final AppState state;

  @override
  State<FuelScreen> createState() => _FuelScreenState();
}

class _FuelScreenState extends State<FuelScreen> {
  final TextEditingController _durasiController = TextEditingController(text: '4');
  final TextEditingController _jarakController = TextEditingController();
  final TextEditingController _pkController = TextEditingController();

  String _mode = 'durasi';
  int _condition = 0;
  double? _pk;
  FuelEstimate? _est;
  bool _showResult = false;

  @override
  void initState() {
    super.initState();
    _pkController.text = widget.state.profile.dayaMesinPk.toString();
    _pk = widget.state.profile.dayaMesinPk;
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadProfile());
  }

  void _loadProfile() {
    final UserProfile p = widget.state.profile;
    _pkController.text = p.dayaMesinPk.toString();
    _pk = p.dayaMesinPk;
    _condition = p.umurMesin;
  }

  @override
  void dispose() {
    _durasiController.dispose();
    _jarakController.dispose();
    _pkController.dispose();
    super.dispose();
  }

  void _selectPk(double v) {
    _pkController.text = v.toString();
    setState(() => _pk = v);
  }

  void _calculate() {
    final double pk = double.tryParse(_pkController.text) ?? 5.5;
    final double? durasi = double.tryParse(_durasiController.text);
    final double? jarak = double.tryParse(_jarakController.text);

    if (_mode == 'durasi' && (durasi == null || durasi <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan durasi melaut yang valid (minimal 1 jam).')),
      );
      return;
    }
    if (_mode == 'jarak' && (jarak == null || jarak <= 0)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Masukkan jarak tempuh yang valid (minimal 1 km).')),
      );
      return;
    }

    final FuelEstimate est = FuelCalculator.estimate(
      powerPk: pk,
      condition: _condition,
      hours: _mode == 'durasi' ? durasi : null,
      distanceKm: _mode == 'jarak' ? jarak : null,
      calibration: widget.state.fuelCalibration,
    );
    setState(() {
      _pk = pk;
      _est = est;
      _showResult = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Hitung Bahan Bakar',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textMain,
            ),
          ),
          Text(
            'Estimasi solar sebelum berangkat, plus cadangan 10%.',
            style: TextStyle(fontSize: 13, color: c.textMuted),
          ),
          const SizedBox(height: 16),
          AppCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<String>(
                  segments: const <ButtonSegment<String>>[
                    ButtonSegment<String>(
                      value: 'durasi',
                      label: Text('Durasi (jam)'),
                      icon: Icon(Icons.access_time, size: 16),
                    ),
                    ButtonSegment<String>(
                      value: 'jarak',
                      label: Text('Jarak (km)'),
                      icon: Icon(Icons.straighten, size: 16),
                    ),
                  ],
                  selected: <String>{_mode},
                  onSelectionChanged: (Set<String> s) =>
                      setState(() => _mode = s.first),
                ),
                const SizedBox(height: 18),
                if (_mode == 'durasi')
                  TextField(
                    controller: _durasiController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Estimasi Durasi Melaut (Jam)',
                      hintText: 'Contoh: 4',
                      prefixIcon: Icon(Icons.access_time),
                    ),
                  )
                else
                  TextField(
                    controller: _jarakController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Estimasi Jarak Tempuh (km)',
                      hintText: 'Contoh: 25',
                      prefixIcon: Icon(Icons.straighten),
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  'Daya Mesin (PK)',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: c.textMain,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final double v in FuelConfig.powerPresets)
                      _PkChip(
                        value: v,
                        label: _labelFor(v),
                        selected: _pk == v,
                        onTap: () => _selectPk(v),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _pkController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Atau angka bebas (PK)',
                    hintText: 'Contoh: 5,5 / 15 / 25 / 40',
                    prefixIcon: Icon(Icons.settings),
                  ),
                  onChanged: (String v) =>
                      setState(() => _pk = double.tryParse(v)),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: _condition,
                  decoration: const InputDecoration(
                    labelText: 'Kondisi Mesin',
                    prefixIcon: Icon(Icons.build),
                  ),
                  items: <DropdownMenuItem<int>>[
                    for (final MapEntry<int, String> e in FuelConfig.conditions.entries)
                      DropdownMenuItem<int>(
                        value: e.key,
                        child: Text(e.value),
                      ),
                  ],
                  onChanged: (int? v) {
                    if (v != null) setState(() => _condition = v);
                  },
                ),
                const SizedBox(height: 18),
                AppButton(
                  label: 'Hitung Estimasi',
                  icon: Icons.calculate,
                  onPressed: _calculate,
                ),
              ],
            ),
          ),
          if (_showResult && _est != null) ...<Widget>[
            const SizedBox(height: 16),
            AppCard(
              accent: c.primary,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Rincian Estimasi Solar',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: c.textMain,
                    ),
                  ),
                  const SizedBox(height: 14),
                  BreakdownRow(label: 'Daya mesin', value: '${_est!.powerPk.toString()} PK'),
                  BreakdownRow(
                    label: _est!.source == 'jarak' ? 'Jarak tempuh' : 'Durasi',
                    value: _est!.source == 'jarak'
                        ? '${_est!.distanceKm.toStringAsFixed(1)} km'
                        : '${_est!.hours.toStringAsFixed(1)} jam',
                  ),
                  BreakdownRow(label: 'Kondisi mesin', value: _est!.conditionLabel.split('(').first.trim()),
                  BreakdownRow(label: 'Konsumsi dasar', value: '${_est!.baseLiters.toStringAsFixed(1)} L'),
                  BreakdownRow(label: 'Faktor usia mesin', value: '×${_est!.conditionFactor.toStringAsFixed(1)}'),
                  BreakdownRow(
                    label: 'Total estimasi',
                    value: '${_est!.totalLiters.toStringAsFixed(1)} L',
                    total: true,
                  ),
                  BreakdownRow(
                    label: 'Cadangan (10%)',
                    value: '${_est!.reserveLiters.toStringAsFixed(1)} L',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: c.warning.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.warning.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Icon(Icons.info_outline, size: 18, color: c.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Bawa minimal ${_est!.grandTotal.toStringAsFixed(1)} L solar '
                            '(estimasi + cadangan 10%).',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.textMain,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _FuelGauge(est: _est!),
                ],
              ),
            ),
            const SizedBox(height: 12),
            NoticeBox(
              text: s.calibrationSamples == 0
                  ? 'Estimasi ini memakai rumus standar (0,2 L/PK/jam). Setelah '
                      'Anda mengisi "solar terpakai" di riwayat pelayaran, '
                      'FishGuard menyesuaikan rumus dengan kapal Anda sendiri.'
                  : 'Estimasi sudah dikalibrasi dengan kapal Anda: '
                      '×${s.fuelCalibration.toStringAsFixed(2)} dari '
                      '${s.calibrationSamples} pelayaran. Atur atau reset di '
                      'Profil → Kalibrasi Solar.',
              icon: Icons.tune,
              color: s.calibrationSamples == 0 ? c.textMuted : c.primary,
            ),
          ],
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  String _labelFor(double v) => switch (v) {
        5.5 => 'Sampan',
        15 => 'Katir kecil',
        25 => 'Katir sedang',
        40 => 'Katir besar',
        _ => 'Mesin',
      };
}

class _PkChip extends StatelessWidget {
  const _PkChip({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final double value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return ChoiceChip(
      label: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            '${value.toString().replaceAll('.0', '')} PK',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: selected ? Colors.white : c.textMain,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: selected ? Colors.white.withValues(alpha: 0.9) : c.textMuted,
            ),
          ),
        ],
      ),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: c.primary,
      backgroundColor: c.bgBody,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: selected ? c.primary : c.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
  }
}

class _FuelGauge extends StatelessWidget {
  const _FuelGauge({required this.est});

  final FuelEstimate est;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    const double maxCapacity = 50;
    final double percentage = (est.totalLiters / maxCapacity).clamp(0.0, 1.0);
    final Color tint = percentage < 0.3
        ? c.danger
        : percentage < 0.6
            ? c.warning
            : c.accent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              'Indikator BBM',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: c.textMain,
              ),
            ),
            Text(
              '${(percentage * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: tint),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: percentage,
            minHeight: 22,
            backgroundColor: c.border,
            valueColor: AlwaysStoppedAnimation<Color>(tint),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${est.totalLiters.toStringAsFixed(1)} L dari $maxCapacity L kapasitas tangki',
          style: TextStyle(fontSize: 12, color: c.textMuted),
        ),
      ],
    );
  }
}
