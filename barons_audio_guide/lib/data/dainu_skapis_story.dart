import '../models/audio_story.dart';

final AudioStory dainuSkapisStory = AudioStory(
  title: "Dainu skapis",
  imageUrl: "assets/images/dainu_skapis.jpg",
  sections: [
    StorySection(
      title: "Kas ir Dainu skapis?",
      audioPath: "assets/audio/dainu_skapis_special.mp3",
      images: [
        'assets/images/dainu_skapis.jpg',
      ],
      text: """
Dainu skapis ir viens no nozīmīgākajiem latviešu kultūras simboliem.

Tajā tika glabātas vairāk nekā divsimt tūkstoši tautasdziesmu.

Tas ir unikāls pasaules mēroga kultūras mantojums.
""",
    ),
  ],
);