import 'poi.dart';

class PoiRepository {
  static List<Poi> all() {
    return [
      Poi(
        name: 'City Park',
        hours: 1,
        category: PoiCategory.nature,
        lat: 56.9620,
        lng: 24.1130,
      ),
      Poi(
        name: 'Art Museum',
        hours: 2,
        category: PoiCategory.museum,
        lat: 56.9558,
        lng: 24.1133,
      ),
      Poi(
        name: 'Old Town Viewpoint',
        hours: 1,
        category: PoiCategory.city,
        lat: 56.9496,
        lng: 24.1052,
      ),
      Poi(
        name: 'Cafe Stop',
        hours: 1,
        category: PoiCategory.food,
        lat: 56.9489,
        lng: 24.1075,
      ),
    ];
  }
}
