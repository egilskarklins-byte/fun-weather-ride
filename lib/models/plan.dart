import 'geo.dart';
import 'poi.dart';
import 'weather.dart';

enum DayTheme { indoor, nature, mixed }

class DayPlan {
  final DateTime date;
  final DayTheme theme;

  /// For singleBase: always same. For movingTour: changes day-by-day.
  final LatLon base;

  /// Must-see assigned for this day (bez overnight pieturām)
  final List<Poi> mustSee;

  /// Full stops list (base + pois + base if singleBase + overnight if any)
  final List<Poi> stops;

  final int estKm;
  final double estHours;

  final WeatherDay? weather;

  /// Teksts, ko tu jau rādi UI ("must-see: 2 • ~5.4 h • ~210 km")
  final String summary;

  /// ✅ True, ja šajā dienā ir automātiski ieliktas nakts pieturas
  final bool hasOvernightStops;

  final double? debugWeatherScore;
  final Map<String, double>? debugPenalties;
  final List<String>? debugMoved;


  const DayPlan({
    required this.date,
    required this.theme,
    required this.base,
    required this.mustSee,
    required this.stops,
    required this.estKm,
    required this.estHours,
    required this.weather,
    required this.summary,
    required this.hasOvernightStops,
    this.debugWeatherScore,
    this.debugPenalties,
    this.debugMoved,

  });

  /// UI ērtībai – tikai overnight pieturas
  List<Poi> get overnightStops =>
      stops.where((p) => p.isOvernightStop).toList();

  /// UI ērtībai – tikai lietotāja izvēlētie must-see
  List<Poi> get realMustSee =>
      mustSee.where((p) => !p.isOvernightStop).toList();
}
