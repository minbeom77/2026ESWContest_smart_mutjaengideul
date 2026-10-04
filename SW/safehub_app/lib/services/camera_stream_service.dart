import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'camera_frame_buffer.dart';

class CameraStreamService {
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _watchdogTimer;

  final CameraFrameBuffer _buffer = CameraFrameBuffer();

  String? _host;
  int? _port;

  void Function(Uint8List frame)? _onFrame;
  void Function(bool connected)? _onConnectionChanged;

  bool _disposed = false;
  bool _connecting = false;
  bool _connected = false;
  DateTime? _lastFrameAt;

  static const Duration _watchdogInterval = Duration(seconds: 2);
  static const Duration _frameTimeout = Duration(seconds: 6);

  Future<void> connect({
    required String host,
    required int port,
    required void Function(Uint8List frame) onFrame,
    required void Function(bool connected) onConnectionChanged,
  }) async {
    if (_disposed) {
      return;
    }

    _host = host;
    _port = port;
    _onFrame = onFrame;
    _onConnectionChanged = onConnectionChanged;

    _startWatchdog();

    if (host.isEmpty || port <= 0) {
      _setConnected(false);
      return;
    }

    await _connectNow();
  }

  Future<void> _connectNow() async {
    if (_disposed || _connecting || _socket != null) {
      return;
    }

    final host = _host;
    final port = _port;

    if (host == null || host.isEmpty || port == null || port <= 0) {
      return;
    }

    _connecting = true;

    try {
      print('[CAMERA] connect attempt $host:$port');
      final socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 5),
      );

      if (_disposed) {
        socket.destroy();
        return;
      }

      _socket = socket;
      _buffer.clear();
      _lastFrameAt = DateTime.now();

      print('[CAMERA] connected $host:$port');
      _setConnected(true);

      _subscription = socket.listen(
        (data) {
          _lastFrameAt = DateTime.now();
          try {
            final frame = _buffer.addAndTakeLatest(data);
            if (frame != null) _onFrame?.call(frame);
          } on FormatException catch (error) {
            print('[CAMERA] invalid frame: $error');
            _handleDisconnect();
          }
        },
        onError: (error) {
          print('[CAMERA] socket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          print('[CAMERA] socket done');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (error) {
      print('[CAMERA] connect failed: $error');
      _resetConnection();
      _setConnected(false);
    } finally {
      _connecting = false;
    }
  }

  void _handleDisconnect() {
    if (_disposed) {
      return;
    }

    _resetConnection();
    _setConnected(false);
  }

  void _startWatchdog() {
    if (_disposed || _watchdogTimer != null) {
      return;
    }

    _watchdogTimer = Timer.periodic(
      _watchdogInterval,
      (_) {
        if (_disposed || _connecting) {
          return;
        }

        if (_socket == null) {
          print('[CAMERA] watchdog reconnect');
          unawaited(_connectNow());
          return;
        }

        final lastFrameAt = _lastFrameAt;
        if (lastFrameAt != null &&
            DateTime.now().difference(lastFrameAt) > _frameTimeout) {
          print('[CAMERA] frame timeout - reconnecting');

          _resetConnection();
          _setConnected(false);

          unawaited(_connectNow());
        }
      },
    );
  }

  void _setConnected(bool connected) {
    if (_connected == connected) {
      return;
    }

    _connected = connected;
    _onConnectionChanged?.call(connected);
  }

  void _resetConnection() {
    _subscription?.cancel();
    _subscription = null;

    _socket?.destroy();
    _socket = null;

    _lastFrameAt = null;
    _buffer.clear();
  }

  Future<void> dispose() async {
    _disposed = true;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    _socket?.destroy();
    _socket = null;

    _buffer.clear();
  }
}
