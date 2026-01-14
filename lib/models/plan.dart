import 'geo.dart';
import 'poi.dart';
import 'weather.dart';

enum DayTheme { indoor, nature, mixed }

class DayPlan {
  final DateTime date;
  final DayTheme theme;

  /// For singleBase: always same. For movingTour: changes day-by-day.
  final LatLon base;

  /// Must-see assigned for this day
  final List<Poi> mustSee;

  /// Full stops list (base + pois + base if singleBase)
  final List<Poi> stops;

  final int estKm;
  final double estHours;

  final WeatherDay? weather;
  final String summary;

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
  });
}
