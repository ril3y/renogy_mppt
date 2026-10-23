# Renogy MPPT charge-controller Dart library — design

**Date:** 2026-10-23
**Status:** draft for approval (nothing built yet)
**Author:** Claude (Opus 4.8) with Riley

## Intent and why

CellScope reads LiFePO4 **batteries**. Riley also has a **Renogy MPPT solar
charge controller** (the `BT-TH-…` device we live-probed earlier — a BT-1/BT-2
Bluetooth module fronting a Renogy MPPT controller over RS232/RS485). The
long-term goal is to monitor that controller — and eventually tie it into a
golf-cart build — from the same app family.

A charge controller is **not** a battery. It speaks a different language: PV
(solar) input, battery output, optional load output, a charge *stage*
(bulk/boost/float/equalize/MPPT), and daily/lifetime energy harvest. So it needs
its **own** library with its own vocabulary, not a bolt-on to the battery stack.

This document covers two pieces of work:

1. **Extract `modbus_ble`** — a tiny, transport-only package carved out of
   `bms_core`, so both the battery stack and the new controller library can
   share the Modbus-over-BLE plumbing without the controller library depending
   on anything called "BMS".
2. **Build `renogy_mppt`** — a standalone Dart/Flutter library for the Renogy
   MPPT controller, built on `modbus_ble`, read-only, "protocol + model" only
   (no UI). UI integration into CellScope comes later, as a separate task.

## Goals

- A Dart/Flutter library that connects to a Renogy MPPT controller over BLE and
  exposes a **live, read-only** stream of controller telemetry:
  - PV (solar): voltage, current, power
  - Battery: voltage, SOC %, charging current, charging power
  - Load (if the model has a load terminal): voltage, current, power, on/off
  - Charge **stage** (deactivated / activated / MPPT / equalize / boost / float
    / current-limiting)
  - Temperatures: controller and battery sensor
  - Today's figures: min/max battery V, max charge/discharge current & power,
    charge/discharge Ah, Wh generated/consumed
  - Lifetime figures: operating days, over-discharge count, full-charge count,
    cumulative Ah and Wh
  - Controller identity: model string, firmware/hardware version, serial,
    rated voltage/current, product type
  - Active faults/alarms (decoded from the fault bitfield)
- A clean public API shaped for a later UI: a `ChargeControllerSnapshot`
  value type, a `ControllerIdentity`, a `ControllerCapabilities` describing
  what this model exposes (so a future UI renders only real fields), and a
  `RenogyController` object with `connect()/startLive()/stopLive()/disconnect()`
  and `snapshots`/`connection` streams — mirroring the battery lib's ergonomics
  so it feels familiar.
- `modbus_ble` extracted such that **the nine existing battery libraries and the
  CellScope app compile unchanged**, because `bms_core` re-exports the moved
  symbols. (On "CI" specifically, see the builder call below — the only CI that
  exists today is the app's `build.yml`.)
- Its own public GitHub repo (`ril3y/renogy_mppt`), matching the house layout
  used by the battery libs (lib/src, exports, pubspec, test, LICENSE, README,
  CHANGELOG, .gitignore, analysis_options), green on CI.
- Protocol correctness **verified live** against Riley's actual controller
  before the register scalings are treated as settled.

## Non-goals

- **No product UI.** No CellScope screen, no registry registration, no widgets
  beyond the throwaway `example/` harness (which is the live-test tool + usage
  sample, not a shipped interface). This is the protocol + model layer. Wiring it
  into the CellScope app is a later, separate task.
- **No writes in the shipped surface.** The Renogy Modbus protocol *can* toggle
  the load output, change charge parameters, and factory-reset. Those are out of
  scope for this library's public API. (See "Read-only stance".)
- **Not a generic Renogy-everything library.** Scope is the MPPT charge
  controller Riley has. PWM controllers, inverters, DC-DC chargers, shunts and
  batteries are out of scope here (the battery already has `renogy_bms`).
- **No multi-device/hub orchestration**, no cloud, no history storage (that's
  the app's job later).

## Anti-goals (these would make it a failure even if it "worked")

- Depending on `bms_core` from `renogy_mppt` (drags battery vocabulary into a
  non-battery library — the whole reason we're extracting `modbus_ble`).
- Shipping register scalings copied from a public spec but never checked against
  the real hardware, presented as if confirmed.
- Any code path that can change controller settings without a deliberate,
  clearly-named, explicitly-opted-in call. For this library: none at all.
- Breaking the nine green battery libraries during the extraction.

## Constraints

- **Platforms:** Windows ARM64 (dev machine), plus iOS/macOS as the battery libs
  target. `universal_ble` is the BLE layer, same as `bms_core`.
- **Dart/Flutter** SDK `^3.13.5`, `flutter >=1.17.0` — match `bms_core`.
- **Lints are CI-fatal** (house rule from the app: `flutter analyze` must be
  clean; `flutter_lints ^6.0.0`).
- **Static-analysis + owner-hardware only.** The register map comes from Riley's
  own app-derived artifact (`Downloads\renogy\RENOGY_MODBUS_PROTOCOL.md` +
  decompiled APK), cross-referenced to the public Rover spec, then verified
  against Riley's own controller over BLE. No third-party devices; no live
  writes. Treat the download as untrusted (read as data, never execute).
- **Git-dependency style**, `publish_to: none`, same as the battery libs
  (`renogy_mppt` depends on `modbus_ble` via git; `bms_core` gains a git dep on
  `modbus_ble`).

## Architecture decision 1: extract `modbus_ble`

**What moves out of `bms_core/lib/src` into a new `modbus_ble` package:**

- `ble_link.dart` → `BleLink` (BLE connect / discover / notify / chunked write /
  `exclusive()` request serialization; already supports split write/notify
  services via `writeService`).
- `modbus.dart` → `crc16Modbus`, `withModbusCrc`, `hasValidModbusCrc`,
  `ModbusRtu`, `ModbusReply`, `ModbusAssembler`, the `fn*` constants.
- `normalizeUuid()` — currently in `driver.dart`. `BleLink` depends on it, so it
  moves into `modbus_ble` (e.g. a small `uuid.dart`). This is the one symbol
  that forces a cross-file change.

**What stays in `bms_core`:** everything battery (`driver.dart` with
`BatteryDriver`/`Battery`/`BleSignature`, `capabilities.dart`, `model.dart`,
`notice.dart`, `secret.dart`).

**How the nine battery libs stay untouched:**

- `bms_core` adds `dependency: modbus_ble` (git) and its `bms_core.dart`
  re-exports it: `export 'package:modbus_ble/modbus_ble.dart';` in place of the
  removed `export 'src/ble_link.dart';` / `export 'src/modbus.dart';`.
- `bms_core/src/driver.dart` imports `normalizeUuid` from
  `package:modbus_ble/modbus_ble.dart` instead of defining it.
- Every battery lib imports `package:bms_core/bms_core.dart` and sees the exact
  same symbol set as before. **No battery-lib source changes.**
- CI across `bms_core` + the nine libs + the app is the proof. If a re-export is
  missed, those builds go red and get fixed before handoff.

`modbus_ble` package: `name: modbus_ble`, depends on `universal_ble` only,
exports `ble_link.dart`, `modbus.dart`, `uuid.dart`. Repo `ril3y/modbus_ble`,
house layout, with a unit test for CRC-16/Modbus and the assembler resync.

**Decision — `BleSignature`:** stays in `bms_core` (it scores battery
advertisements; it's discovery/domain, not pure transport). `renogy_mppt` does
*not* get `BleSignature`; it defines its own lightweight matcher (below). This
keeps `modbus_ble` purely "bytes over BLE".

## Architecture decision 2: `renogy_mppt` package

Layout mirrors `renogy_bms` (the battery lib), minus the UI/registry hooks:

```
renogy_mppt/
  lib/
    renogy_mppt.dart            // public exports
    src/
      gatt.dart                 // service/char UUIDs, unit id
      registers.dart            // register addresses + decoders (RenogyRealtime-style)
      controller.dart           // RenogyController: connect/live/streams + model types
  test/renogy_mppt_test.dart
  example/                      // small Flutter desktop app: scan → connect → print live snapshot
  pubspec.yaml  README.md  CHANGELOG.md  LICENSE  .gitignore  analysis_options.yaml
```

### Live-test harness = the package `example/`

The live-verification pass (Riley's "verify before done") runs through a minimal
**Flutter desktop app in `example/`** that depends on `renogy_mppt`, scans for
the BT module, connects, and dumps a `ChargeControllerSnapshot` + identity to the
screen/console once a second. This is idiomatic for a Dart package (the `example/`
is also the usage doc) and exercises the **real** code path end-to-end — `BleLink`
→ Modbus → decoders → snapshot — not just raw bytes. It runs on this Surface
(ARM64), whose BLE already works with `universal_ble` (same stack CellScope scans
with). The controller is reachable from here, so the implement → run → compare →
fix loop happens locally. The example app is a dev/verification harness and usage
sample only — it is **not** CellScope UI and not the "no UI" non-goal being
walked back; wiring the lib into CellScope proper is still a separate later task.

### Transport (reused, confirmed from the battery lib)

- Service/characteristics: **FFD0 write / FFD1**, **FFF0 notify / FFF1** — the
  BT-1/BT-2 split write/notify pair, identical to `renogy_bms`.
  `BleLink(service: FFF0-notify, writeService: FFD0, write: FFD1, notify: FFF1,
  writeWithResponse: false)`.
- Protocol: **Modbus-RTU function 0x03** (read holding registers), CRC-16/Modbus,
  via `ModbusRtu`/`ModbusAssembler` from `modbus_ble`.
- Request serialization via `BleLink.exclusive()` (one exchange at a time), same
  `_exchange()` pattern as `renogy_bms`.

### Register map — source of truth is the app-derived map on disk

**Primary source:** `C:\Users\riley\Downloads\renogy\RENOGY_MODBUS_PROTOCOL.md`
— reverse-engineered from DC Home v1.10.69 (`com.renogy.dchome`), the same APK
`renogy_bms` came from, with register parsing traced to `BleCtrlActivity.java`,
command frames to `k4/d.java`, and CRC to `ModBusUtils.java`. The decompiled APK
and a `pyrenogy` reference are in the same folder. The public Rover Modbus spec
is a cross-reference only.

**Handling (untrusted download):** read those files as **data**; do not execute
anything from `Downloads\renogy\`. Any helper script runs from a *different*
directory with `python -I`, paths passed as args. (`renogy_bms` was built from
this same source, so this is existing practice.)

**Controller realtime — one read of 35 registers from 0x0100** (frame
`FF 03 01 00 00 23`), parsed per `BleCtrlActivity.java:449–522`:

| Reg / offset | Field | Scale / unit |
|---|---|---|
| 0x0100 | battery SOC | % |
| 0x0101 | battery voltage | ×0.1 V |
| 0x0102 | charging current | ×0.01 A |
| 0x0103 hi / lo | controller temp / battery temp | signed °C |
| 0x0104 | load voltage | ×0.1 V |
| 0x0105 | load current | ×0.01 A |
| 0x0106 | load power | W |
| 0x0107 | solar (PV) voltage | ×0.1 V |
| 0x0108 | solar current | ×0.01 A |
| 0x0109 | solar power | W |
| 0x010A | load switch status | bit |
| 0x0113 / 0x0114 | min / max battery voltage today | ×0.001 V |
| 0x011C–0x011D | power generation today | ×0.001 kWh (32-bit) |
| 0x0120 hi / lo | load-switch+state bitmap / **charging state code** | code |
| 0x0121–0x0122 | fault/alarm bitfield | 32-bit bitmap |

**Identity blocks (separate reads, documented frames):** SKU/model
`FF 03 00 0C 00 08` (0x000C–0x0013, 16 ASCII); serial `FF 03 00 1F 00 09`
(0x001F–0x0027, 18 ASCII); firmware `FF 03 00 14 00 02` (YYYY/MM/DD encoded);
extended params `FF 03 E0 03 00 1B` (battery type, dc-load enable).

**Charging-state codes** (exact, from the app): 0x00 deactivated · 0x01
activated · 0x02 MPPT · 0x03 equalizing · 0x04 boost · 0x05 float · 0x06
current-limiting → maps 1:1 to the `ChargeStage` enum.

**Controller fault bits C0–C14** (exact, from the app): C0 charge-MOS short, C1
anti-reverse-MOS short, C2 PV reverse, C3 PV over-voltage, C4 PV counter-current,
C5 PV-input over-voltage, C6 PV-input short, C7 PV overpower, C8 ambient-temp
high, C9 controller-temp high, C10 load overpower/current, C11 load short, C12
battery under-voltage, C13 battery over-voltage, C14 battery over-discharge.

**What still needs the live pass:** the scalings above come from the app
decompile (authoritative for how the app reads), but the live read is a sanity
check that the values decode to physically sensible numbers on Riley's actual
controller. Lifetime counters (operating days, full-charge count, cumulative
Ah/Wh) are *not* in the app's 35-register block — they're Rover-spec extras; if
wanted, read and confirm them live before shipping, otherwise leave them out of
v1. Decoders decode what's present; absent/zeroed blocks aren't invented.

### Discovery / matching

- A lightweight `RenogyControllerMatcher` (not `BleSignature`): matches the BT
  module by advertised name prefix (`BT-TH`, `BT-1`, `BT-2`, …) and/or the FFD0
  service. Because FFD0 is shared across all Renogy BT devices (we learned this
  the hard way — it mislabeled a controller as a battery), **positive controller
  identification is by the register bank + SKU**, per the app-derived map —
  *not* a single "product-type register" (my earlier wording was wrong). The
  probe reads the **controller SKU block** `FF 03 00 0C 00 08` (0x000C–0x0013)
  and confirms the ASCII SKU matches the controller family list
  (`RNG-CTRL-RVR…`, `RNG-CTRL-RVRPG…`, `RNG-CTRL-WND…`, `RCC…REGO`, `ML2420N`).
  A battery answers its data/SKU at a different bank (0x1388 / 0x13B2, SKU at
  0x1402), so it won't produce a controller SKU and is correctly rejected.
  Provided as a `Future<bool> looksLikeController(BleDevice)` helper.

### Modbus unit id — resolved from the app-derived map

The decompiled DC Home map settles this: the device address is **`0xFF`**
(documented default/broadcast), confirmed by a worked example frame
`FF 03 01 00 00 02 C5 D4` reading 0x0100. `gatt.dart` gets a single constant
`kUnitId = 0xFF` — same as `renogy_bms` — not a discovery step. (My earlier
`[0x01, 0xFF]` candidate-list guess was wrong; dropped.)

### Public API (shape for later UI)

- `class RenogyController` — `connect()`, `startLive()` (1 Hz poll like the
  battery lib), `stopLive()`, `disconnect()`, `Stream<ChargeControllerSnapshot>
  snapshots`, `Stream<bool> connection`, `Future<ControllerIdentity> identify()`.
- `class ChargeControllerSnapshot` — immutable value type with the fields above,
  grouped: `pv`, `battery`, `load`, `stage`, `temps`, `today`, `lifetime`,
  `faults`.
- `enum ChargeStage { deactivated, activated, mppt, equalizing, boost, floating,
  currentLimiting }`.
- `class ControllerIdentity` — model, firmware, hardware, serial, rated V/A,
  product type.
- `class ControllerCapabilities` — booleans for optional sections (e.g.
  `hasLoadTerminal`) so a later UI renders only real fields. Same philosophy as
  `BatteryCapabilities`.
- `class ControllerFault` + decode of the 32-bit fault bitfield into a list.

### Read-only stance

- The library exposes **no write methods** in its public API. The Modbus write
  functions exist in `modbus_ble` (`ModbusRtu.writeSingle/writeMultiple`) but
  `renogy_mppt` never calls them. Load-toggle / parameter-set / factory-reset
  are deliberately not implemented. (Matches CellScope's read-only rule; revisit
  only as an explicit, separately-approved feature.)

### Tests

- CRC/frame-build tests (deterministic): a known realtime read frame for unit id
  on FFD1; decode of a synthetic register block into a `ChargeControllerSnapshot`
  with the scalings above; temperature sign handling; 32-bit cumulative pair
  assembly; charge-stage enum mapping; fault-bit decode.
- Live verification (manual, against Riley's controller) recorded in the README
  once done; scalings adjusted to match observed reality.

### What "green on CI" means — builder call (from review)

There is no per-library CI in this project today: neither `bms_core` nor the
nine battery libs has a `.github/workflows`. The only CI is
`cellscope/.github/workflows/build.yml`, which runs `flutter analyze`/`flutter
test` against the **app** (pulling every lib via git `ref: main`). So:

- The real, authoritative proof that the extraction didn't break anything is
  **the app's `build.yml` going green** after `bms_core` picks up the
  `modbus_ble` dependency — that build transitively compiles all nine libs.
- Per-lib verification is done **locally** (`flutter analyze` + `flutter test`
  in each touched package) before push, same as the libs are maintained today.
- Decision: give the two **new** repos (`modbus_ble`, `renogy_mppt`) a minimal
  GitHub Actions workflow (analyze + test) as good hygiene, since they're new
  and cheap to set up. Existing libs are left as-is (not in scope to retrofit).

## Left to the builder

- Exact file splits and private helpers within `renogy_mppt/src`.
- Naming of the matcher helper and capability flags.
- Whether `today`/`lifetime` are nested value types or flat fields on the
  snapshot (builder's call; nested is the current lean).
- Test fixture byte values.

## Decisions from review (the "theirs" pile — now answered)

**1. Definition of done = live-verified.** The build is paired with a **live BLE
session against Riley's real controller**; the library is not "done" until a live
read decodes cleanly and values are confirmed sensible on the actual hardware.
Because the scalings now come from the app decompile (not a guess), the live pass
is a **sanity check + ambiguity-resolver**, not a from-scratch derivation. One
longer pass (implement + verify together), not build-now-check-later.
Practically: implement from the app-derived map → bring the controller in range,
powered, load safely connected → bring up the reversing-mcp BLE link → read the
SKU/identity block and the 35-register realtime block → confirm the SKU matches,
values decode to physically sensible numbers, charging-state/fault bits behave →
adjust any decoder that disagrees → then green/done. Synthetic-fixture tests
still ship, but the live read gates completion.

**2. Rollout = create both repos, push, bms_core straight to main.** Authorized to
create `ril3y/modbus_ble` and `ril3y/renogy_mppt` as public repos under Riley's
account and push. Sequence (ordering matters because the app tracks `bms_core`
`main` unpinned):

1. Create + push `ril3y/modbus_ble` (transport moved out, its own test green).
2. Bump `bms_core` `main`: add the `modbus_ble` git dep, delete the moved
   `src/ble_link.dart`/`src/modbus.dart`, re-export `modbus_ble`, point
   `driver.dart` at `modbus_ble`'s `normalizeUuid`. Run `bms_core` analyze/test.
3. Confirm the app's `build.yml` goes green (transitively compiles all nine libs
   against the new `bms_core`). This is the proof the extraction broke nothing.
4. Create + push `ril3y/renogy_mppt` (depends on `modbus_ble`), implement, then
   the live-verification pass above.
