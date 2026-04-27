class AudioStory {
  final String title;
  final String imageUrl;
  final List<StorySection> sections;

  const AudioStory({
    required this.title,
    required this.imageUrl,
    required this.sections,
  });
}

class StorySection {
  final String title;
  final String text;
  final String audioPath;
  final List<String> images;

  const StorySection({
    required this.title,
    required this.text,
    required this.audioPath,
    required this.images,
  });
}