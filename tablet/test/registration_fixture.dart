import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class TestRegistrationCamera extends CameraPlatform {
  TestRegistrationCamera(this.photo);
  final Uint8List photo;
  bool denied = false;
  int captures = 0;
  final _errors = StreamController<CameraErrorEvent>.broadcast();
  @override
  Future<List<CameraDescription>> availableCameras() async {
    if (denied) throw CameraException('CameraAccessDenied', 'Synthetic denial');
    return [
      const CameraDescription(
        name: 'test',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
    ];
  }

  @override
  Future<int> createCamera(
    CameraDescription description,
    ResolutionPreset? preset, {
    bool enableAudio = false,
  }) async {
    expect(enableAudio, false);
    return 1;
  }

  @override
  Future<void> initializeCamera(
    int cameraId, {
    ImageFormatGroup imageFormatGroup = ImageFormatGroup.unknown,
  }) async {}
  @override
  Stream<CameraInitializedEvent> onCameraInitialized(int id) => Stream.value(
    CameraInitializedEvent(
      id,
      320,
      240,
      ExposureMode.auto,
      false,
      FocusMode.auto,
      false,
    ),
  );
  @override
  Stream<CameraErrorEvent> onCameraError(int id) => _errors.stream;
  @override
  Stream<DeviceOrientationChangedEvent> onDeviceOrientationChanged() =>
      const Stream.empty();
  @override
  Widget buildPreview(int id) => const SizedBox(width: 320, height: 240);
  @override
  Future<XFile> takePicture(int id) async {
    captures++;
    return XFile.fromData(photo, name: 'synthetic.png');
  }

  @override
  Future<void> dispose(int id) async {}
}

Future<Uint8List> registrationPhoto({int width = 32, int height = 32}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawColor(Colors.green, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

Future<TestRegistrationCamera> installRegistrationCamera(
  WidgetTester tester, {
  int width = 32,
  int height = 32,
}) async {
  final previous = CameraPlatform.instance;
  final photo = await tester.runAsync(
    () => registrationPhoto(width: width, height: height),
  );
  final camera = TestRegistrationCamera(photo!);
  CameraPlatform.instance = camera;
  addTearDown(() => CameraPlatform.instance = previous);
  return camera;
}

Future<void> fillRequiredMemberDetails(WidgetTester tester) async {
  for (final (key, value) in [
    ('member-emergency', '+91 9876543210'),
    ('member-address', 'Synthetic test address'),
  ]) {
    final field = find.byKey(ValueKey(key));
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
  }
}

Future<void> advanceRegistrationToPayment(WidgetTester tester) async {
  await fillRequiredMemberDetails(tester);
  await tester.tap(find.byKey(const ValueKey('member-add-next')));
  await tester.pumpAndSettle();
  await installRegistrationCamera(tester);
  await tester.tap(find.byKey(const ValueKey('member-take-photo')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('member-camera-capture')));
  await tester.runAsync(
    () async => Future<void>.delayed(const Duration(milliseconds: 80)),
  );
  await tester.pumpAndSettle();
  expect(find.byKey(const ValueKey('member-photo-preview')), findsOneWidget);
  await tester.tap(find.byKey(const ValueKey('member-add-next')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('member-plan-silver')));
  await tester.tap(find.byKey(const ValueKey('member-add-next')));
  await tester.pumpAndSettle();
  await tester.ensureVisible(
    find.byKey(const ValueKey('member-payment-confirm')),
  );
  await tester.tap(find.byKey(const ValueKey('member-payment-confirm')));
  await tester.pumpAndSettle();
}
