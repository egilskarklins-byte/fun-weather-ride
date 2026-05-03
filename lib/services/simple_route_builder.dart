import 'dart:math';
import '../models/geo.dart';
import '../models/poi.dart';

class SimpleRouteBuilder {
  static List<Poi> buildRoute({
    required LatLon start,
    required List<Poi> pois,
    bool returnToStart = false,
  }) {
    final remaining = List<Poi>.from(pois);
    final result = <Poi>[];

    var currentLat = start.lat;
    var currentLon = start.lon;

    while (remaining.isNotEmpty) {
      Poi? nearest;
      double bestDist = double.infinity;

      for (final poi in remaining) {
        final d = _distanceKm(
          currentLat,
          currentLon,
          poi.location.lat,
          poi.location.lon,
        );

        if (d < bestDist) {
          bestDist = d;
          nearest = poi;
        }
      }

      if (nearest == null) break;

      result.add(nearest);
      remaining.remove(nearest);

      currentLat = nearest.location.lat;
      currentLon = nearest.location.lon;
    }
    if (returnToStart) {
      result.add(
        Poi(
          id: 'return_to_start',
          name: 'Atpakaļ uz sākumpunktu',
          location: start,
          durationH: 0,
          categories: {PoiCategory.mustSee},
          isIndoor: false,
        ),
      );
    }
    return result;
  }

  static double _distanceKm(
      double lat1,
      double lon1,
      double lat2,
      double lon2,
      ) {
    const R = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a =
        (sin(dLat / 2) * sin(dLat / 2)) +
            cos(_degToRad(lat1)) *
                cos(_degToRad(lat2)) *
                (sin(dLon / 2) * sin(dLon / 2));

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  static double _degToRad(double deg) => deg * 3.141592653589793 / 180.0;
}