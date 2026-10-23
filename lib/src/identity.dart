// Controller identity: model SKU, serial, firmware, and the SKU-based test that
// tells a Renogy charge controller apart from a Renogy battery (both share the
// FFD0 service). SKU and serial are documented ASCII; firmware byte-encoding is
// not yet confirmed and is left to live verification.

/// Unpack big-endian 16-bit registers into trimmed ASCII (drops nulls/padding).
String _ascii(List<int> regs) {
  final bytes = <int>[];
  for (final r in regs) {
    bytes
      ..add((r >> 8) & 0xFF)
      ..add(r & 0xFF);
  }
  return String.fromCharCodes(bytes.where((b) => b >= 0x20 && b < 0x7F)).trim();
}

/// Product SKU / model, from the 8-register block at 0x000C.
String decodeSku(List<int> regs) => _ascii(regs);

/// Serial number, from the 9-register block at 0x001F.
String decodeSerial(List<int> regs) => _ascii(regs);

/// Known Renogy charge-controller SKU shapes: Rover (RNG-CTRL-RVR / RVRPG),
/// Wanderer (RNG-CTRL-WND), REGO (RCC…REGO), and ML24xx.
const List<String> _controllerPrefixes = ['RNG-CTRL-', 'RCC', 'ML24'];

/// True when [sku] names a Renogy charge controller (not a battery/inverter).
bool isControllerSku(String sku) {
  final s = sku.toUpperCase().trim();
  return _controllerPrefixes.any(s.startsWith) || s.contains('REGO');
}

/// Who the controller is. [firmware] is null until its encoding is verified live.
class ControllerIdentity {
  final String sku;
  final String? serial;
  final String? firmware;
  const ControllerIdentity({required this.sku, this.serial, this.firmware});
}

/// What this controller exposes, so a UI renders only real fields.
class ControllerCapabilities {
  final bool hasLoadTerminal;
  const ControllerCapabilities({this.hasLoadTerminal = true});
}
