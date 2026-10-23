// Brand-neutral data model for a Renogy MPPT charge controller. Immutable value
// types a UI can render directly.

import 'registers.dart';

/// One read of a charge controller's live state.
class ChargeControllerSnapshot {
  final DateTime time;

  // Battery
  final int socPercent;
  final double batteryVoltage;
  final double chargingCurrent;

  // Solar (PV) input
  final double solarVoltage;
  final double solarCurrent;
  final double solarPower;

  // Load output
  final double loadVoltage;
  final double loadCurrent;
  final double loadPower;
  final bool loadOn;

  // Temperatures
  final double controllerTempC;
  final double batteryTempC;

  // Today
  final double minBatteryVoltageTodayV;
  final double maxBatteryVoltageTodayV;
  final double energyTodayKwh;

  final ChargeStage stage;
  final int faultMask;

  const ChargeControllerSnapshot({
    required this.time,
    required this.socPercent,
    required this.batteryVoltage,
    required this.chargingCurrent,
    required this.solarVoltage,
    required this.solarCurrent,
    required this.solarPower,
    required this.loadVoltage,
    required this.loadCurrent,
    required this.loadPower,
    required this.loadOn,
    required this.controllerTempC,
    required this.batteryTempC,
    required this.minBatteryVoltageTodayV,
    required this.maxBatteryVoltageTodayV,
    required this.energyTodayKwh,
    required this.stage,
    required this.faultMask,
  });

  /// Build a snapshot from a decoded realtime block.
  factory ChargeControllerSnapshot.fromRealtime(ControllerRealtime rt, {DateTime? time}) =>
      ChargeControllerSnapshot(
        time: time ?? DateTime.now(),
        socPercent: rt.socPercent,
        batteryVoltage: rt.batteryVoltage,
        chargingCurrent: rt.chargingCurrent,
        solarVoltage: rt.solarVoltage,
        solarCurrent: rt.solarCurrent,
        solarPower: rt.solarPower,
        loadVoltage: rt.loadVoltage,
        loadCurrent: rt.loadCurrent,
        loadPower: rt.loadPower,
        loadOn: rt.loadOn,
        controllerTempC: rt.controllerTempC,
        batteryTempC: rt.batteryTempC,
        minBatteryVoltageTodayV: rt.minBatteryVoltageTodayV,
        maxBatteryVoltageTodayV: rt.maxBatteryVoltageTodayV,
        energyTodayKwh: rt.energyTodayKwh,
        stage: rt.stage,
        faultMask: rt.faultMask,
      );
}
