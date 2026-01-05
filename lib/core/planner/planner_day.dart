import 'day_theme.dart';
import 'must_see.dart';
import 'poi.dart';

class PlannerDay {
  final int dayIndex;

  String startLocation;
  String endLocation;

  DayTheme theme;

  final List<MustSee> mustSee;
  final List<Poi> poi;

  PlannerDay({
    required this.dayIndex,
    required this.startLocation,
    required this.endLocation,
  })  : theme = DayTheme.free,
        mustSee = [],
        poi = [];

  int get totalHours {
    int sum = 0;

    for (final m in mustSee) {
      sum += m.hours;
    }

    for (final p in poi) {
      sum += p.hours;
    }

    return sum;
  }
}
