import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/models.dart';
import '../services/app_state.dart';
import '../services/claude_service.dart';
import '../services/fuel_calculator.dart';
import '../services/local_data.dart';
import '../theme/app_theme.dart';
import '../widgets/catch_sheet.dart';
import '../widgets/common.dart';
import '../widgets/sea_map.dart';
import 'catch_log_screen.dart';

/// Profil (PRD PROF-1 / PROF-2 / PROF-3).
class ProfilScreen extends StatefulWidget {
  const ProfilScreen({super.key, required this.state});

  final AppState state;

  @override
  State<ProfilScreen> createState() => _ProfilScreenState();
}

class _ProfilScreenState extends State<ProfilScreen> {
  bool _editing = false;

  final TextEditingController _name = TextEditingController();
  final TextEditingController _hp = TextEditingController();
  final TextEditingController _boat = TextEditingController();
  final TextEditingController _port = TextEditingController();
  final TextEditingController _tank = TextEditingController();
  final TextEditingController _pk = TextEditingController();
  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _contactHp = TextEditingController();
  final TextEditingController _apiKey = TextEditingController();
  final TextEditingController _model = TextEditingController();

  int _engineAge = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    final UserProfile p = widget.state.profile;
    _name.text = p.nama;
    _hp.text = p.hp;
    _boat.text = p.namaKapal;
    _port.text = p.pelabuhanAsal;
    _tank.text = p.tankLiters.toStringAsFixed(0);
    _pk.text = p.dayaMesinPk.toString();
    _engineAge = p.umurMesin;
    _apiKey.text = widget.state.apiKey;
    _model.text = widget.state.aiModel;
  }

  @override
  void dispose() {
    for (final TextEditingController c in <TextEditingController>[
      _name, _hp, _boat, _port, _tank, _pk,
      _contactName, _contactHp, _apiKey, _model,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final UserProfile next = UserProfile(
      nama: _name.text.trim().isEmpty ? 'Nelayan' : _name.text.trim(),
      hp: _hp.text.trim(),
      namaKapal: _boat.text.trim().isEmpty ? 'Kapal Tanpa Nama' : _boat.text.trim(),
      dayaMesinPk: double.tryParse(_pk.text) ?? widget.state.profile.dayaMesinPk,
      umurMesin: _engineAge,
      pelabuhanAsal: _port.text.trim().isEmpty
          ? MapConfig.defaultPortName
          : _port.text.trim(),
      tankLiters: double.tryParse(_tank.text) ?? widget.state.profile.tankLiters,
      isGuest: widget.state.profile.isGuest,
      kontak: widget.state.profile.kontak,
    );
    await widget.state.saveProfile(next);
    await widget.state.setApiKey(_apiKey.text);
    await widget.state.setAiModel(
      _model.text.trim().isEmpty ? ClaudeClient.defaultModel : _model.text.trim(),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profil disimpan')),
      );
      setState(() => _editing = false);
    }
  }

  void _addContact() {
    final String n = _contactName.text.trim();
    final String h = _contactHp.text.trim();
    if (h.isEmpty) return;
    final UserProfile p = widget.state.profile;
    final List<EmergencyContact> list = <EmergencyContact>[
      ...p.kontak,
      EmergencyContact(nama: n.isEmpty ? 'Kontak' : n, hp: h),
    ];
    if (list.length > 3) list.removeAt(0);
    widget.state.saveProfile(UserProfile(
      nama: p.nama,
      hp: p.hp,
      namaKapal: p.namaKapal,
      dayaMesinPk: p.dayaMesinPk,
      umurMesin: p.umurMesin,
      pelabuhanAsal: p.pelabuhanAsal,
      tankLiters: p.tankLiters,
      isGuest: p.isGuest,
      kontak: list,
    ));
    _contactName.clear();
    _contactHp.clear();
  }

  void _removeContact(int index) {
    final UserProfile p = widget.state.profile;
    final List<EmergencyContact> list = <EmergencyContact>[...p.kontak]..removeAt(index);
    widget.state.saveProfile(UserProfile(
      nama: p.nama,
      hp: p.hp,
      namaKapal: p.namaKapal,
      dayaMesinPk: p.dayaMesinPk,
      umurMesin: p.umurMesin,
      pelabuhanAsal: p.pelabuhanAsal,
      tankLiters: p.tankLiters,
      isGuest: p.isGuest,
      kontak: list,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final AppState s = widget.state;
    final UserProfile p = s.profile;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Header
          AppCard(
            margin: EdgeInsets.zero,
            padding: const EdgeInsets.all(20),
            child: Row(
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: <Color>[c.primary, c.primaryLight],
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.person, color: Colors.white, size: 34),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        p.nama,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                          color: c.textMain,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        p.hp.isEmpty ? 'Belum login' : p.hp,
                        style: TextStyle(fontSize: 13, color: c.textMuted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(_editing ? Icons.close : Icons.edit, color: c.primary),
                  onPressed: () => setState(() => _editing = !_editing),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Settings toggles
          AppCard(
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: Column(
              children: <Widget>[
                _SettingTile(
                  icon: Icons.language,
                  title: 'Bahasa',
                  subtitle: 'Indonesia',
                  trailing: Text(
                    'ID',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: c.primary,
                    ),
                  ),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.dark_mode_outlined,
                  title: 'Mode Tampilan',
                  subtitle: s.darkMode ? 'Gelap' : 'Terang',
                  trailing: Switch(
                    value: s.darkMode,
                    activeThumbColor: c.primary,
                    onChanged: (bool v) => s.setDarkMode(v),
                  ),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.notifications_active_outlined,
                  title: 'Pengingat Subuh',
                  subtitle: s.reminderEnabled
                      ? 'Setiap hari ${s.reminderHour.toString().padLeft(2, '0')}.'
                          '${s.reminderMinute.toString().padLeft(2, '0')} WITA'
                      : 'Nonaktif',
                  trailing: Switch(
                    value: s.reminderEnabled,
                    activeThumbColor: c.primary,
                    onChanged: (bool v) async {
                      final bool ok = await s.setReminder(enabled: v);
                      if (!v) return;
                      if (!context.mounted) return;
                      if (!ok) {
                        // Say it plainly: a reminder the phone refuses would
                        // otherwise look set and never fire.
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Notifikasi ditolak HP. Izinkan notifikasi '
                              'FishGuard di Pengaturan Android.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  onTap: s.reminderEnabled
                      ? () => _pickReminderTime(context, s)
                      : null,
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.sync,
                  title: 'Sinkron Otomatis',
                  subtitle: s.backgroundSyncEnabled
                      ? 'Titik DPI diunduh di latar belakang'
                      : 'Nonaktif — sinkron manual saja',
                  trailing: Switch(
                    value: s.backgroundSyncEnabled,
                    activeThumbColor: c.primary,
                    onChanged: (bool v) => s.setBackgroundSync(v),
                  ),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.tune,
                  title: 'Kalibrasi Solar',
                  subtitle: s.calibrationSamples == 0
                      ? 'Belum dikalibrasi — pakai rumus standar'
                      : '${s.calibrationSamples} pelayaran · '
                          '×${s.fuelCalibration.toStringAsFixed(2)}',
                  trailing: Icon(Icons.chevron_right, color: c.textMuted),
                  onTap: () => _showCalibration(context, s),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Data Menunggu Terkirim',
                  // PREP-9: the state is spelled out, not just counted — the
                  // sailor should never wonder whether a record was lost.
                  subtitle: s.pendingOutbox.isEmpty
                      ? 'Tidak ada'
                      : s.flushingOutbox
                          ? 'Mencoba mengirim…'
                          : '${s.pendingOutbox.length} catatan aman di HP · '
                              'server belum tersedia',
                  trailing: s.pendingOutbox.isEmpty
                      ? Icon(Icons.chevron_right, color: c.textMuted)
                      : Chip2(
                          label: '${s.pendingOutbox.length}',
                          color: c.warning,
                        ),
                  onTap: () => _showOutbox(context, s),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.history,
                  title: 'Riwayat Pelayaran',
                  subtitle: '${s.trips.length} kali',
                  trailing: Icon(Icons.chevron_right, color: c.textMuted),
                  onTap: () => _showHistory(context, s),
                ),
                Divider(height: 1, color: c.border),
                _SettingTile(
                  icon: Icons.set_meal,
                  title: 'Hasil Tangkapan',
                  subtitle: s.catches.isEmpty
                      ? 'Belum ada catatan'
                      : '${s.catches.length} catatan · ${formatKg(s.catchKgTotal)}',
                  trailing: Icon(Icons.chevron_right, color: c.textMuted),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext _) => CatchLogScreen(state: s),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Emergency contacts
          AppCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Kontak Darurat (maks. 3)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Dipakai untuk SMS SOS. SMS jalan tanpa paket data.',
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < p.kontak.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.person, size: 16, color: c.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                p.kontak[i].nama,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                p.kontak[i].hp,
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: c.danger, size: 20),
                          onPressed: () => _removeContact(i),
                        ),
                      ],
                    ),
                  ),
                if (p.kontak.length < 3) ...<Widget>[
                  const SizedBox(height: 6),
                  TextField(
                    controller: _contactName,
                    decoration: const InputDecoration(
                      labelText: 'Nama kontak',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _contactHp,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Nomor HP',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      AppButton(
                        label: 'Tambah',
                        dense: true,
                        icon: Icons.add,
                        onPressed: _addContact,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // AI settings
          AppCard(
            margin: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Asisten AI (Claude)',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: c.textMain,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Opsional. Bila diisi, FishGuard minta saran dinamis dari Claude '
                  'berdasarkan data cuaca hari ini. Bila kosong, saran lokal dipakai.',
                  style: TextStyle(fontSize: 12, height: 1.4, color: c.textMuted),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: s.useAi,
                  onChanged: (bool v) => s.setUseAi(v),
                  title: const Text('Pakai AI'),
                  subtitle: Text(
                    s.useAi ? 'Aktif' : 'Nonaktif',
                    style: TextStyle(fontSize: 12, color: c.textMuted),
                  ),
                  contentPadding: EdgeInsets.zero,
                  activeThumbColor: c.primary,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _apiKey,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Kunci API Anthropic (x-api-key)',
                    hintText: 'sk-ant-...',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: ClaudeClient.knownModels.contains(_model.text)
                      ? _model.text
                      : ClaudeClient.defaultModel,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    prefixIcon: Icon(Icons.auto_awesome),
                  ),
                  items: <DropdownMenuItem<String>>[
                    for (final String m in ClaudeClient.knownModels)
                      DropdownMenuItem<String>(value: m, child: Text(m)),
                  ],
                  onChanged: (String? v) {
                    if (v != null) {
                      _model.text = v;
                      setState(() {});
                    }
                  },
                ),
                const SizedBox(height: 6),
                Text(
                  'Kunci disimpan di HP ini saja (shared_preferences). '
                  'Permintaan dikirim langsung ke api.anthropic.com.',
                  style: TextStyle(fontSize: 11.5, height: 1.35, color: c.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Edit form
          if (_editing) ...<Widget>[
            AppCard(
              margin: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(
                    'Edit Profil',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: c.textMain,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama Lengkap',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _hp,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Nomor HP',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _boat,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nama Kapal',
                      prefixIcon: Icon(Icons.directions_boat_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _port,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Pelabuhan Asal',
                      prefixIcon: Icon(Icons.anchor),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: TextField(
                          controller: _pk,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Daya Mesin (PK)',
                            prefixIcon: Icon(Icons.settings),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _tank,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Tangki (L)',
                            prefixIcon: Icon(Icons.local_gas_station),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: _engineAge,
                    decoration: const InputDecoration(
                      labelText: 'Kondisi Mesin',
                      prefixIcon: Icon(Icons.build),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (final MapEntry<int, String> e in FuelConfig.conditions.entries)
                        DropdownMenuItem<int>(value: e.key, child: Text(e.value)),
                    ],
                    onChanged: (int? v) {
                      if (v != null) setState(() => _engineAge = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  AppButton(
                    label: 'Simpan Perubahan',
                    icon: Icons.save,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          AppButton(
            label: 'Keluar',
            variant: ButtonVariant.danger,
            icon: Icons.logout,
            onPressed: () async {
              final bool? ok = await showDialog<bool>(
                context: context,
                builder: (BuildContext ctx) => AlertDialog(
                  title: const Text('Keluar?'),
                  content: const Text('Data tetap tersimpan di HP ini.'),
                  actions: <Widget>[
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Keluar'),
                    ),
                  ],
                ),
              );
              if (ok == true) await widget.state.logout();
            },
          ),
          const SizedBox(height: 24),
          NoticeBox(
            text:
                'FishGuard adalah alat bantu keputusan. Untuk keputusan final, '
                'cek BMKG, Basarnas, dan syahbandar setempat.',
            icon: Icons.shield_outlined,
            color: c.textMuted,
          ),
        ],
      ),
    );
  }

  /// PREP-4: the reminder time is user-configurable. The picker is offered in
  /// 30-minute steps because a subuh nudge does not need minute precision, and
  /// a long list is harder to hit on a wet screen.
  Future<void> _pickReminderTime(BuildContext context, AppState s) async {
    final int? picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext ctx) {
        final AppColors c = ctx.colors;
        return SheetFrame(
          title: 'Jam Pengingat',
          subtitle: 'Pilih jam untuk diingatkan sebelum berangkat',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int h in <int>[3, 4, 5, 6])
                for (final int m in <int>[0, 30])
                  ChoiceChip(
                    label: Text(
                      '${h.toString().padLeft(2, '0')}.'
                      '${m.toString().padLeft(2, '0')}',
                    ),
                    selected: s.reminderHour == h && s.reminderMinute == m,
                    selectedColor: c.primary,
                    labelStyle: TextStyle(
                      color: s.reminderHour == h && s.reminderMinute == m
                          ? Colors.white
                          : c.textMain,
                      fontWeight: FontWeight.w700,
                    ),
                    onSelected: (_) => Navigator.pop(ctx, h * 60 + m),
                  ),
            ],
          ),
        );
      },
    );
    if (picked == null || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final bool ok = await s.setReminder(
      enabled: true,
      hour: picked ~/ 60,
      minute: picked % 60,
    );
    if (!context.mounted) return;
    if (ok) return;
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Jam disimpan, tetapi HP menolak menjadwalkan notifikasi.'),
      ),
    );
  }

  /// The queue's own screen (PREP-9). It exists so the sailor can see that a
  /// record made at sea is still held, rather than wondering whether it was
  /// lost.
  void _showOutbox(BuildContext context, AppState s) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final AppColors c = ctx.colors;
        final List<OutboxItem> items = s.outbox.reversed.toList();
        return SheetFrame(
          title: 'Data Menunggu Terkirim',
          subtitle: items.isEmpty
              ? 'Tidak ada data yang menunggu'
              : '${s.pendingOutbox.length} dari ${items.length} belum terkirim',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NoticeBox(
                text: 'FishGuard belum punya server, jadi catatan dari laut '
                    'disimpan di HP ini dan tidak hilang. Begitu server '
                    'tersedia, antrean ini terkirim otomatis.',
                icon: Icons.cloud_off_outlined,
                color: c.textMuted,
              ),
              if (s.outboxLastError != null) ...<Widget>[
                const SizedBox(height: 8),
                Text(
                  s.outboxLastError!,
                  style: TextStyle(fontSize: 11.5, color: c.textMuted),
                ),
              ],
              if (items.isNotEmpty) ...<Widget>[
                const SizedBox(height: 12),
                AppButton(
                  label: s.flushingOutbox ? 'Mencoba…' : 'Coba Kirim Sekarang',
                  icon: Icons.cloud_upload_outlined,
                  dense: true,
                  variant: ButtonVariant.secondary,
                  onPressed: s.flushingOutbox
                      ? null
                      : () async {
                          await s.flushOutbox();
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                s.outboxLastError ??
                                    'Tidak ada yang bisa dikirim sekarang.',
                              ),
                            ),
                          );
                        },
                ),
                const SizedBox(height: 12),
              ],
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    'Semua catatan sudah tercatat di HP.',
                    style: TextStyle(fontSize: 13, color: c.textMuted),
                  ),
                )
              else
                for (final OutboxItem item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      margin: EdgeInsets.zero,
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            item.delivered ? Icons.check_circle : Icons.schedule,
                            size: 18,
                            color: item.delivered ? c.accent : c.warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  item.kind.label,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  '${formatTanggal(item.createdAt)} '
                                  '${formatJam(item.createdAt)}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (item.attempts > 0)
                            Chip2(
                              label: '${item.attempts}× coba',
                              color: c.warning,
                            ),
                        ],
                      ),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  /// FUEL-4: shows what the estimate has learned from real fill-ups and lets
  /// the sailor undo it. A calibration nobody can see or reset is a number
  /// they cannot trust.
  void _showCalibration(BuildContext context, AppState s) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) {
        final AppColors c = ctx.colors;
        final double pct = (s.fuelCalibration - 1) * 100;
        return AlertDialog(
          title: const Text('Kalibrasi Solar'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Estimasi mesin Anda ${pct >= 0 ? 'lebih boros' : 'lebih hemat'} '
                '${pct.abs().toStringAsFixed(0)}% dari rumus standar.',
                style: const TextStyle(fontSize: 14, height: 1.45),
              ),
              const SizedBox(height: 8),
              Text(
                s.calibrationSamples == 0
                    ? 'Belum ada data. Isi "solar terpakai" di ringkasan '
                        'pelayaran setelah mengisi tangki, dan FishGuard '
                        'menyesuaikan diri dengan kapal Anda.'
                    : 'Dihitung dari ${s.calibrationSamples} pelayaran.',
                style: TextStyle(fontSize: 12.5, color: c.textMuted),
              ),
            ],
          ),
          actions: <Widget>[
            if (s.calibrationSamples > 0)
              TextButton(
                onPressed: () async {
                  await s.resetCalibration();
                  if (ctx.mounted) Navigator.pop(ctx);
                },
                child: const Text('Reset'),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
          ],
        );
      },
    );
  }

  void _showHistory(BuildContext context, AppState s) {
    if (s.trips.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada riwayat pelayaran.')),
      );
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (BuildContext ctx) {
        final AppColors c = ctx.colors;
        return SheetFrame(
          title: 'Riwayat Pelayaran',
          subtitle: '${s.trips.length} perjalanan',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // PROF-3: the whole history as shareable text, which is how a
              // fisherman gets it to a cooperative or a buyer's WhatsApp.
              AppButton(
                label: 'Bagikan Riwayat',
                icon: Icons.share_outlined,
                dense: true,
                variant: ButtonVariant.secondary,
                onPressed: () => _shareHistory(context, s),
              ),
              const SizedBox(height: 12),
              for (final Trip t in s.trips)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppCard(
                    margin: EdgeInsets.zero,
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${formatTanggal(t.mulai)} ${formatJam(t.mulai)}',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Durasi ${formatDurasi(t.durasi)}',
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Jarak ${formatJarak(t.jarakKm)}',
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                'Solar ${t.bbmEstimasiL.toStringAsFixed(1)} L',
                                style: TextStyle(fontSize: 12, color: c.textMuted),
                              ),
                            ),
                          ],
                        ),
                        // PROF-2: the recorded track, drawn from the points the
                        // app already stored. Shown only when there is a line
                        // to draw.
                        if (t.track.length > 1) ...<Widget>[
                          const SizedBox(height: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: SizedBox(
                              height: 150,
                              child: ColoredBox(
                                color: c.mapBg,
                                child: SeaMap(
                                  points: const <DpiPoint>[],
                                  userLat: t.track.first[0],
                                  userLon: t.track.first[1],
                                  track: t.track,
                                  interactive: false,
                                ),
                              ),
                            ),
                          ),
                        ],
                        if (t.visited.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                              'Titik dikunjungi: ${t.visited.join(', ')}',
                              style: TextStyle(fontSize: 11.5, color: c.textMuted),
                            ),
                          ),
                        // FUEL-4: what was actually burned, either shown or
                        // asked for once.
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Row(
                            children: <Widget>[
                              Expanded(
                                child: Text(
                                  t.bbmAktualL == null
                                      ? 'Berapa solar terpakai sebenarnya?'
                                      : 'Solar aktual: '
                                          '${t.bbmAktualL!.toStringAsFixed(1)} L',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: c.textMuted,
                                  ),
                                ),
                              ),
                              if (t.bbmAktualL == null)
                                TextButton(
                                  onPressed: () => _askActualFuel(ctx, s, t),
                                  child: const Text('Isi'),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// PROF-3: formats the history as plain text and hands it to the platform
  /// share sheet. No file is written and nothing is uploaded by FishGuard
  /// itself — the sailor chooses where it goes.
  Future<void> _shareHistory(BuildContext context, AppState s) async {
    final StringBuffer b = StringBuffer()
      ..writeln('Riwayat Pelayaran — FishGuard')
      ..writeln(s.profile.namaKapal)
      ..writeln();
    for (final Trip t in s.trips) {
      b
        ..writeln('${formatTanggal(t.mulai)} ${formatJam(t.mulai)}')
        ..writeln('  Durasi : ${formatDurasi(t.durasi)}')
        ..writeln('  Jarak  : ${formatJarak(t.jarakKm)}')
        ..writeln('  Solar  : ${t.bbmEstimasiL.toStringAsFixed(1)} L (estimasi)');
      if (t.bbmAktualL != null) {
        b.writeln('  Aktual : ${t.bbmAktualL!.toStringAsFixed(1)} L');
      }
      if (t.visited.isNotEmpty) {
        b.writeln('  Titik  : ${t.visited.join(', ')}');
      }
      b.writeln();
    }
    b
      ..writeln('Total: ${s.trips.length} pelayaran, '
          '${formatJarak(s.trips.fold<double>(0, (double a, Trip t) => a + t.jarakKm))}')
      ..writeln('Diekspor ${formatTanggal(DateTime.now())} '
          '${formatJam(DateTime.now())}');

    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      await SharePlus.instance.share(
        ShareParams(text: b.toString(), subject: 'Riwayat Pelayaran FishGuard'),
      );
    } on Object catch (e) {
      // No share sheet on this device (or the user closed it early): keep the
      // text where they can still get at it rather than dropping it.
      messenger.showSnackBar(
        SnackBar(content: Text('Tidak bisa membagikan: $e')),
      );
    }
  }

  /// FUEL-4: one number from the sailor, folded into the personal calibration.
  Future<void> _askActualFuel(
    BuildContext sheetCtx,
    AppState s,
    Trip t,
  ) async {
    final TextEditingController ctl = TextEditingController(
      text: t.bbmEstimasiL > 0 ? t.bbmEstimasiL.toStringAsFixed(1) : '',
    );
    final double? value = await showDialog<double>(
      context: sheetCtx,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Solar Terpakai'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Perkiraan FishGuard ${t.bbmEstimasiL.toStringAsFixed(1)} L. '
              'Masukkan angka sebenarnya dari pengisian tangki, supaya '
              'estimasi berikutnya lebih pas.',
              style: TextStyle(
                fontSize: 12.5,
                color: ctx.colors.textMuted,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Solar terpakai (liter)',
                prefixIcon: Icon(Icons.local_gas_station),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () {
              // Indonesian decimal comma is common on phones; accept both.
              final double? v =
                  double.tryParse(ctl.text.trim().replaceAll(',', '.'));
              if (v != null && v > 0) Navigator.pop(ctx, v);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (value == null) return;
    await s.recordActualFuel(t.id, value);
    if (!sheetCtx.mounted) return;
    ScaffoldMessenger.of(sheetCtx).showSnackBar(
      SnackBar(
        content: Text(
          'Tercatat. Kalibrasi sekarang '
          '×${s.fuelCalibration.toStringAsFixed(2)} '
          '(${s.calibrationSamples} pelayaran).',
        ),
      ),
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final Widget row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 20, color: c.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: c.textMain,
                  ),
                ),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: c.textMuted),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
