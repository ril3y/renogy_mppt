// RenogyController: read-only BLE orchestration for a Renogy MPPT charge
// controller. Modbus-RTU over BLE (unit 0xFF), split write/notify services,
// one exchange at a time. No write methods — this driver never changes settings.

import 'dart:async';
import 'dart:typed_data';

import 'package:modbus_ble/modbus_ble.dart';
import 'package:universal_ble/universal_ble.dart';

import 'gatt.dart';
import 'identity.dart';
import 'model.dart';
import 'registers.dart';

/// Recognise a Renogy charge controller among nearby BLE devices.
class RenogyControllerMatcher {
  /// Cheap advertisement test: a `BT-…` module name, or the FFD0 service.
  /// (FFD0 is shared with Renogy batteries, so this only screens candidates;
  /// [looksLikeController] confirms by reading the SKU.)
  bool advertisesLikeRenogy(BleDevice device) {
    final name = device.name ?? '';
    if (RegExp(r'^BT-', caseSensitive: false).hasMatch(name)) return true;
    final ffd0 = normalizeUuid(kWriteService);
    return device.services.map(normalizeUuid).contains(ffd0);
  }

  /// Connect briefly and confirm the SKU names a charge controller (not a
  /// battery or other Renogy device). Always disconnects.
  Future<bool> looksLikeController(BleDevice device) async {
    final c = RenogyController(device);
    try {
      await c.connect();
      final sku = decodeSku(await c.readRegisters(regSku, regSkuCount));
      return isControllerSku(sku);
    } catch (_) {
      return false;
    } finally {
      await c.disconnect().catchError((_) {});
    }
  }
}

/// A connected Renogy MPPT charge controller. Read-only live monitoring.
class RenogyController {
  final BleDevice device;

  final BleLink _link;
  final ModbusRtu _rtu = const ModbusRtu(unitId: kUnitId);
  final ModbusAssembler _asm = ModbusAssembler(unitId: kUnitId);
  final _replies = StreamController<ModbusReply>.broadcast();
  final _snapshots = StreamController<ChargeControllerSnapshot>.broadcast();
  StreamSubscription<Uint8List>? _rx;
  Timer? _poll;

  RenogyController(this.device)
      : _link = BleLink(device,
            service: kNotifyService,
            notify: kNotifyUuid,
            writeService: kWriteService,
            write: kWriteUuid,
            writeWithResponse: false);

  String get id => 'renogy-mppt-${device.deviceId}';
  String get displayName => device.name?.isNotEmpty == true ? device.name! : 'Renogy MPPT controller';

  Stream<ChargeControllerSnapshot> get snapshots => _snapshots.stream;
  Stream<bool> get connection => _link.connection;

  Future<void> connect() async {
    _rx = _link.incoming.listen((chunk) => _asm.add(chunk).forEach(_replies.add));
    await _link.connect();
  }

  Future<ModbusReply> _exchange(Uint8List frame, int function,
          {Duration timeout = const Duration(seconds: 3)}) =>
      _link.exclusive(() async {
        final reply = _replies.stream
            .firstWhere((r) => r.function == function || r.function == (function | 0x80))
            .timeout(timeout);
        await _link.write(frame);
        final r = await reply;
        if (r.isException) {
          throw StateError('Controller refused request: Modbus exception ${r.exceptionCode}');
        }
        return r;
      });

  Future<List<int>> readRegisters(int address, int count) async =>
      (await _exchange(_rtu.readHolding(address, count), fnReadHolding)).registers;

  /// Poll the realtime block once a second and emit snapshots.
  void startLive() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final rt = ControllerRealtime(await readRegisters(regRealtime, regRealtimeCount));
        _snapshots.add(ChargeControllerSnapshot.fromRealtime(rt));
      } catch (_) {
        // Retried on the next tick.
      }
    });
  }

  void stopLive() => _poll?.cancel();

  Future<ControllerIdentity> identify() async {
    final sku = decodeSku(await readRegisters(regSku, regSkuCount));
    String? serial;
    try {
      serial = decodeSerial(await readRegisters(regSerial, regSerialCount));
    } catch (_) {
      serial = null;
    }
    return ControllerIdentity(sku: sku, serial: serial);
  }

  Future<void> disconnect() async {
    stopLive();
    await _rx?.cancel();
    await _link.disconnect();
  }
}
