## 0.1.0

* Initial release: Renogy MPPT solar charge-controller driver - read-only
  Modbus-RTU over BLE (unit 0xFF, write FFD0/FFD1, notify FFF0/FFF1), built on
  modbus_ble. Decodes PV/battery/load, charge stage, temperatures, today's
  energy and controller faults; identifies controllers by SKU. Register map
  recovered by static analysis of the Renogy DC Home app.
