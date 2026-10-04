import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

class CameraStreamService {
  CameraStreamService({
    this.frameByteLength = 320 * 240 * 4,
    this.watchdogInterval = const Duration(seconds: 2),
    this.frameTimeout = const Duration(seconds: 6),
    this.connectionTimeout = const Duration(seconds: 5),
  }) : assert(frameByteLength > 0 && frameByteLength <= 10 * 1024 * 1024),
       assert(watchdogInterval > Duration.zero),
       assert(frameTimeout > Duration.zero),
       assert(connectionTimeout > Duration.zero);

  final int frameByteLength;
  final Duration watchdogInterval;
  final Duration frameTimeout;
  final Duration connectionTimeout;
  Socket? _socket;
  StreamSubscription<Uint8List>? _subscription;
  Timer? _watchdogTimer;

  final Uint8List _header = Uint8List(4);
  late Uint8List _frameBuffer = Uint8List(frameByteLength);
  int _headerBytes = 0;
  int _frameBytes = 0;

  String? _host;
  int? _port;

  void Function(Uint8List frame)? _onFrame;
  void Function(bool connected)? _onConnectionChanged;

  bool _disposed = false;
  bool _connecting = false;
  bool _connected = false;
  DateTime? _lastFrameAt;

  Future<void> connect({
    required String host,
    required int port,
    required void Function(Uint8List frame) onFrame,
    required void Function(bool connected) onConnectionChanged,
  }) async {
    if (_disposed) {
      return;
    }

    if (_host != host || _port != port) {
      _resetConnection();
      _setConnected(false);
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
        timeout: connectionTimeout,
      );

      if (_disposed || _host != host || _port != port) {
        socket.destroy();
        return;
      }

      _socket = socket;
      _headerBytes = 0;
      _frameBytes = 0;
      _lastFrameAt = DateTime.now();

      print('[CAMERA] connected $host:$port');
      _subscription = socket.listen(
        (data) {
          if (_disposed || !identical(_socket, socket)) return;
          _consumeFrames(data, socket);
        },
        onError: (error) {
          if (_disposed || !identical(_socket, socket)) return;
          print('[CAMERA] socket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          if (_disposed || !identical(_socket, socket)) return;
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

    _watchdogTimer = Timer.periodic(watchdogInterval, (_) {
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
          DateTime.now().difference(lastFrameAt) > frameTimeout) {
        print('[CAMERA] frame timeout - reconnecting');

        _resetConnection();
        _setConnected(false);

        unawaited(_connectNow());
      }
    });
  }

  void _setConnected(bool connected) {
    if (_connected == connected) {
      return;
    }

    _connected = connected;
    _onConnectionChanged?.call(connected);
  }

  void _consumeFrames(Uint8List data, Socket source) {
    var offset = 0;
    while (offset < data.length && !_disposed && identical(_socket, source)) {
      if (_headerBytes < 4) {
        final count = (4 - _headerBytes).clamp(0, data.length - offset);
        _header.setRange(_headerBytes, _headerBytes + count, data, offset);
        _headerBytes += count;
        offset += count;
        if (_headerBytes < 4) return;

        // The existing camera protocol sends one fixed-size RGBA frame.
        final length = ByteData.sublistView(_header).getUint32(0, Endian.big);
        if (length != frameByteLength) {
          _handleDisconnect();
          return;
        }
      }

      final count = (frameByteLength - _frameBytes).clamp(
        0,
        data.length - offset,
      );
      _frameBuffer.setRange(_frameBytes, _frameBytes + count, data, offset);
      _frameBytes += count;
      offset += count;
      if (_frameBytes < frameByteLength) return;

      final frame = _frameBuffer;
      _frameBuffer = Uint8List(frameByteLength);
      _headerBytes = 0;
      _frameBytes = 0;
      // Partial packets do not keep a frozen camera marked as live.
      _lastFrameAt = DateTime.now();
      _setConnected(true);
      if (!_disposed) _onFrame?.call(frame);
    }
  }

  void _resetConnection() {
    _subscription?.cancel();
    _subscription = null;

    _socket?.destroy();
    _socket = null;

    _lastFrameAt = null;
    _headerBytes = 0;
    _frameBytes = 0;
  }

  Future<void> dispose() async {
    _disposed = true;

    _watchdogTimer?.cancel();
    _watchdogTimer = null;

    await _subscription?.cancel();
    _subscription = null;

    _socket?.destroy();
    _socket = null;

    _connected = false;
    _headerBytes = 0;
    _frameBytes = 0;
  }
}
