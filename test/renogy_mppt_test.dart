import 'package:flutter_test/flutter_test.dart';
import 'package:modbus_ble/modbus_ble.dart';
import 'package:renogy_mppt/renogy_mppt.dart';
import 'package:universal_ble/universal_ble.dart';

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
  int minV = 126, // 0x010B x0.1 -> 12.6 V
  int maxV = 142, // 0x010C x0.1 -> 14.2 V
  int dailyGenWh = 1500, // 0x0113 x0.001 -> 1.5 kWh
  int reg32 = 0x0002, // hi byte = load/state bitmap, lo byte = charging-state code
}) {
  final r = List<int>.filled(35, 0);
  r[0] = soc;
  r[1] = battV;
  r[2] = chgA;
  r[3] = tempReg;
  r[7] = solarV;
  r[8] = solarA;
  r[9] = solarW;
  r[11] = minV;
  r[12] = maxV;
  r[19] = dailyGenWh;
  r[32] = reg32;
  return r;
}

void main() {
  test('realtime read frame is FF 03 01 00 00 23 (35 regs @ 0x0100)', () {
    final f = const ModbusRtu(unitId: kUnitId).readHolding(regRealtime, regRealtimeCount);
    expect(_hex(f).startsWith('ff0301000023'), isTrue);
    expect(f.length, 8);
  });

  test('realtime decodes PV/battery/state/today with app scalings', () {
    final rt = ControllerRealtime(_rt());
    expect(rt.socPercent, 100);
    expect(rt.batteryVoltage, closeTo(12.8, 1e-9)); // reg1 x0.1
    expect(rt.chargingCurrent, closeTo(10.5, 1e-9)); // reg2 x0.01
    expect(rt.solarVoltage, closeTo(18.0, 1e-9)); // reg7 x0.1
    expect(rt.solarPower, 270); // reg9 W
    expect(rt.stage, ChargeStage.mppt); // low byte of reg32 = 0x02
    expect(rt.loadOn, isFalse); // high byte of reg32 bit7 clear
    expect(rt.energyTodayKwh, closeTo(1.5, 1e-9)); // reg19 (0x0113) 1500 Wh x0.001
    expect(rt.minBatteryVoltageTodayV, closeTo(12.6, 1e-9)); // reg11 (0x010B) x0.1
    expect(rt.maxBatteryVoltageTodayV, closeTo(14.2, 1e-9)); // reg12 (0x010C) x0.1
  });

  test('temperatures below zero decode as sign-magnitude (app ModBusUtils.G)', () {
    // -20 C controller encodes as 0x94 (0x80|20), -5 C battery as 0x85 (0x80|5)
    final rt = ControllerRealtime(_rt(tempReg: 0x9485));
    expect(rt.controllerTempC, -20);
    expect(rt.batteryTempC, -5);
  });

  test('loadOn reads bit 7 of the high byte of 0x0120', () {
    final rt = ControllerRealtime(_rt(reg32: 0x8002)); // hi bit7 set -> load on; lo 0x02 -> mppt
    expect(rt.loadOn, isTrue);
    expect(rt.stage, ChargeStage.mppt);
  });

  test('fault bits C0..C14 decode in order', () {
    expect(decodeFaults(0), isEmpty);
    expect(decodeFaults(1 << 0), [ControllerFault.chargeMosShort]);
    expect(decodeFaults(1 << 13), [ControllerFault.batteryOverVoltage]);
    expect(decodeFaults((1 << 2) | (1 << 14)),
        [ControllerFault.pvReverse, ControllerFault.batteryOverDischarge]);
  });

  test('SKU decodes ASCII and identifies a controller', () {
    final regs = _skuRegs('RNG-CTRL-RVR40  '); // 16 bytes -> 8 regs
    expect(decodeSku(regs), 'RNG-CTRL-RVR40');
    expect(isControllerSku('RNG-CTRL-RVR40'), isTrue);
    expect(isControllerSku('RCC60REGO-G2'), isTrue);
  });

  test('serial decodes ASCII with trailing padding trimmed', () {
    expect(decodeSerial(_skuRegs('SN12345678        ')), 'SN12345678'); // 18 chars -> 9 regs
  });

  test('a battery SKU is NOT a controller', () {
    expect(isControllerSku('RBT100LFP12S'), isFalse); // shared FFD0, must be rejected
  });

  test('advertisesLikeRenogy matches BT- names and FFD0 service', () {
    final m = RenogyControllerMatcher();
    expect(
        m.advertisesLikeRenogy(
            BleDevice(deviceId: 'a', name: 'BT-TH-66F8EE0D', rssi: -50, services: const [])),
        isTrue);
    expect(
        m.advertisesLikeRenogy(BleDevice(deviceId: 'c', name: 'noname', rssi: -50, services: const [kWriteService])),
        isTrue); // FFD0 advertised
    expect(
        m.advertisesLikeRenogy(BleDevice(deviceId: 'b', name: 'MacBook', rssi: -50, services: const [])),
        isFalse);
  });
}

/// Pack ASCII into big-endian 16-bit registers (2 chars per register).
List<int> _skuRegs(String s) {
  final b = s.codeUnits;
  final regs = <int>[];
  for (var i = 0; i < b.length; i += 2) {
    regs.add((b[i] << 8) | (i + 1 < b.length ? b[i + 1] : 0));
  }
  return regs;
}
