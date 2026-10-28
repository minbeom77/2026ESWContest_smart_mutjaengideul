enum ManualFallAction { fall, normal }

/// Existing CSI envelope, with a distinct device value for operator input.
ManualFallAction? manualFallAction(Map<String, dynamic> event, {DateTime? now}) {
  if (event['device'] != 'safehub_manual_demo') return null;
  final stamp = event['timestamp'];
  if (stamp is! num || !stamp.isFinite ||
      event['message_id'] is! String ||
      (event['message_id'] as String).isEmpty) return null;
  final age = (now ?? DateTime.now()).millisecondsSinceEpoch / 1000 - stamp;
  if (age < -5 || age > 30) return null;
  return switch (event['event']) {
    'fall_detected' => ManualFallAction.fall,
    'normal' => ManualFallAction.normal,
    _ => null,
  };
}
