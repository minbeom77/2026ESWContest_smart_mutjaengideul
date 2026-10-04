import 'package:flutter_test/flutter_test.dart';
import 'package:safehub_app/core/care_incident.dart';

void main() {
  final start = DateTime(2026, 9, 29, 12);
  CareIncident incident(String id) => CareIncident(id: id, openedAt: start, wait: const Duration(seconds: 30));
  test('timeout creates one local request, never a delivery state', () {
    final item = incident('a');
    expect(item.tick(start.add(const Duration(seconds: 29))), false);
    expect(item.tick(start.add(const Duration(seconds: 30))), true);
    expect(item.needsDelivery, true);
    expect(item.tick(start.add(const Duration(seconds: 40))), false);
  });
  test('a confirmed okay response stops waiting for that incident only', () {
    final first = incident('a');
    final second = incident('b');
    first.reply(needsHelp: false);
    expect(first.tick(start.add(const Duration(minutes: 1))), false);
    expect(second.tick(start.add(const Duration(minutes: 1))), true);
  });
  test('late response updates unsent request', () {
    final item = incident('a');
    item.tick(start.add(const Duration(minutes: 1)));
    item.reply(needsHelp: false);
    expect(item.needsDelivery, false);
    expect(item.response, '괜찮아요');
  });
  test('explicit help creates request without waiting for timeout', () {
    final item = incident('a');
    item.reply(needsHelp: true);
    expect(item.needsDelivery, true);
    expect(item.awaitingResponse, false);
  });
  test('cancelling an unsent timeout request does not recreate it on every tick', () {
    final item = incident('a');
    item.tick(start.add(const Duration(minutes: 1)));
    item.cancelUnsentRequest();
    expect(item.tick(start.add(const Duration(minutes: 2))), false);
    expect(item.needsDelivery, false);
    expect(item.awaitingResponse, true);
  });
  test('selected call request preserves the expressed sign and choice', () {
    final message = CareHelpKind.familyCall.message(sign: '아프다', location: '화장실');
    expect(message, contains('아프다'));
    expect(message, contains('통화하기를 요청'));
    expect(message, isNot(contains('와 달라고')));
    final item = incident('a');
    item.reply(needsHelp: true, helpMessage: message);
    expect(item.requestReason, message);
  });
}
