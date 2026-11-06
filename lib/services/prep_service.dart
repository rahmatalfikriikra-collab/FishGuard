import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:workmanager/workmanager.dart';

import 'background_sync.dart';

/// The land-side duties that must happen without the app being open, plus the
/// subuh reminder (PRD PREP-3 / PREP-4 / PROF-3).
///
/// Everything here is best-effort on purpose: a phone that refuses
/// notifications, or an Android build that throttles background work, must
/// never stop the sailor using the app. Every call swallows its own failure
/// and returns a plain bool so the caller can say what actually happened
/// instead of pretending.
class PrepService {
  PrepService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// WorkManager bookkeeping. The unique name keeps the periodic job singular,
  /// so re-registering on each launch does not stack copies.
  static const String syncTaskName = 'fishguard.dpiSync';
  static const String periodicUniqueName = 'fishguard.dpiSync.periodic';

  /// Default reminder time (PRD PREP-4).
  static const int defaultReminderHour = 4;
  static const int defaultReminderMinute = 30;

  static const int _subuhNotificationId = 430;

  static const AndroidNotificationDetails _androidDetails =
      AndroidNotificationDetails(
    'fishguard_prep',
    'Persiapan Melaut',
    channelDescription:
        'Pengingat subuh dan hasil sinkron data di latar belakang',
    importance: Importance.high,
    priority: Priority.high,
  );

  static const NotificationDetails _details =
      NotificationDetails(android: _androidDetails);

  bool _notificationsReady = false;
  bool _workmanagerReady = false;

  /// Wiring that must happen before any other call. Safe to call twice.
  Future<void> init() async {
    await _initNotifications();
    await _initWorkmanager();
  }

  Future<void> _initNotifications() async {
    if (_notificationsReady) return;
    try {
      tzdata.initializeTimeZones();
      // The app is built for one audience: WITA is the PRD's reference clock
      // and every shipped string prints WITA (`formatJam`), so the scheduler
      // has to agree with what the sailor reads on screen.
      tz.setLocalLocation(tz.getLocation('Asia/Makassar'));

      const AndroidInitializationSettings android =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      await _plugin.initialize(
        settings: const InitializationSettings(android: android),
      );
      _notificationsReady = true;
    } on Object catch (e) {
      debugPrint('PrepService: notifikasi tidak siap ($e)');
    }
  }

  Future<void> _initWorkmanager() async {
    if (_workmanagerReady) return;
    try {
      await Workmanager().initialize(callbackDispatcher);
      _workmanagerReady = true;
    } on Object catch (e) {
      debugPrint('PrepService: WorkManager tidak siap ($e)');
    }
  }

  /// Asks for the Android 13+ notification permission. Returns true when the
  /// app may post notifications. A denial is a normal answer, not an error.
  Future<bool> requestPermission() async {
    await _initNotifications();
    if (!_notificationsReady) return false;
    try {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android == null) return true;
      return await android.requestNotificationsPermission() ?? false;
    } on Object catch (e) {
      debugPrint('PrepService: izin notifikasi gagal ($e)');
      return false;
    }
  }

  /// Schedules the daily subuh reminder at [hour]:[minute] WITA.
  ///
  /// PREP-4 wants the time user-configurable with 04.30 as the default.
  /// Returns false when notifications are unavailable, so the caller can say
  /// so instead of showing a reminder that will never fire.
  Future<bool> scheduleSubuhReminder({
    required int hour,
    required int minute,
    bool enabled = true,
  }) async {
    await _initNotifications();
    if (!_notificationsReady) return false;
    try {
      await _plugin.cancel(id: _subuhNotificationId);
      if (!enabled) return true;

      await _plugin.zonedSchedule(
        id: _subuhNotificationId,
        title: 'Sinkronkan sebelum berangkat',
        body: 'Ambil titik DPI hari ini dan prakiraan cuaca selagi masih ada '
            'sinyal. Di laut tidak ada internet.',
        scheduledDate: _nextInstanceOf(hour, minute),
        notificationDetails: _details,
        // Inexact so the phone may batch it with other alarms and save
        // battery; a few minutes either way is fine for a 04.30 reminder and
        // exact alarms need a permission users rightly dislike granting.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      return true;
    } on Object catch (e) {
      debugPrint('PrepService: gagal menjadwalkan pengingat subuh ($e)');
      return false;
    }
  }

  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime next =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }
    return next;
  }

  /// Tells the sailor the background sync brought new data home. Silent when
  /// notifications are unavailable — the data is on disk either way.
  Future<bool> notifyDataReady(int pointCount) async {
    await _initNotifications();
    if (!_notificationsReady) return false;
    try {
      await _plugin.show(
        id: _subuhNotificationId + 1,
        title: 'Data DPI hari ini sudah masuk',
        body: '$pointCount titik siap dipakai tanpa sinyal. Buka FishGuard '
            'untuk melihat peta.',
        notificationDetails: _details,
      );
      return true;
    } on Object catch (e) {
      debugPrint('PrepService: gagal menampilkan notifikasi ($e)');
      return false;
    }
  }

  /// Registers the background DPI sync (PREP-3).
  ///
  /// The PRD wants it to start once today's table is published, i.e. shortly
  /// after the KKP portal updates rather than at a fixed morning hour. Android
  /// only guarantees a 15-minute minimum period, so the job runs every six
  /// hours and [backgroundSync] does the "is there anything new?" check: it
  /// stops after one cheap request when the stored table is already the newest
  /// one. That keeps a full download + OCR pass off the radio and the battery
  /// on the six of seven runs where nothing changed.
  Future<bool> registerBackgroundSync() async {
    await _initWorkmanager();
    if (!_workmanagerReady) return false;
    try {
      await Workmanager().registerPeriodicTask(
        periodicUniqueName,
        syncTaskName,
        frequency: const Duration(hours: 6),
        initialDelay: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
        backoffPolicy: BackoffPolicy.linear,
        backoffPolicyDelay: const Duration(minutes: 30),
      );
      return true;
    } on Object catch (e) {
      debugPrint('PrepService: gagal mendaftarkan sinkron latar belakang ($e)');
      return false;
    }
  }

  /// Cancels the background job when the sailor turns it off.
  Future<void> cancelBackgroundSync() async {
    try {
      await Workmanager().cancelByUniqueName(periodicUniqueName);
    } on Object catch (_) {
      // Nothing to do: the job is gone either way.
    }
  }
}

/// Top-level entry point WorkManager needs — it must stay top-level and
/// `vm:entry-point` so release-mode tree shaking keeps it.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    // The background isolate has its own engine: bindings first, then the
    // plugin registrant, or `SharedPreferences` and any platform channel
    // throws before the work starts.
    WidgetsFlutterBinding.ensureInitialized();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? zoneCode = prefs.getString(kBgZoneKey);
      if (zoneCode == null || zoneCode.isEmpty) return true; // Not set up yet.

      final BgSyncOutcome outcome = await backgroundSync();
      if (outcome.changed) {
        await PrepService().notifyDataReady(outcome.points);
      }
      return true;
    } on Object catch (e) {
      debugPrint('FishGuard background sync gagal: $e');
      // Returning false lets WorkManager retry with the backoff policy.
      return false;
    }
  });
}
