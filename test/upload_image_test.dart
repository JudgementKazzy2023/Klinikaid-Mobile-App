import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:klinikaid_mobile/features/documents/data/upload_image.dart';

/// Photo pickers return WebP/HEIC, which the server refuses; the app turns any
/// non-JPEG/PNG image into a JPEG before OCR and upload.
void main() {
  late Directory temp;
  setUp(() async => temp = await Directory.systemTemp.createTemp('upload-image-'));
  tearDown(() async => temp.delete(recursive: true));

  testWidgets('another image format becomes a capped JPEG next to it', (tester) async {
    await tester.runAsync(() async {
      // GIF stands in for WebP/HEIC: the test engine decodes it, img encodes it.
      final source = File('${temp.path}/scaled_1000000036.gif')
        ..writeAsBytesSync(img.encodeGif(img.Image(width: 3000, height: 1500)));
      final result = await ensureUploadableImage(source.path, maxSide: 1200);
      expect(result, endsWith('scaled_1000000036.jpg'));
      final bytes = File(result).readAsBytesSync();
      expect(bytes.take(3), [0xFF, 0xD8, 0xFF]);
      final decoded = img.decodeJpg(bytes)!;
      expect([decoded.width, decoded.height], [1200, 600]);
    });
  });

  test('JPEG and PNG are returned unchanged', () async {
    for (final name in ['a.jpg', 'b.JPEG', 'c.png']) {
      final path = '${temp.path}/$name';
      expect(await ensureUploadableImage(path), path);
    }
  });
}
