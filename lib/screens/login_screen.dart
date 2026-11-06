import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/common.dart';

/// Login by phone number (PRD AUTH-1/AUTH-2).
///
/// No OTP backend exists, so the phone number is stored locally and the
/// account is marked as a local profile. Labelled honestly: the OTP path is
/// the "butuh internet, lakukan di darat" one.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.state});

  final AppState state;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _phone = TextEditingController();

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  String? _validate(String value) {
    final String digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 'Masukkan nomor HP';
    if (digits.length < 9) return 'Nomor HP terlalu pendek';
    return null;
  }

  Future<void> _login() async {
    final String? err = _validate(_phone.text);
    if (err != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    await widget.state.login(
      UserProfile(
        nama: 'Nelayan',
        hp: _phone.text.trim(),
        isGuest: false,
        kontak: widget.state.profile.kontak,
        dayaMesinPk: widget.state.profile.dayaMesinPk,
        umurMesin: widget.state.profile.umurMesin,
        pelabuhanAsal: widget.state.profile.pelabuhanAsal,
        tankLiters: widget.state.profile.tankLiters,
      ),
    );
  }

  Future<void> _guest() async {
    await widget.state.login(widget.state.profile..isGuest = true);
  }

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Scaffold(
      backgroundColor: c.bgApp,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: 50),
              Center(
                child: Container(
                  width: 92,
                  height: 92,
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.water, size: 46, color: c.primary),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Selamat Datang',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: c.textMain,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Navigasi Aman, Tangkapan Maksimal',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: c.textMuted),
              ),
              const SizedBox(height: 32),
              AppCard(
                padding: const EdgeInsets.all(18),
                margin: EdgeInsets.zero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      autofillHints: const <String>[AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP',
                        hintText: '08xxxxxxxxxx',
                        prefixIcon: Icon(Icons.phone_iphone),
                        helperText: 'Dipakai untuk OTP dan kontak darurat',
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Kirim Kode OTP',
                      icon: Icons.sms_outlined,
                      onPressed: _login,
                    ),
                    const SizedBox(height: 8),
                    // AUTH-1: PRD asks for phone + OTP by SMS/WhatsApp. No OTP
                    // gateway is deployed yet, so the code step is simulated
                    // locally — and this line says so instead of pretending a
                    // message was sent.
                    Text(
                      'Belum ada server OTP. FishGuard memakai nomor ini '
                      'sebagai identitas di HP Anda — tidak ada SMS yang dikirim.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11.5, height: 1.35, color: c.textMuted),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: <Widget>[
                        Expanded(child: Divider(color: c.border)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'atau',
                            style: TextStyle(fontSize: 13, color: c.textMuted),
                          ),
                        ),
                        Expanded(child: Divider(color: c.border)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppButton(
                      label: 'Masuk sebagai Tamu',
                      variant: ButtonVariant.secondary,
                      icon: Icons.person_outline,
                      onPressed: _guest,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              NoticeBox(
                text:
                    'Mode tamu menyimpan semua data di HP ini. Data tetap bisa '
                    'dipakai untuk navigasi, BBM, dan SOS tanpa internet.',
                icon: Icons.cloud_off,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
