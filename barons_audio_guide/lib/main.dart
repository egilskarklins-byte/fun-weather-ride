import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'screens/story_screen.dart';
import 'data/dainu_skapis_story.dart';

void main() {
  runApp(const BaronsApp());
}

class BaronsApp extends StatelessWidget {
  const BaronsApp({super.key});

  @override
  Widget build(BuildContext context) {
    final guide = Uri.base.queryParameters['guide'];

    Widget startScreen = const HomeScreen();

    if (guide == 'dainu') {
      startScreen = StoryScreen(story: dainuSkapisStory);
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Barona audio gids',
      theme: ThemeData(
        primarySwatch: Colors.brown,
      ),
      home: startScreen,
    );
  }
}