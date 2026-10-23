// Renogy MPPT register decode. Registers are big-endian 16-bit words (Modbus).
// Field offsets + scalings recovered from the DC Home controller parser
// (BleCtrlActivity). Register indices below are 0-based from 0x0100.

/// Temperature byte decode as the app does it (ModBusUtils.G): sign-magnitude,
/// bit 7 = sign, bits 0-6 = magnitude. 0x94 -> -20, 0x85 -> -5, 0x80 -> 0.
int _temp(int b) => b < 0x80 ? b : 128 - b;

/// Controller fault/alarm flags, bits C0..C14 of the 32-bit field at 0x0121.
/// Order matches the bit index (C0 = bit 0).
enum ControllerFault {
  chargeMosShort,
  antiReverseMosShort,
  pvReverse,
  pvOverVoltage,
  pvCounterCurrent,
  pvInputOverVoltage,
  pvInputShort,
  pvOverpower,
  ambientTempHigh,
  controllerTempHigh,
  loadOverpower,
  loadShort,
  batteryUnderVoltage,
  batteryOverVoltage,
  batteryOverDischarge,
}

/// Decode the 32-bit fault bitfield into the active faults, in bit order.
List<ControllerFault> decodeFaults(int mask) =>
    [for (var i = 0; i < ControllerFault.values.length; i++) if ((mask >> i) & 1 != 0) ControllerFault.values[i]];

/// Controller charge stage (low byte of register 0x0120).
enum ChargeStage {
  deactivated,
  activated,
  mppt,
  equalizing,
  boost,
  floating,
  currentLimiting;

  static ChargeStage fromCode(int code) =>
      (code >= 0 && code < ChargeStage.values.length) ? ChargeStage.values[code] : ChargeStage.deactivated;
}

/// Main operating data: a read of 35 registers from 0x0100.
class ControllerRealtime {
  final List<int> regs;
  ControllerRealtime(this.regs);

  int _u(int i) => i < regs.length ? regs[i] : 0;

  int get socPercent => _u(0);
  double get batteryVoltage => _u(1) / 10.0; // x0.1 V
  double get chargingCurrent => _u(2) / 100.0; // x0.01 A
  double get controllerTempC => _temp(_u(3) >> 8).toDouble(); // sign-magnitude, high byte
  double get batteryTempC => _temp(_u(3) & 0xFF).toDouble(); // sign-magnitude, low byte
  double get loadVoltage => _u(4) / 10.0;
  double get loadCurrent => _u(5) / 100.0;
  double get loadPower => _u(6).toDouble(); // W
  bool get loadOn => ((_u(32) >> 8) & 0x80) != 0; // bit 7 of the high byte of 0x0120
  double get solarVoltage => _u(7) / 10.0;
  double get solarCurrent => _u(8) / 100.0;
  double get solarPower => _u(9).toDouble(); // W
  double get minBatteryVoltageTodayV => _u(11) / 10.0; // 0x010B, x0.1
  double get maxBatteryVoltageTodayV => _u(12) / 10.0; // 0x010C, x0.1
  double get energyTodayKwh => _u(19) / 1000.0; // 0x0113 daily generation (Wh), x0.001 -> kWh
  ChargeStage get stage => ChargeStage.fromCode(_u(32) & 0xFF); // low byte of 0x0120
  int get faultMask => (_u(33) << 16) | _u(34); // 0x0121/2, 32-bit
  List<ControllerFault> get faults => decodeFaults(faultMask);
}
