import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_story.dart';

class SectionScreen extends StatefulWidget {
  const SectionScreen({
    super.key,
    required this.sections,
    required this.currentIndex,
  });

  final List<StorySection> sections;
  final int currentIndex;

  @override
  State<SectionScreen> createState() => _SectionScreenState();
}

class _SectionScreenState extends State<SectionScreen> {
  final AudioPlayer _player = AudioPlayer();

  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;

  bool _isPlaying = false;
  bool _isLoading = true;

  late int _currentIndex;

  StorySection get section => widget.sections[_currentIndex];

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.currentIndex;
    _loadAudio();

    _player.durationStream.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d ?? Duration.zero);
    });

    _player.positionStream.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });

    _player.playerStateStream.listen((state) {
      if (!mounted) return;

      setState(() {
        _isPlaying = state.playing;
        _isLoading =
            state.processingState == ProcessingState.loading ||
                state.processingState == ProcessingState.buffering;
      });
    });
  }

  Future<void> _loadAudio({bool autoplay = false}) async {
    try {
      setState(() {
        _isLoading = true;
        _position = Duration.zero;
        _duration = Duration.zero;
      });

      await _player.stop();
      await _player.setAsset(section.audioPath);

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (autoplay) {
        await _player.play();
      }
    } catch (_) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleAudio() async {
    if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _repeat() async {
    await _player.seek(Duration.zero);
    await _player.play();
  }

  Future<void> _next() async {
    if (_currentIndex >= widget.sections.length - 1) return;

    setState(() => _currentIndex++);
    await _loadAudio(autoplay: true);
  }

  Future<void> _prev() async {
    if (_currentIndex == 0) return;

    setState(() => _currentIndex--);
    await _loadAudio(autoplay: true);
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = section;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.title),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      s.images.first,
                      width: double.infinity,
                      height: 260,
                      fit: BoxFit.contain,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    s.text,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.5,
                    ),
                  ),

                  Slider(
                    min: 0,
                    max: _duration.inSeconds == 0
                        ? 1
                        : _duration.inSeconds.toDouble(),
                    value: _position.inSeconds
                        .clamp(0, _duration.inSeconds)
                        .toDouble(),
                    onChanged: (value) async {
                      await _player.seek(Duration(seconds: value.toInt()));
                    },
                  ),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(_formatTime(_position)),
                      Text(_formatTime(_duration)),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // 🔁 sadaļu navigācija
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        onPressed: _currentIndex == 0 ? null : _prev,
                        icon: const Icon(Icons.skip_previous),
                      ),
                      IconButton(
                        onPressed: _currentIndex >= widget.sections.length - 1
                            ? null
                            : _next,
                        icon: const Icon(Icons.skip_next),
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 🎧 audio kontrole
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.replay_10),
                        onPressed: () async {
                          final newPos =
                              _position - const Duration(seconds: 10);
                          await _player.seek(
                              newPos < Duration.zero ? Duration.zero : newPos);
                        },
                      ),

                      const SizedBox(width: 20),

                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _toggleAudio,
                        icon: Icon(
                          _isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                        label: Text(
                          _isLoading
                              ? "Ielādē..."
                              : _isPlaying
                              ? "Pauze"
                              : _position == Duration.zero
                              ? "Atskaņot"
                              : "Turpināt",
                        ),
                      ),

                      const SizedBox(width: 20),

                      IconButton(
                        icon: const Icon(Icons.forward_10),
                        onPressed: () async {
                          final newPos =
                              _position + const Duration(seconds: 10);
                          await _player.seek(
                              newPos > _duration ? _duration : newPos);
                        },
                      ),
                    ],
                  ),

                  const SizedBox(height: 10),

                  // 🔁 repeat
                  Center(
                    child: TextButton.icon(
                      onPressed: _repeat,
                      icon: const Icon(Icons.replay),
                      label: const Text("Atkārtot"),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _formatTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}