import 'dart:async';
import 'dart:io';

import 'package:capturenest_recorder/capturenest_recorder.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';

import 'models/recording.dart';
import 'services/recording_store.dart';
import 'widgets/brand_mark.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await RecordingStore.open();
  runApp(CaptureNestApp(store: store));
}

class CaptureNestApp extends StatelessWidget {
  const CaptureNestApp({super.key, required this.store});

  final RecordingStore store;

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xff08111E);
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff53E3C2),
      brightness: Brightness.dark,
      surface: ink,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'CaptureNest',
      theme: ThemeData(
        colorScheme: scheme,
        scaffoldBackgroundColor: ink,
        useMaterial3: true,
        appBarTheme: const AppBarTheme(backgroundColor: ink, elevation: 0),
        cardTheme: CardThemeData(
          color: const Color(0xff111F31),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
      ),
      home: RecorderHome(store: store),
    );
  }
}

class RecorderHome extends StatefulWidget {
  const RecorderHome({super.key, required this.store});

  final RecordingStore store;

  @override
  State<RecorderHome> createState() => _RecorderHomeState();
}

class _RecorderHomeState extends State<RecorderHome> {
  var _tab = 0;
  var _microphone = true;
  var _deviceAudio = false;
  var _frontCamera = false;
  var _cloudExport = false;
  var _quality = CaptureQuality.high;
  var _countdown = 3;
  var _isStarting = false;
  var _isRecording = false;
  var _isPaused = false;
  var _remainingCountdown = 0;
  Duration _elapsed = Duration.zero;
  Stopwatch? _stopwatch;
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    if (_isStarting || _isRecording) return;
    setState(() {
      _isStarting = true;
      _remainingCountdown = _countdown;
    });
    try {
      while (_remainingCountdown > 0) {
        await Future<void>.delayed(const Duration(seconds: 1));
        if (!mounted) return;
        setState(() => _remainingCountdown--);
      }
      await CaptureNestRecorder.start(RecordingOptions(
        microphone: _microphone,
        deviceAudio: _deviceAudio,
        frontCamera: _frontCamera,
        quality: _quality,
      ));
      if (!mounted) return;
      _stopwatch = Stopwatch()..start();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _stopwatch != null) {
          setState(() => _elapsed = _stopwatch!.elapsed);
        }
      });
      setState(() {
        _isStarting = false;
        _isRecording = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isStarting = false;
        _remainingCountdown = 0;
      });
      _showError(error);
    }
  }

  // iOS only lets a broadcast extension record other apps, so the record button
  // opens the system broadcast sheet there; the video is saved to Photos.
  Future<void> _startFullScreen() async {
    try {
      await CaptureNestRecorder.startFullScreen();
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _togglePause() async {
    try {
      if (_isPaused) {
        await CaptureNestRecorder.resume();
        _stopwatch?.start();
      } else {
        await CaptureNestRecorder.pause();
        _stopwatch?.stop();
      }
      if (mounted) setState(() => _isPaused = !_isPaused);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _stop() async {
    _ticker?.cancel();
    _stopwatch?.stop();
    final elapsed = _stopwatch?.elapsed ?? _elapsed;
    try {
      final path = await CaptureNestRecorder.stop();
      final now = DateTime.now();
      await widget.store.put(Recording(
        id: now.microsecondsSinceEpoch.toString(),
        path: path,
        title: 'Capture ${_titleTimestamp(now)}',
        createdAt: now,
        duration: elapsed,
      ));
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _elapsed = Duration.zero;
        _stopwatch = null;
        _tab = 1;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_cloudExport
            ? 'Saved locally. Use Share to export it to your cloud provider.'
            : 'Recording saved privately on this device.'),
      ));
    } catch (error) {
      // The native capture is finished either way, so never leave the controls stuck.
      if (!mounted) return;
      setState(() {
        _isRecording = false;
        _isPaused = false;
        _elapsed = Duration.zero;
        _stopwatch = null;
      });
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(_errorText(error))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = _tab == 0
        ? _recordPage(context)
        : LibraryPage(
            recordings: widget.store.recordings,
            onChanged: () => setState(() {}),
            store: widget.store,
          );
    return Scaffold(
      body: SafeArea(child: page),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const <Widget>[
          NavigationDestination(
              icon: Icon(Icons.fiber_manual_record_outlined), label: 'Record'),
          NavigationDestination(
              icon: Icon(Icons.video_library_outlined), label: 'Library'),
        ],
      ),
    );
  }

  Widget _recordPage(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: <Widget>[
        const Row(children: <Widget>[
          BrandMark(),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('CaptureNest', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                Text('Private screen capture', style: TextStyle(color: Color(0xff9CB0C9))),
              ],
            ),
          ),
          Icon(Icons.shield_outlined, color: Color(0xff53E3C2)),
        ]),
        const SizedBox(height: 28),
        _recordButton(),
        const SizedBox(height: 20),
        _settingsCard(),
        const SizedBox(height: 14),
        _privacyCard(),
      ],
    );
  }

  Widget _recordButton() {
    final active = _isRecording || _isStarting;
    final label = _isStarting
        ? (_remainingCountdown > 0 ? 'Starting in $_remainingCountdown' : 'Preparing capture…')
        : _isRecording
            ? _formatDuration(_elapsed)
            : 'Start recording';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(100),
            onTap: active ? null : (Platform.isIOS ? _startFullScreen : _start),
            child: Ink(
              width: 178,
              height: 178,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: active ? const Color(0xffFE6B79) : const Color(0xff53E3C2),
                boxShadow: const <BoxShadow>[
                  BoxShadow(color: Color(0x4053E3C2), blurRadius: 32, spreadRadius: 4),
                ],
              ),
              child: Icon(
                active ? Icons.stop_rounded : Icons.fiber_manual_record_rounded,
                color: const Color(0xff08111E),
                size: 70,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 21)),
          const SizedBox(height: 5),
          Text(
            active
                ? (_isPaused ? 'Capture paused' : 'Capture is running')
                : Platform.isIOS
                    ? 'Tap, then Start Broadcast. Stop it with the red bar at the top. Videos are saved to Photos.'
                    : 'Tap once, then approve system capture.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xffA9BDD3)),
          ),
          if (_isRecording) ...<Widget>[
            const SizedBox(height: 20),
            Row(children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _togglePause,
                  icon: Icon(_isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded),
                  label: Text(_isPaused ? 'Resume' : 'Pause'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xffFE6B79)),
                  onPressed: _stop,
                  icon: const Icon(Icons.stop_rounded),
                  label: const Text('Stop'),
                ),
              ),
            ]),
          ],
        ]),
      ),
    );
  }

  Widget _settingsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Text('Capture setup', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
          ),
          SwitchListTile.adaptive(
            value: _microphone,
            onChanged: _isRecording ? null : (value) => setState(() => _microphone = value),
            title: const Text('Microphone'),
            subtitle: const Text('Narrate your recording'),
            secondary: const Icon(Icons.mic_none_rounded),
          ),
          SwitchListTile.adaptive(
            value: _deviceAudio,
            onChanged: _isRecording ? null : (value) => setState(() => _deviceAudio = value),
            title: const Text('Device audio'),
            subtitle: const Text('Android 10+ when the source allows it'),
            secondary: const Icon(Icons.volume_up_outlined),
          ),
          SwitchListTile.adaptive(
            value: _frontCamera,
            onChanged: _isRecording ? null : (value) => setState(() => _frontCamera = value),
            title: const Text('Front camera'),
            subtitle: const Text('Picture-in-picture when supported'),
            secondary: const Icon(Icons.camera_front_outlined),
          ),
          ListTile(
            leading: const Icon(Icons.high_quality_outlined),
            title: const Text('Video quality'),
            trailing: DropdownButton<CaptureQuality>(
              value: _quality,
              underline: const SizedBox.shrink(),
              onChanged: _isRecording ? null : (value) => setState(() => _quality = value!),
              items: CaptureQuality.values
                  .map((quality) => DropdownMenuItem<CaptureQuality>(
                        value: quality,
                        child: Text(quality.name[0].toUpperCase() + quality.name.substring(1)),
                      ))
                  .toList(),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.timer_outlined),
            title: const Text('Countdown'),
            trailing: SegmentedButton<int>(
              showSelectedIcon: false,
              segments: const <ButtonSegment<int>>[
                ButtonSegment<int>(value: 0, label: Text('Off')),
                ButtonSegment<int>(value: 3, label: Text('3s')),
                ButtonSegment<int>(value: 5, label: Text('5s')),
              ],
              selected: <int>{_countdown},
              onSelectionChanged: _isRecording
                  ? null
                  : (values) => setState(() => _countdown = values.first),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _privacyCard() {
    return Card(
      color: const Color(0xff0F2B32),
      child: SwitchListTile.adaptive(
        value: _cloudExport,
        onChanged: _isRecording ? null : (value) => setState(() => _cloudExport = value),
        title: const Text('Offer cloud export after recording'),
        subtitle: const Text('Still saved locally first. You choose the provider in the share sheet.'),
        secondary: const Icon(Icons.cloud_upload_outlined, color: Color(0xff53E3C2)),
      ),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({
    super.key,
    required this.recordings,
    required this.store,
    required this.onChanged,
  });

  final List<Recording> recordings;
  final RecordingStore store;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: recordings.isEmpty
          ? const _EmptyLibrary()
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              children: <Widget>[
                const Row(children: <Widget>[
                  Expanded(child: Text('Your captures', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
                  Icon(Icons.lock_outline, color: Color(0xff53E3C2)),
                ]),
                const SizedBox(height: 6),
                const Text('Private to this device until you choose to share.', style: TextStyle(color: Color(0xff9CB0C9))),
                const SizedBox(height: 18),
                ...recordings.map((recording) => _RecordingCard(
                      recording: recording,
                      store: store,
                      onChanged: onChanged,
                    )),
              ],
            ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary();

  @override
  Widget build(BuildContext context) => const Center(
        child: Padding(
          padding: EdgeInsets.all(38),
          child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
            BrandMark(size: 72),
            SizedBox(height: 20),
            Text('Your nest is empty', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
            SizedBox(height: 8),
            Text('Record your screen and each private capture will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff9CB0C9))),
          ]),
        ),
      );
}

class _RecordingCard extends StatelessWidget {
  const _RecordingCard({required this.recording, required this.store, required this.onChanged});

  final Recording recording;
  final RecordingStore store;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final fileMissing = !File(recording.path).existsSync();
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        onTap: fileMissing
            ? null
            : () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => PlayerPage(recording: recording),
                )),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(color: const Color(0xff1E3850), borderRadius: BorderRadius.circular(15)),
          child: Icon(fileMissing ? Icons.error_outline : Icons.play_arrow_rounded,
              color: fileMissing ? const Color(0xffFE6B79) : const Color(0xff53E3C2)),
        ),
        title: Text(recording.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(fileMissing
            ? 'File is no longer available'
            : '${_shortDate(recording.createdAt)} · ${_formatDuration(recording.duration)}'),
        trailing: PopupMenuButton<String>(
          onSelected: (choice) => _handleChoice(context, choice),
          itemBuilder: (_) => <PopupMenuEntry<String>>[
            const PopupMenuItem(value: 'share', child: Text('Share / cloud export')),
            const PopupMenuItem(value: 'gallery', child: Text('Save to gallery')),
            const PopupMenuItem(value: 'trim', child: Text('Trim & export')),
            const PopupMenuItem(value: 'rename', child: Text('Rename')),
            const PopupMenuDivider(),
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }

  Future<void> _handleChoice(BuildContext context, String choice) async {
    if (choice == 'share') {
      await Share.shareXFiles(<XFile>[XFile(recording.path)], text: recording.title);
      return;
    }
    if (choice == 'gallery') {
      try {
        await CaptureNestRecorder.saveToGallery(recording.path);
        if (context.mounted) _message(context, 'Saved to your media library.');
      } catch (error) {
        if (context.mounted) _message(context, _errorText(error));
      }
      return;
    }
    if (choice == 'trim') {
      if (!context.mounted) return;
      final trimmed = await Navigator.of(context).push<Recording>(MaterialPageRoute<Recording>(
        builder: (_) => TrimPage(recording: recording),
      ));
      if (trimmed != null) {
        await store.put(trimmed);
        onChanged();
      }
      return;
    }
    if (choice == 'rename') {
      final controller = TextEditingController(text: recording.title);
      final newName = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Rename capture'),
          content: TextField(controller: controller, autofocus: true, maxLength: 80),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text.trim()), child: const Text('Save')),
          ],
        ),
      );
      controller.dispose();
      if (newName != null && newName.isNotEmpty) {
        await store.put(recording.copyWith(title: newName));
        onChanged();
      }
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this capture?'),
        content: const Text('This removes the local video and cannot be undone.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Keep it')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Delete')),
        ],
      ),
    );
    if (approved == true) {
      final file = File(recording.path);
      if (await file.exists()) await file.delete();
      await store.remove(recording.id);
      onChanged();
    }
  }
}

class PlayerPage extends StatefulWidget {
  const PlayerPage({super.key, required this.recording});
  final Recording recording;

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  late final VideoPlayerController _player;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(File(widget.recording.path))..initialize().then((_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.recording.title)),
        body: Center(
          child: !_player.value.isInitialized
              ? const CircularProgressIndicator()
              : AspectRatio(aspectRatio: _player.value.aspectRatio, child: VideoPlayer(_player)),
        ),
        floatingActionButton: _player.value.isInitialized
            ? FloatingActionButton.extended(
                onPressed: () => setState(() => _player.value.isPlaying ? _player.pause() : _player.play()),
                icon: Icon(_player.value.isPlaying ? Icons.pause : Icons.play_arrow),
                label: Text(_player.value.isPlaying ? 'Pause' : 'Play'),
              )
            : null,
      );
}

class TrimPage extends StatefulWidget {
  const TrimPage({super.key, required this.recording});
  final Recording recording;

  @override
  State<TrimPage> createState() => _TrimPageState();
}

class _TrimPageState extends State<TrimPage> {
  late final VideoPlayerController _player;
  RangeValues _range = const RangeValues(0, 1);
  Duration _duration = const Duration(seconds: 1);
  var _exporting = false;

  @override
  void initState() {
    super.initState();
    _player = VideoPlayerController.file(File(widget.recording.path))..initialize().then((_) {
      if (!mounted) return;
      setState(() {
        _duration = _player.value.duration > Duration.zero ? _player.value.duration : widget.recording.duration;
        _range = RangeValues(0, _duration.inMilliseconds.toDouble());
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final path = await CaptureNestRecorder.trim(
        inputPath: widget.recording.path,
        from: Duration(milliseconds: _range.start.round()),
        to: Duration(milliseconds: _range.end.round()),
      );
      if (!mounted) return;
      final now = DateTime.now();
      Navigator.pop(
        context,
        Recording(
          id: now.microsecondsSinceEpoch.toString(),
          path: path,
          title: '${widget.recording.title} (trimmed)',
          createdAt: now,
          duration: Duration(milliseconds: (_range.end - _range.start).round()),
        ),
      );
    } catch (error) {
      if (mounted) _message(context, _errorText(error));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final max = _duration.inMilliseconds.toDouble().clamp(1, double.infinity).toDouble();
    final start = _range.start.clamp(0, max).toDouble();
    final end = _range.end.clamp(0, max).toDouble();
    return Scaffold(
      appBar: AppBar(title: const Text('Trim capture')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: <Widget>[
          if (_player.value.isInitialized)
            AspectRatio(aspectRatio: _player.value.aspectRatio, child: VideoPlayer(_player))
          else
            const AspectRatio(aspectRatio: 16 / 9, child: Center(child: CircularProgressIndicator())),
          const SizedBox(height: 28),
          Text('${_formatDuration(Duration(milliseconds: _range.start.round()))}  –  ${_formatDuration(Duration(milliseconds: _range.end.round()))}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          RangeSlider(
            values: RangeValues(start, end),
            min: 0,
            max: max,
            onChanged: (value) {
              if (value.end - value.start >= 500) setState(() => _range = value);
            },
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: _exporting ? null : _export,
            icon: _exporting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.content_cut),
            label: Text(_exporting ? 'Exporting…' : 'Export trimmed video'),
          ),
        ]),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _titleTimestamp(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}.${date.minute.toString().padLeft(2, '0')}';

String _shortDate(DateTime date) => '${date.day}/${date.month}/${date.year}';

void _message(BuildContext context, String text) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text.replaceFirst('Exception: ', ''))));
}



String _errorText(Object error) {
  if (error is PlatformException) return error.message ?? error.code;
  return error.toString().replaceFirst('Exception: ', '');
}
