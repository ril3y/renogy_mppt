// Renogy MPPT register decode. Registers are big-endian 16-bit words (Modbus).
// Field offsets + scalings recovered from the DC Home controller parser
// (BleCtrlActivity). Register indices below are 0-based from 0x0100.

int _s8(int b) => b >= 0x80 ? b - 0x100 : b;

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
  double get controllerTempC => _s8(_u(3) >> 8).toDouble(); // signed, high byte
  double get batteryTempC => _s8(_u(3) & 0xFF).toDouble(); // signed, low byte
  double get loadVoltage => _u(4) / 10.0;
  double get loadCurrent => _u(5) / 100.0;
  double get loadPower => _u(6).toDouble(); // W
  bool get loadOn => (_u(10) & 0x01) != 0;
  double get solarVoltage => _u(7) / 10.0;
  double get solarCurrent => _u(8) / 100.0;
  double get solarPower => _u(9).toDouble(); // W
  double get minBatteryVoltageTodayV => _u(19) / 1000.0; // 0x0113, x0.001
  double get maxBatteryVoltageTodayV => _u(20) / 1000.0; // 0x0114, x0.001
  double get energyTodayKwh => ((_u(28) << 16) | _u(29)) / 1000.0; // 0x011C/D, 32-bit x0.001 kWh
  ChargeStage get stage => ChargeStage.fromCode(_u(32) & 0xFF); // low byte of 0x0120
  int get faultMask => (_u(33) << 16) | _u(34); // 0x0121/2, 32-bit
}
