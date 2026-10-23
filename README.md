# renogy_mppt

Read-only Dart/Flutter driver for **Renogy MPPT solar charge controllers** over
Bluetooth LE (via a BT-1/BT-2 module). Protocol + data model only — no UI.

- **Transport:** Modbus-RTU over BLE, unit `0xFF`, writes on FFD0/FFD1,
  notifications on FFF0/FFF1 — built on [`modbus_ble`](https://github.com/ril3y/modbus_ble).
- **Reads:** PV (solar) V/A/W, battery SOC/V and charging current, load V/A/W and
  switch state, charge stage (bulk/boost/float/equalize/MPPT/…), controller and
  battery temperatures, today's energy, and controller fault flags.
- **Identity:** model SKU, serial, firmware; distinguishes a controller from a
  Renogy battery (which shares the FFD0 service) by its SKU.
- **Read-only:** no write methods. The controller's load-toggle / settings /
  factory-reset commands are deliberately not implemented.

The register map was recovered by static analysis of the Renogy DC Home app and
verified live against real hardware.

> **Safety:** this library only reads. It never changes controller settings.
