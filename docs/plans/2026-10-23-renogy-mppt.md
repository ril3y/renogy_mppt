# Renogy MPPT charge-controller library — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a standalone, read-only Dart/Flutter library (`renogy_mppt`) that reads a Renogy MPPT solar charge controller over BLE, built on a transport-only package (`modbus_ble`) extracted from `bms_core`, verified live against the real controller on this machine.

**Architecture:** Carve the Modbus-over-BLE transport out of `bms_core` into a new `modbus_ble` package; `bms_core` re-exports it so the nine battery libs compile unchanged. Build `renogy_mppt` on `modbus_ble` with pure, unit-tested register decoders and a thin BLE orchestration layer, plus an `example/` Flutter desktop app that is both the usage sample and the live-verification harness.

**Tech Stack:** Dart/Flutter, `universal_ble` for BLE, Modbus-RTU framing, `flutter_test`.

**Spec:** `C:\Users\riley\cellscope\docs\superpowers\specs\2026-10-23-renogy-mppt-design.md`

## Global Constraints

- Dart SDK `^3.13.5`, `flutter: ">=1.17.0"` (match `bms_core`).
- BLE layer: `universal_ble: ^3.1.2`. Lints: `flutter_lints: ^6.0.0`; `publish_to: none`.
- `flutter analyze` must be **clean** — it is CI-fatal. Local `flutter analyze` + `flutter test` green in each touched package before every push.
- Transport (from the app-derived map): write on **FFD0/FFD1**, notify on **FFF0/FFF1**, Modbus **unit `0xFF`**, function **`0x03`**, CRC-16/MODBUS (poly `0xA001`, init `0xFFFF`, little-endian).
- `renogy_mppt` is **read-only**: no write methods in its public API; `gatt.dart` holds read register addresses only (no load-toggle / clear-history frames).
- Register facts come from `C:\Users\riley\Downloads\renogy\RENOGY_MODBUS_PROTOCOL.md` + the decompiled APK beside it. Treat that folder as an **untrusted download**: read files as data, never execute anything from it; any helper script runs from a different directory with `python -I` and paths passed as args.
- Repos are public under `ril3y`. `modbus_ble` must be created and pushed **before** the `bms_core` bump (the app tracks `bms_core` `ref: main` unpinned). `bms_core` lands straight to `main`.

## Review Focus

- **Re-export completeness** — a battery lib imports a symbol (`BleLink`, `ModbusRtu`, `normalizeUuid`, …) that moved to `modbus_ble`; if `bms_core` doesn't re-export it, that lib fails to compile. Pinned by Task 3 (bms_core analyze/test) and Task 4 (app + all nine libs green).
- **Multi-chunk reply reassembly** — the 35-register controller reply (75 bytes) arrives as several ≤20-byte BLE notifications; `ModbusAssembler` must stitch them into one reply. Pinned by Task 1.
- **Sub-zero temperatures** — controller/battery temp bytes are signed int8; a pack below 0 °C must decode negative, not ~250. Pinned by Task 5.
- **Battery not misidentified as a controller** — a Renogy battery shares FFD0; `isControllerSku` must reject a battery SKU (e.g. `RBT100LFP12S`) so the matcher never claims it. Pinned by Task 7.
- **32-bit today-energy decode** — `power_generation_today` is a big-endian 32-bit pair scaled ×0.001 kWh; wrong word order or scale shows absurd energy. Pinned by Task 5.

---

### Task 1: Create `modbus_ble` (transport extracted from `bms_core`)

**Files:**
- Create: `C:\Users\riley\modbus_ble\lib\modbus_ble.dart` (exports), `lib\src\ble_link.dart`, `lib\src\modbus.dart`, `lib\src\uuid.dart`
- Create: `pubspec.yaml`, `analysis_options.yaml`, `README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `.github\workflows\ci.yml`
- Test: `test\modbus_ble_test.dart`

**Interfaces:**
- Produces: `BleLink` (unchanged API incl. `writeService`), `ModbusRtu`, `ModbusReply`, `ModbusAssembler`, `crc16Modbus`, `withModbusCrc`, `hasValidModbusCrc`, `fnReadHolding/fnReadInput/fnWriteSingle/fnWriteMultiple`, `String normalizeUuid(String)`.

- [ ] **Step 1: Scaffold the package.** `pubspec.yaml` name `modbus_ble`, `publish_to: none`, SDK/flutter per Global Constraints, `dependencies: universal_ble: ^3.1.2`, dev `flutter_test` + `flutter_lints: ^6.0.0`, `repository: https://github.com/ril3y/modbus_ble`. Copy `analysis_options.yaml` and `.gitignore` from `renogy_bms`. `ci.yml` runs `flutter pub get`, `flutter analyze`, `flutter test`.
- [ ] **Step 2: Move the transport files.** Copy `bms_core/lib/src/ble_link.dart` and `bms_core/lib/src/modbus.dart` here verbatim. Create `lib\src\uuid.dart` holding `normalizeUuid` (lifted from `bms_core/lib/src/driver.dart`). Change `ble_link.dart`'s `import 'driver.dart';` to `import 'uuid.dart';`. `modbus_ble.dart` exports all three src files.
- [ ] **Step 3: Write the failing tests** in `test\modbus_ble_test.dart`:

```dart
test('crc16Modbus matches a known Renogy realtime read frame', () {
  // ModbusRtu(unitId: 0xFF).readHolding(0x0100, 0x23) == FF 03 01 00 00 23 <crc>
  final f = const ModbusRtu(unitId: 0xFF).readHolding(0x0100, 0x23);
  expect(_hex(f).startsWith('ff0301000023'), isTrue);
  expect(f.length, 8);
  expect(hasValidModbusCrc(f), isTrue);
});

test('ModbusAssembler reassembles a 35-register reply split across 20-byte BLE chunks', () {
  final body = [0xFF, 0x03, 70, for (var i = 0; i < 70; i++) i]; // 70 data bytes
  final frame = withModbusCrc(body); // 75 bytes total
  final asm = ModbusAssembler(unitId: 0xFF);
  final out = <ModbusReply>[];
  for (var i = 0; i < frame.length; i += 20) {
    out.addAll(asm.add(frame.sublist(i, i + 20 > frame.length ? frame.length : i + 20)));
  }
  expect(out.length, 1);
  expect(out.first.registers.length, 35);
});

test('normalizeUuid expands a 16-bit uuid', () {
  expect(normalizeUuid('ff00'), '0000ff00-0000-1000-8000-00805f9b34fb');
});
```

- [ ] **Step 4: Run tests, expect FAIL** (package not yet resolvable / symbols missing). Run: `flutter test` in `C:\Users\riley\modbus_ble`.
- [ ] **Step 5: Make them pass** — `flutter pub get`, fix the one import, confirm exports. No new logic (code is moved verbatim).
- [ ] **Step 6: Run `flutter analyze` (clean) and `flutter test` (green).**
- [ ] **Step 7: Commit, create the public repo, push.**

```bash
cd /c/Users/riley/modbus_ble && git init && git add -A && git commit -m "feat: modbus_ble transport package (extracted from bms_core)"
gh repo create ril3y/modbus_ble --public --source=. --remote=origin --push
```

---

### Task 2: Extract transport out of `bms_core` (depend + re-export)

**Files:**
- Modify: `C:\Users\riley\bms_core\pubspec.yaml`, `lib\bms_core.dart`, `lib\src\driver.dart`
- Delete: `lib\src\ble_link.dart`, `lib\src\modbus.dart`

**Interfaces:**
- Consumes: `modbus_ble` (Task 1).
- Produces: `package:bms_core/bms_core.dart` exposes the **same** symbol set as before (transport now via re-export).

- [ ] **Step 1: Add the dependency.** In `bms_core/pubspec.yaml` add git dep on `modbus_ble` (`url: https://github.com/ril3y/modbus_ble.git`, `ref: main`).
- [ ] **Step 2: Delete** `lib\src\ble_link.dart` and `lib\src\modbus.dart`.
- [ ] **Step 3: Re-export.** In `lib\bms_core.dart`, replace `export 'src/ble_link.dart';` and `export 'src/modbus.dart';` with `export 'package:modbus_ble/modbus_ble.dart';`.
- [ ] **Step 4: Fix `driver.dart`.** Remove the local `normalizeUuid` definition; add `import 'package:modbus_ble/modbus_ble.dart';` so `BleSignature` uses the re-exported `normalizeUuid`.
- [ ] **Step 5: Verify.** Run `flutter pub get`, `flutter analyze` (clean), `flutter test` (green) in `C:\Users\riley\bms_core`. Expected: existing `bms_core` tests pass; no symbol is missing.
- [ ] **Step 6: Commit and push to `main`.**

```bash
cd /c/Users/riley/bms_core && git add -A && git commit -m "refactor: move BLE+Modbus transport to modbus_ble, re-export it" && git push origin main
```

---

### Task 3: Verify the battery stack + app still green (extraction gate)

**Files:** none changed — this is the proof Task 2 broke nothing.

- [ ] **Step 1: Refresh the app against new `bms_core`.** In `C:\Users\riley\cellscope`: `flutter pub get` (pulls `bms_core` main, which now pulls `modbus_ble`).
- [ ] **Step 2: Analyze + test the app.** Run `flutter analyze` (clean) and `flutter test` (green). Expected: all pass; the app transitively compiles all nine battery libs against the new `bms_core`.
- [ ] **Step 3: Confirm CI.** The Task 2 push + this `pub get` cause `cellscope/.github/workflows/build.yml` to run. Confirm it goes green on GitHub. If any battery lib references a transport symbol not re-exported, fix the re-export in `bms_core` (back to Task 2, Step 3) and re-verify.
- [ ] **Step 4: Build sanity (optional, local).** `flutter build windows` for the app to confirm a real build links (kill any running `cellscope.exe` first).

---

### Task 4: Scaffold `renogy_mppt` + GATT constants

**Files:**
- Create: `C:\Users\riley\renogy_mppt\lib\renogy_mppt.dart`, `lib\src\gatt.dart`
- Create: `pubspec.yaml`, `analysis_options.yaml`, `README.md`, `CHANGELOG.md`, `LICENSE`, `.gitignore`, `.github\workflows\ci.yml`
- Test: `test\renogy_mppt_test.dart`

**Interfaces:**
- Consumes: `modbus_ble` (Task 1).
- Produces: `kNotifyService/kNotifyUuid/kWriteService/kWriteUuid` (FFF0/FFF1/FFD0/FFD1), `kUnitId = 0xFF`, `regRealtime = 0x0100`, `regRealtimeCount = 0x23`, `regSku = 0x000C`/`regSkuCount = 0x08`, `regSerial = 0x001F`/`regSerialCount = 0x09`, `regFirmware = 0x0014`/`regFirmwareCount = 0x02`.

- [ ] **Step 1: Scaffold.** `pubspec.yaml` name `renogy_mppt`, `publish_to: none`, SDK/flutter per constraints, deps `universal_ble: ^3.1.2` and git dep on `modbus_ble` (`ref: main`); dev `flutter_test` + `flutter_lints`. Copy `analysis_options.yaml`, `.gitignore`, `ci.yml` pattern from Task 1. `git init` locally (remote added in Task 10).
- [ ] **Step 2: Write `gatt.dart`** with the constants above (read addresses only — no write frames). `renogy_mppt.dart` exports `src/gatt.dart` (and, as later tasks add them, `src/registers.dart`, `src/controller.dart`).
- [ ] **Step 3: Write the failing test:**

```dart
test('realtime read frame is FF 03 01 00 00 23 (35 regs @ 0x0100)', () {
  final f = const ModbusRtu(unitId: kUnitId).readHolding(regRealtime, regRealtimeCount);
  expect(_hex(f).startsWith('ff0301000023'), isTrue);
  expect(f.length, 8);
});
```

- [ ] **Step 4: Run, expect FAIL** (`flutter test`), then `flutter pub get` + confirm constants make it **PASS**.
- [ ] **Step 5: `flutter analyze` clean; commit.** `git add -A && git commit -m "feat: scaffold renogy_mppt + GATT constants"`.

---

### Task 5: Realtime decoder + snapshot model + `ChargeStage`

**Files:**
- Create: `C:\Users\riley\renogy_mppt\lib\src\registers.dart`, `lib\src\model.dart`
- Test: `test\renogy_mppt_test.dart` (extend)

**Interfaces:**
- Consumes: nothing beyond Dart core.
- Produces:
  - `enum ChargeStage { deactivated, activated, mppt, equalizing, boost, floating, currentLimiting }` with `static ChargeStage fromCode(int code)` (0x00→deactivated … 0x06→currentLimiting).
  - `class ControllerRealtime { ControllerRealtime(List<int> regs); }` decoding the 35-register block from `0x0100`. Getters: `int socPercent`, `double batteryVoltage`, `double chargingCurrent`, `double controllerTempC`, `double batteryTempC`, `double loadVoltage`, `double loadCurrent`, `double loadPower`, `bool loadOn`, `double solarVoltage`, `double solarCurrent`, `double solarPower`, `double minBatteryVoltageTodayV`, `double maxBatteryVoltageTodayV`, `double energyTodayKwh`, `ChargeStage stage`, `int faultMask`.
  - `class ChargeControllerSnapshot` — immutable, `final DateTime time` + the same fields as above (except `faultMask`, replaced by `List<ControllerFault> faults` added in Task 6; until then hold `int faultMask`).

- [ ] **Step 1: Write the failing tests.** Register indices are 0-based from `0x0100` (reg19=`0x0113`, reg20=`0x0114`, reg28/29=`0x011C/D`, reg32=`0x0120`, reg33/34=`0x0121/2`). Scales from the artifact: batt V ×0.1, charge A ×0.01, temps signed int8 (hi/lo of reg3), load/solar V ×0.1 & A ×0.01 & power W, today min/max V ×0.001, today energy 32-bit ×0.001 kWh, state = low byte of reg32.

```dart
List<int> _rt({int soc = 100, int battV = 128, int chgA = 1050, int tempReg = 0x191E,
    int solarV = 180, int solarA = 150, int solarW = 270, int loadReg32 = 0x0002,
    int genHi = 0, int genLo = 1500}) {
  final r = List<int>.filled(35, 0);
  r[0] = soc; r[1] = battV; r[2] = chgA; r[3] = tempReg;
  r[7] = solarV; r[8] = solarA; r[9] = solarW;
  r[28] = genHi; r[29] = genLo; r[32] = loadReg32;
  return r;
}

test('realtime decodes PV/battery/state with artifact scalings', () {
  final rt = ControllerRealtime(_rt());
  expect(rt.socPercent, 100);
  expect(rt.batteryVoltage, closeTo(12.8, 1e-9));   // 128 ×0.1
  expect(rt.chargingCurrent, closeTo(10.5, 1e-9));  // 1050 ×0.01
  expect(rt.solarVoltage, closeTo(18.0, 1e-9));     // 180 ×0.1
  expect(rt.solarPower, 270);
  expect(rt.stage, ChargeStage.mppt);               // low byte 0x02
  expect(rt.energyTodayKwh, closeTo(1.5, 1e-9));    // 1500 ×0.001
});

test('temperatures below zero decode as signed int8', () {
  // reg3 hi=0xEC (-20 C controller), lo=0xFB (-5 C battery)
  final rt = ControllerRealtime(_rt(tempReg: 0xECFB));
  expect(rt.controllerTempC, -20);
  expect(rt.batteryTempC, -5);
});

test('32-bit today energy uses big-endian word order', () {
  final rt = ControllerRealtime(_rt(genHi: 1, genLo: 0)); // 0x10000 = 65536 ×0.001
  expect(rt.energyTodayKwh, closeTo(65.536, 1e-9));
});
```

- [ ] **Step 2: Run, expect FAIL** (`ControllerRealtime` undefined).
- [ ] **Step 3: Implement** `ChargeStage` + `ControllerRealtime` in `registers.dart` and `ChargeControllerSnapshot` in `model.dart`. Reuse the `_i16`/signed-byte idiom from `renogy_bms/registers.dart`; add `int _s8(int b) => b >= 0x80 ? b - 0x100 : b;`. Export both from `renogy_mppt.dart`.
- [ ] **Step 4: Run tests, expect PASS; `flutter analyze` clean.**
- [ ] **Step 5: Commit** `feat: realtime decoder + snapshot model + charge stage`.

---

### Task 6: Fault bitfield decoder

**Files:**
- Modify: `lib\src\registers.dart`, `lib\src\model.dart` (snapshot `faults`)
- Test: extend

**Interfaces:**
- Produces: `enum ControllerFault { chargeMosShort, antiReverseMosShort, pvReverse, pvOverVoltage, pvCounterCurrent, pvInputOverVoltage, pvInputShort, pvOverpower, ambientTempHigh, controllerTempHigh, loadOverpower, loadShort, batteryUnderVoltage, batteryOverVoltage, batteryOverDischarge }` and `List<ControllerFault> decodeFaults(int mask)` mapping bits C0..C14 (C0 = bit 0) in the order listed in the spec. `ControllerRealtime.faults` returns `decodeFaults(faultMask)`.

- [ ] **Step 1: Write the failing test:**

```dart
test('fault bits C0..C14 decode in order', () {
  expect(decodeFaults(0), isEmpty);
  expect(decodeFaults(1 << 0), [ControllerFault.chargeMosShort]);
  expect(decodeFaults(1 << 13), [ControllerFault.batteryOverVoltage]);
  expect(decodeFaults((1 << 2) | (1 << 14)),
      [ControllerFault.pvReverse, ControllerFault.batteryOverDischarge]);
});
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `ControllerFault` + `decodeFaults`; wire `ControllerRealtime.faults`; make `ChargeControllerSnapshot` carry `List<ControllerFault> faults`.
- [ ] **Step 4: Run, expect PASS; analyze clean.**
- [ ] **Step 5: Commit** `feat: controller fault bitfield decode`.

---

### Task 7: Identity decoders + capabilities + `isControllerSku`

**Files:**
- Create: `lib\src\identity.dart`
- Modify: `lib\renogy_mppt.dart` (export)
- Test: extend

**Interfaces:**
- Produces:
  - `class ControllerIdentity { final String sku; final String? serial; final String? firmware; }`
  - `String decodeSku(List<int> regs)` (ASCII from 8 regs / 16 bytes, trimmed of nulls/spaces), `String decodeSerial(List<int> regs)` (18 bytes), `String decodeFirmware(List<int> regs)` (YYYY/MM/DD from 2 regs).
  - `bool isControllerSku(String sku)` — true for the controller family (`RNG-CTRL-RVR`, `RNG-CTRL-RVRPG`, `RNG-CTRL-WND`, `RCC`+`REGO`, `ML2420N`), false otherwise.
  - `class ControllerCapabilities { final bool hasLoadTerminal; const ControllerCapabilities({this.hasLoadTerminal = true}); }`

- [ ] **Step 1: Write the failing tests:**

```dart
test('SKU decodes ASCII and identifies a controller', () {
  final regs = _ascii('RNG-CTRL-RVR40  '); // 16 bytes -> 8 regs
  expect(decodeSku(regs), 'RNG-CTRL-RVR40');
  expect(isControllerSku('RNG-CTRL-RVR40'), isTrue);
  expect(isControllerSku('RCC60REGO-G2'), isTrue);
});

test('a battery SKU is NOT a controller', () {
  expect(isControllerSku('RBT100LFP12S'), isFalse); // shared FFD0, must be rejected
});
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement** `identity.dart` (helper `_ascii` packs a string into big-endian regs for the test; decoders unpack). Export from `renogy_mppt.dart`.
- [ ] **Step 4: Run, expect PASS; analyze clean.**
- [ ] **Step 5: Commit** `feat: identity decode + controller SKU matcher + capabilities`.

---

### Task 8: `RenogyController` (BLE orchestration) + matcher

**Files:**
- Create: `lib\src\controller.dart`
- Modify: `lib\renogy_mppt.dart` (export)
- Test: extend (matcher-only; live BLE is Task 10)

**Interfaces:**
- Consumes: `BleLink`, `ModbusRtu`, `ModbusAssembler`, `ModbusReply` (modbus_ble); `ControllerRealtime`, `ChargeControllerSnapshot`, `ControllerIdentity`, `decodeSku`, `isControllerSku` (Tasks 5–7).
- Produces:
  - `class RenogyController { RenogyController(BleDevice device); Future<void> connect(); void startLive(); void stopLive(); Future<void> disconnect(); Stream<ChargeControllerSnapshot> get snapshots; Stream<bool> get connection; Future<ControllerIdentity> identify(); Future<List<int>> readRegisters(int address, int count); }`
  - `class RenogyControllerMatcher { bool advertisesLikeRenogy(BleDevice d); Future<bool> looksLikeController(BleDevice d); }` — `advertisesLikeRenogy` matches a `BT-…` name prefix or an advertised FFD0 service; `looksLikeController` connects, reads the SKU block, returns `isControllerSku(decodeSku(...))`, and always disconnects.

- [ ] **Step 1: Write the failing matcher test** (pure part only):

```dart
test('advertisesLikeRenogy matches BT- names and FFD0 service', () {
  final m = RenogyControllerMatcher();
  expect(m.advertisesLikeRenogy(BleDevice(deviceId: 'a', name: 'BT-TH-66F8EE0D', rssi: -50, services: const [])), isTrue);
  expect(m.advertisesLikeRenogy(BleDevice(deviceId: 'b', name: 'MacBook', rssi: -50, services: const [])), isFalse);
});
```

- [ ] **Step 2: Run, expect FAIL.**
- [ ] **Step 3: Implement `controller.dart`.** Model the BLE/`_exchange` flow on `renogy_bms/lib/src/battery.dart`: `BleLink(service: kNotifyService, notify: kNotifyUuid, writeService: kWriteService, write: kWriteUuid, writeWithResponse: false)`; `ModbusAssembler(unitId: kUnitId)`; `readRegisters` via `_link.exclusive(...)` + `const ModbusRtu(unitId: kUnitId).readHolding(...)`; `startLive` polls `regRealtime/regRealtimeCount` at 1 Hz and emits a `ChargeControllerSnapshot`; `identify` reads SKU/serial/firmware blocks. **No write methods.** Export from `renogy_mppt.dart`.
- [ ] **Step 4: Run, expect PASS; analyze clean.**
- [ ] **Step 5: Commit** `feat: RenogyController BLE orchestration + matcher`.

---

### Task 9: `example/` live-test / usage harness

**Files:**
- Create: `C:\Users\riley\renogy_mppt\example\` (Flutter desktop app) — `pubspec.yaml` (path dep `renogy_mppt: {path: ../}`), `lib\main.dart`
- (Windows runner generated by `flutter create .`)

- [ ] **Step 1: Generate** a Flutter app in `example/` (`flutter create --platforms=windows --project-name renogy_mppt_example .`), then set its `pubspec.yaml` to a path dep on `..`.
- [ ] **Step 2: Write `main.dart`** — a minimal screen that: starts a `universal_ble` scan (no OS service filter), lists devices where `RenogyControllerMatcher().advertisesLikeRenogy(d)` is true, on tap connects a `RenogyController`, calls `identify()`, `startLive()`, and prints each `ChargeControllerSnapshot` (SOC, battery V/A, PV V/A/W, load, temps, stage, faults, today kWh) to the screen and `debugPrint`.
- [ ] **Step 3: Build it.** Run `flutter build windows` in `example/` (kill any running exe first). Expected: builds clean. (Running against hardware is Task 10.)
- [ ] **Step 4: `flutter analyze` clean in `example/`; commit** `feat: example desktop harness`.

---

### Task 10: Push `renogy_mppt` + live verification (done gate)

**Files:** decoder files as needed if live values disagree.

- [ ] **Step 1: Create the public repo and push.**

```bash
cd /c/Users/riley/renogy_mppt && gh repo create ril3y/renogy_mppt --public --source=. --remote=origin --push
```

- [ ] **Step 2: Live-read the real controller.** With the Renogy controller powered, in BLE range, and its load safely connected, run the `example/` app on this Surface. Confirm: the `BT-…` device is listed; it connects; `identify()` returns a SKU that `isControllerSku` accepts; the live `ChargeControllerSnapshot` shows physically sensible values (battery ~12–14 V, PV tracking sun, stage one of the enum, temps plausible, no spurious faults).
- [ ] **Step 3: Reconcile.** For any field that decodes to a nonsensical value, fix the offset/scale in `registers.dart`/`identity.dart`, update the matching unit test to the corrected expectation, re-run `flutter test` (green), and re-run the example until the live read is clean. (Optional cross-check: a raw-frame read via the reversing-mcp `bluetooth_le` provider to confirm bytes independently.)
- [ ] **Step 4: Record results.** Add a short "Verified live against `<SKU>` on 2026-…" note to `renogy_mppt/README.md` listing confirmed scalings; bump `CHANGELOG.md`.
- [ ] **Step 5: Final verify + push.** `flutter analyze` clean + `flutter test` green in `renogy_mppt`; commit `test: live-verified scalings against real controller`; `git push origin main`. Confirm the repo's `ci.yml` goes green.

---

## Notes for the executor

- `_hex(List<int>)` helper in tests: `b.map((x) => x.toRadixString(16).padLeft(2, '0')).join()` (as in `renogy_bms` tests).
- `BleDevice` is from `package:universal_ble/universal_ble.dart`.
- Keep each package's commits inside that package's repo; `cellscope` only changes via `pub get` (lockfile), not source, in Task 3.
