import 'dart:math';

class LatLon {
  final double lat;
  final double lon;
  const LatLon(this.lat, this.lon);
}

/// Haversine distance (km) between two points
double haversineKm(LatLon a, LatLon b) {
  const r = 6371.0;
  final dLat = _deg2rad(b.lat - a.lat);
  final dLon = _deg2rad(b.lon - a.lon);

  final sa = sin(dLat / 2);
  final sb = sin(dLon / 2);

  final h = sa * sa + cos(_deg2rad(a.lat)) * cos(_deg2rad(b.lat)) * sb * sb;
  return 2 * r * asin(min(1, sqrt(h)));
}

double _deg2rad(double d) => d * pi / 180.0;

LatLon centroid(List<LatLon> pts) {
  if (pts.isEmpty) return const LatLon(0, 0);
  final lat = pts.map((e) => e.lat).reduce((a, b) => a + b) / pts.length;
  final lon = pts.map((e) => e.lon).reduce((a, b) => a + b) / pts.length;
  return LatLon(lat, lon);
}

/// Projection of point onto a direction axis for "forward progress"
double projectionOnAxis({required LatLon origin, required LatLon axisPoint, required LatLon p}) {
  // approximate planar projection using lat/lon degrees (ok for Latvia scale)
  final ax = axisPoint.lon - origin.lon;
  final ay = axisPoint.lat - origin.lat;
  final px = p.lon - origin.lon;
  final py = p.lat - origin.lat;

  final denom = (ax * ax + ay * ay);
  if (denom == 0) return 0;
  return (px * ax + py * ay) / denom;
}
