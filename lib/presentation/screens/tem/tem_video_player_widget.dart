import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Reproductor de video WebM para estímulos TEM.
///
/// Reemplaza la animación labial programática. Recibe una URL `gs://`
/// del video del estímulo, la resuelve a HTTPS y la reproduce sin audio
/// (la pista de audio ya se maneja con just_audio).
class TemVideoPlayerWidget extends StatefulWidget {
  final String? videoUrl;

  const TemVideoPlayerWidget({super.key, required this.videoUrl});

  @override
  State<TemVideoPlayerWidget> createState() => TemVideoPlayerWidgetState();
}

class TemVideoPlayerWidgetState extends State<TemVideoPlayerWidget> {
  late final Player _player;
  late final VideoController _controller;

  String? _resolvedUrl;
  String? _lastSourceUrl;
  bool _ready = false;

  /// Permite al padre saber si el video ya está listo para reproducir.
  bool get isReady => _ready;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
    // Silenciar video — el audio se reproduce con just_audio
    _player.setVolume(0);
    _prepareVideo(widget.videoUrl);
  }

  @override
  void didUpdateWidget(TemVideoPlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _prepareVideo(widget.videoUrl);
    }
  }

  Future<void> _prepareVideo(String? gsUrl) async {
    debugPrint('[VID] _prepareVideo called | gsUrl=$gsUrl');
    if (gsUrl == null || gsUrl.isEmpty) {
      debugPrint(
        '[VID] _prepareVideo → gsUrl null/empty, setting _ready=false',
      );
      setState(() => _ready = false);
      return;
    }

    // Evitar re-resolver la misma URL
    if (gsUrl == _lastSourceUrl && _resolvedUrl != null) {
      debugPrint('[VID] _prepareVideo → same source, skip resolve');
      return;
    }
    _lastSourceUrl = gsUrl;

    try {
      final sw = Stopwatch()..start();
      final String url;
      if (gsUrl.startsWith('gs://')) {
        url = await FirebaseStorage.instance.refFromURL(gsUrl).getDownloadURL();
      } else {
        url = gsUrl;
      }
      _resolvedUrl = url;
      debugPrint(
        '[VID] resolved in ${sw.elapsedMilliseconds}ms → ${url.substring(0, url.length.clamp(0, 80))}...',
      );
      await _player.open(Media(url), play: false);
      debugPrint(
        '[VID] player.open done in ${sw.elapsedMilliseconds}ms | _ready=true',
      );
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      debugPrint('[VID] prepareVideo ERROR: $e');
      if (mounted) setState(() => _ready = false);
    }
  }

  /// Inicia la reproducción del video desde el inicio.
  Future<void> play() async {
    debugPrint('[VID] play() called | _ready=$_ready');
    if (!_ready) return;
    final sw = Stopwatch()..start();
    await _player.seek(Duration.zero);
    debugPrint('[VID] seek(0) done in ${sw.elapsedMilliseconds}ms');
    await _player.play();
    debugPrint('[VID] play() done in ${sw.elapsedMilliseconds}ms');
  }

  /// Pausa el video.
  Future<void> pause() async {
    await _player.pause();
  }

  /// Detiene el video y rebobina al inicio.
  Future<void> stop() async {
    debugPrint('[VID] stop() called');
    await _player.pause();
    await _player.seek(Duration.zero);
    debugPrint('[VID] stop() done');
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: 300,
        height: 220,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: _ready
                ? IgnorePointer(
                    child: Video(
                      controller: _controller,
                      fill: Colors.black,
                      controls: null,
                    ),
                  )
                : const Center(
                    child: Icon(
                      Icons.videocam_off_rounded,
                      size: 48,
                      color: Colors.white38,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
