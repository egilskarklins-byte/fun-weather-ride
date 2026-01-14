import 'dart:convert';

import 'geo.dart';
import 'poi.dart';
import 'trip.dart';

class Project {
  final String id;
  final String name;

  final DateTime? startDate;
  final DateTime? endDate;

  final TripMode mode;
  final TransportMode transport;
  final FitnessLevel fitness;
  final TravelParty party;

  final String regionText;
  final LatLon startPoint;

  final double maxKmPerDay;

  final List<Poi> mustSee;

  Project({
    required this.id,
    required this.name,
    required this.mode,
    required this.transport,
    required this.fitness,
    required this.party,
    required this.regionText,
    required this.startPoint,
    required this.maxKmPerDay,
    required this.mustSee,
    this.startDate,
    this.endDate,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'startDate': startDate?.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'mode': mode.name,
    'transport': transport.name,
    'fitness': fitness.name,
    'party': party.name,
    'regionText': regionText,
    'startPoint': {'lat': startPoint.lat, 'lon': startPoint.lon},
    'maxKmPerDay': maxKmPerDay,
    'mustSee': mustSee
        .map((p) => {
      'id': p.id,
      'name': p.name,
      'lat': p.location.lat,
      'lon': p.location.lon,
      'durationH': p.durationH,
      'isIndoor': p.isIndoor,
      'categories': p.categories.map((c) => c.name).toList(),
    })
        .toList(),
    'v': 1,
  };

  static Project fromJson(Map<String, dynamic> json) {
    DateTime? dt(String? s) => (s == null || s.isEmpty) ? null : DateTime.tryParse(s);

    T enumByName<T extends Enum>(List<T> values, String name, T fallback) {
      return values.firstWhere(
            (e) => e.name == name,
        orElse: () => fallback,
      );
    }

    final sp = json['startPoint'] as Map<String, dynamic>?;

    final must = (json['mustSee'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map((e) {
      final catsRaw = (e['categories'] as List? ?? const []).map((x) => x.toString()).toList();
      final cats = <PoiCategory>{};
      for (final c in catsRaw) {
        final hit = PoiCategory.values.where((v) => v.name == c).toList();
        if (hit.isNotEmpty) cats.add(hit.first);
      }
      if (cats.isEmpty) cats.add(PoiCategory.mustSee);

      return Poi(
        id: (e['id'] ?? '').toString(),
        name: (e['name'] ?? '').toString(),
        location: LatLon(
          (e['lat'] as num).toDouble(),
          (e['lon'] as num).toDouble(),
        ),
        durationH: ((e['durationH'] as num?) ?? 1.5).toDouble(),
        categories: cats,
        isIndoor: (e['isIndoor'] as bool?) ?? false,
      );
    }).toList();

    return Project(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      startDate: dt(json['startDate']?.toString()),
      endDate: dt(json['endDate']?.toString()),
      mode: enumByName(TripMode.values, (json['mode'] ?? TripMode.singleBase.name).toString(), TripMode.singleBase),
      transport: enumByName(TransportMode.values, (json['transport'] ?? TransportMode.car.name).toString(), TransportMode.car),
      fitness: enumByName(FitnessLevel.values, (json['fitness'] ?? FitnessLevel.medium.name).toString(), FitnessLevel.medium),
      party: enumByName(TravelParty.values, (json['party'] ?? TravelParty.solo.name).toString(), TravelParty.solo),
      regionText: (json['regionText'] ?? 'Rīga un apkārtne, Latvija').toString(),
      startPoint: LatLon(
        ((sp?['lat'] as num?) ?? 56.9496).toDouble(),
        ((sp?['lon'] as num?) ?? 24.1052).toDouble(),
      ),
      maxKmPerDay: ((json['maxKmPerDay'] as num?) ?? 180).toDouble(),
      mustSee: must,
    );
  }

  static String encodeList(List<Project> projects) =>
      jsonEncode(projects.map((p) => p.toJson()).toList());

  static List<Project> decodeList(String raw) =>
      (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(Project.fromJson).toList();
}
