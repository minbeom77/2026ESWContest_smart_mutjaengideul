import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../services/wifi_sensing_service.dart';

class WifiSensingPanel extends StatefulWidget {
  const WifiSensingPanel({
    super.key,
    required this.service,
    this.allowDummy = true,
  });
  final WifiSensingService service;
  final bool allowDummy;

  @override
  State<WifiSensingPanel> createState() => _WifiSensingPanelState();
}

class _WifiSensingPanelState extends State<WifiSensingPanel> {
  Timer? _timer;
  Timer? _portsTimer;
  Future<void>? _pollTask;
  bool _refreshQueued = false, _portsPolling = false;
  Map<String, dynamic>? _state;
  List<dynamic> _ports = [];
  final Set<String> _selected = {};
  List<String> _deleted = [];
  final _round = TextEditingController(text: '회차 1');
  int _page = 0, _seconds = 8, _channel = 0;
  String? _port;
  String _label = '정지', _error = '', _notice = '', _portsError = '';
  bool _busy = false;
  bool _dwt = true, _pca = true, _lowpass = true;
  int _stageGeneration = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
    _refreshPorts();
    _timer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _refresh(),
    );
    _portsTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_page == 0 && _state?['connected'] != true && !_busy) _refreshPorts();
    });
  }

  @override
  void didUpdateWidget(covariant WifiSensingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.service != widget.service ||
        oldWidget.allowDummy != widget.allowDummy) {
      _stageGeneration++;
      _state = null;
      _ports = [];
      _port = null;
      _selected.clear();
      _deleted = [];
      _notice = _error = _portsError = '';
      _busy = false;
      _refresh(immediate: true);
      _refreshPorts();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _portsTimer?.cancel();
    _round.dispose();
    super.dispose();
  }

  Future<void> _refresh({bool immediate = false}) {
    if (!mounted) return Future<void>.value();
    if (_pollTask != null) {
      if (immediate) _refreshQueued = true;
      return _pollTask!;
    }
    return _pollTask = _pollLoop().whenComplete(() => _pollTask = null);
  }

  Future<void> _pollLoop() async {
    do {
      _refreshQueued = false;
      final generation = _stageGeneration;
      final service = widget.service;
      try {
        final state = await service.state({
          'denoise': '$_dwt',
          'normalize': '$_pca',
          'pca': '$_pca',
          'lowpass': '$_lowpass',
          'subcarrier': '$_channel',
        });
        if (!mounted || generation != _stageGeneration) continue;
        if (!widget.allowDummy &&
            (state['dummy_allowed'] != false || state['mode'] == 'dummy')) {
          setState(() {
            _state = null;
            _error = '실제 수신 전용 CSI 서비스를 연결하세요. 연결 설정에서 서비스 주소를 확인해주세요.';
          });
          continue;
        }
        setState(() {
          _state = state;
          _error = '';
          final ids = (state['records'] as List).map((r) => r['id']).toSet();
          _selected.removeWhere((id) => !ids.contains(id));
          if (!(state['behaviors'] as List).contains(_label)) _label = '정지';
        });
      } catch (error) {
        if (mounted && generation == _stageGeneration) {
          setState(() {
            _state = null;
            _error =
                error is FormatException
                    ? error.message
                    : '센싱 서비스 연결 대기 · 같은 기기에서 CSI 서비스를 실행해주세요.';
          });
        }
      }
    } while (mounted && _refreshQueued);
  }

  Future<void> _refreshPorts() async {
    if (!mounted || _portsPolling) return;
    _portsPolling = true;
    final service = widget.service;
    try {
      final ports = await service.ports();
      if (!mounted || service != widget.service) return;
      setState(() {
        _ports = ports;
        _portsError = '';
        if (!ports.any((p) => p['port'] == _port)) {
          _port = ports.length == 1 ? ports.first['port'] as String : null;
        }
      });
    } catch (_) {
      if (mounted && service == widget.service)
        setState(() {
          _portsError = 'USB 포트 목록을 확인하지 못했습니다. 자동으로 다시 확인합니다.';
        });
    } finally {
      _portsPolling = false;
    }
  }

  Future<bool> _command(
    String action, [
    Map<String, dynamic> data = const {},
  ]) async {
    if (!mounted || _busy || _state == null) return false;
    final service = widget.service;
    _stageGeneration++; // Earlier GETs cannot undo an action's fresh state.
    setState(() {
      _busy = true;
      _notice = '';
    });
    try {
      final result = await service.command(action, data);
      if (!mounted || service != widget.service) return false;
      setState(() {
        _notice = result['path'] == null ? '' : '저장 위치: ${result['path']}';
      });
      return true;
    } catch (error) {
      if (mounted && service == widget.service)
        setState(() {
          _notice =
              error is TimeoutException
                  ? '${error.message}'
                  : '$error'.replaceFirst('Bad state: ', '');
        });
      return false;
    } finally {
      if (mounted && service == widget.service) {
        _stageGeneration++;
        await _refresh(immediate: true);
      }
      if (mounted && service == widget.service)
        setState(() {
          _busy = false;
        });
    }
  }

  Future<String?> _input(String title, String hint) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _TextInputDialog(title: title, hint: hint),
    );
    return result == null || result.isEmpty ? null : result;
  }

  Future<bool> _confirm(String message) async =>
      await showDialog<bool>(
        context: context,
        builder:
            (context) => AlertDialog(
              title: const Text('선택 항목 확인'),
              content: Text(message),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('삭제'),
                ),
              ],
            ),
      ) ??
      false;

  void _stages(void Function() change) {
    setState(() {
      change();
      _stageGeneration++;
      if (_state != null) _state = {..._state!, 'waveform': null};
    });
    _refresh(immediate: true);
  }

  Widget _button(
    String label,
    VoidCallback? action, {
    bool primary = false,
    bool requiresState = true,
  }) =>
      primary
          ? FilledButton(
            style: FilledButton.styleFrom(foregroundColor: Colors.white),
            onPressed:
                _busy || (requiresState && _state == null) ? null : action,
            child: Text(label),
          )
          : OutlinedButton(
            onPressed:
                _busy || (requiresState && _state == null) ? null : action,
            child: Text(label),
          );

  Widget _card(String title, List<Widget> children) => Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: const Color(0xFFFAF9F6),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        ...children,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final dummy = _state?['mode'] == 'dummy';
    final warnings = List<String>.from(_state?['storage_warnings'] ?? const []);
    return Theme(
      data: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF426AC8)),
        fontFamily: 'Pretendard',
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 16,
              runSpacing: 8,
              children: [
                const Text(
                  '와이파이 센싱',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SegmentedButton<int>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith(
                      (states) =>
                          states.contains(WidgetState.selected)
                              ? const Color(0xFFDDE5FA)
                              : const Color(0xFFFAF9F6),
                    ),
                    foregroundColor: const WidgetStatePropertyAll(
                      Color(0xFF242735),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(value: 0, label: Text('1. 신호 수집')),
                    ButtonSegment(value: 1, label: Text('2. 기록 · 학습')),
                    ButtonSegment(value: 2, label: Text('3. 현재 행동')),
                  ],
                  selected: {_page},
                  onSelectionChanged:
                      (value) => setState(() {
                        _page = value.first;
                      }),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (dummy || _error.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                color: const Color(0xFFFFE7B2),
                child: Text(
                  _error.isNotEmpty
                      ? _error
                      : '모의 신호 사용 중 · 실제 측정이나 행동 인식 정확도를 의미하지 않습니다.',
                ),
              ),
            if (_notice.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: SelectableText(_notice),
              ),
            if (warnings.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                color: const Color(0xFFFFE7B2),
                child: Text(
                  [
                    '일부 저장 파일을 읽지 못했습니다. 정상 기록과 실시간 수신은 계속 사용할 수 있습니다.',
                    ...warnings.take(3),
                    if (warnings.length > 3) '추가 알림 ${warnings.length - 3}개',
                  ].join('\n'),
                ),
              ),
            Expanded(
              child: ListView(
                children:
                    _page == 0
                        ? _capturePage()
                        : _page == 1
                        ? _recordsPage()
                        : _recognitionPage(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _capturePage() {
    final connected = _state?['connected'] == true;
    final capture = _state?['capture'];
    final collecting =
        capture != null &&
        ['preparing', 'recording'].contains(capture['state']);
    final behaviors = List<String>.from(_state?['behaviors'] ?? ['정지', '낙상']);
    return [
      _card('수신기 연결', [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 240,
              child: DropdownButtonFormField<String>(
                value: _port,
                decoration: const InputDecoration(labelText: 'ESP32 USB 포트'),
                items:
                    _ports
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p['port'],
                            child: Text('${p['port']}'),
                          ),
                        )
                        .toList(),
                onChanged:
                    connected
                        ? null
                        : (v) => setState(() {
                          _port = v;
                        }),
              ),
            ),
            _button('포트 새로고침', _refreshPorts, requiresState: false),
            _button(
              connected ? '연결 해제' : '실제 신호 연결',
              connected
                  ? () => _command('disconnect')
                  : _port == null || _state == null
                  ? null
                  : () => _command('connect', {'mode': 'live', 'port': _port}),
              primary: true,
            ),
            if (widget.allowDummy && _state?['dummy_allowed'] != false)
              _button(
                '장비 없이 모의 신호',
                connected ? null : () => _command('connect', {'mode': 'dummy'}),
              ),
          ],
        ),
        const SizedBox(height: 10),
        if (_portsError.isNotEmpty) Text(_portsError),
        if (_ports.length > 1 && _port == null)
          const Text('USB 장치가 여러 개입니다. ESP32 수신기의 포트를 선택하세요.'),
        Text(
          _state == null
              ? '서비스 대기'
              : '${_state!['fresh'] == true ? '수신 중' : '새 신호 대기'} · ${(_state!['rate_hz'] as num).toStringAsFixed(1)} Hz · ${_state!['error']}',
        ),
      ]),
      _card('들어오는 신호', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilterChip(
              label: const Text('1 DWT'),
              selected: _dwt,
              onSelected:
                  (v) => _stages(() {
                    _dwt = v;
                  }),
            ),
            FilterChip(
              label: const Text('2 표준화 · PCA'),
              selected: _pca,
              onSelected:
                  (v) => _stages(() {
                    _pca = v;
                  }),
            ),
            FilterChip(
              label: const Text('3 저역 통과'),
              selected: _lowpass,
              onSelected:
                  (v) => _stages(() {
                    _lowpass = v;
                  }),
            ),
            ActionChip(
              label: const Text('원본 보기'),
              onPressed:
                  () => _stages(() {
                    _dwt = _pca = _lowpass = false;
                  }),
            ),
            ActionChip(
              label: const Text('최종 전처리'),
              onPressed:
                  () => _stages(() {
                    _dwt = _pca = _lowpass = true;
                  }),
            ),
          ],
        ),
        if (!_pca)
          Row(
            children: [
              Text('채널 ${_channel + 1} / 52'),
              Expanded(
                child: Slider(
                  value: _channel.toDouble(),
                  max: 51,
                  divisions: 51,
                  onChanged:
                      (v) => _stages(() {
                        _channel = v.round();
                      }),
                ),
              ),
            ],
          ),
        const SizedBox(height: 12),
        SizedBox(
          height: 170,
          child:
              _state?['waveform'] == null
                  ? Center(
                    child: Text(
                      '${_state?['waveform_reason'] ?? '신호를 연결해주세요.'}',
                    ),
                  )
                  : CustomPaint(
                    painter: _WavePainter(
                      List<num>.from(_state!['waveform']['signal']),
                    ),
                  ),
        ),
        const SizedBox(height: 8),
        const Text(
          '최근 4초 · 세로축 자동 범위 | 버튼은 관찰 단계만 변경합니다. 학습·판단에는 3단계를 모두 적용합니다.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('행동을 선택하고 기록', [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 170,
              child: DropdownButtonFormField<String>(
                value: _label,
                decoration: const InputDecoration(labelText: '행동'),
                items:
                    behaviors
                        .map((b) => DropdownMenuItem(value: b, child: Text(b)))
                        .toList(),
                onChanged:
                    collecting
                        ? null
                        : (v) => setState(() {
                          _label = v!;
                        }),
              ),
            ),
            _button('행동 추가', () async {
              final name = await _input('행동 추가', '예: 걷기, 앉기, 호흡');
              if (name != null) await _command('add_behavior', {'name': name});
            }),
            _button(
              '행동 삭제',
              ['정지', '낙상'].contains(_label)
                  ? null
                  : () async {
                    if (await _confirm('$_label 범주를 삭제할까요? 기존 측정 기록은 유지됩니다.')) {
                      await _command('remove_behavior', {'name': _label});
                    }
                  },
            ),
            SizedBox(
              width: 150,
              child: TextField(
                controller: _round,
                decoration: const InputDecoration(labelText: '측정 회차'),
                enabled: !collecting,
              ),
            ),
            SizedBox(
              width: 125,
              child: DropdownButtonFormField<int>(
                value: _seconds,
                decoration: const InputDecoration(labelText: '기록 시간'),
                items:
                    [4, 8, 16, 30, 60]
                        .map(
                          (s) => DropdownMenuItem(value: s, child: Text('$s초')),
                        )
                        .toList(),
                onChanged:
                    collecting
                        ? null
                        : (v) => setState(() {
                          _seconds = v!;
                        }),
              ),
            ),
            _button(
              collecting ? '기록 취소' : '3초 준비 후 기록',
              collecting
                  ? () => _command('cancel_capture')
                  : _state?['fresh'] != true
                  ? null
                  : () => _command('capture', {
                    'label': _label,
                    'seconds': _seconds,
                    'round': _round.text,
                  }),
              primary: true,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          capture == null
              ? '같은 실험의 기록은 같은 회차로 유지하세요. 별도로 다시 실험할 때 회차를 바꾸세요.'
              : '${{'preparing': '준비 중', 'recording': '기록 중', 'complete': '저장 완료', 'failed': '수집 실패', 'cancelled': '취소됨'}[capture['state']]} · ${capture['error']}${collecting ? ' · ${(capture['remaining'] as num).ceil()}초 남음' : ''}',
        ),
      ]),
    ];
  }

  List<Widget> _recordsPage() {
    final records = List<dynamic>.from(_state?['records'] ?? []);
    final training = _state?['training'] ?? {'state': 'idle'};
    return [
      _card('학습에 사용할 기록만 선택', [
        const Text(
          '학습 단위는 최신 모델과 같은 4초입니다. 행동 2종 이상, 행동마다 서로 다른 측정 회차 3개 이상이 필요합니다.',
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _button(
              '전체 선택',
              () => setState(() {
                _selected.addAll(records.map((r) => r['id'] as String));
              }),
            ),
            _button('선택 해제', () => setState(_selected.clear)),
            _button(
              '선택 ${_selected.length}개 삭제',
              _selected.isEmpty
                  ? null
                  : () async {
                    final ids = _selected.toList();
                    if (await _confirm('선택한 ${ids.length}개 기록을 휴지통으로 옮길까요?')) {
                      if (await _command('delete_records', {'ids': ids}) &&
                          mounted)
                        setState(() {
                          _deleted = ids;
                        });
                    }
                  },
            ),
            if (_deleted.isNotEmpty)
              _button('방금 삭제 복원', () async {
                if (await _command('restore_records', {'ids': _deleted}) &&
                    mounted)
                  setState(() {
                    _deleted = [];
                  });
              }),
            _button('기록 가져오기', () async {
              final path = await _input(
                '이 기기의 기록 JSON 또는 ZIP 가져오기',
                '파일의 전체 경로',
              );
              if (path != null)
                await _command('import_records', {
                  'paths': [path],
                });
            }),
            _button(
              '선택 기록 내보내기',
              _selected.isEmpty
                  ? null
                  : () =>
                      _command('export_records', {'ids': _selected.toList()}),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (records.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Text('저장된 기록이 없습니다. 신호 수집에서 행동을 기록하세요.'),
          ),
        for (final record in records)
          CheckboxListTile(
            dense: true,
            value: _selected.contains(record['id']),
            onChanged:
                (checked) => setState(() {
                  checked!
                      ? _selected.add(record['id'])
                      : _selected.remove(record['id']);
                }),
            title: Text(
              '${record['label']} · ${(record['duration'] as num).toStringAsFixed(1)}초',
            ),
            subtitle: Text(
              '${record['experiment_id']} · ${record['collection']?['mode'] == 'dummy'
                  ? '모의 기록'
                  : record['collection']?['mode'] == 'live'
                  ? '실측 기록'
                  : '연습 기록'}',
            ),
          ),
      ]),
      _card('선택 기록으로 학습', [
        Text(
          _state?['training_allowed'] == true
              ? '체크한 ${_selected.length}개 기록만 사용합니다. 모의·실측 기록은 함께 학습할 수 없습니다.'
              : 'Pi는 수집·추론용입니다. 기록을 PC로 내보내 학습한 다음 모델을 가져오세요.',
        ),
        const SizedBox(height: 12),
        if (training['state'] == 'running') const LinearProgressIndicator(),
        Text(
          '${{'idle': '학습 대기', 'running': '학습 중 · 다른 화면으로 이동해도 계속됩니다.', 'complete': '학습 완료 · 현재 행동 화면에서 인식을 시작하세요.', 'failed': '학습 실패'}[training['state']]} ${training['error'] ?? ''}',
        ),
        const SizedBox(height: 10),
        _button(
          '선택 기록 학습 시작',
          _state?['training_allowed'] != true ||
                  _selected.isEmpty ||
                  training['state'] == 'running'
              ? null
              : () => _command('train', {'ids': _selected.toList()}),
          primary: true,
        ),
      ]),
    ];
  }

  List<Widget> _recognitionPage() {
    final models = List<dynamic>.from(_state?['models'] ?? []);
    final model = _state?['model'];
    final recog = _state?['recognition'];
    final result = recog?['result'];
    return [
      _card('사용할 모델', [
        DropdownButtonFormField<String>(
          value: model?['model_id'],
          isExpanded: true,
          decoration: const InputDecoration(labelText: '저장된 모델'),
          items:
              models
                  .map(
                    (m) => DropdownMenuItem<String>(
                      value: m['model_id'],
                      child: Text(
                        '${m['name'] ?? '행동 모델'} · ${(m['labels'] as List).join(', ')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
          onChanged:
              _busy ||
                      _state == null ||
                      _state?['training']?['state'] == 'running'
                  ? null
                  : (v) {
                    if (v != null) _command('select_model', {'id': v});
                  },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            if (model?['balanced_accuracy'] != null)
              Text(
                '평가 기록의 균형 정확도 ${((model['balanced_accuracy'] as num) * 100).toStringAsFixed(1)}%',
              ),
            _button('PC에서 만든 모델 가져오기', () async {
              final path = await _input(
                '압축을 푼 model 폴더 가져오기',
                'model.json과 weights.npz가 있는 전체 폴더 경로',
              );
              if (path != null) await _command('import_model', {'path': path});
            }),
            _button(
              'Pi용 모델 내보내기',
              model == null ? null : () => _command('export_model'),
            ),
            _button(
              recog?['running'] == true ? '인식 중지' : '새 신호 인식 시작',
              model == null
                  ? null
                  : recog?['running'] != true &&
                      (_state?['fresh'] != true ||
                          _state?['training']?['state'] == 'running')
                  ? null
                  : () => _command(
                    recog?['running'] == true
                        ? 'stop_recognition'
                        : 'recognize',
                  ),
              primary: true,
            ),
          ],
        ),
      ]),
      _card('현재 행동', [
        Text(
          result?['label'] ?? '판단 대기',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 42,
            color: Color(0xFF426AC8),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          '${recog?['reason'] ?? '모델을 선택한 뒤 새 신호 인식을 시작하세요.'}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        if (result != null)
          for (final entry in (result['scores'] as Map).entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  SizedBox(width: 100, child: Text('${entry.key}')),
                  Expanded(
                    child: LinearProgressIndicator(
                      value: (entry.value as num).toDouble(),
                      minHeight: 8,
                    ),
                  ),
                  SizedBox(
                    width: 65,
                    child: Text(
                      '${((entry.value as num) * 100).toStringAsFixed(0)}%',
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
            ),
        const Text(
          '퍼센트는 모델 점수입니다. 실제 정답 확률을 보장하지 않으며, 새 신호가 끊기면 이전 결과를 지웁니다.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    ];
  }
}

class _TextInputDialog extends StatefulWidget {
  const _TextInputDialog({required this.title, required this.hint});
  final String title, hint;
  @override
  State<_TextInputDialog> createState() => _TextInputDialogState();
}

class _TextInputDialogState extends State<_TextInputDialog> {
  final controller = TextEditingController();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      child: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: widget.hint),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('취소'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, controller.text.trim()),
        child: const Text('확인'),
      ),
    ],
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.values);
  final List<num> values;

  @override
  void paint(Canvas canvas, Size size) {
    final grid =
        Paint()
          ..color = const Color(0xFFE0E4EC)
          ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    if (values.length < 2) return;
    final low = values.reduce(math.min).toDouble();
    final high = values.reduce(math.max).toDouble();
    final span = math.max(high - low, .000001);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1);
      final y =
          size.height - 12 - (values[i] - low) / span * (size.height - 24);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF426AC8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) => oldDelegate.values != values;
}
