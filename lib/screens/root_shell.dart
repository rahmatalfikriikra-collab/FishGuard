import 'package:flutter/material.dart';

import '../services/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/sos_sheet.dart';
import 'beranda_screen.dart';
import 'fuel_screen.dart';
import 'navigasi_screen.dart';
import 'peta_screen.dart';
import 'profil_screen.dart';

/// Header + bottom navigation + the five main screens, matching the prototype.
class RootShell extends StatefulWidget {
  const RootShell({super.key, required this.state, this.initialIndex = 0});

  final AppState state;
  final int initialIndex;

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;

    final List<Widget> screens = <Widget>[
      BerandaScreen(
        state: widget.state,
        onNavigate: (int i) => setState(() => _index = i),
      ),
      PetaScreen(state: widget.state, onNavigate: (int i) => setState(() => _index = i)),
      NavigasiScreen(state: widget.state),
      FuelScreen(state: widget.state),
      ProfilScreen(state: widget.state),
    ];

    return Scaffold(
      backgroundColor: c.bgApp,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(58),
        child: SafeArea(
          bottom: false,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: c.cardBg,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.sailing, color: c.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  'FISHGUARD',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                    letterSpacing: 1,
                    color: c.primary,
                  ),
                ),
                const Spacer(),
                _GpsBadge(state: widget.state),
              ],
            ),
          ),
        ),
      ),
      body: IndexedStack(index: _index, children: screens),
      floatingActionButton: _index == 0
          ? null
          : null,
      bottomNavigationBar: _BottomNav(
        index: _index,
        onChanged: (int i) => setState(() => _index = i),
        onSos: () => showSosSheet(context, widget.state),
      ),
    );
  }
}

class _GpsBadge extends StatelessWidget {
  const _GpsBadge({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    final bool locked = state.gpsLocked;
    final Color tint = locked ? c.accent : c.warning;
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              locked
                  ? 'GPS terkunci di ${state.lat.toStringAsFixed(4)}, ${state.lon.toStringAsFixed(4)}'
                  : 'GPS belum terkunci. Posisi memakai ${state.profile.pelabuhanAsal}.',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: tint.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              locked ? Icons.satellite_alt : Icons.satellite_alt_outlined,
              size: 13,
              color: tint,
            ),
            const SizedBox(width: 5),
            Text(
              locked ? 'GPS Aktif' : 'GPS Mati',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tint,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.onChanged,
    required this.onSos,
  });

  final int index;
  final ValueChanged<int> onChanged;
  final VoidCallback onSos;

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    const List<(IconData, IconData, String)> items = <(IconData, IconData, String)>[
      (Icons.home_outlined, Icons.home, 'Beranda'),
      (Icons.map_outlined, Icons.map, 'Peta'),
      (Icons.explore_outlined, Icons.explore, 'Navigasi'),
      (Icons.local_gas_station_outlined, Icons.local_gas_station, 'BBM'),
      (Icons.person_outline, Icons.person, 'Profil'),
    ];

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: c.navBg,
          border: Border(top: BorderSide(color: c.border)),
        ),
        child: SizedBox(
          height: 62,
          child: Row(
            children: <Widget>[
              for (int i = 0; i < items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onChanged(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          index == i ? items[i].$2 : items[i].$1,
                          size: 22,
                          color: index == i ? c.primary : c.textMuted,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          items[i].$3,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight:
                                index == i ? FontWeight.w700 : FontWeight.w500,
                            color: index == i ? c.primary : c.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // SOS stays reachable from every screen (PRD HOME-5).
              Expanded(
                child: InkWell(
                  onTap: onSos,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: c.danger,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.sos, size: 18, color: Colors.white),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'SOS',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: c.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
