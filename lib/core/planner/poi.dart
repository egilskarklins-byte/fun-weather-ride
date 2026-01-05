enum PoiCategory {
  nature,
  museum,
  city,
  food,
}

class Poi {
  final String name;
  final int hours;
  final PoiCategory category;
  final double lat;
  final double lng;

  Poi({
    required this.name,
    required this.hours,
    required this.category,
    required this.lat,
    required this.lng,
  });
}
