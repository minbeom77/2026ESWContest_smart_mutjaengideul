import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/house_scenario.dart';
import '../../services/situation_service.dart';

/// One accessible surface for notice, response and an unsent help draft.
class ScenarioEventOverlay extends StatefulWidget {
  const ScenarioEventOverlay({
    super.key,
    required this.service,
    required this.camera,
    required this.onAcknowledge,
    required this.onSignal,
  });
  final SituationService service;
  final Widget camera;
  final VoidCallback onAcknowledge, onSignal;
  @override
  State<ScenarioEventOverlay> createState() => _ScenarioEventOverlayState();
}

class _ScenarioEventOverlayState extends State<ScenarioEventOverlay> {
  static const ink = Color(0xFF242424),
      muted = Color(0xFF625E5A),
      accent = Color(0xFF8D2345);
  String reaction = '미확인', target = '본인', request = '', draft = '';
  bool details = false;
  bool _videoReportOpen = false;
  double cameraHeight = 340;
  Timer? _reportTimer, _countdownTimer;
  HouseIncident? _armedIncident;
  bool _collapseSeen = false;
  int _secondsRemaining = 0;
  @override
  void initState() {
    super.initState();
    if (RegExp(r'가족|보호자').hasMatch(incident?.evidence ?? '') &&
        !service.helpSign.contains('아프'))
      target = '다른 사람';
    service.addListener(_syncCollapseSign);
    _syncCollapseSign();
  }

  void _cancelAutoReport() {
    _reportTimer?.cancel();
    _countdownTimer?.cancel();
    _reportTimer = _countdownTimer = null;
    _secondsRemaining = 0;
  }

  void _syncCollapseSign() {
    if (!mounted) return;
    if (!helping || (_armedIncident != null && incident != _armedIncident)) {
      _cancelAutoReport();
      return;
    }
    final sign = (service.helpSign.isNotEmpty
        ? service.helpSign : service.pendingSign).replaceAll(RegExp(r'[\s.!?,·]'), '');
    if (_collapseSeen || draft.isNotEmpty ||
        !const {'쓰러지다', '쓰러짐', '쓰러졌다', '쓰러졌어요', '낙상'}.contains(sign)) return;
    _collapseSeen = true;
    _armedIncident = incident;
    setState(() {
      target = '다른 사람';
      reaction = '미확인';
      _secondsRemaining = 7;
    });
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _secondsRemaining > 0) {
        setState(() => _secondsRemaining--);
      }
    });
    _reportTimer = Timer(const Duration(seconds: 7), () {
      if (mounted && helping && incident == _armedIncident &&
          draft.isEmpty && target == '다른 사람' && reaction == '미확인') {
        prepare('119 신고 내용', automatic: true);
        setState(() => _videoReportOpen = true);
      } else {
        _cancelAutoReport();
      }
    });
  }

  @override
  void dispose() {
    service.removeListener(_syncCollapseSign);
    _cancelAutoReport();
    super.dispose();
  }

  void closeHelp() {
    _cancelAutoReport();
    setState(() {
      draft = '';
      _videoReportOpen = false;
      target = '본인';
      reaction = '미확인';
    });
    if (service.flow.active?.kind == HouseScenario.assistance) {
      // An assistance response must also stop its delivered alarm or advance
      // to a queued incident, just like an acknowledged sign.
      widget.onAcknowledge();
    } else {
      // Declining help does not acknowledge an underlying fire/disaster.
      service.cancelHelp();
    }
  }

  SituationService get service => widget.service;
  HouseIncident? get incident => service.flow.active;
  bool get helping =>
      incident?.kind == HouseScenario.assistance || service.helpOpen;
  bool get simulated => service.scenarioTestMode;
  String get kindName => switch (incident?.kind) {
    HouseScenario.broadcast => incident?.origin == 'sound' ? '경보음 감지' : '아파트 안내방송',
    HouseScenario.disaster => '재난 알림',
    _ => '도움 확인',
  };
  String get headline =>
      _videoReportOpen ? '119 수어·영상 신고'
          : draft.isNotEmpty
          ? '도움 요청 내용을 확인해 주세요'
          : helping
          ? (const {'csi', 'csi_demo'}.contains(incident?.origin) ? '낙상 의심 신호가 감지됐어요' : '도움이 필요하신가요?')
          : incident?.kind == HouseScenario.broadcast
          ? (incident?.origin == 'sound' ? '위급상황 확인 · 경보음이 감지됐어요' : RegExp(r'화재|불이').hasMatch(incident?.evidence ?? '')
              ? '화재 관련 안내방송'
              : '위험 관련 안내방송')
          : '${RegExp(r'지진|태풍|호우|산불|홍수|대설|폭염|한파').firstMatch(incident?.evidence ?? '')?.group(0) ?? '재난'} 알림이 도착했어요';

  Widget text(
    String value, {
    double size = 24,
    bool bold = false,
    Color color = ink,
    int? lines,
  }) => Text(
    value,
    maxLines: lines,
    overflow: lines == null ? null : TextOverflow.ellipsis,
    style: TextStyle(
      fontFamily: 'Pretendard',
      fontSize: size,
      height: 1.4,
      color: color,
      fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
    ),
  );
  Widget button(
    String label,
    VoidCallback callback, {
    bool primary = false,
    IconData? icon,
  }) => SizedBox(
    height: 64,
    child: FilledButton.icon(
      onPressed: callback,
      icon: Icon(
        icon ?? (primary ? Icons.check_rounded : Icons.arrow_forward_rounded),
        size: 26,
        color: primary ? Colors.white : accent,
      ),
      label: Text(
        label,
        style: const TextStyle(
          fontFamily: 'Pretendard',
          fontSize: 22,
          fontWeight: FontWeight.w600,
        ),
      ),
      style: FilledButton.styleFrom(
        backgroundColor: primary ? accent : const Color(0xFFF2EEEA),
        foregroundColor: primary ? Colors.white : ink,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
  Widget box(Widget child, {Color color = const Color(0xFFF7F5F2)}) =>
      Container(
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE5DFD8)),
        ),
        child: child,
      );

  void prepare(String type, {bool automatic = false}) {
    _cancelAutoReport();
    request = type;
    final address = service.settings.address.trim();
    final sign =
        service.helpSign.isNotEmpty ? service.helpSign : service.pendingSign;
    final person =
        target == '다른 사람'
            ? automatic
                ? '쓰러짐 수어가 입력됐습니다. 다른 사람의 상태와 도움 필요 여부는 확인이 필요합니다.'
                : '다른 사람의 상태를 확인하고 도움이 필요합니다.'
            : '사용자가 도움을 요청합니다.';
    setState(
      () =>
          draft = [
            '${simulated ? '[시연] ' : ''}$type · 미전송',
            person,
            '주소: ${address.isEmpty ? '미등록 · 실제 요청 전 입력 필요' : address}',
            if (sign.isNotEmpty) '인식한 수어: $sign',
            if (target == '다른 사람') '불러도 반응이 있는지: $reaction',
            if (automatic) '7초 동안 괜찮다 응답이 확인되지 않아 문안을 준비했습니다. 의식 상태는 미확인입니다.',
            if (incident?.kind != HouseScenario.assistance)
              '받은 알림: ${incident?.evidence ?? ''}',
            '청각장애인 영상 신고 지원: 수어·문자로 소통이 필요합니다.',
          ].join('\n'),
    );
    service.respond(
      '$type 내용 확인 · 대상: $target${target == '다른 사람' ? ' · 반응: $reaction' : ''}',
    );
  }

  Widget notice() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      text(incident?.origin == 'sound' ? '감지 근거 · 음향 분류' : '방송·재난 원문', size: 18, color: muted),
      const SizedBox(height: 12),
      box(
        SelectableText(
          incident?.evidence ?? '원문을 확인해 주세요.',
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 28,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
      const SizedBox(height: 20),
      text('내용을 확인한 뒤 아래에서 응답해 주세요.', size: 24),
      if (service.deferredHelp) ...[
        const SizedBox(height: 12),
        text('도움 수어도 받았어요. 이 알림을 확인한 뒤 도움 화면이 열려요.', size: 22, color: accent),
      ],
      const SizedBox(height: 18),
      TextButton.icon(
        onPressed: () => setState(() => details = !details),
        icon: Icon(details ? Icons.expand_less : Icons.expand_more),
        label: Text(
          details ? '상세 내용 접기' : '시간·알림 전달 상태 보기',
          style: const TextStyle(fontFamily: 'Pretendard', fontSize: 20),
        ),
      ),
      if (details)
        box(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              text(incident?.relevance ?? '수신 내용 확인 필요', size: 20),
              text(incident?.delivery ?? service.actuatorStatus, size: 20),
              text('확인은 알림을 읽었다는 뜻이며 위험 해제를 의미하지 않아요.', size: 20),
              TextButton(
                onPressed: widget.onSignal,
                child: const Text(
                  '빛·진동·음성 다시 알림',
                  style: TextStyle(fontFamily: 'Pretendard', fontSize: 20),
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Widget help() => LayoutBuilder(
    builder: (context, bounds) {
      final sign =
          service.helpSign.isNotEmpty ? service.helpSign : service.pendingSign;
      final camera = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SizedBox(height: cameraHeight, child: widget.camera),
          ),
          const SizedBox(height: 14),
          text(
            sign.isEmpty ? '수어를 기다리고 있어요' : '인식한 수어  $sign',
            size: 28,
            bold: true,
          ),
        ],
      );
      final touch = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          text(
            sign.isEmpty ? '수어 또는 터치로 선택해 주세요.' : '“$sign” 수어를 인식했어요.',
            size: 26,
            bold: true,
          ),
          const SizedBox(height: 18),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: '본인', label: Text('내 도움이 필요해요')),
              ButtonSegment(value: '다른 사람', label: Text('다른 사람이 아파요')),
            ],
            selected: {target},
            onSelectionChanged:
                (values) {
                  _cancelAutoReport();
                  setState(() {
                  target = values.first;
                  reaction = '미확인';
                  });
                },
            style: ButtonStyle(
              textStyle: WidgetStateProperty.all(
                const TextStyle(fontFamily: 'Pretendard', fontSize: 18),
              ),
              minimumSize: WidgetStateProperty.all(const Size(0, 58)),
            ),
          ),
          const SizedBox(height: 16),
          if (target == '다른 사람') ...[
            text('불러도 반응이 있나요?', size: 24),
            if (_secondsRemaining > 0) ...[
              const SizedBox(height: 8),
              text('$_secondsRemaining초 안에 괜찮다 수어가 없으면 신고 내용 확인으로 이동해요.',
                  size: 20, color: accent),
              TextButton(
                onPressed: () => setState(_cancelAutoReport),
                child: const Text('자동 전환 취소'),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  ['반응 있어요', '반응 없어요', '미확인']
                      .map(
                        (value) => ChoiceChip(
                          label: Text(
                            value,
                            style: const TextStyle(
                              fontFamily: 'Pretendard',
                              fontSize: 20,
                            ),
                          ),
                          selected: reaction == value,
                          padding: const EdgeInsets.all(10),
                          onSelected: (_) {
                            _cancelAutoReport();
                            setState(() => reaction = value);
                          },
                        ),
                      )
                      .toList(),
            ),
            const SizedBox(height: 16),
          ],
          button(
            '가족에게 전할 내용 확인',
            () => prepare('가족에게 전할 내용'),
            icon: Icons.family_restroom,
          ),
          const SizedBox(height: 12),
          button(
            '119 신고 내용 확인',
            () => prepare('119 신고 내용'),
            primary: true,
            icon: Icons.description_outlined,
          ),
          const SizedBox(height: 16),
          text('아직 실제 연락은 전송되지 않아요.', size: 20, color: muted),
        ],
      );
      if (bounds.maxWidth < 850)
        return Column(children: [camera, const SizedBox(height: 24), touch]);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(flex: 6, child: camera),
          const SizedBox(width: 28),
          Expanded(flex: 4, child: touch),
        ],
      );
    },
  );

  Widget videoReport() => LayoutBuilder(builder: (context, bounds) {
    final sign = service.helpSign.isNotEmpty
        ? service.helpSign : service.pendingSign;
    final camera = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(height: cameraHeight, child: widget.camera),
        ),
        const SizedBox(height: 12),
        text('인식한 수어', size: 20, color: muted),
        text(sign.isEmpty ? '수어를 기다리고 있어요' : sign, size: 40, bold: true),
      ],
    );
    final information = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.sign_language_outlined, color: accent, size: 36),
          const SizedBox(height: 10),
          text('청각장애인 영상 신고 지원', size: 26, bold: true),
          const SizedBox(height: 8),
          text('수어·문자로 상황을 전달하는 화면입니다.', size: 22),
          const SizedBox(height: 12),
          text('시연 · 119 및 수어통역사 미연결', size: 20, color: accent, bold: true),
        ])),
        const SizedBox(height: 16),
        text('주소', size: 18, color: muted),
        text(service.settings.address.trim().isEmpty
            ? '미등록 · 실제 요청 전 입력 필요' : service.settings.address.trim(),
            size: 26, bold: true),
        const SizedBox(height: 12),
        text('현재 상황', size: 18, color: muted),
        text('수어로 전달한 응급상황 · 반응 상태: $reaction', size: 22),
        const SizedBox(height: 18),
        button('신고 내용으로 돌아가기',
            () => setState(() => _videoReportOpen = false),
            icon: Icons.description_outlined),
      ],
    );
    if (bounds.maxWidth < 850) {
      return Column(children: [camera, const SizedBox(height: 20), information]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 6, child: camera),
      const SizedBox(width: 24),
      Expanded(flex: 4, child: information),
    ]);
  });

  Widget report() => _videoReportOpen ? videoReport() : Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      box(
        SelectableText(
          draft,
          style: const TextStyle(
            fontFamily: 'Pretendard',
            fontSize: 26,
            height: 1.6,
            color: ink,
          ),
        ),
      ),
      const SizedBox(height: 20),
      text(
        '미전송 · 실제 신고·연락 기능은 연결되어 있지 않아요.',
        size: 22,
        bold: true,
        color: accent,
      ),
      const SizedBox(height: 20),
      if (request.startsWith('119')) ...[
        button('119 수어·영상 신고 연결 시연',
            () => setState(() => _videoReportOpen = true),
            primary: true, icon: Icons.video_call_outlined),
        const SizedBox(height: 16),
        text('청각장애인 영상 신고 지원 · 수어통역 연계 화면 시연', size: 20),
        const SizedBox(height: 16),
      ],
      button('내용 복사', () async {
        await Clipboard.setData(ClipboardData(text: draft));
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('내용을 복사했어요. 전송은 하지 않았어요.')),
          );
      }, icon: Icons.copy_outlined),
    ],
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: service,
    builder:
        (context, _) => BlockSemantics(
          child: Material(
            color: const Color(0x802B2529),
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final helpPage = (helping && draft.isEmpty) || _videoReportOpen;
                  final height = (helpPage
                          ? 820.0
                          : draft.isNotEmpty
                          ? 670.0
                          : 610.0)
                      .clamp(0.0, bounds.maxHeight - 32);
                  cameraHeight = (height - (simulated ? 340 : 310)).clamp(
                    150.0,
                    430.0,
                  );
                  final time = incident?.receivedAt;
                  final received =
                      time == null
                          ? ''
                          : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')} 수신';
                  return Center(
                    child: Container(
                      width: (helpPage ? 1280.0 : 1000.0).clamp(
                        0.0,
                        bounds.maxWidth - 32,
                      ),
                      height: height,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEFDFC),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFF7F2ED)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x2631252B),
                            blurRadius: 40,
                            offset: Offset(0, 18),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Material(
                          color: Colors.transparent,
                          child: Padding(
                            padding: const EdgeInsets.all(26),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF7E8ED),
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: Icon(
                                        helping
                                            ? Icons.front_hand_outlined
                                            : Icons.campaign_outlined,
                                        color: accent,
                                        size: 27,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: text(
                                        kindName,
                                        size: 18,
                                        bold: true,
                                        color: accent,
                                      ),
                                    ),
                                    if (simulated || incident?.origin == 'csi_demo')
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFFF3D6),
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
                                        ),
                                        child: text(
                                          '시연',
                                          size: 16,
                                          bold: true,
                                          color: const Color(0xFF513A12),
                                        ),
                                      )
                                    else
                                      text(received, size: 16, color: muted),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      tooltip: '알림 창 닫기',
                                      onPressed:
                                          helping
                                              ? closeHelp
                                              : widget.onAcknowledge,
                                      iconSize: 26,
                                      constraints: const BoxConstraints(
                                        minWidth: 52,
                                        minHeight: 52,
                                      ),
                                      icon: const Icon(
                                        Icons.close_rounded,
                                        color: muted,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 20),
                                Semantics(
                                  liveRegion: true,
                                  child: text(headline, size: 34, bold: true),
                                ),
                                const SizedBox(height: 18),
                                Expanded(
                                  child: SingleChildScrollView(
                                    child:
                                        draft.isNotEmpty
                                            ? report()
                                            : helping
                                            ? help()
                                            : notice(),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                if (simulated)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 14),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFFF3D6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.science_outlined,
                                            color: Color(0xFF513A12),
                                            size: 22,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: text(
                                              service.scenarioActuators
                                                ? '시연 입력 · 실제 LED·진동 작동 / 119 신고 없음'
                                                : '화면 테스트 · 실제 장치와 신고는 작동하지 않아요.',
                                              size: 18,
                                              color: const Color(0xFF513A12),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: button(
                                        draft.isNotEmpty
                                            ? '다시 선택하기'
                                            : helping
                                            ? '괜찮아요'
                                            : '도움이 필요해요',
                                        () {
                                          if (draft.isNotEmpty) {
                                            setState(() {
                                              draft = '';
                                              _videoReportOpen = false;
                                            });
                                          } else if (helping) {
                                            closeHelp();
                                          } else {
                                            service.openHelp();
                                          }
                                        },
                                        icon:
                                            draft.isNotEmpty
                                                ? Icons.arrow_back_rounded
                                                : Icons.front_hand_outlined,
                                      ),
                                    ),
                                    if (!helping || draft.isNotEmpty) ...[
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: button(
                                          draft.isNotEmpty
                                              ? '확인하고 돌아가기'
                                              : incident?.kind ==
                                                  HouseScenario.broadcast
                                              ? '방송 확인했어요'
                                              : '알림 확인했어요',
                                          helping
                                              ? closeHelp
                                              : widget.onAcknowledge,
                                          primary: true,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
  );
}
