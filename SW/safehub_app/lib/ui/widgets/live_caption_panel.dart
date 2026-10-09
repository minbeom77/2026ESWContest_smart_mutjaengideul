import 'package:flutter/material.dart';

import '../../services/live_caption_service.dart';

class LiveCaptionPanel extends StatefulWidget {
  const LiveCaptionPanel(
      {super.key,
      required this.service,
      required this.configured,
      this.preview = false});
  final LiveCaptionService service;
  final bool configured;
  final bool preview;

  @override
  State<LiveCaptionPanel> createState() => _LiveCaptionPanelState();
}

class _LiveCaptionPanelState extends State<LiveCaptionPanel> {
  final _scroll = ScrollController();
  String _lastText = '';

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.service,
        builder: (context, _) {
          final service = widget.service;
          final text = service.text;
          if (_lastText != text) {
            _lastText = text;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _scroll.hasClients) {
                _scroll.jumpTo(_scroll.position.maxScrollExtent);
              }
            });
          }
          final available = widget.configured && !widget.preview;
          final color = service.serverError
              ? const Color(0xFFFFC778)
              : service.listening
                  ? const Color(0xFF9DD9B0)
                  : const Color(0xFFC6CBD0);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Row(children: [
                Icon(Icons.closed_caption_outlined,
                    color: Color(0xFFBFD7FF), size: 24),
                SizedBox(width: 10),
                Expanded(
                    child: Text('실시간 음성 자막',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 21,
                            fontWeight: FontWeight.w600))),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Icon(service.listening ? Icons.mic : Icons.mic_off_outlined,
                    size: 17, color: color),
                const SizedBox(width: 7),
                Expanded(
                    child: Text(
                        widget.preview
                            ? '체험 모드 · 마이크 사용 안 함'
                            : !available
                                ? '연결 설정에서 음성 서버 주소를 입력하세요'
                                : service.status,
                        style: TextStyle(color: color, fontSize: 13))),
              ]),
              const SizedBox(height: 10),
              LinearProgressIndicator(
                  value: service.listening
                      ? (service.level * 8).clamp(0.0, 1.0)
                      : 0,
                  minHeight: 3,
                  color: color,
                  backgroundColor: const Color(0x22FFFFFF)),
              const SizedBox(height: 12),
              Expanded(
                  child: text.isEmpty
                      ? Center(
                          child: Text(
                              service.serverError
                                  ? '음성 변환 결과를 받지 못했습니다.\n서버 연결 상태를 확인해 주세요.'
                                  : '말하면 여기에 자막이 표시됩니다',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  color: Color(0xFFBBC1C7),
                                  fontSize: 19,
                                  height: 1.5)))
                      : SingleChildScrollView(
                          controller: _scroll,
                          child: Text(text,
                              key: const ValueKey('live-caption-text'),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 25,
                                  fontWeight: FontWeight.w500,
                                  height: 1.5)))),
              const SizedBox(height: 10),
              Wrap(alignment: WrapAlignment.end, spacing: 8, children: [
                TextButton(
                    onPressed: text.isEmpty ? null : service.clear,
                    child: const Text('자막 지우기')),
                OutlinedButton.icon(
                  onPressed: !available
                      ? null
                      : () {
                          if (service.enabled) {
                            service.pause();
                          } else {
                            service.start();
                          }
                        },
                  icon: Icon(service.enabled ? Icons.pause : Icons.mic_none,
                      size: 19),
                  label: Text(service.enabled ? '자막 일시정지' : '자막 다시 시작'),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(130, 44),
                      foregroundColor: const Color(0xFFBFD7FF)),
                ),
              ]),
            ],
          );
        },
      );
}
