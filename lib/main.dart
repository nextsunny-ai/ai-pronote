import 'dart:async';
import 'dart:io';
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
  runApp(PronoteApp(
    repository: FileNoteRepository(documents),
    recorder: DeviceAudioRecorderGateway(),
    currentVersion: packageInfo.version,
    updateChecker: const RemoteUpdateChecker(
      'https://nextsunny-ai.github.io/ai-pronote/mobile-update.json',
    ),
    openExternalUrl: (url) async {
      await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    },
  ));
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
        builder: (_) => NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
    if (mounted) setState(() => _notes = widget.repository.list());
  }

  Future<void> _openNote(NoteDocument note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => NoteEditor(
          repository: widget.repository,
          initialNote: note,
        ),
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
              const Text('AI PRONOTE', style: TextStyle(fontWeight: FontWeight.w800)),
              Text('버전 ${widget.displayVersion}', style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    FilledButton.icon(
                      onPressed: _newNote,
                      icon: const Icon(Icons.note_add_outlined),
                      label: const Text('새 노트'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => RecordingScreen(
                            recorder: widget.recorder,
                            directoryProvider: widget.recordingDirectoryProvider,
                          ),
                        ),
                      ),
                      icon: const Icon(Icons.mic_none_rounded),
                      label: const Text('회의 녹음'),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                Text('최근 노트', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
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
      final recordings = await (
        widget.directoryProvider?.call() ?? _defaultRecordingDirectory()
      );
      if (!mounted) return;
      final path = '${recordings.path}${Platform.pathSeparator}meeting_${DateTime.now().millisecondsSinceEpoch}.m4a';
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
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
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
  const NoteEditor({super.key, required this.repository, required this.initialNote});

  final NoteRepository repository;
  final NoteDocument initialNote;

  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  late NoteDocument _note = widget.initialNote;
  InkStroke? _active;
  InkTool _tool = InkTool.pen;
  Timer? _saveTimer;

  void _begin(PointerDownEvent event) {
    if (_tool == InkTool.eraser) return;
    final point = _point(event.localPosition, event.pressure);
    setState(() {
      _active = InkStroke(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        tool: _tool,
        color: 0xff1c1d1a,
        width: _tool == InkTool.highlighter ? 18 : 4,
        points: [point],
      );
    });
  }

  void _move(PointerMoveEvent event) {
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
    final active = _active;
    if (active == null) return;
    setState(() {
      _note = _note.copyWith(
        updatedAt: DateTime.now(),
        strokes: [..._note.strokes, active],
      );
      _active = null;
    });
    _scheduleSave();
  }

  InkPoint _point(Offset offset, double pressure) => InkPoint(
        x: offset.dx,
        y: offset.dy,
        pressure: pressure > 0 ? pressure.clamp(0.0, 1.0) : .5,
      );

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 250), () => widget.repository.save(_note));
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
          title: Text(_note.title),
          actions: const [Padding(padding: EdgeInsets.only(right: 16), child: Center(child: Text('자동 저장')))],
        ),
        body: Column(
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: SegmentedButton<InkTool>(
                segments: const [
                  ButtonSegment(value: InkTool.pen, label: Text('펜'), icon: Icon(Icons.edit_outlined)),
                  ButtonSegment(value: InkTool.highlighter, label: Text('형광펜'), icon: Icon(Icons.border_color_outlined)),
                  ButtonSegment(value: InkTool.eraser, label: Text('지우개'), icon: Icon(Icons.auto_fix_normal_outlined)),
                ],
                selected: {_tool},
                onSelectionChanged: (tools) => setState(() => _tool = tools.first),
              ),
            ),
            Expanded(
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xffddd9cf)),
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
                    painter: InkPainter(strokes: _note.strokes, active: _active),
                    size: Size.infinite,
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
      final color = Color(stroke.color).withValues(alpha: stroke.tool == InkTool.highlighter ? .28 : 1);
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
        canvas.drawCircle(Offset(stroke.points.first.x, stroke.points.first.y), paint.strokeWidth / 2, paint..style = PaintingStyle.fill);
      }
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.strokes != strokes || oldDelegate.active != active;
}
