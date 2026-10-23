// Renogy MPPT charge-controller BLE + Modbus constants, recovered by static
// analysis of com.renogy.dchome (DC Home v1.10.69). Modbus-RTU over BLE, unit
// 0xFF, split transport: writes to FFD0/FFD1, notifications on FFF0/FFF1 (same
// BT-1/BT-2 module layout as Renogy batteries, different register banks).

const String kNotifyService = '0000fff0-0000-1000-8000-00805f9b34fb';
const String kNotifyUuid = '0000fff1-0000-1000-8000-00805f9b34fb'; // device -> app
const String kWriteService = '0000ffd0-0000-1000-8000-00805f9b34fb';
const String kWriteUuid = '0000ffd1-0000-1000-8000-00805f9b34fb'; // app -> device

/// Modbus slave id. Renogy's documented default/broadcast address.
const int kUnitId = 0xFF;

// Holding-register reads (function 0x03). Addresses from the app-derived map.

/// Main operating data: 35 registers from 0x0100 (frame FF 03 01 00 00 23).
const int regRealtime = 0x0100;
const int regRealtimeCount = 0x23;

/// Product SKU / model: 8 registers (16 ASCII chars) from 0x000C.
const int regSku = 0x000C;
const int regSkuCount = 0x08;

/// Serial number: 9 registers (18 ASCII chars) from 0x001F.
const int regSerial = 0x001F;
const int regSerialCount = 0x09;

/// Firmware version: 2 registers (YYYY/MM/DD encoded) from 0x0014.
const int regFirmware = 0x0014;
const int regFirmwareCount = 0x02;
