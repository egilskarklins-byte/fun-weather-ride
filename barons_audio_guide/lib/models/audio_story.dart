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

  final String? question;
  final List<String>? answers;
  final int? correctIndex;

  const StorySection({
    required this.title,
    required this.text,
    required this.audioPath,
    required this.images,

    this.question,
    this.answers,
    this.correctIndex,
  });
}