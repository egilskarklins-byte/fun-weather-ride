import 'geo.dart';

enum PoiCategory {
  mustSee,
  nature,
  beach,
  viewpoint,
  museum,
  indoor,
  food,
  city,
}

class Poi {
  final String id;
  final String name;
  final LatLon location;

  final double durationH;
  final Set<PoiCategory> categories;
  final bool isIndoor;

  const Poi({
    required this.id,
    required this.name,
    required this.location,
    this.durationH = 1.5,
    this.categories = const {PoiCategory.mustSee},
    this.isIndoor = false,
  });
}
