import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class CaptionResult {
  const CaptionResult(this.segment, this.text, this.isFinal, this.epoch);
  final int segment;
  final String text;
  final bool isFinal;
  final int epoch;
}

abstract interface class CaptionConnection {
  Stream<CaptionResult> get results;
  void add(Uint8List pcm);
  void reset(int epoch);
  Future<void> close();
}

/// Acknowledgements bound outstanding audio to two seconds. A stalled server
/// closes the session instead of silently accumulating delayed conversation.
class WebSocketCaptionConnection implements CaptionConnection {
  WebSocketCaptionConnection._(this._socket) {
    _socket.pingInterval = const Duration(seconds: 10);
    _subscription = _socket.listen(
      _receive,
      onError: _fail,
      onDone: () {
        if (!_closed) _fail(StateError('음성 서버 연결이 끊겼습니다'));
      },
    );
    _watchdog = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_outstanding > 0 &&
          DateTime.now().difference(_lastAck) > const Duration(seconds: 3)) {
        _fail(StateError('음성 서버 응답이 지연되었습니다'));
      }
    });
  }

  static Future<WebSocketCaptionConnection> connect(Uri uri) async {
    final socket = await WebSocket.connect(
      uri.toString(),
    ).timeout(const Duration(seconds: 5));
    final connection = WebSocketCaptionConnection._(socket);
    try {
      await connection._ready.future.timeout(const Duration(seconds: 5));
      return connection;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }

  final WebSocket _socket;
  final _ready = Completer<void>();
  final _results = StreamController<CaptionResult>();
  late final StreamSubscription<dynamic> _subscription;
  late final Timer _watchdog;
  bool _closed = false;
  int _outstanding = 0;
  DateTime _lastAck = DateTime.now();

  @override
  Stream<CaptionResult> get results => _results.stream;

  void _receive(dynamic data) {
    if (_closed) return;
    try {
      final message = jsonDecode(data as String) as Map<String, dynamic>;
      if (message['type'] == 'ready') {
        if (message['protocol'] != 'safehub.pcm.v1') {
          throw StateError('지원하지 않는 음성 스트리밍 규격');
        }
        if (!_ready.isCompleted) _ready.complete();
      }
      final acknowledged = message['bytes'];
      if (acknowledged is int && acknowledged >= 0) {
        _outstanding = (_outstanding - acknowledged).clamp(0, 64000);
        _lastAck = DateTime.now();
      }
      if (message['type'] == 'caption') {
        _results.add(
          CaptionResult(
            message['segment'] as int,
            message['text'] as String,
            message['final'] as bool,
            message['epoch'] as int,
          ),
        );
      }
    } catch (error) {
      _fail(error);
    }
  }

  void _fail(Object error) {
    if (_closed) return;
    if (!_ready.isCompleted) {
      _ready.completeError(error);
    } else {
      _results.addError(error);
    }
    unawaited(close());
  }

  @override
  void add(Uint8List pcm) {
    if (_closed) throw StateError('음성 연결 종료');
    if (pcm.length.isOdd || _outstanding + pcm.length > 64000) {
      throw StateError('음성 처리 지연 · 다시 연결합니다');
    }
    if (_outstanding == 0) _lastAck = DateTime.now();
    _outstanding += pcm.length;
    for (var offset = 0; offset < pcm.length; offset += 3200) {
      final end = (offset + 3200).clamp(0, pcm.length);
      _socket.add(Uint8List.sublistView(pcm, offset, end));
    }
  }

  @override
  void reset(int epoch) {
    if (!_closed) _socket.add(jsonEncode({'type': 'reset', 'epoch': epoch}));
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _watchdog.cancel();
    await _subscription.cancel();
    // A controller with no listener must not block startup failure cleanup.
    unawaited(_results.close());
    unawaited(_socket.close());
  }
}
