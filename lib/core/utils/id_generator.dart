import 'dart:math';

/// Minimal UUID v4 generator.
///
/// The backend types `sessionId` as `UUID`, so a client-generated identifier must be a real UUID or
/// Jackson rejects the request with a 400 - a bug that only shows up at runtime. Generating it here
/// (instead of adding a package for one string) keeps the dependency list honest.
class IdGenerator {
  const IdGenerator._();

  static final Random _random = Random.secure();

  static String uuidV4() {
    final List<int> bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    // Version 4 and RFC 4122 variant bits.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    String hex(int start, int end) => bytes
        .sublist(start, end)
        .map((int byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();

    return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
  }
}
