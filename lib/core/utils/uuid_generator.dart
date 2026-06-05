import 'dart:math';

/// Utility to generate RFC 4122 compliant UUID v4 strings without external packages.
class UuidGenerator {
  static String generateV4() {
    final random = Random();
    String hexDigit(int value) => value.toRadixString(16);
    final buffer = StringBuffer();
    for (var i = 0; i < 36; i++) {
      if (i == 8 || i == 13 || i == 18 || i == 23) {
        buffer.write('-');
      } else if (i == 14) {
        buffer.write('4');
      } else if (i == 19) {
        buffer.write(hexDigit((random.nextInt(4) + 8)));
      } else {
        buffer.write(hexDigit(random.nextInt(16)));
      }
    }
    return buffer.toString();
  }
}
