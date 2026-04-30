import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/audio_story.dart';

enum SectionTab {
  photo,
  text,
  audio,
  quiz,
}

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

  int? _selectedAnswer;
  bool _answered = false;

  late int _currentIndex;
  SectionTab _selectedTab = SectionTab.photo;

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
        _selectedAnswer = null;
        _answered = false;
      });

      await _player.stop();
      await _player.setAsset(section.audioPath);

      if (!mounted) return;

      setState(() => _isLoading = false);

      if (autoplay) {
        await _player.play();
      }
    } catch (_) {
      if (!mounted) return;
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

    setState(() {
      _currentIndex++;
      _selectedTab = SectionTab.photo;
    });

    await _loadAudio(autoplay: false);
  }

  Future<void> _prev() async {
    if (_currentIndex == 0) return;

    setState(() {
      _currentIndex--;
      _selectedTab = SectionTab.photo;
    });

    await _loadAudio(autoplay: false);
  }

  Color _quizButtonColor({
    required int index,
    required int correctIndex,
  }) {
    if (!_answered) {
      return Colors.blue.shade600;
    }

    if (index == correctIndex) {
      return Colors.green.shade400;
    }

    if (index == _selectedAnswer) {
      return Colors.red.shade400;
    }

    return Colors.grey.shade300;
  }

  Color _quizTextColor({
    required int index,
    required int correctIndex,
  }) {
    if (!_answered) {
      return Colors.white;
    }

    if (index == correctIndex || index == _selectedAnswer) {
      return Colors.white;
    }

    return Colors.black87;
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
                  Text(
                    s.title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 14),

                  _buildTabButtons(),

                  const SizedBox(height: 22),

                  if (_selectedTab == SectionTab.photo) _buildPhotoTab(s),
                  if (_selectedTab == SectionTab.text) _buildTextTab(s),
                  if (_selectedTab == SectionTab.audio) _buildAudioTab(),
                  if (_selectedTab == SectionTab.quiz) _buildQuizTab(s),

                  const SizedBox(height: 30),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _currentIndex == 0 ? null : _prev,
                        icon: const Icon(Icons.skip_previous),
                        label: const Text("Iepriekšējā"),
                      ),
                      OutlinedButton.icon(
                        onPressed: _currentIndex >= widget.sections.length - 1
                            ? null
                            : _next,
                        icon: const Icon(Icons.skip_next),
                        label: const Text("Nākamā"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabButtons() {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _tabButton(
          tab: SectionTab.photo,
          label: "Foto",
          icon: Icons.photo,
        ),
        _tabButton(
          tab: SectionTab.text,
          label: "Teksts",
          icon: Icons.article,
        ),
        _tabButton(
          tab: SectionTab.audio,
          label: "Audio",
          icon: Icons.headphones,
        ),
        _tabButton(
          tab: SectionTab.quiz,
          label: "Tests",
          icon: Icons.quiz,
        ),
      ],
    );
  }

  Widget _tabButton({
    required SectionTab tab,
    required String label,
    required IconData icon,
  }) {
    final selected = _selectedTab == tab;

    return ElevatedButton.icon(
      onPressed: () {
        setState(() {
          _selectedTab = tab;
        });
      },
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: selected ? Colors.blue.shade700 : Colors.grey.shade200,
        foregroundColor: selected ? Colors.white : Colors.black87,
        padding: const EdgeInsets.symmetric(
          vertical: 12,
          horizontal: 14,
        ),
      ),
    );
  }

  Widget _buildPhotoTab(StorySection s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.images.length == 1)
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: GestureDetector(
              onTap: () {
                _openGallery(context, s.images, 0);
              },
              child: Image.asset(
                s.images.first,
                width: double.infinity,
                height: 280,
                fit: BoxFit.contain,
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: s.images.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              crossAxisSpacing: 6,
              mainAxisSpacing: 6,
            ),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: () {
                  _openGallery(context, s.images, index);
                },
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(
                    s.images[index],
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildTextTab(StorySection s) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Text(
          s.text,
          style: const TextStyle(
            fontSize: 20,
            height: 1.5,
          ),
        ),
      ),
    );
  }

  Widget _buildAudioTab() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(
              Icons.headphones,
              size: 52,
            ),

            const SizedBox(height: 12),

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

            const SizedBox(height: 18),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.replay_10),
                  onPressed: () async {
                    final newPos = _position - const Duration(seconds: 10);
                    await _player.seek(
                      newPos < Duration.zero ? Duration.zero : newPos,
                    );
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
                    final newPos = _position + const Duration(seconds: 10);
                    await _player.seek(
                      newPos > _duration ? _duration : newPos,
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 10),

            TextButton.icon(
              onPressed: _repeat,
              icon: const Icon(Icons.replay),
              label: const Text("Atkārtot"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuizTab(StorySection s) {
    if (s.question == null || s.answers == null || s.correctIndex == null) {
      return Card(
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Padding(
          padding: EdgeInsets.all(18),
          child: Text(
            "Šai sadaļai tests vēl nav pievienots.",
            style: TextStyle(fontSize: 18),
          ),
        ),
      );
    }

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Jautājums",
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 10),

            Text(
              s.question!,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 14),

            ...List.generate(s.answers!.length, (index) {
              final buttonColor = _quizButtonColor(
                index: index,
                correctIndex: s.correctIndex!,
              );

              final textColor = _quizTextColor(
                index: index,
                correctIndex: s.correctIndex!,
              );

              return Container(
                width: double.infinity,
                margin: const EdgeInsets.symmetric(vertical: 5),
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: buttonColor,
                    disabledBackgroundColor: buttonColor,
                    foregroundColor: textColor,
                    disabledForegroundColor: textColor,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 12,
                    ),
                  ),
                  onPressed: _answered
                      ? null
                      : () {
                    setState(() {
                      _selectedAnswer = index;
                      _answered = true;
                    });
                  },
                  child: Text(
                    s.answers![index],
                    style: const TextStyle(fontSize: 17),
                  ),
                ),
              );
            }),

            if (_answered) ...[
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _selectedAnswer == s.correctIndex
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _selectedAnswer == s.correctIndex
                        ? Colors.green.shade300
                        : Colors.red.shade300,
                  ),
                ),
                child: Text(
                  _selectedAnswer == s.correctIndex
                      ? "✅ Pareizi!"
                      : "❌ Nepareizi\n✔ Pareizā atbilde: ${s.answers![s.correctIndex!]}",
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
void _openGallery(BuildContext context, List<String> images, int startIndex) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => _GalleryScreen(
        images: images,
        startIndex: startIndex,
      ),
    ),
  );
}
String _formatTime(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
class _GalleryScreen extends StatefulWidget {
  const _GalleryScreen({
    required this.images,
    required this.startIndex,
  });

  final List<String> images;
  final int startIndex;

  @override
  State<_GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<_GalleryScreen> {
  late final PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.startIndex;
    _controller = PageController(initialPage: widget.startIndex);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goPrevious() {
    if (_currentIndex <= 0) return;

    _controller.previousPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _goNext() {
    if (_currentIndex >= widget.images.length - 1) return;

    _controller.nextPage(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canGoPrevious = _currentIndex > 0;
    final canGoNext = _currentIndex < widget.images.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text("${_currentIndex + 1}/${widget.images.length}"),
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            itemCount: widget.images.length,
            onPageChanged: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            itemBuilder: (context, index) {
              return InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Image.asset(
                    widget.images[index],
                    fit: BoxFit.contain,
                  ),
                ),
              );
            },
          ),
          if (canGoPrevious)
            Positioned(
              left: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filled(
                  onPressed: _goPrevious,
                  icon: const Icon(Icons.chevron_left),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ),
          if (canGoNext)
            Positioned(
              right: 12,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton.filled(
                  onPressed: _goNext,
                  icon: const Icon(Icons.chevron_right),
                  color: Colors.white,
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}