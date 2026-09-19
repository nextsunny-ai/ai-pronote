import 'dart:async';
import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

import 'notes/note_document.dart';
import 'notes/file_note_repository.dart';
import 'notes/note_repository.dart';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'recording/audio_recorder_gateway.dart';
import 'recording/device_audio_recorder.dart';
import 'update/update_checker.dart';

Future<Directory> _defaultRecordingDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final recordings = Directory(
    '${documents.path}${Platform.pathSeparator}recordings',
  );
  await recordings.create(recursive: true);
  return recordings;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final packageInfo = await PackageInfo.fromPlatform();
  runApp(
    PronoteApp(
      repository: FileNoteRepository(documents),
      recorder: DeviceAudioRecorderGateway(),
      currentVersion: packageInfo.version,
      updateChecker: const RemoteUpdateChecker(
        'https://nextsunny-ai.github.io/ai-pronote/mobile-update.json',
      ),
      openExternalUrl: (url) async {
        await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
    ),
  );
}

class PronoteApp extends StatelessWidget {
  const PronoteApp({
    super.key,
    required this.repository,
    this.recorder = const DisabledAudioRecorderGateway(),
    this.recordingDirectoryProvider,
    this.currentVersion = '1.0.0',
    this.updateChecker,
    this.openExternalUrl,
  });

  final NoteRepository repository;
  final AudioRecorderGateway recorder;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final String currentVersion;
  final UpdateChecker? updateChecker;
  final Future<void> Function(String url)? openExternalUrl;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'AI PRONOTE',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff20211f),
        surface: const Color(0xfffbfaf7),
      ),
      scaffoldBackgroundColor: const Color(0xfff4f2ec),
      useMaterial3: true,
    ),
    home: UpdatePromptHost(
      currentVersion: currentVersion,
      updateChecker: updateChecker,
      openExternalUrl: openExternalUrl,
      child: HomeScreen(
        repository: repository,
        recorder: recorder,
        recordingDirectoryProvider: recordingDirectoryProvider,
        displayVersion: _displayVersion(currentVersion),
      ),
    ),
  );
}

String _displayVersion(String version) {
  final parts = version.split('.');
  return parts.length >= 2 ? '${parts[0]}.${parts[1]}' : version;
}

class UpdatePromptHost extends StatefulWidget {
  const UpdatePromptHost({
    super.key,
    required this.currentVersion,
    required this.child,
    this.updateChecker,
    this.openExternalUrl,
  });

  final String currentVersion;
  final Widget child;
  final UpdateChecker? updateChecker;
  final Future<void> Function(String url)? openExternalUrl;

  @override
  State<UpdatePromptHost> createState() => _UpdatePromptHostState();
}

class _UpdatePromptHostState extends State<UpdatePromptHost> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final checker = widget.updateChecker;
    if (checker == null) return;
    final update = await checker.check(widget.currentVersion);
    if (!mounted || update == null) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('새 버전이 있습니다'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(update.version),
            if (update.notes.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(update.notes),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('나중에'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              await widget.openExternalUrl?.call(update.downloadUrl);
            },
            child: const Text('업데이트 받기'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    required this.recorder,
    this.recordingDirectoryProvider,
    required this.displayVersion,
  });

  final NoteRepository repository;
  final AudioRecorderGateway recorder;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final String displayVersion;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<NoteDocument>> _notes = widget.repository.list();

  Future<void> _newNote() async {
    final note = NoteDocument(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: '제목 없는 노트',
      updatedAt: DateTime.now(),
    );
    await widget.repository.save(note);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
    if (mounted) setState(() => _notes = widget.repository.list());
  }

  Future<void> _openNote(NoteDocument note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
    if (mounted) setState(() => _notes = widget.repository.list());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI PRONOTE',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          Text(
            '버전 ${widget.displayVersion}',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '무엇을 기록할까요?',
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
            ),
            const SizedBox(height: 6),
            Text(
              '노트를 쓰거나 회의 녹음을 시작하세요.',
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: const Color(0xff6b6a65)),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 620;
                final cards = [
                  Expanded(
                    child: _StartCard(
                      key: const ValueKey('start-note-card'),
                      icon: Icons.draw_outlined,
                      title: '새 노트',
                      description: 'Apple Pencil로 쓰고 그리기',
                      primary: true,
                      onTap: _newNote,
                    ),
                  ),
                  if (wide)
                    const SizedBox(width: 14)
                  else
                    const SizedBox(height: 12),
                  Expanded(
                    child: _StartCard(
                      key: const ValueKey('start-recording-card'),
                      icon: Icons.mic_none_rounded,
                      title: '회의 녹음',
                      description: '음성을 남기며 함께 필기하기',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecordingScreen(
                            recorder: widget.recorder,
                            directoryProvider:
                                widget.recordingDirectoryProvider,
                          ),
                        ),
                      ),
                    ),
                  ),
                ];
                return SizedBox(
                  height: wide ? 180 : 308,
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: cards,
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: cards,
                        ),
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              '최근 노트',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<NoteDocument>>(
                future: _notes,
                builder: (context, snapshot) {
                  final notes = snapshot.data ?? const [];
                  if (notes.isEmpty) {
                    return const Align(
                      alignment: Alignment.topLeft,
                      child: Text('아직 저장된 노트가 없습니다.'),
                    );
                  }
                  return ListView.separated(
                    itemCount: notes.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) => Card(
                      child: ListTile(
                        onTap: () => _openNote(notes[index]),
                        leading: const Icon(Icons.description_outlined),
                        title: Text(notes[index].title),
                        subtitle: Text('${notes[index].strokes.length}개 필기 획'),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StartCard extends StatelessWidget {
  const _StartCard({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final foreground = primary ? Colors.white : const Color(0xff20211f);
    return Material(
      color: primary ? const Color(0xff20211f) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: primary ? Colors.white12 : const Color(0xfff1efe8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(icon, color: foreground, size: 30),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: foreground,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: TextStyle(
                      color: primary ? Colors.white70 : const Color(0xff6b6a65),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.recorder,
    this.directoryProvider,
  });

  final AudioRecorderGateway recorder;
  final Future<Directory> Function()? directoryProvider;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _recording = false;
  bool _busy = false;
  String? _message;

  Future<void> _start() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final permitted = await widget.recorder.hasPermission();
      if (!mounted) return;
      if (!permitted) {
        setState(() => _message = '마이크 권한을 허용한 뒤 다시 시도해 주세요.');
        return;
      }
      final recordings =
          await (widget.directoryProvider?.call() ??
              _defaultRecordingDirectory());
      if (!mounted) return;
      final path =
          '${recordings.path}${Platform.pathSeparator}meeting_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await widget.recorder.start(path);
      if (!mounted) return;
      setState(() {
        _recording = true;
        _message = null;
      });
    } catch (_) {
      setState(() => _message = '녹음을 시작하지 못했습니다. 마이크 설정을 확인해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _message = '녹음이 기기에 저장되었습니다.';
      });
    } catch (_) {
      setState(() => _message = '녹음을 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('회의 녹음')),
    body: SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _recording ? Icons.graphic_eq_rounded : Icons.mic_none_rounded,
                size: 72,
                color: _recording ? Colors.redAccent : null,
              ),
              const SizedBox(height: 20),
              Text(
                _recording ? '녹음 중' : '새 회의 녹음',
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _busy ? null : (_recording ? _stop : _start),
                icon: Icon(_recording ? Icons.stop_rounded : Icons.mic_rounded),
                label: Text(_recording ? '녹음 정지' : '녹음 시작'),
              ),
              if (_message != null) ...[
                const SizedBox(height: 20),
                Text(_message!, textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class NoteEditor extends StatefulWidget {
  const NoteEditor({
    super.key,
    required this.repository,
    required this.initialNote,
  });

  final NoteRepository repository;
  final NoteDocument initialNote;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late NoteDocument _note = widget.initialNote;
  InkStroke? _active;
  InkTool _tool = InkTool.pen;
  int _inkColor = 0xff1c1d1a;
  double _inkWidth = 4;
  Timer? _saveTimer;
  final List<List<InkStroke>> _undoHistory = [];
  final List<List<InkStroke>> _redoHistory = [];
  bool _fingerDrawingEnabled = false;

  bool _canDraw(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus ||
      event.kind == PointerDeviceKind.mouse ||
      _fingerDrawingEnabled;

  void _begin(PointerDownEvent event) {
    if (!_canDraw(event)) return;
    if (_tool == InkTool.eraser) {
      _eraseAt(event.localPosition);
      return;
    }
    final point = _point(event.localPosition, event.pressure);
    setState(() {
      _active = InkStroke(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tool: _tool,
        color: _inkColor,
        width: _tool == InkTool.highlighter ? _inkWidth * 4.5 : _inkWidth,
        points: [point],
      );
    });
  }

  void _move(PointerMoveEvent event) {
    if (!_canDraw(event)) return;
    final active = _active;
    if (active == null) return;
    setState(() {
      _active = InkStroke(
        id: active.id,
        tool: active.tool,
        color: active.color,
        width: active.width,
        points: [...active.points, _point(event.localPosition, event.pressure)],
      );
    });
  }

  void _finish(PointerEvent event) {
    if (!_canDraw(event)) return;
    final active = _active;
    if (active == null) return;
    _active = null;
    _commitStrokes([..._note.strokes, active]);
  }

  void _commitStrokes(List<InkStroke> strokes) {
    _undoHistory.add(List<InkStroke>.of(_note.strokes));
    _redoHistory.clear();
    setState(() {
      _note = _note.copyWith(updatedAt: DateTime.now(), strokes: strokes);
      _active = null;
    });
    _scheduleSave();
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    final previous = _undoHistory.removeLast();
    _redoHistory.add(List<InkStroke>.of(_note.strokes));
    setState(
      () =>
          _note = _note.copyWith(updatedAt: DateTime.now(), strokes: previous),
    );
    _scheduleSave();
  }

  void _redo() {
    if (_redoHistory.isEmpty) return;
    final next = _redoHistory.removeLast();
    _undoHistory.add(List<InkStroke>.of(_note.strokes));
    setState(
      () => _note = _note.copyWith(updatedAt: DateTime.now(), strokes: next),
    );
    _scheduleSave();
  }

  void _eraseAt(Offset offset) {
    final hit = _note.strokes.lastIndexWhere(
      (stroke) => stroke.points.any(
        (point) =>
            (Offset(point.x, point.y) - offset).distance <=
            (stroke.width / 2 + 18),
      ),
    );
    if (hit < 0) return;
    final strokes = List<InkStroke>.of(_note.strokes)..removeAt(hit);
    _commitStrokes(strokes);
  }

  InkPoint _point(Offset offset, double pressure) => InkPoint(
    x: offset.dx,
    y: offset.dy,
    pressure: pressure > 0 ? pressure.clamp(0.0, 1.0) : .5,
  );

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 250),
      () => widget.repository.save(_note),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.repository.save(_note);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_note.title),
          const Text(
            '1페이지',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      actions: const [
        Padding(
          padding: EdgeInsets.only(right: 16),
          child: Center(child: Text('자동 저장', style: TextStyle(fontSize: 12))),
        ),
      ],
    ),
    body: Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              SegmentedButton<InkTool>(
                segments: const [
                  ButtonSegment(
                    value: InkTool.pen,
                    label: Text('펜'),
                    icon: Icon(Icons.edit_outlined),
                  ),
                  ButtonSegment(
                    value: InkTool.highlighter,
                    label: Text('형광펜'),
                    icon: Icon(Icons.border_color_outlined),
                  ),
                  ButtonSegment(
                    value: InkTool.eraser,
                    label: Text('지우개'),
                    icon: Icon(Icons.auto_fix_normal_outlined),
                  ),
                ],
                selected: {_tool},
                onSelectionChanged: (tools) =>
                    setState(() => _tool = tools.first),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('undo-ink'),
                tooltip: '실행 취소',
                onPressed: _undoHistory.isEmpty ? null : _undo,
                icon: const Icon(Icons.undo_rounded),
              ),
              IconButton.filledTonal(
                key: const ValueKey('redo-ink'),
                tooltip: '다시 실행',
                onPressed: _redoHistory.isEmpty ? null : _redo,
                icon: const Icon(Icons.redo_rounded),
              ),
              const SizedBox(width: 8),
              for (final color in const [0xff1c1d1a, 0xff315f83, 0xffa8433e])
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    key: ValueKey('ink-color-$color'),
                    onTap: () => setState(() => _inkColor = color),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Color(color),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _inkColor == color
                              ? Colors.white
                              : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: _inkColor == color
                            ? const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 0,
                                  spreadRadius: 2,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                ),
              PopupMenuButton<double>(
                tooltip: '펜 굵기',
                initialValue: _inkWidth,
                onSelected: (value) => setState(() => _inkWidth = value),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 2, child: Text('얇게')),
                  PopupMenuItem(value: 4, child: Text('보통')),
                  PopupMenuItem(value: 8, child: Text('굵게')),
                ],
                icon: const Icon(Icons.line_weight_rounded),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                key: const ValueKey('finger-drawing-toggle'),
                tooltip: _fingerDrawingEnabled ? '손가락 필기 끄기' : '손가락 필기 켜기',
                onPressed: () => setState(
                  () => _fingerDrawingEnabled = !_fingerDrawingEnabled,
                ),
                icon: Icon(
                  _fingerDrawingEnabled
                      ? Icons.touch_app_rounded
                      : Icons.pan_tool_alt_outlined,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _fingerDrawingEnabled ? '손가락 필기' : '손가락 이동',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: InteractiveViewer(
              minScale: .6,
              maxScale: 4,
              panEnabled: !_fingerDrawingEnabled,
              scaleEnabled: !_fingerDrawingEnabled,
              boundaryMargin: const EdgeInsets.all(160),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xffddd9cf)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 18,
                      offset: Offset(0, 6),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: Listener(
                  key: const ValueKey('ink-canvas'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: _begin,
                  onPointerMove: _move,
                  onPointerUp: _finish,
                  onPointerCancel: (_) => setState(() => _active = null),
                  child: CustomPaint(
                    painter: InkPainter(
                      strokes: _note.strokes,
                      active: _active,
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class InkPainter extends CustomPainter {
  const InkPainter({required this.strokes, this.active});

  final List<InkStroke> strokes;
  final InkStroke? active;

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, ?active]) {
      if (stroke.points.isEmpty) continue;
      final color = Color(stroke.color)
          .withValues(alpha: stroke.tool == InkTool.highlighter ? .28 : 1);
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path()..moveTo(stroke.points.first.x, stroke.points.first.y);
      for (final point in stroke.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      final pressure = stroke.points.last.pressure;
      paint.strokeWidth = stroke.width * (.55 + pressure * .65);
      canvas.drawPath(path, paint);
      if (stroke.points.length == 1) {
        canvas.drawCircle(
          Offset(stroke.points.first.x, stroke.points.first.y),
          paint.strokeWidth / 2,
          paint..style = PaintingStyle.fill,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.active != active;
}
