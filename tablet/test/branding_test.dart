import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_management_app/main.dart';

void main() {
  testWidgets('Android and web use the RepLab display name', (tester) async {
    await tester.pumpWidget(const GymManagementApp(home: SizedBox()));
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).title,
      'RepLab',
    );
    final android = File('android/app/src/main/AndroidManifest.xml')
        .readAsStringSync();
    expect(android, contains('android:label="RepLab"'));
    expect(android, contains('android:icon="@mipmap/ic_launcher"'));
    final manifest = jsonDecode(File('web/manifest.json').readAsStringSync());
    expect(manifest['name'], 'RepLab');
    expect(manifest['short_name'], 'RepLab');
    expect(manifest['background_color'], '#FFFFFF');
    expect(manifest['theme_color'], '#FFFFFF');
    expect(
      File('android/app/src/main/res/values/colors.xml').readAsStringSync(),
      contains('<color name="ic_launcher_background">#FFFFFF</color>'),
    );
    expect(
      File('web/index.html').readAsStringSync(),
      contains('<title>RepLab</title>'),
    );
  });

  test(
    'launcher variants have red artwork, white backgrounds and safe padding',
    () async {
      const res = 'android/app/src/main/res';
      const foreground = '$res/drawable-nodpi/ic_launcher_foreground_image.png';
      final files = {
        'branding/replab_icon.png': 1024,
        '$res/mipmap-mdpi/ic_launcher.png': 48,
        '$res/mipmap-hdpi/ic_launcher.png': 72,
        '$res/mipmap-xhdpi/ic_launcher.png': 96,
        '$res/mipmap-xxhdpi/ic_launcher.png': 144,
        '$res/mipmap-xxxhdpi/ic_launcher.png': 192,
        foreground: 432,
        'web/icons/Icon-192.png': 192,
        'web/icons/Icon-512.png': 512,
        'web/icons/Icon-maskable-192.png': 192,
        'web/icons/Icon-maskable-512.png': 512,
        'web/favicon.png': 32,
      };
      for (final entry in files.entries) {
        final codec = await ui.instantiateImageCodec(
          File(entry.key).readAsBytesSync(),
        );
        final image = (await codec.getNextFrame()).image;
        try {
          expect(image.width, entry.value, reason: entry.key);
          expect(image.height, entry.value, reason: entry.key);
          final data = (await image.toByteData())!.buffer.asUint8List();
          final size = entry.value;
          final transparent = entry.key == foreground;
          for (final corner in [
            0,
            size - 1,
            size * (size - 1),
            size * size - 1,
          ]) {
            expect(
              data.sublist(corner * 4, corner * 4 + 4),
              transparent ? [0, 0, 0, 0] : [255, 255, 255, 255],
              reason: entry.key,
            );
          }
          final center = ((size ~/ 2) * size + size ~/ 2) * 4;
          expect(
            data[center],
            greaterThan(data[center + 1] * 2),
            reason: entry.key,
          );
          expect(data[center + 3], 255, reason: entry.key);
          final radius = transparent
              ? size * 33 / 108
              : entry.key.contains('maskable')
              ? size * .4
              : null;
          if (radius != null) {
            for (var y = 0; y < size; y++) {
              for (var x = 0; x < size; x++) {
                final offset = (y * size + x) * 4;
                final visible = transparent
                    ? data[offset + 3] > 16
                    : data[offset + 1] < 239;
                if (!visible) continue;
                final dx = x + .5 - size / 2;
                final dy = y + .5 - size / 2;
                expect(
                  dx * dx + dy * dy,
                  lessThanOrEqualTo(radius * radius),
                  reason: entry.key,
                );
              }
            }
          }
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    },
  );
}
