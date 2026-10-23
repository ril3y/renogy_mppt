import 'package:flutter_test/flutter_test.dart';
import 'package:modbus_ble/modbus_ble.dart';
import 'package:renogy_mppt/renogy_mppt.dart';

String _hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  test('realtime read frame is FF 03 01 00 00 23 (35 regs @ 0x0100)', () {
    final f = const ModbusRtu(unitId: kUnitId).readHolding(regRealtime, regRealtimeCount);
    expect(_hex(f).startsWith('ff0301000023'), isTrue);
    expect(f.length, 8);
  });
}
