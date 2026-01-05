import 'day_theme.dart';
import 'poi.dart';

class ThemePoiMap {
  static List<PoiCategory> categoriesForTheme(DayTheme theme) {
    switch (theme) {
      case DayTheme.nature:
        return [
          PoiCategory.nature,
        ];

      case DayTheme.city:
        return [
          PoiCategory.city,
          PoiCategory.museum,
          PoiCategory.food,
        ];

      case DayTheme.indoor:
        return [
          PoiCategory.museum,
          PoiCategory.food,
        ];

      case DayTheme.free:
      default:
        return [
          PoiCategory.city,
          PoiCategory.food,
        ];
    }
  }
}
