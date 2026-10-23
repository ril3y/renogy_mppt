/// Read-only Renogy MPPT solar charge-controller driver: Modbus-RTU over BLE
/// (unit 0xFF, write FFD0/FFD1, notify FFF0/FFF1), built on modbus_ble. Protocol
/// and data model only; no UI, no writes.
library;

export 'src/gatt.dart';
export 'src/model.dart';
export 'src/registers.dart';
