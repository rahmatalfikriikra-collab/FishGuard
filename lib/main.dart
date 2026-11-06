import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/login_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/root_shell.dart';
import 'services/app_state.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const FishGuardApp());
}

class FishGuardApp extends StatefulWidget {
  const FishGuardApp({super.key});

  @override
  State<FishGuardApp> createState() => _FishGuardAppState();
}

class _FishGuardAppState extends State<FishGuardApp>
    with WidgetsBindingObserver {
  final AppState _state = AppState();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _boot();
  }

  /// Loads storage first, then brings up the pieces that need the sailor's own
  /// settings: the subuh reminder (PREP-4) and the background DPI sync
  /// (PREP-3). Both are best-effort — a phone that refuses notifications still
  /// gets a working app, and [PrepService] reports which happened.
  Future<void> _boot() async {
    await _state.load();
    if (!mounted) return;
    await _state.prep.init();
    if (!mounted) return;
    if (_state.reminderEnabled) {
      await _state.prep.scheduleSubuhReminder(
        hour: _state.reminderHour,
        minute: _state.reminderMinute,
      );
    }
    if (_state.backgroundSyncEnabled && _state.dpiWpp.isNotEmpty) {
      await _state.prep.registerBackgroundSync();
    }
    // Catch up with whatever KKP and BMKG published since this phone last
    // looked. The background worker is throttled by Android, so this is the
    // reliable path: the app is open, the sailor is about to rely on the data.
    unawaited(_state.autoRefresh());
    _startAutoRefreshTimer();
    // PREP-9: the launch after a trip is the first chance the queue has had
    // to leave the phone. Nothing is delivered yet (no server), but the
    // attempt is recorded so the outbox screen reflects reality.
    if (_state.hasPendingOutbox) await _state.flushOutbox();
  }

  /// Keeps the data current while the app stays open.
  ///
  /// Fifteen minutes is chosen against how the sources actually publish: KKP
  /// posts one table a day, BMKG refreshes its marine forecast a few times a
  /// day, so anything faster would spend radio and battery to learn nothing.
  /// The check is cheap — a small JSON request per source — and does no
  /// download at all when nothing new exists.
  static const Duration _autoRefreshEvery = Duration(minutes: 15);

  void _startAutoRefreshTimer() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = Timer.periodic(_autoRefreshEvery, (_) {
      _state.autoRefresh();
    });
  }

  /// PREP-9: coming back to the foreground is the moment signal is most likely
  /// to have returned, so that is when the queue is offered to the server.
  ///
  /// With no backend the attempt cannot succeed, so it is throttled to once an
  /// hour: a queue that retries on every resume would write to storage and
  /// rewrite the same error for nothing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      // Nothing to keep current while the app is in the background: the timer
      // would only be throttled by the OS, and the WorkManager job covers the
      // case where the phone keeps running without us.
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
      return;
    }
    // Returning to the foreground is when the phone most likely has signal
    // again, and the most likely moment for a table to have been published
    // while the app was away.
    _startAutoRefreshTimer();
    _state.autoRefresh();
    if (!_state.hasPendingOutbox) return;
    final DateTime now = DateTime.now();
    if (_lastFlush != null &&
        now.difference(_lastFlush!) < const Duration(hours: 1)) {
      return;
    }
    _lastFlush = now;
    _state.flushOutbox();
  }

  DateTime? _lastFlush;
  Timer? _autoRefreshTimer;

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _state,
      builder: (BuildContext context, Widget? _) {
        return MaterialApp(
          title: 'FishGuard',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(dark: _state.darkMode),
          themeMode: _state.darkMode ? ThemeMode.dark : ThemeMode.light,
          builder: (BuildContext context, Widget? child) {
            // Keep the layout at phone width on tablets so the prototype's
            // proportions hold, and never let text scaling break the layout.
            final MediaQueryData mq = MediaQuery.of(context);
            return MediaQuery(
              data: mq.copyWith(
                textScaler: mq.textScaler.clamp(
                  minScaleFactor: 1.0,
                  maxScaleFactor: 1.35,
                ),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: child,
                ),
              ),
            );
          },
          home: _state.loading
              ? const _SplashScreen()
              : !_state.onboarded
                  ? OnboardingScreen(state: _state)
                  : !_state.loggedIn
                      ? LoginScreen(state: _state)
                      : RootShell(state: _state),
        );
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final AppColors c = context.colors;
    return Scaffold(
      backgroundColor: c.bgApp,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.sailing, size: 64, color: c.primary),
            const SizedBox(height: 16),
            Text(
              'FISHGUARD',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: c.primary,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.6, color: c.primary),
            ),
          ],
        ),
      ),
    );
  }
}
