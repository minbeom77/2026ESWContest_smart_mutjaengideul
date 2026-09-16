String getEventName(Map<String, dynamic> event) {
  switch (event['event']) {
    case 'fall_detected':
      return '낙상 감지';
    default:
      return event['event']?.toString() ?? '알 수 없는 이벤트';
  }
}

String getLocationName(Map<String, dynamic> event) {
  switch (event['location']) {
    case 'bedroom':
      return '침실';
    case 'bathroom':
      return '화장실';
    default:
      return '실내';
  }
}
