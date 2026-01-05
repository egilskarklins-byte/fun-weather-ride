import 'planner_day.dart';
import 'planner_input.dart';
import 'day_theme.dart';
import 'theme_poi_map.dart';
import 'poi_repository.dart';

class PlannerEngine {
  List<PlannerDay> plan(PlannerInput input) {
    final days = _buildDays(input);

    _assignThemes(days, input);
    _distributeMustSee(days, input);
    _fillPoi(days, input);

    return days;
  }

  // -------------------------
  // DAY CREATION (MODE LOGIC)
  // -------------------------
  List<PlannerDay> _buildDays(PlannerInput input) {
    final List<PlannerDay> days = [];

    String currentLocation = input.startLocation;

    for (int i = 0; i < input.days; i++) {
      final start = currentLocation;

      final end = input.mode == TripMode.singleBase
          ? input.startLocation
          : 'NextLocation_${i + 1}';

      days.add(
        PlannerDay(
          dayIndex: i + 1,
          startLocation: start,
          endLocation: end,
        ),
      );

      if (input.mode == TripMode.movingTour) {
        currentLocation = end;
      }
    }

    return days;
  }

  // -------------------------
  // WEATHER → THEME
  // -------------------------
  void _assignThemes(List<PlannerDay> days, PlannerInput input) {
    for (int i = 0; i < days.length; i++) {
      days[i].theme = DayThemeResolver.fromWeather(input.weather[i]);
    }
  }

  // -------------------------
  // MUST-SEE (simple distribution)
  // -------------------------
  void _distributeMustSee(List<PlannerDay> days, PlannerInput input) {
    int dayIndex = 0;

    for (final place in input.mustSee) {
      days[dayIndex].mustSee.add(place);
      dayIndex = (dayIndex + 1) % days.length;
    }
  }

  // -------------------------
  // POI FILL (RESPECT maxHoursPerDay)
  // -------------------------
  void _fillPoi(List<PlannerDay> days, PlannerInput input) {
    for (final day in days) {
      final categories = ThemePoiMap.categoriesForTheme(day.theme);

      final availablePoi = PoiRepository.all()
          .where((p) => categories.contains(p.category))
          .toList();

      for (final poi in availablePoi) {
        if (day.totalHours + poi.hours <= input.maxHoursPerDay) {
          day.poi.add(poi);
        }
      }
    }
  }
}
