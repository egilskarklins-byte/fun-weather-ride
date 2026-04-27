import '../models/audio_story.dart';

final List<AudioStory> stories = [
  AudioStory(
    title: "Krišjānis Barons",
    imageUrl: "assets/images/barons.jpg",
    sections: [
      StorySection(
        title: "Ievads",
        audioPath: "assets/audio/barons_01_ievads.mp3",
        images: [
          "assets/images/barons.jpg",
        ],
        text: """
Iedomājies laiku, kad Latvijai vēl nebija savas valsts.

Tieši tad Krišjānis Barons sāka vākt latviešu tautas dziesmas — dainas.

Viņš ticēja, ka tajās slēpjas tautas gudrība, vēsture un dvēsele.

Bez viņa darba mēs šodien daudz ko vienkārši nezinātu.

Viņu bieži sauc par Dainu tēvu.
""",
      ),
      StorySection(
        title: "Bērnība",
        audioPath: "assets/audio/barons_02_berniba.mp3",
        images: [
          "assets/images/barons.jpg",
        ],
        text: """
Krišjānis Barons piedzima laikā, kad latviešu zemnieku bērniem izglītība nebija pašsaprotama.

Tomēr viņa dzīvē agri parādījās interese par zināšanām, valodu un grāmatām.

Šī interese vēlāk kļuva par pamatu viņa lielajam mūža darbam.
""",
      ),
      StorySection(
        title: "Studijas",
        audioPath: "assets/audio/barons_03_studijas.mp3",
        images: [
          "assets/images/barons.jpg",
        ],
        text: """
Studiju gadi Baronam deva plašāku skatījumu uz pasauli.

Viņš iepazina zinātni, literatūru un idejas, kas vēlāk palīdzēja saprast tautasdziesmu nozīmi daudz dziļāk.

Barons nebija tikai vācējs — viņš bija arī domātājs un kārtotājs.
""",
      ),
      StorySection(
        title: "Darbība Krievijā",
        audioPath: "assets/audio/barons_04_krievija.mp3",
        images: [
          "assets/images/barons.jpg",
        ],
        text: """
Pēc studiju gadiem Krišjānis Barons devās uz Krievijas impērijas galvaspilsētu Pēterburgu.

Tur viņš strādāja par mājskolotāju un vienlaikus iesaistījās latviešu sabiedriskajā dzīvē.

Pēterburgā viņš satika citus latviešu domubiedrus, ar kuriem apsprieda kultūras un izglītības jautājumus.

Viņš piedalījās arī laikraksta “Pēterburgas Avīzes” darbībā.

Tieši šajā laikā Barons arvien vairāk pievērsās tautasdziesmām un sāka tās apzināti vākt.

Dzīve svešumā palīdzēja viņam saprast, cik svarīgi ir saglabāt latviešu kultūru un identitāti.
""",
      ),
      StorySection(
        title: "Dainu vākšana",
        audioPath: "assets/audio/barons_05_dainas.mp3",
        images: [
          "assets/images/dainu_skapis.jpg",
        ],
        text: """
Latviešu tautasdziesmas tika pierakstītas no cilvēku atmiņām.

Tās ceļoja no mājām uz mājām, no pagastiem uz pilsētām, līdz nonāca pie Barona.

Viņa uzdevums bija tās sakārtot tā, lai tās varētu saglabāt nākamajām paaudzēm.
""",
      ),
      StorySection(
        title: "Dainu skapis",
        audioPath: "assets/audio/barons_06_dainu_skapis.mp3",
        images: [
          "assets/images/dainu_skapis.jpg",
        ],
        text: """
Šis nav parasts skapis.

Tas ir slavenais Dainu skapis.

Tajā glabātas vairāk nekā 200 tūkstoši tautas dziesmu.

Katra lapiņa ir kā daļa no Latvijas stāsta.

Barons tās rūpīgi sakārtoja, lai nekas nepazustu.
""",
      ),
      StorySection(
        title: "Mantojums",
        audioPath: "assets/audio/barons_07_mantojums.mp3",
        images: [
          "assets/images/barons.jpg",
          "assets/images/dainu_skapis.jpg",
        ],
        text: """
Krišjāņa Barona darbs nav tikai pagātnes liecība.

Tas joprojām palīdz saprast, kā latvieši domāja, dziedāja, juta un nodeva savu pieredzi tālāk.

Tāpēc Barona vārds Latvijas kultūrā ir īpašs.
""",
      ),
    ],
  ),
];