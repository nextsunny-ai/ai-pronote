import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature, PointerDeviceKind;

import 'package:flutter/material.dart';

import 'notes/note_document.dart';
import 'notes/file_note_repository.dart';
import 'notes/note_repository.dart';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'processing/file_processing_job_repository.dart';
import 'processing/local_meeting_processing_gateway.dart';
import 'recording/audio_recorder_gateway.dart';
import 'recording/device_audio_recorder.dart';
import 'recording/device_video_recorder.dart';
import 'recording/video_recorder_gateway.dart';
import 'update/update_checker.dart';

Future<Directory> _defaultRecordingDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final recordings = Directory(
    '${documents.path}${Platform.pathSeparator}recordings',
  );
  await recordings.create(recursive: true);
  return recordings;
}

Future<Directory> _defaultVideoDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  final videos = Directory('${documents.path}${Platform.pathSeparator}videos');
  await videos.create(recursive: true);
  return videos;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await getApplicationDocumentsDirectory();
  final packageInfo = await PackageInfo.fromPlatform();
  runApp(
    PronoteApp(
      repository: FileNoteRepository(documents),
      recorder: DeviceAudioRecorderGateway(),
      videoRecorderFactory: DeviceVideoRecorderGateway.new,
      processingGateway:
          Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? LocalMeetingProcessingGateway(
              baseUri: Uri.parse('http://127.0.0.1:8795'),
            )
          : null,
      processingJobRepository: FileProcessingJobRepository(documents),
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
    this.videoRecorderFactory,
    this.processingGateway,
    this.processingJobRepository,
    this.recordingDirectoryProvider,
    this.recordingValidator,
    this.currentVersion = '1.0.0',
    this.updateChecker,
    this.openExternalUrl,
  });

  final NoteRepository repository;
  final AudioRecorderGateway recorder;
  final VideoRecorderGateway Function()? videoRecorderFactory;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final Future<bool> Function(String path)? recordingValidator;
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
        videoRecorderFactory: videoRecorderFactory,
        processingGateway: processingGateway,
        processingJobRepository: processingJobRepository,
        recordingDirectoryProvider: recordingDirectoryProvider,
        recordingValidator: recordingValidator,
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
    this.videoRecorderFactory,
    this.processingGateway,
    this.processingJobRepository,
    this.recordingDirectoryProvider,
    this.recordingValidator,
    required this.displayVersion,
  });

  final NoteRepository repository;
  final AudioRecorderGateway recorder;
  final VideoRecorderGateway Function()? videoRecorderFactory;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final Future<bool> Function(String path)? recordingValidator;
  final String displayVersion;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _NoteSort { updated, title }

class _HomeScreenState extends State<HomeScreen> {
  late Future<List<NoteDocument>> _notes = widget.repository.list();
  late Future<List<ProcessingJobRecord>> _processingJobs =
      widget.processingJobRepository?.list() ??
      Future.value(const <ProcessingJobRecord>[]);
  String _query = '';
  bool _favoritesOnly = false;
  _NoteSort _sort = _NoteSort.updated;

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
    if (mounted) {
      setState(() {
        _notes = widget.repository.list();
      });
    }
  }

  Future<void> _openNote(NoteDocument note) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
    if (mounted) {
      setState(() {
        _notes = widget.repository.list();
      });
    }
  }

  Future<void> _toggleFavorite(NoteDocument note) async {
    await widget.repository.save(
      note.copyWith(isFavorite: !note.isFavorite, updatedAt: DateTime.now()),
    );
    if (mounted) {
      setState(() {
        _notes = widget.repository.list();
      });
    }
  }

  Future<void> _chooseMeetingMode() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '회의 기록 방식',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text('음성만 녹음하거나 카메라 영상과 음성을 함께 남길 수 있습니다.'),
                const SizedBox(height: 18),
                ListTile(
                  key: const ValueKey('meeting-audio-mode'),
                  leading: const Icon(Icons.mic_rounded),
                  title: const Text('음성 녹음'),
                  subtitle: const Text('가볍게 녹음하며 회의 노트 필기'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RecordingScreen(
                          recorder: widget.recorder,
                          repository: widget.repository,
                          processingGateway: widget.processingGateway,
                          processingJobRepository:
                              widget.processingJobRepository,
                          directoryProvider: widget.recordingDirectoryProvider,
                          recordingValidator: widget.recordingValidator,
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _processingJobs =
                            widget.processingJobRepository?.list() ??
                            Future.value(const <ProcessingJobRecord>[]);
                      });
                    }
                  },
                ),
                const Divider(),
                ListTile(
                  key: const ValueKey('meeting-video-mode'),
                  leading: const Icon(Icons.videocam_rounded),
                  title: const Text('영상 + 음성 녹화'),
                  subtitle: const Text('카메라로 칠판과 현장을 함께 기록'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => VideoRecordingScreen(
                          recorder:
                              (widget.videoRecorderFactory ??
                                      () =>
                                          const DisabledVideoRecorderGateway())
                                  .call(),
                          repository: widget.repository,
                          processingGateway: widget.processingGateway,
                          processingJobRepository:
                              widget.processingJobRepository,
                        ),
                      ),
                    );
                    if (mounted) {
                      setState(() {
                        _processingJobs =
                            widget.processingJobRepository?.list() ??
                            Future.value(const <ProcessingJobRecord>[]);
                      });
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
        child: ListView(
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
                      title: '회의 기록',
                      description: '음성 또는 영상으로 기록하며 필기',
                      onTap: _chooseMeetingMode,
                    ),
                  ),
                ];
                return SizedBox(
                  height: wide ? 120 : 220,
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
            FutureBuilder<List<ProcessingJobRecord>>(
              future: _processingJobs,
              builder: (context, snapshot) {
                final jobs = snapshot.data ?? const <ProcessingJobRecord>[];
                if (jobs.isEmpty || widget.processingGateway == null) {
                  return const SizedBox.shrink();
                }
                final latest = jobs.first;
                final filename = latest.recordingPath
                    .replaceAll('\\', '/')
                    .split('/')
                    .last;
                return Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '지난 받아쓰기 작업',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        margin: EdgeInsets.zero,
                        child: ListTile(
                          key: ValueKey('resume-job-${latest.jobId}'),
                          leading: const Icon(Icons.history_rounded),
                          title: Text(filename),
                          subtitle: Text('작업번호 ${latest.jobId}'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => TranscriptionResultScreen(
                                gateway: widget.processingGateway!,
                                jobId: latest.jobId,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 28),
            Text(
              '내 노트',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SearchBar(
              key: const ValueKey('note-search'),
              hintText: '노트 제목 검색',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(Colors.white),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilterChip(
                  key: const ValueKey('favorites-filter'),
                  selected: _favoritesOnly,
                  avatar: const Icon(Icons.star_outline_rounded, size: 18),
                  label: const Text('즐겨찾기'),
                  onSelected: (selected) =>
                      setState(() => _favoritesOnly = selected),
                ),
                const Spacer(),
                PopupMenuButton<_NoteSort>(
                  key: const ValueKey('note-sort'),
                  tooltip: '노트 정렬',
                  initialValue: _sort,
                  onSelected: (value) => setState(() => _sort = value),
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: _NoteSort.updated,
                      child: Text('최근 수정순'),
                    ),
                    PopupMenuItem(value: _NoteSort.title, child: Text('제목순')),
                  ],
                  child: Row(
                    children: [
                      const Icon(Icons.sort_rounded, size: 20),
                      const SizedBox(width: 5),
                      Text(_sort == _NoteSort.updated ? '최근 수정순' : '제목순'),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FutureBuilder<List<NoteDocument>>(
              future: _notes,
              builder: (context, snapshot) {
                final notes = snapshot.data ?? const [];
                final visible = notes
                    .where(
                      (note) =>
                          (!_favoritesOnly || note.isFavorite) &&
                          note.title.toLowerCase().contains(
                            _query.toLowerCase(),
                          ),
                    )
                    .toList(growable: false);
                visible.sort(
                  _sort == _NoteSort.updated
                      ? (a, b) => b.updatedAt.compareTo(a.updatedAt)
                      : (a, b) => a.title.compareTo(b.title),
                );
                if (notes.isEmpty) {
                  return const Align(
                    alignment: Alignment.topLeft,
                    child: Text('아직 저장된 노트가 없습니다.'),
                  );
                }
                if (visible.isEmpty) {
                  return const Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('검색 결과가 없습니다.'),
                    ),
                  );
                }
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 330,
                    mainAxisExtent: 150,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemCount: visible.length,
                  itemBuilder: (context, index) => _NoteLibraryCard(
                    note: visible[index],
                    onTap: () => _openNote(visible[index]),
                    onFavorite: () => _toggleFavorite(visible[index]),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ),
  );
}

class _NoteLibraryCard extends StatelessWidget {
  const _NoteLibraryCard({
    required this.note,
    required this.onTap,
    required this.onFavorite,
  });

  final NoteDocument note;
  final VoidCallback onTap;
  final VoidCallback onFavorite;

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xfff1efe8),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(Icons.edit_note_rounded),
                ),
                const Spacer(),
                IconButton(
                  key: ValueKey('favorite-note-${note.id}'),
                  tooltip: note.isFavorite ? '즐겨찾기 해제' : '즐겨찾기',
                  onPressed: onFavorite,
                  icon: Icon(
                    note.isFavorite
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    color: note.isFavorite ? const Color(0xffd79b28) : null,
                  ),
                ),
                Text(
                  '${note.pages.length}페이지',
                  style: Theme.of(context).textTheme.labelMedium
                      ?.copyWith(color: const Color(0xff77746d)),
                ),
              ],
            ),
            const Spacer(),
            Text(
              note.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              '${note.updatedAt.year}.${note.updatedAt.month.toString().padLeft(2, '0')}.${note.updatedAt.day.toString().padLeft(2, '0')}',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: const Color(0xff77746d)),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 140;
            final iconBox = DecoratedBox(
              decoration: BoxDecoration(
                color: primary ? Colors.white12 : const Color(0xfff1efe8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: EdgeInsets.all(compact ? 10 : 12),
                child: Icon(icon, color: foreground, size: compact ? 26 : 30),
              ),
            );
            final copy = Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: foreground,
                    fontSize: compact ? 18 : 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: primary ? Colors.white70 : const Color(0xff6b6a65),
                  ),
                ),
              ],
            );
            return Padding(
              padding: EdgeInsets.all(compact ? 14 : 22),
              child: compact
                  ? Row(
                      children: [
                        iconBox,
                        const SizedBox(width: 14),
                        Expanded(child: copy),
                        Icon(Icons.chevron_right_rounded, color: foreground),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [iconBox, copy],
                    ),
            );
          },
        ),
      ),
    );
  }
}

class TranscriptionResultScreen extends StatefulWidget {
  const TranscriptionResultScreen({
    super.key,
    required this.gateway,
    required this.jobId,
  });

  final MeetingProcessingGateway gateway;
  final String jobId;

  @override
  State<TranscriptionResultScreen> createState() =>
      _TranscriptionResultScreenState();
}

class _TranscriptionResultScreenState extends State<TranscriptionResultScreen> {
  MeetingProcessingJob? _job;
  MeetingProcessingResult? _result;
  String? _error;
  Timer? _pollTimer;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    _pollTimer?.cancel();
    try {
      final job = await widget.gateway.readJob(widget.jobId);
      if (!mounted) return;
      if (job.status == 'done') {
        final result = await widget.gateway.readResult(widget.jobId);
        if (!mounted) return;
        setState(() {
          _job = job;
          _result = result;
          _error = null;
          _loading = false;
        });
        return;
      }
      if (job.status == 'error' || job.status == 'interrupted') {
        setState(() {
          _job = job;
          _error = job.phase.isEmpty ? '받아쓰기를 완료하지 못했습니다.' : job.phase;
          _loading = false;
        });
        return;
      }
      setState(() {
        _job = job;
        _error = null;
        _loading = false;
      });
      _pollTimer = Timer(const Duration(seconds: 1), _refresh);
    } on MeetingProcessingException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '받아쓰기 상태를 확인하지 못했습니다. 작업 결과는 삭제되지 않습니다.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = _job;
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('받아쓰기 결과')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (result == null && _error == null) ...[
              LinearProgressIndicator(
                value: job != null && job.progress > 0
                    ? job.progress.clamp(0, 100) / 100
                    : null,
              ),
              const SizedBox(height: 16),
              Text(
                job?.phase.isNotEmpty == true ? job!.phase : '받아쓰기 준비 중',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              const Text('이 화면을 닫아도 녹음 원본과 서버 작업은 보존됩니다.'),
            ],
            if (_loading && result == null && _error != null)
              const Center(child: CircularProgressIndicator()),
            if (_error != null) ...[
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _loading
                    ? null
                    : () {
                        setState(() {
                          _loading = true;
                          _error = null;
                        });
                        _refresh();
                      },
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('다시 확인'),
              ),
            ],
            if (result != null) ...[
              Text(
                result.filename.isEmpty ? '받아쓰기' : result.filename,
                style: Theme.of(context).textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 20),
              Text(
                '받아쓰기',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              SelectableText(
                result.transcript.isEmpty
                    ? '인식된 말소리가 없습니다.'
                    : result.transcript,
              ),
              if (result.summary.isNotEmpty) ...[
                const SizedBox(height: 28),
                Text(
                  result.summaryTitle.isEmpty ? 'AI 회의록' : result.summaryTitle,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SelectableText(result.summary),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class RecordingScreen extends StatefulWidget {
  const RecordingScreen({
    super.key,
    required this.recorder,
    required this.repository,
    this.processingGateway,
    this.processingJobRepository,
    this.directoryProvider,
    this.recordingValidator,
  });

  final AudioRecorderGateway recorder;
  final NoteRepository repository;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final Future<Directory> Function()? directoryProvider;
  final Future<bool> Function(String path)? recordingValidator;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen> {
  bool _recording = false;
  bool _paused = false;
  bool _busy = false;
  String? _message;
  String? _activePath;
  String? _savedPath;
  Timer? _ticker;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _elapsedLabel {
    final duration = _elapsed.elapsed;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

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
      _elapsed
        ..reset()
        ..start();
      _startTicker();
      setState(() {
        _recording = true;
        _paused = false;
        _activePath = path;
        _savedPath = null;
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
      final savedPath = await widget.recorder.stop();
      if (!mounted) return;
      _elapsed.stop();
      _ticker?.cancel();
      final path = savedPath ?? _activePath;
      final file = path == null ? null : File(path);
      final saved =
          path != null &&
          (widget.recordingValidator != null
              ? await widget.recordingValidator!(path)
              : file != null && await file.exists() && await file.length() > 0);
      if (!mounted) return;
      setState(() {
        _recording = false;
        _paused = false;
        _activePath = null;
        _savedPath = saved ? path : null;
        _message = saved
            ? '녹음이 기기에 저장되었습니다.\n$path'
            : '녹음 파일을 확인하지 못했습니다. 저장 공간을 확인해 주세요.';
      });
    } catch (_) {
      setState(() => _message = '녹음을 저장하지 못했습니다. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTranscription() async {
    final gateway = widget.processingGateway;
    final path = _savedPath;
    if (_busy || gateway == null || path == null) return;
    setState(() {
      _busy = true;
      _message = '받아쓰기 작업을 준비하고 있습니다…';
    });
    try {
      final job = await gateway.submitTranscription(path);
      await widget.processingJobRepository?.save(
        ProcessingJobRecord(
          jobId: job.id,
          recordingPath: path,
          createdAt: DateTime.now(),
          status: job.status,
        ),
      );
      if (!mounted) return;
      setState(() {
        _message = '받아쓰기 작업을 시작했습니다.\n작업번호 ${job.id}';
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TranscriptionResultScreen(gateway: gateway, jobId: job.id),
        ),
      );
    } on MeetingProcessingException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = '받아쓰기를 시작하지 못했습니다. 녹음 원본은 기기에 그대로 보존되어 있습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePause() async {
    if (_busy || !_recording) return;
    setState(() => _busy = true);
    try {
      if (_paused) {
        await widget.recorder.resume();
        _elapsed.start();
      } else {
        await widget.recorder.pause();
        _elapsed.stop();
      }
      if (!mounted) return;
      setState(() {
        _paused = !_paused;
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = '녹음 상태를 바꾸지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMeetingNote() async {
    final now = DateTime.now();
    final note = NoteDocument(
      id: now.microsecondsSinceEpoch.toString(),
      title:
          '회의 노트 ${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}',
      updatedAt: now,
    );
    await widget.repository.save(note);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_recording) return true;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('녹음이 진행 중입니다'),
        content: const Text('화면을 닫기 전에 녹음을 정지하고 안전하게 저장해 주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 녹음'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('정지하고 나가기'),
          ),
        ],
      ),
    );
    if (stop != true) return false;
    await _stop();
    return !_recording;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_recording,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || !_recording) return;
      if (await _confirmLeave() && context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('회의 녹음')),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _recording
                      ? Icons.graphic_eq_rounded
                      : Icons.mic_none_rounded,
                  size: 72,
                  color: _recording ? Colors.redAccent : null,
                ),
                const SizedBox(height: 20),
                Text(
                  _paused ? '일시정지' : (_recording ? '녹음 중' : '새 회의 녹음'),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (_recording) ...[
                  const SizedBox(height: 8),
                  Text(
                    _elapsedLabel,
                    key: const ValueKey('recording-elapsed'),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      onPressed: _busy ? null : (_recording ? _stop : _start),
                      icon: Icon(
                        _recording ? Icons.stop_rounded : Icons.mic_rounded,
                      ),
                      label: Text(_recording ? '녹음 정지' : '녹음 시작'),
                    ),
                    if (_recording)
                      OutlinedButton.icon(
                        key: const ValueKey('pause-recording'),
                        onPressed: _busy ? null : _togglePause,
                        icon: Icon(
                          _paused
                              ? Icons.play_arrow_rounded
                              : Icons.pause_rounded,
                        ),
                        label: Text(_paused ? '계속 녹음' : '일시정지'),
                      ),
                    OutlinedButton.icon(
                      key: const ValueKey('open-meeting-note'),
                      onPressed: _busy ? null : _openMeetingNote,
                      icon: const Icon(Icons.draw_outlined),
                      label: Text(_recording ? '녹음하며 필기' : '회의 노트 열기'),
                    ),
                    if (!_recording &&
                        _savedPath != null &&
                        widget.processingGateway != null)
                      FilledButton.tonalIcon(
                        key: const ValueKey('start-transcription'),
                        onPressed: _busy ? null : _startTranscription,
                        icon: const Icon(Icons.text_snippet_outlined),
                        label: const Text('받아쓰기 시작'),
                      ),
                  ],
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
    ),
  );
}

class VideoRecordingScreen extends StatefulWidget {
  const VideoRecordingScreen({
    super.key,
    required this.recorder,
    required this.repository,
    this.processingGateway,
    this.processingJobRepository,
    this.directoryProvider,
    this.recordingValidator,
  });

  final VideoRecorderGateway recorder;
  final NoteRepository repository;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final Future<Directory> Function()? directoryProvider;
  final Future<bool> Function(String path)? recordingValidator;

  @override
  State<VideoRecordingScreen> createState() => _VideoRecordingScreenState();
}

class _VideoRecordingScreenState extends State<VideoRecordingScreen> {
  bool _ready = false;
  bool _recording = false;
  bool _busy = true;
  String? _message;
  String? _destinationPath;
  String? _savedPath;
  Timer? _ticker;
  final Stopwatch _elapsed = Stopwatch();

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    unawaited(widget.recorder.dispose());
    super.dispose();
  }

  String get _elapsedLabel {
    final duration = _elapsed.elapsed;
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  Future<void> _initialize() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await widget.recorder.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ready = false;
        _message = '카메라와 마이크를 준비하지 못했습니다. 기기 권한을 확인해 주세요.';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _start() async {
    if (_busy || !_ready) return;
    setState(() => _busy = true);
    try {
      final directory =
          await (widget.directoryProvider?.call() ?? _defaultVideoDirectory());
      final path =
          '${directory.path}${Platform.pathSeparator}meeting_${DateTime.now().millisecondsSinceEpoch}.mp4';
      await widget.recorder.start();
      if (!mounted) return;
      _elapsed
        ..reset()
        ..start();
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
      setState(() {
        _destinationPath = path;
        _savedPath = null;
        _recording = true;
        _message = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = '영상 녹화를 시작하지 못했습니다. 카메라 설정을 확인해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    if (_busy || !_recording || _destinationPath == null) return;
    setState(() => _busy = true);
    try {
      final path = await widget.recorder.stop(_destinationPath!);
      _elapsed.stop();
      _ticker?.cancel();
      final saved = widget.recordingValidator != null
          ? await widget.recordingValidator!(path)
          : await File(path).exists() && await File(path).length() > 0;
      if (!mounted) return;
      setState(() {
        _recording = false;
        _destinationPath = null;
        _savedPath = saved ? path : null;
        _message = saved
            ? '영상과 음성이 기기에 저장되었습니다.\n$path'
            : '영상 파일을 확인하지 못했습니다. 저장 공간을 확인해 주세요.';
      });
    } catch (_) {
      if (mounted) {
        setState(() => _message = '영상 녹화를 저장하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _startTranscription() async {
    final gateway = widget.processingGateway;
    final path = _savedPath;
    if (_busy || gateway == null || path == null) return;
    setState(() {
      _busy = true;
      _message = '받아쓰기 작업을 준비하고 있습니다…';
    });
    try {
      final job = await gateway.submitTranscription(path);
      await widget.processingJobRepository?.save(
        ProcessingJobRecord(
          jobId: job.id,
          recordingPath: path,
          createdAt: DateTime.now(),
          status: job.status,
        ),
      );
      if (!mounted) return;
      setState(() {
        _message = '받아쓰기 작업을 시작했습니다.\n작업번호 ${job.id}';
      });
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              TranscriptionResultScreen(gateway: gateway, jobId: job.id),
        ),
      );
    } on MeetingProcessingException catch (error) {
      if (!mounted) return;
      setState(() => _message = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _message = '받아쓰기를 시작하지 못했습니다. 영상 원본은 기기에 그대로 보존되어 있습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openMeetingNote() async {
    final now = DateTime.now();
    final note = NoteDocument(
      id: now.microsecondsSinceEpoch.toString(),
      title:
          '영상 회의 노트 ${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}',
      updatedAt: now,
    );
    await widget.repository.save(note);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            NoteEditor(repository: widget.repository, initialNote: note),
      ),
    );
  }

  Future<bool> _confirmLeave() async {
    if (!_recording) return true;
    final stop = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('영상 녹화가 진행 중입니다'),
        content: const Text('화면을 닫기 전에 녹화를 정지하고 안전하게 저장해 주세요.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 녹화'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('정지하고 나가기'),
          ),
        ],
      ),
    );
    if (stop != true) return false;
    await _stop();
    return !_recording;
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_recording,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || !_recording) return;
      if (await _confirmLeave() && context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('영상 + 음성 녹화')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: ColoredBox(
                    color: Colors.black,
                    child: Center(
                      child: _ready
                          ? AspectRatio(
                              aspectRatio: widget.recorder.aspectRatio,
                              child: widget.recorder.buildPreview(),
                            )
                          : _busy
                          ? const CircularProgressIndicator()
                          : const Icon(
                              Icons.videocam_off_outlined,
                              size: 64,
                              color: Colors.white70,
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (_recording)
                Text(
                  '녹화 중  $_elapsedLabel',
                  key: const ValueKey('video-recording-elapsed'),
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.redAccent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 8),
                Text(_message!, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    key: const ValueKey('toggle-video-recording'),
                    onPressed: _busy || !_ready
                        ? null
                        : (_recording ? _stop : _start),
                    icon: Icon(
                      _recording
                          ? Icons.stop_rounded
                          : Icons.fiber_manual_record_rounded,
                    ),
                    label: Text(_recording ? '녹화 정지' : '녹화 시작'),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('open-video-meeting-note'),
                    onPressed: _busy ? null : _openMeetingNote,
                    icon: const Icon(Icons.draw_outlined),
                    label: Text(_recording ? '녹화하며 필기' : '회의 노트 열기'),
                  ),
                  if (!_recording &&
                      _savedPath != null &&
                      widget.processingGateway != null)
                    FilledButton.tonalIcon(
                      key: const ValueKey('start-video-transcription'),
                      onPressed: _busy ? null : _startTranscription,
                      icon: const Icon(Icons.text_snippet_outlined),
                      label: const Text('받아쓰기 시작'),
                    ),
                  if (!_ready && !_busy)
                    TextButton.icon(
                      onPressed: _initialize,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('카메라 다시 연결'),
                    ),
                ],
              ),
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
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  InkStroke? _active;
  InkTool _tool = InkTool.pen;
  int _inkColor = 0xff1c1d1a;
  double _inkWidth = 4;
  Timer? _saveTimer;
  final List<List<InkStroke>> _undoHistory = [];
  final List<List<InkStroke>> _redoHistory = [];
  bool _fingerDrawingEnabled = false;
  int _currentPageIndex = 0;
  Rect? _selectionRect;
  Set<String> _selectedStrokeIds = {};
  Offset? _lassoStart;
  Offset? _dragStart;
  Rect? _dragOriginRect;
  List<InkStroke>? _dragOriginalStrokes;
  late bool _showTextBody;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: _note.title);
    _bodyController = TextEditingController(text: _note.body);
    _showTextBody = _note.body.isNotEmpty;
  }

  List<InkStroke> get _currentStrokes => _note.pages[_currentPageIndex].strokes;

  NoteDocument _withCurrentStrokes(List<InkStroke> strokes) {
    final pages = List<NotePage>.of(_note.pages);
    pages[_currentPageIndex] = pages[_currentPageIndex].copyWith(
      strokes: strokes,
    );
    return _note.copyWith(updatedAt: DateTime.now(), pages: pages);
  }

  bool _canDraw(PointerEvent event) =>
      event.kind == PointerDeviceKind.stylus ||
      event.kind == PointerDeviceKind.invertedStylus ||
      event.kind == PointerDeviceKind.mouse ||
      _fingerDrawingEnabled;

  void _begin(PointerDownEvent event) {
    if (!_canDraw(event)) return;
    if (_tool == InkTool.lasso) {
      final position = event.localPosition;
      if (_selectionRect?.contains(position) == true &&
          _selectedStrokeIds.isNotEmpty) {
        _dragStart = position;
        _dragOriginRect = _selectionRect;
        _dragOriginalStrokes = List<InkStroke>.of(_currentStrokes);
      } else {
        setState(() {
          _lassoStart = position;
          _selectionRect = Rect.fromPoints(position, position);
          _selectedStrokeIds = {};
        });
      }
      return;
    }
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
    if (_tool == InkTool.lasso) {
      if (_dragStart != null && _dragOriginalStrokes != null) {
        final delta = event.localPosition - _dragStart!;
        final moved = _dragOriginalStrokes!
            .map(
              (stroke) => _selectedStrokeIds.contains(stroke.id)
                  ? InkStroke(
                      id: stroke.id,
                      tool: stroke.tool,
                      color: stroke.color,
                      width: stroke.width,
                      points: stroke.points
                          .map(
                            (point) => InkPoint(
                              x: point.x + delta.dx,
                              y: point.y + delta.dy,
                              pressure: point.pressure,
                            ),
                          )
                          .toList(growable: false),
                    )
                  : stroke,
            )
            .toList(growable: false);
        setState(() {
          _note = _withCurrentStrokes(moved);
          _selectionRect = _dragOriginRect?.shift(delta);
        });
      } else if (_lassoStart != null) {
        setState(
          () => _selectionRect = Rect.fromPoints(
            _lassoStart!,
            event.localPosition,
          ),
        );
      }
      return;
    }
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
    if (_tool == InkTool.lasso) {
      if (_dragStart != null && _dragOriginalStrokes != null) {
        _undoHistory.add(_dragOriginalStrokes!);
        _redoHistory.clear();
        _dragStart = null;
        _dragOriginRect = null;
        _dragOriginalStrokes = null;
        _scheduleSave();
      } else if (_selectionRect != null) {
        final area = _selectionRect!;
        setState(() {
          _selectedStrokeIds = _currentStrokes
              .where(
                (stroke) => stroke.points.any(
                  (point) => area.contains(Offset(point.x, point.y)),
                ),
              )
              .map((stroke) => stroke.id)
              .toSet();
          _lassoStart = null;
          if (_selectedStrokeIds.isEmpty) _selectionRect = null;
        });
      }
      return;
    }
    final active = _active;
    if (active == null) return;
    _active = null;
    _commitStrokes([..._currentStrokes, active]);
  }

  void _commitStrokes(List<InkStroke> strokes) {
    _undoHistory.add(List<InkStroke>.of(_currentStrokes));
    _redoHistory.clear();
    setState(() {
      _note = _withCurrentStrokes(strokes);
      _active = null;
    });
    _scheduleSave();
  }

  void _undo() {
    if (_undoHistory.isEmpty) return;
    final previous = _undoHistory.removeLast();
    _redoHistory.add(List<InkStroke>.of(_currentStrokes));
    setState(() => _note = _withCurrentStrokes(previous));
    _scheduleSave();
  }

  void _redo() {
    if (_redoHistory.isEmpty) return;
    final next = _redoHistory.removeLast();
    _undoHistory.add(List<InkStroke>.of(_currentStrokes));
    setState(() => _note = _withCurrentStrokes(next));
    _scheduleSave();
  }

  void _eraseAt(Offset offset) {
    final hit = _currentStrokes.lastIndexWhere(
      (stroke) => stroke.points.any(
        (point) =>
            (Offset(point.x, point.y) - offset).distance <=
            (stroke.width / 2 + 18),
      ),
    );
    if (hit < 0) return;
    final strokes = List<InkStroke>.of(_currentStrokes)..removeAt(hit);
    _commitStrokes(strokes);
  }

  void _goToPage(int index) {
    if (index < 0 || index >= _note.pages.length) return;
    setState(() {
      _currentPageIndex = index;
      _active = null;
      _undoHistory.clear();
      _redoHistory.clear();
    });
  }

  void _addPage() {
    final page = NotePage(id: 'page-${DateTime.now().microsecondsSinceEpoch}');
    setState(() {
      _note = _note.copyWith(
        updatedAt: DateTime.now(),
        pages: [..._note.pages, page],
      );
      _currentPageIndex = _note.pages.length - 1;
      _active = null;
      _undoHistory.clear();
      _redoHistory.clear();
    });
    _scheduleSave();
  }

  void _duplicatePage() {
    final source = _note.pages[_currentPageIndex];
    final now = DateTime.now().microsecondsSinceEpoch;
    final duplicate = NotePage(
      id: 'page-$now',
      strokes: source.strokes
          .map(
            (stroke) => InkStroke(
              id: '${stroke.id}-page-copy-$now',
              tool: stroke.tool,
              color: stroke.color,
              width: stroke.width,
              points: List<InkPoint>.of(stroke.points),
            ),
          )
          .toList(growable: false),
    );
    final pages = List<NotePage>.of(_note.pages)
      ..insert(_currentPageIndex + 1, duplicate);
    setState(() {
      _note = _note.copyWith(updatedAt: DateTime.now(), pages: pages);
      _currentPageIndex += 1;
      _selectionRect = null;
      _selectedStrokeIds = {};
      _undoHistory.clear();
      _redoHistory.clear();
    });
    _scheduleSave();
  }

  void _deletePage() {
    if (_note.pages.length == 1) return;
    final pages = List<NotePage>.of(_note.pages)..removeAt(_currentPageIndex);
    setState(() {
      _note = _note.copyWith(updatedAt: DateTime.now(), pages: pages);
      if (_currentPageIndex >= pages.length) {
        _currentPageIndex = pages.length - 1;
      }
      _selectionRect = null;
      _selectedStrokeIds = {};
      _undoHistory.clear();
      _redoHistory.clear();
    });
    _scheduleSave();
  }

  void _deleteSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    _commitStrokes(
      _currentStrokes
          .where((stroke) => !_selectedStrokeIds.contains(stroke.id))
          .toList(growable: false),
    );
    setState(() {
      _selectionRect = null;
      _selectedStrokeIds = {};
    });
  }

  void _duplicateSelection() {
    if (_selectedStrokeIds.isEmpty) return;
    final now = DateTime.now().microsecondsSinceEpoch;
    final copies = _currentStrokes
        .where((stroke) => _selectedStrokeIds.contains(stroke.id))
        .map(
          (stroke) => InkStroke(
            id: '${stroke.id}-copy-$now',
            tool: stroke.tool,
            color: stroke.color,
            width: stroke.width,
            points: stroke.points
                .map(
                  (point) => InkPoint(
                    x: point.x + 24,
                    y: point.y + 24,
                    pressure: point.pressure,
                  ),
                )
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    _commitStrokes([..._currentStrokes, ...copies]);
    setState(() {
      _selectedStrokeIds = copies.map((stroke) => stroke.id).toSet();
      _selectionRect = _selectionRect?.shift(const Offset(24, 24));
    });
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
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('note-title-field'),
              controller: _titleController,
              maxLines: 1,
              style: const TextStyle(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (value) {
                final title = value.trim().isEmpty ? '제목 없는 노트' : value;
                _note = _note.copyWith(title: title, updatedAt: DateTime.now());
                _scheduleSave();
              },
            ),
          ),
          Text(
            '${_currentPageIndex + 1}/${_note.pages.length} 페이지',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      actions: [
        IconButton(
          key: const ValueKey('note-body-toggle'),
          tooltip: _showTextBody ? '텍스트 본문 닫기' : '텍스트 본문 열기',
          onPressed: () => setState(() => _showTextBody = !_showTextBody),
          icon: Icon(
            _showTextBody ? Icons.subject_rounded : Icons.subject_outlined,
          ),
        ),
        const Padding(
          padding: EdgeInsets.only(right: 16),
          child: Center(child: Text('자동 저장', style: TextStyle(fontSize: 12))),
        ),
      ],
    ),
    body: Column(
      children: [
        Container(
          height: 46,
          margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                key: const ValueKey('previous-page'),
                tooltip: '이전 페이지',
                onPressed: _currentPageIndex == 0
                    ? null
                    : () => _goToPage(_currentPageIndex - 1),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Text(
                '${_currentPageIndex + 1} / ${_note.pages.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              IconButton(
                key: const ValueKey('next-page'),
                tooltip: '다음 페이지',
                onPressed: _currentPageIndex == _note.pages.length - 1
                    ? null
                    : () => _goToPage(_currentPageIndex + 1),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
              const VerticalDivider(indent: 10, endIndent: 10),
              IconButton(
                key: const ValueKey('add-page'),
                tooltip: '새 페이지',
                onPressed: _addPage,
                icon: const Icon(Icons.note_add_outlined),
              ),
              IconButton(
                key: const ValueKey('duplicate-page'),
                tooltip: '현재 페이지 복제',
                onPressed: _duplicatePage,
                icon: const Icon(Icons.copy_all_rounded),
              ),
              IconButton(
                key: const ValueKey('delete-page'),
                tooltip: '현재 페이지 삭제',
                onPressed: _note.pages.length == 1 ? null : _deletePage,
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
            ],
          ),
        ),
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
                  ButtonSegment(
                    value: InkTool.lasso,
                    label: Text('올가미'),
                    icon: Icon(Icons.gesture_rounded),
                  ),
                ],
                selected: {_tool},
                onSelectionChanged: (tools) =>
                    setState(() => _tool = tools.first),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                key: const ValueKey('duplicate-selection'),
                tooltip: '선택 복제',
                onPressed: _selectedStrokeIds.isEmpty
                    ? null
                    : _duplicateSelection,
                icon: const Icon(Icons.copy_rounded),
              ),
              IconButton.filledTonal(
                key: const ValueKey('delete-selection'),
                tooltip: '선택 삭제',
                onPressed: _selectedStrokeIds.isEmpty ? null : _deleteSelection,
                icon: const Icon(Icons.delete_outline_rounded),
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
        if (_showTextBody)
          Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xffddd9cf)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('note-body-field'),
                    controller: _bodyController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: '텍스트 본문',
                      hintText: '회의 내용이나 메모를 입력하세요.',
                      border: InputBorder.none,
                      alignLabelWithHint: true,
                    ),
                    onChanged: (value) {
                      _note = _note.copyWith(
                        body: value,
                        updatedAt: DateTime.now(),
                      );
                      _scheduleSave();
                    },
                  ),
                ),
                IconButton(
                  tooltip: '텍스트 본문 접기',
                  onPressed: () => setState(() => _showTextBody = false),
                  icon: const Icon(Icons.close_rounded),
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
              panEnabled: !_fingerDrawingEnabled && _tool != InkTool.lasso,
              scaleEnabled: !_fingerDrawingEnabled && _tool != InkTool.lasso,
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
                      strokes: _currentStrokes,
                      active: _active,
                      selectionRect: _selectionRect,
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
  const InkPainter({required this.strokes, this.active, this.selectionRect});

  final List<InkStroke> strokes;
  final InkStroke? active;
  final Rect? selectionRect;

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
    final selection = selectionRect;
    if (selection != null) {
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0x181f6feb)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        selection,
        Paint()
          ..color = const Color(0xff1f6feb)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.strokes != strokes ||
      oldDelegate.active != active ||
      oldDelegate.selectionRect != selectionRect;
}
