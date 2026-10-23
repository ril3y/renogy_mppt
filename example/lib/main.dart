// Minimal live-test harness for the renogy_mppt package: scan for the BT module,
// connect, identify, and print a ChargeControllerSnapshot once a second. This is
// both the usage example and the tool used to verify scalings against real
// hardware. It only reads.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:renogy_mppt/renogy_mppt.dart';
import 'package:universal_ble/universal_ble.dart';

void main() => runApp(const ExampleApp());

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Renogy MPPT example',
        theme: ThemeData.dark(useMaterial3: true),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _matcher = RenogyControllerMatcher();
  final Map<String, BleDevice> _devices = {};
  RenogyController? _controller;
  ControllerIdentity? _identity;
  ChargeControllerSnapshot? _snap;
  String _status = 'Idle';
  StreamSubscription<ChargeControllerSnapshot>? _snapSub;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  Future<void> _startScan() async {
    _devices.clear();
    setState(() => _status = 'Scanning for a Renogy BT module…');
    UniversalBle.onScanResult = (d) {
      if (_matcher.advertisesLikeRenogy(d)) setState(() => _devices[d.deviceId] = d);
    };
    try {
      await UniversalBle.startScan();
    } catch (e) {
      setState(() => _status = 'Scan error: $e');
    }
  }

  Future<void> _connect(BleDevice d) async {
    await UniversalBle.stopScan();
    await _teardown();
    setState(() => _status = 'Connecting to ${d.name ?? d.deviceId}…');
    final c = RenogyController(d);
    _controller = c;
    try {
      await c.connect();
      final id = await c.identify();
      setState(() {
        _identity = id;
        _status = 'Connected: ${id.sku}';
      });
      _snapSub = c.snapshots.listen((s) {
        debugPrint('SOC ${s.socPercent}%  batt ${s.batteryVoltage}V  '
            'pv ${s.solarVoltage}V/${s.solarPower}W  stage ${s.stage.name}  faults ${s.faults.map((f) => f.name)}');
        setState(() => _snap = s);
      });
      c.startLive();
    } catch (e) {
      setState(() => _status = 'Connect failed: $e');
    }
  }

  Future<void> _copy() async {
    final buf = StringBuffer()
      ..writeln('Renogy MPPT live read — ${DateTime.now().toIso8601String()}')
      ..writeln('Status: $_status');
    final snap = _snap;
    if (snap != null) {
      snapshotRows(_identity, snap).forEach((k, v) => buf.writeln('$k: $v'));
    } else {
      buf.writeln('(no snapshot yet)');
    }
    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Copied readings to clipboard')));
    }
  }

  Future<void> _teardown() async {
    await _snapSub?.cancel();
    _snapSub = null;
    await _controller?.disconnect();
    _controller = null;
    _snap = null;
    _identity = null;
  }

  @override
  void dispose() {
    _teardown();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Renogy MPPT — live harness'),
        actions: [
          IconButton(onPressed: _startScan, icon: const Icon(Icons.refresh), tooltip: 'Rescan'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _copy,
        icon: const Icon(Icons.copy),
        label: const Text('Copy readings'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(padding: const EdgeInsets.all(12), child: Text(_status)),
          const Divider(height: 1),
          for (final d in _devices.values)
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: Text(d.name?.isNotEmpty == true ? d.name! : '(unnamed)'),
              subtitle: Text(d.deviceId),
              onTap: () => _connect(d),
            ),
          if (_snap != null) Expanded(child: _SnapshotView(_identity, _snap!)),
        ],
      ),
    );
  }
}

/// The rows shown on screen and copied to the clipboard — one source of truth.
Map<String, String> snapshotRows(ControllerIdentity? identity, ChargeControllerSnapshot s) => {
      if (identity != null) 'Model': identity.sku,
      if (identity?.serial != null) 'Serial': identity!.serial!,
      'SOC': '${s.socPercent} %',
      'Battery': '${s.batteryVoltage.toStringAsFixed(1)} V   ${s.chargingCurrent.toStringAsFixed(2)} A',
      'Solar (PV)':
          '${s.solarVoltage.toStringAsFixed(1)} V   ${s.solarCurrent.toStringAsFixed(2)} A   ${s.solarPower.toStringAsFixed(0)} W',
      'Load': '${s.loadOn ? 'on' : 'off'}   ${s.loadVoltage.toStringAsFixed(1)} V   ${s.loadPower.toStringAsFixed(0)} W',
      'Temp': 'ctrl ${s.controllerTempC.toStringAsFixed(0)}°C   batt ${s.batteryTempC.toStringAsFixed(0)}°C',
      'Stage': s.stage.name,
      'Today': '${s.energyTodayKwh.toStringAsFixed(3)} kWh',
      'Faults': s.faults.isEmpty ? 'none' : s.faults.map((f) => f.name).join(', '),
    };

class _SnapshotView extends StatelessWidget {
  final ControllerIdentity? identity;
  final ChargeControllerSnapshot s;
  const _SnapshotView(this.identity, this.s);

  @override
  Widget build(BuildContext context) {
    final rows = snapshotRows(identity, s);
    return ListView(
      children: [
        for (final e in rows.entries)
          ListTile(dense: true, title: Text(e.key), trailing: Text(e.value)),
      ],
    );
  }
}
