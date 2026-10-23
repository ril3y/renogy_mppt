import 'package:flutter_test/flutter_test.dart';
import 'package:modbus_ble/modbus_ble.dart';
import 'package:renogy_mppt/renogy_mppt.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

/// Builds a 35-register realtime block (indices are 0-based from 0x0100).
List<int> _rt({
  int soc = 100,
  int battV = 128,
  int chgA = 1050,
  int tempReg = 0x191E,
  int solarV = 180,
  int solarA = 150,
  int solarW = 270,
  int loadReg32 = 0x0002,
  int genHi = 0,
  int genLo = 1500,
}) {
  final r = List<int>.filled(35, 0);
  r[0] = soc;
  r[1] = battV;
  r[2] = chgA;
  r[3] = tempReg;
  r[7] = solarV;
  r[8] = solarA;
  r[9] = solarW;
  r[28] = genHi;
  r[29] = genLo;
  r[32] = loadReg32;
  return r;
}

void main() {
  test('realtime read frame is FF 03 01 00 00 23 (35 regs @ 0x0100)', () {
    final f = const ModbusRtu(unitId: kUnitId).readHolding(regRealtime, regRealtimeCount);
    expect(_hex(f).startsWith('ff0301000023'), isTrue);
    expect(f.length, 8);
  });

  test('realtime decodes PV/battery/state with artifact scalings', () {
    final rt = ControllerRealtime(_rt());
    expect(rt.socPercent, 100);
    expect(rt.batteryVoltage, closeTo(12.8, 1e-9)); // 128 x0.1
    expect(rt.chargingCurrent, closeTo(10.5, 1e-9)); // 1050 x0.01
    expect(rt.solarVoltage, closeTo(18.0, 1e-9)); // 180 x0.1
    expect(rt.solarPower, 270);
    expect(rt.stage, ChargeStage.mppt); // low byte 0x02
    expect(rt.energyTodayKwh, closeTo(1.5, 1e-9)); // 1500 x0.001
  });

  test('temperatures below zero decode as signed int8', () {
    // reg3 hi=0xEC (-20 C controller), lo=0xFB (-5 C battery)
    final rt = ControllerRealtime(_rt(tempReg: 0xECFB));
    expect(rt.controllerTempC, -20);
    expect(rt.batteryTempC, -5);
  });

  test('32-bit today energy uses big-endian word order', () {
    final rt = ControllerRealtime(_rt(genHi: 1, genLo: 0)); // 0x10000 = 65536 x0.001
    expect(rt.energyTodayKwh, closeTo(65.536, 1e-9));
  });
}
