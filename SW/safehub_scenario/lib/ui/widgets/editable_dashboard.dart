import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';

class DashboardTile {
  DashboardTile(this.x, this.y, this.w, this.h);
  double x, y, w, h;
  DashboardTile copy() => DashboardTile(x, y, w, h);
  List<double> toJson() => [x, y, w, h];
}

Map<String, DashboardTile> defaultDashboardLayout() => {
  'status': DashboardTile(0, 0, 1, .20),
  'camera': DashboardTile(0, .22, .62, .66),
  'captions': DashboardTile(.64, .22, .36, .36),
  'notices': DashboardTile(.64, .60, .36, .24),
  'help': DashboardTile(.64, .86, .36, .14),
  'csi': DashboardTile(0, .90, .62, .10),
};

Map<String, DashboardTile> parseDashboardLayout(Object? raw) {
  final layout = defaultDashboardLayout();
  if (raw is! Map) return layout;
  for (final id in layout.keys.toList()) {
    final values = raw[id];
    if (values is! List ||
        values.length != 4 ||
        values.any((v) => v is! num || !v.toDouble().isFinite))
      continue;
    final n = values.cast<num>().map((v) => v.toDouble()).toList();
    if (n[2] < .1 || n[3] < .07 || n[0] < 0 ||
        n[1] < 0 ||
        n[2] <= 0 ||
        n[3] <= 0 ||
        n[0] + n[2] > 1.001 ||
        n[1] + n[3] > 1.001)
      continue;
    layout[id] = DashboardTile(n[0], n[1], n[2], n[3]);
  }
  return layout;
}

class EditableDashboard extends StatefulWidget {
  const EditableDashboard({
    super.key,
    required this.tiles,
    required this.editing,
    required this.onEditingChanged,
    this.storageFile,
  });
  final Map<String, Widget> tiles;
  final bool editing;
  final ValueChanged<bool> onEditingChanged;
  final File? storageFile;
  @override
  State<EditableDashboard> createState() => _EditableDashboardState();
}

class _EditableDashboardState extends State<EditableDashboard> {
  static const accent = Color(0xFF8D2345);
  static const labels = {
    'status': '우리 집 상황',
    'camera': '수어 카메라',
    'captions': '음성 자막',
    'notices': '최근 알림',
    'help': '도움 요청',
    'csi': '재난 안내',
  };
  Map<String, DashboardTile> layout = defaultDashboardLayout();
  Map<String, DashboardTile>? original;
  String selected = 'camera';
  bool loaded = false, saving = false;
  File get file =>
      widget.storageFile ??
      File(
        '${Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '.'}/SafeHubScenarioData/ui-layout.json',
      );
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      if (await file.exists())
        layout = parseDashboardLayout(jsonDecode(await file.readAsString()));
    } catch (_) {
      /* Use the default layout if a saved file is unavailable. */
    }
    if (mounted) setState(() => loaded = true);
  }

  Map<String, DashboardTile> copy() =>
      layout.map((key, value) => MapEntry(key, value.copy()));
  @override
  void didUpdateWidget(covariant EditableDashboard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing && !oldWidget.editing) original = copy();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(layout.map((key, value) => MapEntry(key, value.toJson()))),
        flush: true,
      );
      if (await file.exists()) await file.copy('${file.path}.previous');
      // Windows rename cannot replace an existing file; write the tiny verified document in place.
      await file.writeAsString(await temporary.readAsString(), flush: true);
      if (mounted) {
        widget.onEditingChanged(false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('이 기기에 화면 배치를 저장했어요.')));
      }
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('배치를 저장하지 못했어요. 다시 시도해 주세요.')),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void adjust(
    String id,
    DragUpdateDetails delta,
    Size size, {
    bool resize = false,
  }) {
    final value = layout[id]!;
    setState(() {
      selected = id;
      if (resize) {
        final minWidth =
            id == 'status'
                ? 520.0
                : id == 'camera'
                ? 400.0
                : 320.0;
        final minHeight = switch (id) {
          'status' => 120.0,
          'camera' => 380.0,
          'captions' => 240.0,
          'notices' => 150.0,
          'help' => 90.0,
          _ => 65.0,
        };
        value.w = (value.w + delta.delta.dx / size.width).clamp(
          (minWidth / size.width).clamp(.1, 1 - value.x),
          1 - value.x,
        );
        value.h = (value.h + delta.delta.dy / size.height).clamp(
          (minHeight / size.height).clamp(.08, 1 - value.y),
          1 - value.y,
        );
      } else {
        value.x = (value.x + delta.delta.dx / size.width).clamp(
          0.0,
          1 - value.w,
        );
        value.y = (value.y + delta.delta.dy / size.height).clamp(
          0.0,
          1 - value.h,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final size = Size(
        bounds.maxWidth,
        bounds.maxHeight - (widget.editing ? 78 : 0),
      );
      final tileOrder = widget.tiles.keys.toList();
      if (widget.editing) { tileOrder.remove(selected); tileOrder.add(selected); }
      return Column(
        children: [
          if (widget.editing)
            Container(
              height: 66,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFF7E8ED),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Row(
                children: [
                  const Icon(Icons.dashboard_customize_outlined, color: accent),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      '제목 막대를 끌어 이동 · 오른쪽 아래 모서리로 크기 조절',
                      style: TextStyle(fontFamily: 'Pretendard', fontSize: 18),
                    ),
                  ),
                  DropdownButton<String>(value: selected,
                    items: labels.entries.map((entry) => DropdownMenuItem(value: entry.key, child: Text(entry.value))).toList(),
                    onChanged: (value) { if (value != null) setState(() => selected = value); }),
                  TextButton(
                    onPressed:
                        () => setState(() => layout = defaultDashboardLayout()),
                    child: const Text('기본 배치'),
                  ),
                  TextButton(
                    onPressed:
                        () => setState(() {
                          layout = defaultDashboardLayout();
                          final width = (size.height * .62 / size.width).clamp(
                            .32,
                            .50,
                          );
                          layout['camera']!.w = width;
                          layout['csi']!.w = width;
                          for (final id in ['captions', 'notices', 'help']) {
                            layout[id]!.x = width + .02;
                            layout[id]!.w = .98 - width;
                          }
                        }),
                    child: const Text('카메라 세로형'),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(
                        () => layout = original ?? defaultDashboardLayout(),
                      );
                      widget.onEditingChanged(false);
                    },
                    child: const Text('취소'),
                  ),
                  FilledButton(
                    onPressed: saving ? null : save,
                    child: Text(saving ? '저장 중' : '배치 저장'),
                  ),
                ],
              ),
            ),
          Expanded(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                for (final id in tileOrder)
                  if (layout.containsKey(id))
                    Positioned(
                      key: ValueKey('tile-$id'),
                      left: layout[id]!.x * size.width,
                      top: layout[id]!.y * size.height,
                      width: layout[id]!.w * size.width,
                      height: layout[id]!.h * size.height,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AbsorbPointer(
                            absorbing: widget.editing,
                            child: widget.tiles[id]!,
                          ),
                          if (widget.editing) ...[
                            IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(
                                    color:
                                        selected == id
                                            ? accent
                                            : const Color(0xFFB9AAA9),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              child: GestureDetector(
                                key: ValueKey('move-$id'),
                                onPanUpdate: (delta) => adjust(id, delta, size),
                                child: Container(
                                  height: 42,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.vertical(
                                      top: Radius.circular(18),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.drag_indicator,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        labels[id] ?? id,
                                        style: const TextStyle(
                                          fontFamily: 'Pretendard',
                                          color: Colors.white,
                                          fontSize: 18,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              right: 0,
                              bottom: 0,
                              child: GestureDetector(
                                key: ValueKey('resize-$id'),
                                onPanUpdate:
                                    (delta) =>
                                        adjust(id, delta, size, resize: true),
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: const BoxDecoration(
                                    color: accent,
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(14),
                                      bottomRight: Radius.circular(18),
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.open_in_full,
                                    color: Colors.white,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      );
    },
  );
}
