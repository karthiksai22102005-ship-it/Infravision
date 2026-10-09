import 'dart:math';

/// Identifier generation for the Observation Portal (§33).
///
/// Every observation gets a readable local id (`OBS-…`) plus an immutable
/// client-generated id (UUID v4 shape) that doubles as the idempotency key
/// when the report is eventually submitted to the backend. That is what makes
/// retries, restarts and duplicate taps safe.
class IdGenerator {
  IdGenerator._();

  static const String _hex = '0123456789abcdef';
  static const String _tokenAlphabet =
      'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no I/O/0/1
  static final Random _random = Random.secure();

  static String _randomToken(int length, [String alphabet = _tokenAlphabet]) {
    final StringBuffer buffer = StringBuffer();
    for (int i = 0; i < length; i++) {
      buffer.write(alphabet[_random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  /// RFC-4122 shaped random (version 4) identifier — 122 bits of entropy.
  static String uuid() {
    final List<int> bytes = List<int>.filled(16, 0);
    for (int i = 0; i < 16; i++) {
      bytes[i] = _random.nextInt(256);
    }
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((int b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }

  /// Human-readable observation id, e.g. `OBS-20260930-7KQ2XM`.
  static String observationId([DateTime? at]) {
    final DateTime ts = at ?? DateTime.now();
    final String date =
        '${ts.year.toString().padLeft(4, '0')}${ts.month.toString().padLeft(2, '0')}${ts.day.toString().padLeft(2, '0')}';
    return 'OBS-$date-${_randomToken(6)}';
  }

  /// Evidence id, e.g. `EV-9FD2K1QM4T`.
  static String evidenceId() => 'EV-${_randomToken(10)}';

  /// Case-insensitive hex token (used for SHA-256 prefixes in the UI).
  static String hexToken(int length) => _randomToken(length, _hex);
}
