import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'app_loading.dart';

Future<Uint8List?> captureMemberPhoto(BuildContext context) =>
    showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _MemberCamera(),
    );

class _MemberCamera extends StatefulWidget {
  const _MemberCamera();
  @override
  State<_MemberCamera> createState() => _MemberCameraState();
}

class _MemberCameraState extends State<_MemberCamera>
    with WidgetsBindingObserver {
  CameraController? _camera;
  List<CameraDescription> _cameras = [];
  int _selected = 0, _generation = 0;
  bool _loading = true, _taking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    CameraController? camera;
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) throw CameraException('no_camera', 'No camera');
      if (!mounted || generation != _generation) return;
      camera = CameraController(
        _cameras[_selected],
        ResolutionPreset.medium,
        enableAudio: false,
      );
      await camera.initialize();
      if (!mounted || generation != _generation) {
        await camera.dispose();
        return;
      }
      setState(() => _camera = camera);
    } catch (_) {
      await camera?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _error = 'Camera unavailable. Allow camera access in app/browser settings and retry.';
        });
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      ++_generation;
      final camera = _camera;
      _camera = null;
      camera?.dispose();
    } else if (state == AppLifecycleState.resumed && !_taking) {
      _start();
    }
  }

  Future<void> _take() async {
    if (_taking || _camera == null) return;
    setState(() => _taking = true);
    try {
      final file = await _camera!.takePicture();
      final codec = await ui.instantiateImageCodecWithSize(
        await ui.ImmutableBuffer.fromUint8List(await file.readAsBytes()),
        getTargetSize: (width, height) => width >= height
            ? ui.TargetImageSize(width: width > 512 ? 512 : width)
            : ui.TargetImageSize(height: height > 512 ? 512 : height),
      );
      ByteData? data;
      try {
        final frame = await codec.getNextFrame();
        try {
          data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
        } finally {
          frame.image.dispose();
        }
      } finally {
        codec.dispose();
      }
      if (data == null || data.lengthInBytes > 2 * 1024 * 1024) {
        throw StateError('Photo too large');
      }
      if (mounted) Navigator.pop(context, data.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not take the photo. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_taking,
    child: Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Take member photo'),
            ),
            Flexible(
              child: _loading
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: DumbbellLoader(label: 'Opening camera'),
                    )
                  : _camera != null && _camera!.value.isInitialized
                  ? CameraPreview(_camera!)
                  : const SizedBox.shrink(),
            ),
            if (_error != null)
              Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
            Padding(
              padding: const EdgeInsets.all(16),
              child: OverflowBar(
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _taking ? null : () => Navigator.pop(context),
                    child: const Text('Cancel camera'),
                  ),
                  if (_cameras.length > 1)
                    IconButton(
                      tooltip: 'Switch camera',
                      onPressed: _taking || _loading
                          ? null
                          : () async {
                              await _camera?.dispose();
                              _camera = null;
                              _selected = (_selected + 1) % _cameras.length;
                              if (mounted) _start();
                            },
                      icon: const Icon(Icons.cameraswitch_outlined),
                    ),
                  if (_camera == null && !_loading)
                    OutlinedButton(
                      onPressed: _start,
                      child: const Text('Retry camera'),
                    ),
                  FilledButton.icon(
                    key: const ValueKey('member-camera-capture'),
                    onPressed: _taking || _loading || _camera == null
                        ? null
                        : _take,
                    icon: _taking
                        ? const DumbbellLoader(size: 20)
                        : const Icon(Icons.camera_alt_outlined),
                    label: const Text('Capture photo'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
