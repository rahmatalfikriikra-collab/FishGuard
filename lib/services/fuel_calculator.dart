import 'dart:math' as math;

/// Fuel estimate, ported from the prototype formula and extended with the
/// PRD's distance input and 10% reserve.
///
///   konsumsi dasar = PK x durasi (jam) x 0,2 L/(PK.jam)
///   faktor usia   = 1,0 (< 5 th) | 1,2 (5-10 th) | 1,4 (> 10 th)
///   total         = dasar x faktor
///   cadangan      = 10% dari total
///
/// FUEL-3 wants these coefficients server-side so they can be recalibrated
/// without a release; they live here as a single named block so the swap is
/// mechanical once the backend exists.
class FuelEstimate {
  const FuelEstimate({
    required this.powerPk,
    required this.hours,
    required this.distanceKm,
    required this.conditionFactor,
    required this.conditionLabel,
    required this.baseLiters,
    required this.totalLiters,
    required this.reserveLiters,
    required this.source,
  });

  final double powerPk;
  final double hours;
  final double distanceKm;
  final double conditionFactor;
  final String conditionLabel;
  final double baseLiters;
  final double totalLiters;
  final double reserveLiters;

  /// 'waktu' when the duration drove the estimate, 'jarak' for distance.
  final String source;

  double get grandTotal => totalLiters + reserveLiters;

  double get _speedKnots => FuelConfig.speedKnotsFor(powerPk);

  double get rangeKm => totalLiters / _litersPerKm * _speedKnots * 1.852;

  double get hoursOfFuel => totalLiters / _litersPerHour;

  double get _litersPerHour =>
      powerPk * FuelConfig.litersPerPkHour * conditionFactor;

  double get _litersPerKm =>
      _litersPerHour / (_speedKnots * 1.852);
}

class FuelConfig {
  /// Litres per PK per hour, from the prototype's 0,2 coefficient.
  static const double litersPerPkHour = 0.2;

  /// Reserve carried on top of the estimate (PRD FUEL-2).
  static const double reserveFraction = 0.10;

  /// Bounds for the personal calibration (PRD FUEL-4). Outside this range a
  /// reported fill-up is far likelier to be a typo than a real engine.
  static const double minCalibration = 0.6;
  static const double maxCalibration = 1.8;

  /// Headings offered in the form. Free numeric entry is allowed too (FUEL-1).
  static const List<double> powerPresets = <double>[5.5, 15, 25, 40];

  static const Map<int, String> conditions = <int, String>{
    0: 'Mesin Baru (< 5 tahun)',
    1: 'Mesin Sedang (5 - 10 tahun)',
    2: 'Mesin Tua (> 10 tahun)',
  };

  static double factorFor(int condition) => switch (condition) {
        0 => 1.0,
        1 => 1.2,
        _ => 1.4,
      };

  /// Assumed cruising speed, used only to convert a distance into hours.
  static double speedKnotsFor(double powerPk) {
    if (powerPk <= 5.5) return 4.0;
    if (powerPk <= 15) return 6.5;
    if (powerPk <= 25) return 8.0;
    return 9.5;
  }
}

class FuelCalculator {
  /// Exactly one of [hours] / [distanceKm] should be provided.
  ///
  /// [calibration] is the personal multiplier learned from finished trips
  /// (PRD FUEL-4), 1.0 meaning "never calibrated". It is applied to the total
  /// rather than to the coefficient so the breakdown on screen still shows the
  /// published formula, with the sailor's own correction named separately.
  static FuelEstimate estimate({
    required double powerPk,
    required int condition,
    double? hours,
    double? distanceKm,
    double calibration = 1.0,
  }) {
    final double factor = FuelConfig.factorFor(condition);
    final double speed = FuelConfig.speedKnotsFor(powerPk);

    final double effectiveHours;
    final String source;
    final double resolvedDistance;
    if (distanceKm != null && distanceKm > 0) {
      effectiveHours = distanceKm / (speed * 1.852);
      source = 'jarak';
      resolvedDistance = distanceKm;
    } else {
      effectiveHours = math.max(hours ?? 0, 0);
      source = 'waktu';
      resolvedDistance = effectiveHours * speed * 1.852;
    }

    final double base = powerPk * effectiveHours * FuelConfig.litersPerPkHour;
    final double total = base * factor * _safeCalibration(calibration);

    return FuelEstimate(
      powerPk: powerPk,
      hours: effectiveHours,
      distanceKm: resolvedDistance,
      conditionFactor: factor,
      conditionLabel: FuelConfig.conditions[condition] ?? 'Mesin',
      baseLiters: base,
      totalLiters: total,
      reserveLiters: total * FuelConfig.reserveFraction,
      source: source,
    );
  }

  /// PRD NAV-6: warn when the remaining estimated fuel cannot cover the trip
  /// home plus the 10% reserve.
  static bool canReachHome({
    required double remainingLiters,
    required double distanceHomeKm,
    required double powerPk,
    required int condition,
    double calibration = 1.0,
  }) {
    if (remainingLiters <= 0) return false;
    final double factor = FuelConfig.factorFor(condition);
    final double speed = FuelConfig.speedKnotsFor(powerPk);
    final double hoursHome = distanceHomeKm / (speed * 1.852);
    final double needed = powerPk *
        hoursHome *
        FuelConfig.litersPerPkHour *
        factor *
        _safeCalibration(calibration);
    return remainingLiters >= needed * (1 + FuelConfig.reserveFraction);
  }

  /// Guards against a stored value that a bad write or an old build left
  /// outside the sane range: an estimate must never be negative or absurd.
  static double _safeCalibration(double v) {
    if (!v.isFinite || v <= 0) return 1.0;
    return v.clamp(FuelConfig.minCalibration, FuelConfig.maxCalibration);
  }
}
