import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/services/camera_frame_buffer.dart';

Uint8List packet(List<int> payload) {
  final bytes = Uint8List(4 + payload.length);
  ByteData.sublistView(bytes).setUint32(0, payload.length, Endian.big);
  bytes.setRange(4, bytes.length, payload);
  return bytes;
}

void main() {
  test('같이 수신한 프레임은 최신 완성 프레임만 반환한다', () {
    final parser = CameraFrameBuffer();
    expect(parser.addAndTakeLatest(Uint8List.fromList([
      ...packet([1, 2]), ...packet([3, 4]), ...packet([5, 6]),
    ])), [5, 6]);
    expect(parser.addAndTakeLatest(Uint8List(0)), isNull);
  });

  test('TCP에서 나뉜 헤더와 데이터는 완성될 때만 반환한다', () {
    final parser = CameraFrameBuffer();
    final data = packet([7, 8, 9]);
    expect(parser.addAndTakeLatest(Uint8List.sublistView(data, 0, 2)), isNull);
    expect(parser.addAndTakeLatest(Uint8List.sublistView(data, 2, 5)), isNull);
    expect(parser.addAndTakeLatest(Uint8List.sublistView(data, 5)), [7, 8, 9]);
  });

  test('최신 완성 프레임 뒤의 미완성 프레임을 보존한다', () {
    final parser = CameraFrameBuffer();
    final next = packet([8, 9]);
    expect(parser.addAndTakeLatest(Uint8List.fromList([
      ...packet([1]), ...packet([2]), ...next.sublist(0, 5),
    ])), [2]);
    expect(parser.addAndTakeLatest(Uint8List.sublistView(next, 5)), [8, 9]);
  });

  test('재연결 시 이전 연결의 미완성 데이터를 버린다', () {
    final parser = CameraFrameBuffer();
    parser.addAndTakeLatest(Uint8List.fromList([0, 0]));
    parser.clear();
    expect(parser.addAndTakeLatest(packet([10])), [10]);
  });

  test('잘못된 길이는 거부하고 다음 정상 프레임을 처리한다', () {
    final parser = CameraFrameBuffer();
    expect(() => parser.addAndTakeLatest(Uint8List(4)), throwsFormatException);
    final oversized = Uint8List(4);
    ByteData.sublistView(oversized).setUint32(0, CameraFrameBuffer.maxFrameBytes + 1, Endian.big);
    expect(() => parser.addAndTakeLatest(oversized), throwsFormatException);
    expect(parser.addAndTakeLatest(packet([11])), [11]);
  });
}
