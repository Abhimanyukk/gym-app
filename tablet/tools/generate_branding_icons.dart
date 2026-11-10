// Run from tablet/: flutter test --no-pub tools/generate_branding_icons.dart
// Uses the installed SVG renderer; normal tests never regenerate assets.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('generate RepLab launcher and web icons from the master SVG', () async {
    final source = File('branding/replab_icon.svg').readAsStringSync();
    const background =
        '<rect id="background" width="108" height="108" fill="#FFFFFF"/>';
    expect(background.allMatches(source), hasLength(1));
    final icon = await vg.loadPicture(
      SvgStringLoader(source.replaceFirst(background, '')),
      null,
    );
    try {
      Future<void> writeIcon(
        String path,
        int size, {
        double scale = 1,
        bool transparent = false,
      }) async {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        if (!transparent) {
          canvas.drawColor(const ui.Color(0xffffffff), ui.BlendMode.src);
        }
        canvas.translate(size / 2, size / 2);
        canvas.scale(size / icon.size.width * scale);
        canvas.translate(-icon.size.width / 2, -icon.size.height / 2);
        canvas.drawPicture(icon.picture);
        final picture = recorder.endRecording();
        final image = await picture.toImage(size, size);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File(path);
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      await writeIcon('branding/replab_icon.png', 1024);
      const res = 'android/app/src/main/res';
      for (final (density, size) in [
        ('mdpi', 48),
        ('hdpi', 72),
        ('xhdpi', 96),
        ('xxhdpi', 144),
        ('xxxhdpi', 192),
      ]) {
        await writeIcon('$res/mipmap-$density/ic_launcher.png', size);
      }
      // Android's 108dp layers reserve the central 66dp circle for artwork.
      await writeIcon(
        '$res/drawable-nodpi/ic_launcher_foreground_image.png',
        432,
        scale: 2 / 3,
        transparent: true,
      );
      for (final size in [192, 512]) {
        await writeIcon('web/icons/Icon-$size.png', size);
        // Web maskable icons keep the symbol inside the central 80% circle.
        await writeIcon('web/icons/Icon-maskable-$size.png', size, scale: .9);
      }
      await writeIcon('web/favicon.png', 32);
    } finally {
      icon.picture.dispose();
    }
  });
}
