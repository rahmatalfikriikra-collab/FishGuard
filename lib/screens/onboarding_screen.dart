import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// PRD AUTH-3: three onboarding pages — location permission, emergency contact,
/// and the "alat bantu, bukan pengganti info resmi" disclaimer.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.state});

  final AppState state;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _controller = PageController();
  int _page = 0;

  final TextEditingController _contactName = TextEditingController();
  final TextEditingController _contactPhone = TextEditingController();

  bool _locating = false;
  String? _locationMessage;

  @override
  void dispose() {
    _controller.dispose();
    _contactName.dispose();
    _contactPhone.dispose();
    super.dispose();
  }

  Future<void> _requestLocation() async {
    setState(() {
      _locating = true;
      _locationMessage = null;
    });
    try {
      final bool serviceOn = await Geolocator.isLocationServiceEnabled();
      if (!serviceOn) {
        setState(() {
          _locating = false;
          _locationMessage =
              'GPS belum aktif. Nyalakan lokasi, atau lanjut dan pakai pelabuhan asal.';
        });
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() {
          _locating = false;
          _locationMessage =
              'Izin lokasi ditolak. FishGuard tetap bisa dipakai; posisi awal memakai pelabuhan asal.';
        });
        return;
      }
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 20),
        ),
      );
      widget.state.updatePosition(pos.latitude, pos.longitude);
      setState(() {
        _locating = false;
        _locationMessage = 'Posisi terkunci: '
            '${pos.latitude.toStringAsFixed(4)}, ${pos.longitude.toStringAsFixed(4)}';
      });
    } catch (e) {
      setState(() {
        _locating = false;
        _locationMessage = 'GPS tidak tersedia (${e.runtimeType}). '
            'Posisi awal memakai pelabuhan asal.';
      });
    }
  }

  Future<void> _finish() async {
    final String name = _contactName.text.trim();
    final String phone = _contactPhone.text.trim();
    if (phone.isNotEmpty) {
      await widget.state.saveProfile(
        UserProfile(
          nama: widget.state.profile.nama,
          hp: widget.state.profile.hp,
          namaKapal: widget.state.profile.namaKapal,
          dayaMesinPk: widget.state.profile.dayaMesinPk,
          umurMesin: widget.state.profile.umurMesin,
          pelabuhanAsal: widget.state.profile.pelabuhanAsal,
          tankLiters: widget.state.profile.tankLiters,
          isGuest: widget.state.profile.isGuest,
          kontak: <EmergencyContact>[
            EmergencyContact(nama: name.isEmpty ? 'Kontak Darurat' : name, hp: phone),
          ],
        ),
      );
    }
    await widget.state.completeOnboarding();
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Scaffold(
      backgroundColor: c.bgApp,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: <Widget>[
                  Icon(Icons.sailing, color: c.primary, size: 26),
                  const SizedBox(width: 8),
                  Text(
                    'FISHGUARD',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                      letterSpacing: 1,
                      color: c.primary,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _finish,
                    child: Text('Lewati', style: TextStyle(color: c.textMuted)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (int i) => setState(() => _page = i),
                children: <Widget>[
                  _Page(
                    icon: Icons.my_location,
                    title: 'Izin Lokasi',
                    body:
                        'FishGuard memakai GPS untuk menunjukkan posisi kapal, '
                        'jarak ke titik DPI, dan arah pulang. Lokasi Anda hanya '
                        'disimpan di HP ini, kecuali saat Anda mengirim SOS.',
                    child: Column(
                      children: <Widget>[
                        AppButton(
                          label: _locating ? 'Mencari GPS...' : 'Aktifkan Lokasi',
                          icon: Icons.gps_fixed,
                          onPressed: _locating ? null : _requestLocation,
                        ),
                        if (_locationMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: NoticeBox(
                              text: _locationMessage!,
                              icon: Icons.place,
                              color: _locationMessage!.startsWith('Posisi terkunci')
                                  ? c.accent
                                  : c.warning,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _Page(
                    icon: Icons.contact_phone,
                    title: 'Kontak Darurat',
                    body:
                        'Saat Anda menekan SOS, FishGuard mengirim SMS berisi '
                        'koordinat ke kontak ini. SMS tetap jalan tanpa paket data.',
                    child: Column(
                      children: <Widget>[
                        TextField(
                          controller: _contactName,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(
                            labelText: 'Nama kontak (keluarga)',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _contactPhone,
                          keyboardType: TextInputType.phone,
                          decoration: const InputDecoration(
                            labelText: 'Nomor HP kontak',
                            prefixIcon: Icon(Icons.phone_outlined),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Page(
                    icon: Icons.gavel,
                    title: 'Alat Bantu, Bukan Pengganti',
                    body:
                        'FishGuard membantu keputusan Anda, tetapi bukan pengganti '
                        'informasi resmi BMKG, Basarnas, atau syahbandar. Selalu '
                        'cek kondisi nyata di laut dan utamakan keselamatan.',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        NoticeBox(
                          text:
                              'Status LAYAK berasal dari prakiraan, bukan jaminan. '
                              'Cuaca bisa berubah cepat di laut.',
                          icon: Icons.shield_outlined,
                          color: c.warning,
                        ),
                        const SizedBox(height: 10),
                        NoticeBox(
                          text:
                              'SOS mengirim SMS ke kontak Anda dan menampilkan '
                              'nomor Basarnas 115 / darurat 112. FishGuard belum '
                              'terhubung otomatis ke tim SAR.',
                          icon: Icons.sos,
                          color: c.danger,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List<Widget>.generate(3, (int i) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _page == i ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _page == i ? c.primary : c.border,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 18),
                  AppButton(
                    label: _page == 2 ? 'Mulai Pakai FishGuard' : 'Lanjut',
                    icon: _page == 2 ? Icons.check : Icons.arrow_forward,
                    onPressed: () {
                      if (_page == 2) {
                        _finish();
                      } else {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Page extends StatelessWidget {
  const _Page({
    required this.icon,
    required this.title,
    required this.body,
    required this.child,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 8),
          Center(
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: c.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: c.primary),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: c.textMain,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, height: 1.45, color: c.textMuted),
          ),
          const SizedBox(height: 26),
          child,
        ],
      ),
    );
  }
}
