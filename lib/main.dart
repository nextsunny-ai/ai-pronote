import 'dart:async';
import 'package:flutter/material.dart';

import 'notes/note_document.dart';
import 'notes/file_note_repository.dart';
import 'notes/note_repository.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  runApp(PronoteApp(repository: FileNoteRepository(documents)));
}

class PronoteApp extends StatelessWidget {
  const PronoteApp({super.key, required this.repository});

  final NoteRepository repository;

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
        home: HomeScreen(repository: repository),
      );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final NoteRepository repository;

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

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          title: const Text('AI PRONOTE', style: TextStyle(fontWeight: FontWeight.w800)),
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
                      onPressed: () {},
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
