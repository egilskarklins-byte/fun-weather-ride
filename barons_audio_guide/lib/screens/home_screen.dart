import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../data/barons_stories.dart';
import 'story_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  late Animation<double> _fadeText;
  late Animation<double> _slideText;
  late Animation<double> _buttonFade;
  late Animation<double> _zoomBg;
  late Animation<double> _pixelReveal;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    _pixelReveal = Tween(begin: 1.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.58, curve: Curves.easeOutCubic),
      ),
    );

    _fadeText = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.78, curve: Curves.easeOut),
      ),
    );

    _slideText = Tween(begin: 26.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.34, 0.78, curve: Curves.easeOutCubic),
      ),
    );

    _buttonFade = Tween(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.58, 1.0, curve: Curves.easeOut),
      ),
    );

    _zoomBg = Tween(begin: 1.06, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutCubic,
      ),
    );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _openStory(BuildContext context, dynamic story) {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => StoryScreen(story: story),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final story = stories.first;

    return Scaffold(
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Stack(
            children: [
              Positioned.fill(
                child: Transform.scale(
                  scale: _zoomBg.value,
                  child: Image.asset(
                    story.imageUrl,
                    fit: BoxFit.cover,
                  ),
                ),
              ),

              Positioned.fill(
                child: CustomPaint(
                  painter: _PixelRevealPainter(
                    progress: _pixelReveal.value,
                  ),
                ),
              ),

              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.08),
                        Colors.black.withOpacity(0.18),
                        Colors.black.withOpacity(0.72),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                  child: Column(
                    children: [
                      const Align(
                        alignment: Alignment.topLeft,
                        child: Text(
                          'Barona audio gids',
                          style: TextStyle(
                            fontSize: 17,
                            color: Colors.white70,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),

                      const Spacer(),

                      Transform.translate(
                        offset: Offset(0, _slideText.value),
                        child: Opacity(
                          opacity: _fadeText.value,
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.36),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.16),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  story.title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                    height: 1.05,
                                  ),
                                ),

                                const SizedBox(height: 13),

                                const Text(
                                  'Iepazīsti Krišjāni Baronu caur stāstiem, attēliem un audio.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: Colors.white,
                                    height: 1.32,
                                  ),
                                ),

                                const SizedBox(height: 5),

                                const Text(
                                  'Interaktīva pieredze ar jautājumiem un galerijām.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.white70,
                                    height: 1.32,
                                  ),
                                ),

                                const SizedBox(height: 22),

                                Opacity(
                                  opacity: _buttonFade.value,
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: ElevatedButton.icon(
                                      icon: const Icon(Icons.play_arrow_rounded),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 15,
                                        ),
                                        backgroundColor: Colors.white,
                                        foregroundColor: Colors.brown.shade900,
                                        elevation: 8,
                                        shadowColor: Colors.black45,
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                          BorderRadius.circular(18),
                                        ),
                                      ),
                                      onPressed: () {
                                        _openStory(context, story);
                                      },
                                      label: const Text(
                                        'Sākt apskati',
                                        style: TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.bold,
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
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PixelRevealPainter extends CustomPainter {
  _PixelRevealPainter({
    required this.progress,
  });

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.01) return;

    const cell = 19.0;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.longestSide * 0.78;

    final columns = (size.width / cell).ceil();
    final rows = (size.height / cell).ceil();

    final paint = Paint()..style = PaintingStyle.fill;

    for (int y = 0; y < rows; y++) {
      for (int x = 0; x < columns; x++) {
        final px = x * cell + cell / 2;
        final py = y * cell + cell / 2;

        final dx = px - center.dx;
        final dy = py - center.dy;

        final distance = math.sqrt(dx * dx + dy * dy);
        final angle = math.atan2(dy, dx);

        final normalizedDistance = (distance / maxRadius).clamp(0.0, 1.0);
        final normalizedAngle = (angle + math.pi) / (math.pi * 2);

        final spiral = (normalizedDistance * 0.78 +
            normalizedAngle * 0.42 +
            progress * 0.65) %
            1.0;

        final reveal = (progress - spiral + 0.32).clamp(0.0, 1.0);

        if (reveal > 0) {
          final opacity = reveal.clamp(0.0, 1.0);
          final blockOpacity = 0.84 * opacity;

          paint.color = Colors.black.withOpacity(blockOpacity);

          final shrink = cell * (1.0 - opacity) * 0.44;

          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(
                x * cell + shrink,
                y * cell + shrink,
                cell - shrink * 2 + 1,
                cell - shrink * 2 + 1,
              ),
              Radius.circular(4 * opacity),
            ),
            paint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelRevealPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}