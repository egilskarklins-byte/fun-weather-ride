import 'package:flutter/material.dart';

import '../models/audio_story.dart';
import 'section_screen.dart';

class StoryScreen extends StatelessWidget {
  const StoryScreen({
    super.key,
    required this.story,
  });

  final AudioStory story;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(story.title),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: story.sections.length,
        itemBuilder: (context, index) {
          final section = story.sections[index];

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 8),
            elevation: 6,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  section.images.first,
                  width: 60,
                  height: 60,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(
                section.title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
              trailing: const Icon(Icons.play_arrow),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SectionScreen(
                      sections: story.sections,
                      currentIndex: index,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}