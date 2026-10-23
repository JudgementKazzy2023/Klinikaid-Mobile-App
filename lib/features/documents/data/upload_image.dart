import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// The server and Storage accept only PDF, JPEG and PNG, but Android's photo
/// picker often returns WebP or HEIC. Anything else is decoded with the
/// platform decoder (which reads what the phone can open) and re-encoded as a
/// JPEG next to the original, with its longest side capped so it stays well
/// under the 5 MB limit. JPEG and PNG paths are returned unchanged.
Future<String> ensureUploadableImage(String path, {int maxSide = 2400}) async {
  final ext = p.extension(path).toLowerCase();
  if (const {'.jpg', '.jpeg', '.png'}.contains(ext)) return path;

  final buffer = await ui.ImmutableBuffer.fromUint8List(
    await File(path).readAsBytes(),
  );
  final descriptor = await ui.ImageDescriptor.encoded(buffer);
  final scale = math.min(
    1.0,
    maxSide / math.max(descriptor.width, descriptor.height),
  );
  final codec = await descriptor.instantiateCodec(
    targetWidth: (descriptor.width * scale).round(),
    targetHeight: (descriptor.height * scale).round(),
  );
  final frame = await codec.getNextFrame();
  final rgba = await frame.image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  final image = img.Image.fromBytes(
    width: frame.image.width,
    height: frame.image.height,
    bytes: rgba!.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  frame.image.dispose();
  codec.dispose();
  descriptor.dispose();
  buffer.dispose();

  final out = File(p.setExtension(path, '.jpg'));
  await out.writeAsBytes(img.encodeJpg(image, quality: 85), flush: true);
  return out.path;
}
