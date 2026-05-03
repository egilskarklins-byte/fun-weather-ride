import 'dart:convert';

import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:http/http.dart' as http;

import '../models/geo.dart';
import '../models/poi.dart';

class GoogleRouteResult {
  final List<gmaps.LatLng> polylinePoints;
  final int distanceMeters;
  final String durationText;

  const GoogleRouteResult({
    required this.polylinePoints,
    required this.distanceMeters,
    required this.durationText,
  });
}

class GoogleRoutesService {
  final String apiKey;

  const GoogleRoutesService({
    required this.apiKey,
  });

  Future<GoogleRouteResult> computeDrivingRoute({
    required LatLon start,
    required List<Poi> orderedPois,
  }) async {
    if (orderedPois.isEmpty) {
      throw Exception('Nav izvēlēts neviens POI');
    }

    final destination = orderedPois.last;
    final intermediatePois = orderedPois.length > 1
        ? orderedPois.sublist(0, orderedPois.length - 1)
        : <Poi>[];

    final uri = Uri.parse(
      'https://routes.googleapis.com/directions/v2:computeRoutes',
    );

    final body = <String, dynamic>{
      'origin': _waypoint(start.lat, start.lon),
      'destination':
      _waypoint(destination.location.lat, destination.location.lon),
      if (intermediatePois.isNotEmpty)
        'intermediates': intermediatePois
            .map((p) => _waypoint(p.location.lat, p.location.lon))
            .toList(),
      'travelMode': 'DRIVE',
      'routingPreference': 'TRAFFIC_UNAWARE',
      'computeAlternativeRoutes': false,
      'languageCode': 'lv',
      'units': 'METRIC',
      'polylineQuality': 'OVERVIEW',
    };

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': 'AIzaSyBXUdUPuEI9poi_ZQCmlBffsMOfphXHWV8',
        'X-Goog-FieldMask':
        'routes.polyline.encodedPolyline,routes.distanceMeters,routes.duration',
      },
      body: jsonEncode(body),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Routes API HTTP ${response.statusCode}: ${response.body}',
      );
    }

    final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
    final routes = (jsonMap['routes'] as List<dynamic>? ?? []);

    if (routes.isEmpty) {
      throw Exception('Routes API neatgrieza maršrutu');
    }

    final firstRoute = routes.first as Map<String, dynamic>;
    final polylineMap =
        firstRoute['polyline'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final encoded = (polylineMap['encodedPolyline'] ?? '').toString();

    if (encoded.isEmpty) {
      throw Exception('Routes API neatgrieza polyline');
    }

    final distanceMeters =
        (firstRoute['distanceMeters'] as num?)?.toInt() ?? 0;
    final rawDuration = (firstRoute['duration'] ?? '').toString();

    return GoogleRouteResult(
      polylinePoints: _decodePolyline(encoded),
      distanceMeters: distanceMeters,
      durationText: _formatDuration(rawDuration),
    );
  }

  Map<String, dynamic> _waypoint(double lat, double lon) {
    return {
      'location': {
        'latLng': {
          'latitude': lat,
          'longitude': lon,
        },
      },
    };
  }

  String _formatDuration(String raw) {
    // Routes API parasti dod, piem., "3721s"
    final seconds =
        int.tryParse(raw.replaceAll('s', '').trim()) ?? 0;

    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;

    if (hours > 0) {
      return '${hours}h ${minutes}min';
    }
    return '${minutes}min';
  }

  List<gmaps.LatLng> _decodePolyline(String encoded) {
    final List<gmaps.LatLng> poly = [];
    int index = 0;
    int lat = 0;
    int lng = 0;

    while (index < encoded.length) {
      int result = 0;
      int shift = 0;
      int b;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      result = 0;
      shift = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      final dlng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(
        gmaps.LatLng(
          lat / 1e5,
          lng / 1e5,
        ),
      );
    }

    return poly;
  }
}