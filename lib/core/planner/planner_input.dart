import 'must_see.dart';
import 'weather_day.dart';

enum TripMode {
  singleBase,
  movingTour,
}

class PlannerInput {
  final int days;
  final int maxHoursPerDay;
  final List<MustSee> mustSee;
  final List<WeatherDay> weather;

  final TripMode mode;
  final String startLocation;

  PlannerInput({
    required this.days,
    required this.maxHoursPerDay,
    required this.mustSee,
    required this.weather,
    required this.mode,
    required this.startLocation,
  });
}
