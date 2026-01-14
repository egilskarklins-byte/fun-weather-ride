import 'geo.dart';
import 'poi.dart';

enum TripMode { singleBase, movingTour }
enum TransportMode { car, bike }
enum FitnessLevel { low, medium, high }
enum TravelParty { solo, couple, family }

class TripInput {
  final DateTime startDate;
  final DateTime endDate;
  final int daysCount;

  final TripMode mode;
  final TransportMode transport;
  final FitnessLevel fitness;
  final TravelParty party;

  final String regionText;
  final LatLon startPoint;

  final int maxKmPerDay;

  final List<Poi> mustSee;

  const TripInput({
    required this.startDate,
    required this.endDate,
    required this.daysCount,
    required this.mode,
    required this.transport,
    required this.fitness,
    required this.party,
    required this.regionText,
    required this.startPoint,
    required this.maxKmPerDay,
    required this.mustSee,
  });

  double fitnessMultiplier() => switch (fitness) {
    FitnessLevel.low => 0.75,
    FitnessLevel.medium => 1.0,
    FitnessLevel.high => 1.2,
  };

  /// Dienas laika "budžets" (braukšana + pieturas) — NEATKARĪGI no km slīdņa.
  /// Km slīdnis limitē attālumu atsevišķi.
  double get maxHoursPerDay => switch (transport) {
    TransportMode.car => 9.0,
    TransportMode.bike => 6.0,
  };
}
