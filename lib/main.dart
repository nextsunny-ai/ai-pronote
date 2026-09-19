import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature, PointerDeviceKind;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import 'notes/note_document.dart';
import 'notes/file_note_repository.dart';
import 'notes/note_exporter.dart';
import 'notes/note_repository.dart';

import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'processing/file_processing_job_repository.dart';
import 'processing/local_meeting_processing_gateway.dart';
import 'processing/transcript_exporter.dart';
import 'recording/audio_recorder_gateway.dart';
import 'recording/device_audio_recorder.dart';
import 'recording/device_video_recorder.dart';
import 'recording/video_recorder_gateway.dart';
import 'storage/application_storage.dart';
import 'update/update_checker.dart';

Future<Directory> _defaultApplicationDirectory() async {
  final documents = await getApplicationDocumentsDirectory();
  return ApplicationStorage(documents).prepare();
}

Future<Directory> _defaultRecordingDirectory() async {
  final documents = await _defaultApplicationDirectory();
  final recordings = Directory(
    '${documents.path}${Platform.pathSeparator}recordings',
  );
  await recordings.create(recursive: true);
  return recordings;
}

Future<Directory> _defaultVideoDirectory() async {
  final documents = await _defaultApplicationDirectory();
  final videos = Directory('${documents.path}${Platform.pathSeparator}videos');
  await videos.create(recursive: true);
  return videos;
}

Future<Directory> _defaultExportDirectory() async {
  final documents = await _defaultApplicationDirectory();
  final exports = Directory(
    '${documents.path}${Platform.pathSeparator}AI_PRONOTE_exports',
  );
  await exports.create(recursive: true);
  return exports;
}

Future<String?> _pickExistingMeetingMedia() async {
  const media = XTypeGroup(
    label: '녹음 및 영상',
    extensions: ['m4a', 'mp3', 'wav', 'aac', 'mp4', 'mov', 'm4v'],
  );
  final file = await openFile(acceptedTypeGroups: const [media]);
  return file?.path;
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final documents = await _defaultApplicationDirectory();
  final packageInfo = await PackageInfo.fromPlatform();
  runApp(
    PronoteApp(
      repository: FileNoteRepository(documents),
      noteExporter: const NoteExporter(_defaultExportDirectory),
      recorder: DeviceAudioRecorderGateway(),
      videoRecorderFactory: DeviceVideoRecorderGateway.new,
      processingGateway:
          Platform.isWindows || Platform.isMacOS || Platform.isLinux
          ? LocalMeetingProcessingGateway(
              baseUri: Uri.parse('http://127.0.0.1:8795'),
            )
          : null,
      processingJobRepository: FileProcessingJobRepository(documents),
      transcriptExporter: const TranscriptExporter(_defaultExportDirectory),
      importRecordingPicker: _pickExistingMeetingMedia,
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
    this.noteExporter,
    this.recorder = const DisabledAudioRecorderGateway(),
    this.videoRecorderFactory,
    this.processingGateway,
    this.processingJobRepository,
    this.transcriptExporter,
    this.importRecordingPicker,
    this.recordingDirectoryProvider,
    this.videoDirectoryProvider,
    this.recordingValidator,
    this.currentVersion = '1.0.1',
    this.updateChecker,
    this.openExternalUrl,
  });

  final NoteRepository repository;
  final NoteExporter? noteExporter;
  final AudioRecorderGateway recorder;
  final VideoRecorderGateway Function()? videoRecorderFactory;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final TranscriptExporter? transcriptExporter;
  final Future<String?> Function()? importRecordingPicker;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final Future<Directory> Function()? videoDirectoryProvider;
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
        noteExporter: noteExporter,
        recorder: recorder,
        videoRecorderFactory: videoRecorderFactory,
        processingGateway: processingGateway,
        processingJobRepository: processingJobRepository,
        transcriptExporter: transcriptExporter,
        importRecordingPicker: importRecordingPicker,
        recordingDirectoryProvider: recordingDirectoryProvider,
        videoDirectoryProvider: videoDirectoryProvider,
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
    this.noteExporter,
    this.videoRecorderFactory,
    this.processingGateway,
    this.processingJobRepository,
    this.transcriptExporter,
    this.importRecordingPicker,
    this.recordingDirectoryProvider,
    this.videoDirectoryProvider,
    this.recordingValidator,
    required this.displayVersion,
  });

  final NoteRepository repository;
  final AudioRecorderGateway recorder;
  final NoteExporter? noteExporter;
  final VideoRecorderGateway Function()? videoRecorderFactory;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final TranscriptExporter? transcriptExporter;
  final Future<String?> Function()? importRecordingPicker;
  final Future<Directory> Function()? recordingDirectoryProvider;
  final Future<Directory> Function()? videoDirectoryProvider;
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
  bool _importingMedia = false;
  final ScrollController _homeScrollController = ScrollController();

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
        builder: (_) => NoteEditor(
          repository: widget.repository,
          initialNote: note,
          exporter: widget.noteExporter,
        ),
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
        builder: (_) => NoteEditor(
          repository: widget.repository,
          initialNote: note,
          exporter: widget.noteExporter,
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _notes = widget.repository.list();
      });
    }
  }

  String _noteDate(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';

  Future<void> _chooseNote() async {
    final notes = await widget.repository.list();
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .72,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            children: [
              Text(
                '노트',
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              ListTile(
                key: const ValueKey('create-note-from-note-menu'),
                leading: const Icon(Icons.note_add_outlined),
                title: const Text('새 노트 만들기'),
                subtitle: const Text('빈 페이지에서 필기 시작'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _newNote();
                },
              ),
              if (notes.isNotEmpty) ...[
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Text(
                    '기존 노트',
                    style: Theme.of(sheetContext).textTheme.labelLarge,
                  ),
                ),
                for (final note in notes)
                  ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(note.title),
                    subtitle: Text(_noteDate(note.updatedAt)),
                    onTap: () async {
                      Navigator.pop(sheetContext);
                      await _openNote(note);
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _openHome() {
    if (!_homeScrollController.hasClients) return;
    _homeScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  Future<List<File>> _meetingMediaFiles() async {
    final audioDirectory =
        await (widget.recordingDirectoryProvider?.call() ??
            _defaultRecordingDirectory());
    final videoDirectory =
        await (widget.videoDirectoryProvider?.call() ??
            _defaultVideoDirectory());
    final files = <File>[];
    for (final directory in [audioDirectory, videoDirectory]) {
      if (!await directory.exists()) continue;
      await for (final entity in directory.list()) {
        if (entity is File) files.add(entity);
      }
    }
    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
    return files;
  }

  Future<void> _openProcessingJob(ProcessingJobRecord job) async {
    final gateway = widget.processingGateway;
    if (gateway == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이 기기에서는 회의 원본과 노트를 먼저 확인할 수 있습니다.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => TranscriptionResultScreen(
          gateway: gateway,
          jobId: job.jobId,
          noteRepository: widget.repository,
          transcriptExporter: widget.transcriptExporter,
        ),
      ),
    );
  }

  Future<void> _openLibrary({
    LibraryFilter initialFilter = LibraryFilter.all,
  }) async {
    final notes = await widget.repository.list();
    final jobs =
        await (widget.processingJobRepository?.list() ??
            Future.value(const <ProcessingJobRecord>[]));
    final media = await _meetingMediaFiles();
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => UnifiedLibraryScreen(
          notes: notes,
          jobs: jobs,
          mediaFiles: media,
          initialFilter: initialFilter,
          onOpenNote: _openNote,
          onOpenJob: _openProcessingJob,
          onProcessMedia: widget.processingGateway == null
              ? null
              : _processMediaFile,
        ),
      ),
    );
  }

  Future<void> _openAssistant() async {
    final jobs =
        await (widget.processingJobRepository?.list() ??
            Future.value(const <ProcessingJobRecord>[]));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(
              'AI 비서',
              style: Theme.of(sheetContext).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              widget.processingGateway == null
                  ? 'AI 연결 후 회의록 정리와 후속 작업을 사용할 수 있습니다.'
                  : '회의를 선택해 AI 회의록과 후속 작업을 이어가세요.',
            ),
            const SizedBox(height: 12),
            if (jobs.isEmpty)
              const ListTile(
                leading: Icon(Icons.info_outline_rounded),
                title: Text('아직 연결할 회의가 없습니다.'),
                subtitle: Text('회의를 녹음하거나 기존 파일을 가져오세요.'),
              )
            else
              for (final job in jobs)
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(_fileName(job.recordingPath)),
                  subtitle: Text('상태 ${job.status}'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openProcessingJob(job);
                  },
                ),
          ],
        ),
      ),
    );
  }

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

  Future<void> _openSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
          children: [
            Text(
              '설정',
              style: Theme.of(sheetContext).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('AI 연결'),
              subtitle: Text(
                widget.processingGateway == null
                    ? '녹음·영상·필기는 로그인 없이 사용 가능'
                    : '받아쓰기와 AI 회의록 연결 사용 가능',
              ),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('보관함'),
              subtitle: const Text('노트·회의록·녹음·영상을 한곳에서 검색'),
              onTap: () {
                Navigator.pop(sheetContext);
                _openLibrary();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('AI PRONOTE'),
              subtitle: Text('버전 ${widget.displayVersion} · (주)써니엔터테인먼트'),
            ),
          ],
        ),
      ),
    );
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
                          noteExporter: widget.noteExporter,
                          processingGateway: widget.processingGateway,
                          processingJobRepository:
                              widget.processingJobRepository,
                          transcriptExporter: widget.transcriptExporter,
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
                          noteExporter: widget.noteExporter,
                          processingGateway: widget.processingGateway,
                          processingJobRepository:
                              widget.processingJobRepository,
                          transcriptExporter: widget.transcriptExporter,
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
                  key: const ValueKey('import-meeting-media'),
                  enabled: !_importingMedia,
                  leading: const Icon(Icons.upload_file_outlined),
                  title: const Text('기존 녹음·영상 가져오기'),
                  subtitle: const Text('저장된 파일로 받아쓰기 시작'),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _importMeetingMedia();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _importMeetingMedia() async {
    final picker = widget.importRecordingPicker;
    if (_importingMedia || picker == null) return;
    setState(() => _importingMedia = true);
    try {
      final path = await picker();
      if (path == null) return;
      await _processMediaFile(path);
    } on MeetingProcessingException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('파일을 가져오지 못했습니다. 다시 시도해 주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _importingMedia = false);
    }
  }

  Future<void> _processMediaFile(String path) async {
    final gateway = widget.processingGateway;
    if (gateway == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('받아쓰기 연결을 설정한 후 사용할 수 있습니다.')),
        );
      }
      return;
    }
    final file = File(path);
    final valid = widget.recordingValidator != null
        ? await widget.recordingValidator!(path)
        : await file.exists() && await file.length() > 0;
    if (!valid) {
      throw const MeetingProcessingException('선택한 파일을 읽을 수 없습니다.');
    }
    final job = await gateway.submitTranscription(path);
    final record = ProcessingJobRecord(
      jobId: job.id,
      recordingPath: path,
      createdAt: DateTime.now(),
      status: job.status,
    );
    await widget.processingJobRepository?.save(record);
    if (!mounted) return;
    setState(() {
      _processingJobs =
          widget.processingJobRepository?.list() ??
          Future.value(const <ProcessingJobRecord>[]);
    });
    await _openProcessingJob(record);
  }

  @override
  void dispose() {
    _homeScrollController.dispose();
    super.dispose();
  }

  Widget _navigationDrawer(BuildContext context) => NavigationDrawer(
    selectedIndex: 0,
    onDestinationSelected: (index) {
      Navigator.pop(context);
      switch (index) {
        case 0:
          _openHome();
          return;
        case 1:
          _chooseMeetingMode();
          return;
        case 2:
          _importMeetingMedia();
          return;
        case 3:
          _openLibrary(initialFilter: LibraryFilter.meetings);
          return;
        case 4:
          _chooseNote();
          return;
        case 5:
          _openAssistant();
          return;
        case 6:
          _openLibrary();
          return;
        case 7:
          _openSettings();
          return;
      }
    },
    children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 22, 20, 18),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.asset(
                'assets/branding/ai_pronote_mark.png',
                width: 34,
                height: 34,
              ),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'AI PRONOTE',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  Text('회의와 노트를 한곳에', style: TextStyle(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
      const Divider(indent: 20, endIndent: 20),
      const NavigationDrawerDestination(
        key: ValueKey('top-home-navigation'),
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: Text('홈'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-meeting-navigation'),
        icon: Icon(Icons.mic_none_rounded),
        selectedIcon: Icon(Icons.mic_rounded),
        label: Text('새 회의'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-transcription-navigation'),
        icon: Icon(Icons.graphic_eq_rounded),
        label: Text('받아쓰기'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-minutes-navigation'),
        icon: Icon(Icons.description_outlined),
        label: Text('회의록'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-note-navigation'),
        icon: Icon(Icons.edit_note_rounded),
        label: Text('내 노트'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-assistant-navigation'),
        icon: Icon(Icons.auto_awesome_outlined),
        label: Text('AI 비서'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-library-navigation'),
        icon: Icon(Icons.manage_search_rounded),
        label: Text('통합 찾기'),
      ),
      const NavigationDrawerDestination(
        key: ValueKey('top-settings-navigation'),
        icon: Icon(Icons.settings_outlined),
        label: Text('설정'),
      ),
      const Padding(
        padding: EdgeInsets.fromLTRB(28, 18, 28, 12),
        child: Text(
          'SUNNY ENTERTAINMENT',
          style: TextStyle(fontSize: 11, letterSpacing: 1.1),
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    drawer: _navigationDrawer(context),
    appBar: AppBar(
      backgroundColor: const Color(0xfff7f5ef),
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leading: Builder(
        builder: (context) => IconButton(
          key: const ValueKey('open-navigation'),
          tooltip: '메뉴',
          onPressed: () => Scaffold.of(context).openDrawer(),
          icon: const Icon(Icons.menu_rounded),
        ),
      ),
      title: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/branding/ai_pronote_mark.png',
              width: 38,
              height: 38,
              fit: BoxFit.cover,
              semanticLabel: 'AI PRONOTE 로고',
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'AI PRONOTE',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                '버전 ${widget.displayVersion}',
                style: const TextStyle(fontSize: 11, color: Color(0xff77746d)),
              ),
            ],
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '내 노트',
          onPressed: _chooseNote,
          icon: const Icon(Icons.edit_note_rounded),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: FilledButton.icon(
            onPressed: _chooseMeetingMode,
            icon: const Icon(Icons.mic_none_rounded, size: 18),
            label: const Text('회의 시작'),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: ListView(
          controller: _homeScrollController,
          children: [
            Text(
              '오늘의 기록',
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -.6),
            ),
            const SizedBox(height: 6),
            Text(
              '노트를 쓰거나 회의를 기록하세요.',
              style: Theme.of(context).textTheme.bodyMedium
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
                      title: '노트',
                      description: '새 노트를 만들거나 기존 노트 열기',
                      primary: true,
                      onTap: _chooseNote,
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
                      title: '회의',
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
                                noteRepository: widget.repository,
                                transcriptExporter: widget.transcriptExporter,
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

enum LibraryFilter { all, meetings, notes, media }

class UnifiedLibraryScreen extends StatefulWidget {
  const UnifiedLibraryScreen({
    super.key,
    required this.notes,
    required this.jobs,
    required this.mediaFiles,
    required this.onOpenNote,
    required this.onOpenJob,
    this.onProcessMedia,
    this.initialFilter = LibraryFilter.all,
  });

  final List<NoteDocument> notes;
  final List<ProcessingJobRecord> jobs;
  final List<File> mediaFiles;
  final Future<void> Function(NoteDocument note) onOpenNote;
  final Future<void> Function(ProcessingJobRecord job) onOpenJob;
  final Future<void> Function(String path)? onProcessMedia;
  final LibraryFilter initialFilter;

  @override
  State<UnifiedLibraryScreen> createState() => _UnifiedLibraryScreenState();
}

class _UnifiedLibraryScreenState extends State<UnifiedLibraryScreen> {
  late LibraryFilter _filter = widget.initialFilter;
  String _query = '';

  String _fileName(String path) => path.replaceAll('\\', '/').split('/').last;

  String _date(DateTime value) =>
      '${value.year}.${value.month.toString().padLeft(2, '0')}.${value.day.toString().padLeft(2, '0')}';

  String _fileSize(File file) {
    try {
      final bytes = file.lengthSync();
      if (bytes >= 1024 * 1024) {
        return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
      }
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    } catch (_) {
      return '크기 확인 불가';
    }
  }

  bool _matches(String value) =>
      _query.isEmpty || value.toLowerCase().contains(_query.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes
        .where((note) => _matches('${note.title} ${note.body}'))
        .toList(growable: false);
    final jobs = widget.jobs
        .where(
          (job) => _matches(
            '${_fileName(job.recordingPath)} ${job.jobId} ${job.status}',
          ),
        )
        .toList(growable: false);
    final media = widget.mediaFiles
        .where((file) => _matches(_fileName(file.path)))
        .toList(growable: false);
    final showNotes =
        _filter == LibraryFilter.all || _filter == LibraryFilter.notes;
    final showMeetings =
        _filter == LibraryFilter.all || _filter == LibraryFilter.meetings;
    final showMedia =
        _filter == LibraryFilter.all || _filter == LibraryFilter.media;
    final empty =
        (!showNotes || notes.isEmpty) &&
        (!showMeetings || jobs.isEmpty) &&
        (!showMedia || media.isEmpty);

    return Scaffold(
      appBar: AppBar(title: const Text('통합 찾기')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          children: [
            SearchBar(
              key: const ValueKey('library-search'),
              hintText: '노트·회의록·녹음·영상 검색',
              leading: const Icon(Icons.search_rounded),
              elevation: const WidgetStatePropertyAll(0),
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SegmentedButton<LibraryFilter>(
                segments: const [
                  ButtonSegment(value: LibraryFilter.all, label: Text('전체')),
                  ButtonSegment(
                    value: LibraryFilter.meetings,
                    label: Text('회의록'),
                  ),
                  ButtonSegment(value: LibraryFilter.notes, label: Text('노트')),
                  ButtonSegment(
                    value: LibraryFilter.media,
                    label: Text('녹음·영상'),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (value) =>
                    setState(() => _filter = value.first),
              ),
            ),
            if (empty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(child: Text('찾은 기록이 없습니다.')),
              ),
            if (showMeetings && jobs.isNotEmpty) ...[
              const _LibrarySectionTitle('회의록'),
              for (final job in jobs)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: Text(_fileName(job.recordingPath)),
                    subtitle: Text('${_date(job.createdAt)} · ${job.status}'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.onOpenJob(job),
                  ),
                ),
            ],
            if (showNotes && notes.isNotEmpty) ...[
              const _LibrarySectionTitle('내 노트'),
              for (final note in notes)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.edit_note_rounded),
                    title: Text(note.title),
                    subtitle: Text(_date(note.updatedAt)),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => widget.onOpenNote(note),
                  ),
                ),
            ],
            if (showMedia && media.isNotEmpty) ...[
              const _LibrarySectionTitle('녹음·영상'),
              for (final file in media)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: Icon(
                      file.path.toLowerCase().endsWith('.mp4')
                          ? Icons.videocam_outlined
                          : Icons.graphic_eq_rounded,
                    ),
                    title: Text(_fileName(file.path)),
                    subtitle: Text(
                      '${_date(file.lastModifiedSync())} · ${_fileSize(file)}',
                    ),
                    trailing: widget.onProcessMedia == null
                        ? const Icon(Icons.lock_outline_rounded)
                        : TextButton(
                            onPressed: () => widget.onProcessMedia!(file.path),
                            child: const Text('받아쓰기'),
                          ),
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('보관 위치: ${file.path}')),
                      );
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _LibrarySectionTitle extends StatelessWidget {
  const _LibrarySectionTitle(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Text(
      label,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
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
    required this.noteRepository,
    this.transcriptExporter,
  });

  final MeetingProcessingGateway gateway;
  final String jobId;
  final NoteRepository noteRepository;
  final TranscriptExporter? transcriptExporter;

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
  bool _savingNote = false;
  bool _savedAsNote = false;
  bool _exporting = false;
  String? _exportedPath;
  bool _creatingSummary = false;

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

  Future<void> _saveAsNote() async {
    final result = _result;
    if (result == null || _savingNote || _savedAsNote) return;
    setState(() => _savingNote = true);
    final filename = result.filename.replaceAll('\\', '/').split('/').last;
    final dot = filename.lastIndexOf('.');
    final fallbackTitle = dot > 0 ? filename.substring(0, dot) : filename;
    final title = result.summaryTitle.trim().isNotEmpty
        ? result.summaryTitle.trim()
        : (fallbackTitle.trim().isEmpty ? '받아쓰기 노트' : fallbackTitle);
    final body = result.summary.trim().isEmpty
        ? result.transcript
        : '${result.summary.trim()}\n\n---\n\n받아쓰기\n${result.transcript.trim()}';
    try {
      final now = DateTime.now();
      await widget.noteRepository.save(
        NoteDocument(
          id: now.microsecondsSinceEpoch.toString(),
          title: title,
          body: body,
          updatedAt: now,
        ),
      );
      if (!mounted) return;
      setState(() => _savedAsNote = true);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('받아쓰기 내용을 노트에 저장했습니다.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노트를 저장하지 못했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _savingNote = false);
    }
  }

  Future<void> _exportText() async {
    final exporter = widget.transcriptExporter;
    final result = _result;
    if (exporter == null || result == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await exporter.export(result);
      if (!mounted) return;
      setState(() => _exportedPath = path);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('텍스트 파일을 저장했습니다.\n$path')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('텍스트 파일을 저장하지 못했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _showSummaryDialog() async {
    var provider = 'claude_cli';
    var consent = false;
    final selected = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('AI 회의록 만들기'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('사용할 연결을 선택하세요.'),
                const SizedBox(height: 12),
                RadioGroup<String>(
                  groupValue: provider,
                  onChanged: (value) => setDialogState(() => provider = value!),
                  child: const Column(
                    children: [
                      RadioListTile<String>(
                        value: 'claude_cli',
                        title: Text('Claude 연결'),
                        subtitle: Text('이 PC의 Claude 로그인을 사용합니다.'),
                      ),
                      RadioListTile<String>(
                        value: 'codex_cli',
                        title: Text('ChatGPT/Codex 연결'),
                        subtitle: Text('이 PC의 Codex 로그인을 사용합니다.'),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 24),
                CheckboxListTile(
                  key: const ValueKey('summary-consent'),
                  value: consent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  onChanged: (value) =>
                      setDialogState(() => consent = value ?? false),
                  title: const Text('받아쓰기 본문을 선택한 AI에 보내기'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: consent
                  ? () => Navigator.pop(dialogContext, provider)
                  : null,
              child: const Text('회의록 생성'),
            ),
          ],
        ),
      ),
    );
    if (selected != null) await _createSummary(selected);
  }

  Future<void> _createSummary(String provider) async {
    if (_creatingSummary) return;
    setState(() => _creatingSummary = true);
    try {
      var job = await widget.gateway.requestSummary(
        widget.jobId,
        provider: provider,
      );
      for (
        var attempt = 0;
        attempt < 60 && job.summaryStatus != 'done';
        attempt++
      ) {
        if (job.summaryStatus == 'failed') {
          throw const MeetingProcessingException('AI 회의록 생성에 실패했습니다.');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
        job = await widget.gateway.readJob(widget.jobId);
      }
      if (job.summaryStatus != 'done') {
        throw const MeetingProcessingException(
          'AI 회의록을 계속 만들고 있습니다. 잠시 후 다시 열어 확인하세요.',
        );
      }
      final result = await widget.gateway.readResult(widget.jobId);
      if (!mounted) return;
      setState(() {
        _job = job;
        _result = result;
      });
    } catch (error) {
      if (!mounted) return;
      final message = error is MeetingProcessingException
          ? error.message
          : 'AI 회의록을 만들지 못했습니다.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _creatingSummary = false);
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
              const SizedBox(height: 18),
              FilledButton.icon(
                key: const ValueKey('save-transcript-as-note'),
                onPressed: _savingNote || _savedAsNote ? null : _saveAsNote,
                icon: Icon(
                  _savedAsNote ? Icons.check_rounded : Icons.note_add_outlined,
                ),
                label: Text(_savedAsNote ? '노트에 저장됨' : '노트로 저장'),
              ),
              if (result.summary.isEmpty) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  key: const ValueKey('create-ai-summary'),
                  onPressed: _creatingSummary ? null : _showSummaryDialog,
                  icon: _creatingSummary
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome_outlined),
                  label: Text(_creatingSummary ? 'AI 회의록 생성 중' : 'AI 회의록 만들기'),
                ),
              ],
              if (widget.transcriptExporter != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  key: const ValueKey('export-transcript-text'),
                  onPressed: _exporting ? null : _exportText,
                  icon: Icon(
                    _exportedPath == null
                        ? Icons.download_outlined
                        : Icons.check_rounded,
                  ),
                  label: Text(
                    _exportedPath == null ? '텍스트 파일 저장' : '텍스트 파일 저장됨',
                  ),
                ),
              ],
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
    this.noteExporter,
    this.processingGateway,
    this.processingJobRepository,
    this.transcriptExporter,
    this.directoryProvider,
    this.recordingValidator,
  });

  final AudioRecorderGateway recorder;
  final NoteRepository repository;
  final NoteExporter? noteExporter;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final TranscriptExporter? transcriptExporter;
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
          builder: (_) => TranscriptionResultScreen(
            gateway: gateway,
            jobId: job.id,
            noteRepository: widget.repository,
            transcriptExporter: widget.transcriptExporter,
          ),
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
        builder: (_) => NoteEditor(
          repository: widget.repository,
          initialNote: note,
          exporter: widget.noteExporter,
        ),
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
    this.noteExporter,
    this.processingGateway,
    this.processingJobRepository,
    this.transcriptExporter,
    this.directoryProvider,
    this.recordingValidator,
  });

  final VideoRecorderGateway recorder;
  final NoteRepository repository;
  final NoteExporter? noteExporter;
  final MeetingProcessingGateway? processingGateway;
  final ProcessingJobRepository? processingJobRepository;
  final TranscriptExporter? transcriptExporter;
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
          builder: (_) => TranscriptionResultScreen(
            gateway: gateway,
            jobId: job.id,
            noteRepository: widget.repository,
            transcriptExporter: widget.transcriptExporter,
          ),
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
        builder: (_) => NoteEditor(
          repository: widget.repository,
          initialNote: note,
          exporter: widget.noteExporter,
        ),
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
    this.exporter,
  });

  final NoteRepository repository;
  final NoteDocument initialNote;
  final NoteExporter? exporter;

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
  bool _fingerDrawingEnabled = true;
  int _currentPageIndex = 0;
  Rect? _selectionRect;
  Set<String> _selectedStrokeIds = {};
  Offset? _lassoStart;
  Offset? _dragStart;
  Rect? _dragOriginRect;
  List<InkStroke>? _dragOriginalStrokes;
  late bool _showTextBody;
  bool _exporting = false;

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
    final current = _note.pages[_currentPageIndex];
    final page = NotePage(
      id: 'page-${DateTime.now().microsecondsSinceEpoch}',
      paperStyle: current.paperStyle,
      paperColor: current.paperColor,
    );
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
      paperStyle: source.paperStyle,
      paperColor: source.paperColor,
      stickies: source.stickies
          .map(
            (sticky) => NoteSticky(
              id: '${sticky.id}-page-copy-$now',
              text: sticky.text,
              x: sticky.x,
              y: sticky.y,
              color: sticky.color,
            ),
          )
          .toList(growable: false),
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

  void _setPaperStyle(PaperStyle style) {
    final pages = List<NotePage>.of(_note.pages);
    pages[_currentPageIndex] = pages[_currentPageIndex].copyWith(
      paperStyle: style,
    );
    setState(
      () => _note = _note.copyWith(updatedAt: DateTime.now(), pages: pages),
    );
    _scheduleSave();
  }

  void _setPaperColor(int color) {
    final pages = List<NotePage>.of(_note.pages);
    pages[_currentPageIndex] = pages[_currentPageIndex].copyWith(
      paperColor: color,
    );
    setState(
      () => _note = _note.copyWith(updatedAt: DateTime.now(), pages: pages),
    );
    _scheduleSave();
  }

  Future<void> _addSticky() async {
    final text = await _askStickyText(title: '포스트잇 추가');
    if (text == null || text.trim().isEmpty) return;
    final page = _note.pages[_currentPageIndex];
    final offset = (page.stickies.length % 5) * 18.0;
    final sticky = NoteSticky(
      id: 'sticky-${DateTime.now().microsecondsSinceEpoch}',
      text: text.trim(),
      x: 36 + offset,
      y: 40 + offset,
    );
    _replaceCurrentPage(page.copyWith(stickies: [...page.stickies, sticky]));
  }

  Future<void> _editSticky(NoteSticky sticky) async {
    final text = await _askStickyText(
      title: '포스트잇 수정',
      initialValue: sticky.text,
    );
    if (text == null) return;
    if (text.trim().isEmpty) {
      _deleteSticky(sticky.id);
      return;
    }
    final page = _note.pages[_currentPageIndex];
    _replaceCurrentPage(
      page.copyWith(
        stickies: page.stickies
            .map(
              (item) => item.id == sticky.id
                  ? item.copyWith(text: text.trim())
                  : item,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<String?> _askStickyText({
    required String title,
    String initialValue = '',
  }) async {
    var value = initialValue;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextFormField(
          key: const ValueKey('sticky-text-field'),
          initialValue: initialValue,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(hintText: '메모를 입력하세요'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, value),
            child: const Text('저장'),
          ),
        ],
      ),
    );
    return result;
  }

  void _moveSticky(String id, Offset delta) {
    final page = _note.pages[_currentPageIndex];
    _replaceCurrentPage(
      page.copyWith(
        stickies: page.stickies
            .map(
              (item) => item.id == id
                  ? item.copyWith(
                      x: (item.x + delta.dx).clamp(0, 2000),
                      y: (item.y + delta.dy).clamp(0, 2000),
                    )
                  : item,
            )
            .toList(growable: false),
      ),
      saveImmediately: false,
    );
  }

  void _deleteSticky(String id) {
    final page = _note.pages[_currentPageIndex];
    _replaceCurrentPage(
      page.copyWith(
        stickies: page.stickies
            .where((item) => item.id != id)
            .toList(growable: false),
      ),
    );
  }

  void _replaceCurrentPage(NotePage page, {bool saveImmediately = true}) {
    final pages = List<NotePage>.of(_note.pages)..[_currentPageIndex] = page;
    setState(
      () => _note = _note.copyWith(updatedAt: DateTime.now(), pages: pages),
    );
    if (saveImmediately) _scheduleSave();
  }

  String _paperLabel(PaperStyle style) => switch (style) {
    PaperStyle.blank => '무지',
    PaperStyle.ruled => '줄노트',
    PaperStyle.narrowRuled => '좁은 줄노트',
    PaperStyle.grid => '모눈',
    PaperStyle.dotted => '점선',
    PaperStyle.manuscript => '원고지',
  };

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

  Future<void> _exportNote() async {
    final exporter = widget.exporter;
    if (exporter == null || _exporting) return;
    setState(() => _exporting = true);
    try {
      await widget.repository.save(_note);
      await exporter.export(_note);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('문서 2개를 저장했습니다')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('노트를 내보내지 못했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
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
            width: MediaQuery.sizeOf(context).width < 600 ? 130 : 240,
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
        if (widget.exporter != null)
          IconButton(
            key: const ValueKey('export-note'),
            tooltip: '문서로 내보내기',
            onPressed: _exporting ? null : _exportNote,
            icon: _exporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_rounded),
          ),
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
              PopupMenuButton<PaperStyle>(
                key: const ValueKey('paper-style-menu'),
                tooltip: '종이 배경',
                initialValue: _note.pages[_currentPageIndex].paperStyle,
                onSelected: _setPaperStyle,
                itemBuilder: (_) => PaperStyle.values
                    .map(
                      (style) => PopupMenuItem(
                        value: style,
                        child: Row(
                          children: [
                            Icon(
                              style == _note.pages[_currentPageIndex].paperStyle
                                  ? Icons.check_rounded
                                  : Icons.description_outlined,
                            ),
                            const SizedBox(width: 12),
                            Text(_paperLabel(style)),
                          ],
                        ),
                      ),
                    )
                    .toList(growable: false),
                icon: const Icon(Icons.grid_4x4_rounded),
              ),
              IconButton.filledTonal(
                key: const ValueKey('add-sticky'),
                tooltip: '포스트잇 추가',
                onPressed: _addSticky,
                icon: const Icon(Icons.sticky_note_2_outlined),
              ),
              PopupMenuButton<int>(
                key: const ValueKey('paper-color-menu'),
                tooltip: '종이 색상',
                initialValue: _note.pages[_currentPageIndex].paperColor,
                onSelected: _setPaperColor,
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 0xfffffdf8, child: Text('아이보리')),
                  PopupMenuItem(value: 0xffffffff, child: Text('흰색')),
                  PopupMenuItem(value: 0xfffff7ed, child: Text('크림')),
                  PopupMenuItem(value: 0xfff1f7f3, child: Text('민트')),
                  PopupMenuItem(value: 0xfff3f2fa, child: Text('라벤더')),
                ],
                icon: const Icon(Icons.palette_outlined),
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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Listener(
                      key: const ValueKey('ink-canvas'),
                      behavior: HitTestBehavior.opaque,
                      onPointerDown: _begin,
                      onPointerMove: _move,
                      onPointerUp: _finish,
                      onPointerCancel: (_) => setState(() => _active = null),
                      child: CustomPaint(
                        painter: InkPainter(
                          page: _note.pages[_currentPageIndex],
                          strokes: _currentStrokes,
                          active: _active,
                          selectionRect: _selectionRect,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                    for (final sticky
                        in _note.pages[_currentPageIndex].stickies)
                      Positioned(
                        left: sticky.x,
                        top: sticky.y,
                        child: GestureDetector(
                          key: ValueKey('sticky-${sticky.id}'),
                          onPanUpdate: (details) =>
                              _moveSticky(sticky.id, details.delta),
                          onPanEnd: (_) => _scheduleSave(),
                          onTap: () => _editSticky(sticky),
                          onLongPress: () => _deleteSticky(sticky.id),
                          child: Container(
                            width: 150,
                            constraints: const BoxConstraints(minHeight: 110),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Color(sticky.color),
                              borderRadius: BorderRadius.circular(4),
                              boxShadow: const [
                                BoxShadow(
                                  color: Color(0x24000000),
                                  blurRadius: 10,
                                  offset: Offset(0, 5),
                                ),
                              ],
                            ),
                            child: Text(
                              sticky.text,
                              style: const TextStyle(
                                color: Color(0xff29271f),
                                fontSize: 15,
                                height: 1.35,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
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
  const InkPainter({
    required this.page,
    required this.strokes,
    this.active,
    this.selectionRect,
  });

  final NotePage page;
  final List<InkStroke> strokes;
  final InkStroke? active;
  final Rect? selectionRect;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Color(page.paperColor),
    );
    _paintPaper(canvas, size);
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

  void _paintPaper(Canvas canvas, Size size) {
    if (page.paperStyle == PaperStyle.blank) return;
    final fine = Paint()
      ..color = const Color(0x24315f83)
      ..strokeWidth = 1;
    final accent = Paint()
      ..color = const Color(0x305f8974)
      ..strokeWidth = 1;
    switch (page.paperStyle) {
      case PaperStyle.blank:
        return;
      case PaperStyle.ruled:
      case PaperStyle.narrowRuled:
        final step = page.paperStyle == PaperStyle.ruled ? 36.0 : 24.0;
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), fine);
        }
        break;
      case PaperStyle.grid:
      case PaperStyle.manuscript:
        final step = page.paperStyle == PaperStyle.grid ? 28.0 : 34.0;
        for (var x = step; x < size.width; x += step) {
          canvas.drawLine(Offset(x, 0), Offset(x, size.height), fine);
        }
        for (var y = step; y < size.height; y += step) {
          canvas.drawLine(Offset(0, y), Offset(size.width, y), fine);
        }
        if (page.paperStyle == PaperStyle.manuscript) {
          for (var y = step; y < size.height; y += step * 5) {
            canvas.drawLine(Offset(0, y), Offset(size.width, y), accent);
          }
        }
        break;
      case PaperStyle.dotted:
        for (var x = 20.0; x < size.width; x += 24) {
          for (var y = 20.0; y < size.height; y += 24) {
            canvas.drawCircle(
              Offset(x, y),
              1.1,
              fine..style = PaintingStyle.fill,
            );
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant InkPainter oldDelegate) =>
      oldDelegate.page != page ||
      oldDelegate.strokes != strokes ||
      oldDelegate.active != active ||
      oldDelegate.selectionRect != selectionRect;
}
