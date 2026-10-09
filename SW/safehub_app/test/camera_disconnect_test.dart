import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/camera_stream_service.dart';
import 'package:safehub_app/ui/home_page.dart';

import 'local_preview_test.dart' show mockAudioPlugins;

class _Camera extends CameraStreamService {
  late void Function(Uint8List) frame;
  late void Function(bool) connection;

  @override
  Future<void> connect({
    required String host,
    required int port,
    required void Function(Uint8List) onFrame,
    required void Function(bool) onConnectionChanged,
  }) async {
    frame = onFrame;
    connection = onConnectionChanged;
  }

  @override
  Future<void> dispose() async {}
}

ui.Image _image() {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = picture.toImageSync(1, 1);
  picture.dispose();
  return image;
}

void main() {
  for (final reconnect in [false, true]) {
    testWidgets(
      'late decode is discarded after disconnect (reconnect=$reconnect)',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        mockAudioPlugins(tester);
        final camera = _Camera();
        final callbacks = <void Function(ui.Image)>[];

        await tester.pumpWidget(
          MaterialApp(
            home: SafeHubHomePage(
              cameraStreamService: camera,
              cameraDecoder: (_, __, ___, ____, callback) =>
                  callbacks.add(callback),
            ),
          ),
        );
        // The injected service uses the same callback path as a real connection.
        // No network address or physical camera is required for this test.
        camera.connection(true);
        camera.frame(Uint8List(320 * 240 * 4));
        expect(callbacks, hasLength(1));
        camera.connection(false);
        if (reconnect) camera.connection(true);

        final stale = _image();
        callbacks.removeAt(0)(stale);
        await tester.pump();
        expect(stale.debugDisposed, isTrue);
        expect(find.byKey(const ValueKey('camera_preview')), findsNothing);

        if (!reconnect) camera.connection(true);
        camera.frame(Uint8List(320 * 240 * 4));
        final fresh = _image();
        callbacks.removeAt(0)(fresh);
        await tester.pump();
        expect(
          tester
              .widget<RawImage>(find.byKey(const ValueKey('camera_preview')))
              .image,
          same(fresh),
        );

        // A callback from the disposed page also releases its decoded image.
        camera.frame(Uint8List(320 * 240 * 4));
        await tester.pumpWidget(const SizedBox());
        final afterDispose = _image();
        callbacks.removeAt(0)(afterDispose);
        await tester.pump();
        expect(fresh.debugDisposed, isTrue);
        expect(afterDispose.debugDisposed, isTrue);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
