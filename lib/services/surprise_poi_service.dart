import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/geo.dart';
import '../models/poi.dart';

class SurprisePoiService {
  SurprisePoiService({
    this.apiKey,
  });

  // Atstājam, lai nekas nelūztu citos failos.
  // OSM variantā tas netiek izmantots.
  final String? apiKey;

  static const List<String> _overpassUrls = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
  ];

  Future<List<Poi>> fetchPois({
    required LatLon center,
    required double radiusKm,
    double minRating = 4.0,
    int maxResults = 30,
  }) async {
    return fetchPoisInRadius(
      center: center,
      radiusKm: radiusKm,
      minRating: minRating,
      maxResults: maxResults,
    );
  }

  Future<List<Poi>> fetchPoisInRadius({
    required LatLon center,
    required double radiusKm,
    double minRating = 4.0,
    int maxResults = 30,
  }) async {
    final searchCenters = _buildSearchCenters(center, radiusKm);
    final allCandidates = <_OsmPlace>[];

    for (final searchCenter in searchCenters) {
      final localRadiusMeters = min(
        25000,
        max(3000, (min(radiusKm, 25) * 1000).round()),
      );

      final fetched = await _fetchOverpassPlaces(
        center: searchCenter,
        radiusMeters: localRadiusMeters,
      );

      allCandidates.addAll(fetched);
    }

    final deduped = _dedupePlaces(allCandidates);

    final withinRequestedRadius = deduped.where((p) {
      final distKm = _haversineKm(center.lat, center.lon, p.lat, p.lon);
      return distKm <= radiusKm;
    }).toList();

    final filtered = withinRequestedRadius.where((p) {
      return _looksInteresting(p);
    }).toList();

    filtered.sort((a, b) {
      final scoreA = _scorePlace(a, center);
      final scoreB = _scorePlace(b, center);
      return scoreB.compareTo(scoreA);
    });

    final limited = filtered.take(maxResults).toList();

    return limited.map(_osmPlaceToPoi).toList();
  }

  Future<List<_OsmPlace>> _fetchOverpassPlaces({
    required LatLon center,
    required int radiusMeters,
  }) async {
    final query = '''
[out:json][timeout:25];
(
  node(around:$radiusMeters,${center.lat},${center.lon})["tourism"="attraction"];
  way(around:$radiusMeters,${center.lat},${center.lon})["tourism"="attraction"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["tourism"="attraction"];

  node(around:$radiusMeters,${center.lat},${center.lon})["tourism"="museum"];
  way(around:$radiusMeters,${center.lat},${center.lon})["tourism"="museum"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["tourism"="museum"];

  node(around:$radiusMeters,${center.lat},${center.lon})["tourism"="gallery"];
  way(around:$radiusMeters,${center.lat},${center.lon})["tourism"="gallery"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["tourism"="gallery"];

  node(around:$radiusMeters,${center.lat},${center.lon})["tourism"="viewpoint"];
  way(around:$radiusMeters,${center.lat},${center.lon})["tourism"="viewpoint"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["tourism"="viewpoint"];

  node(around:$radiusMeters,${center.lat},${center.lon})["leisure"="park"];
  way(around:$radiusMeters,${center.lat},${center.lon})["leisure"="park"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["leisure"="park"];

  node(around:$radiusMeters,${center.lat},${center.lon})["natural"];
  way(around:$radiusMeters,${center.lat},${center.lon})["natural"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["natural"];

  node(around:$radiusMeters,${center.lat},${center.lon})["historic"];
  way(around:$radiusMeters,${center.lat},${center.lon})["historic"];
  relation(around:$radiusMeters,${center.lat},${center.lon})["historic"];
);
out center tags;
''';

    Object? lastError;

    for (final baseUrl in _overpassUrls) {
      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          if (attempt > 0) {
            await Future.delayed(const Duration(seconds: 2));
          }

          final response = await http.post(
            Uri.parse(baseUrl),
            headers: const {
              'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
              'User-Agent': 'FunWeatherRide/1.0',
            },
            body: {
              'data': query,
            },
          );

          if (response.statusCode == 429) {
            lastError = Exception('OSM Overpass kļūda: 429');
            continue;
          }

          if (response.statusCode != 200) {
            lastError =
                Exception('OSM Overpass kļūda: ${response.statusCode}');
            continue;
          }

          final jsonMap = jsonDecode(response.body) as Map<String, dynamic>;
          final elements =
          (jsonMap['elements'] as List<dynamic>? ?? const <dynamic>[]);

          return elements
              .map((e) => _OsmPlace.fromOverpass(e as Map<String, dynamic>))
              .whereType<_OsmPlace>()
              .toList();
        } catch (e) {
          lastError = e;
        }
      }
    }

    throw lastError ?? Exception('OSM Overpass nav pieejams');
  }

  List<LatLon> _buildSearchCenters(LatLon center, double radiusKm) {
    final centers = <LatLon>[center];

    if (radiusKm <= 35) {
      return centers;
    }

    final offsetKm = min(radiusKm * 0.45, 22.0);

    centers.add(_offsetLatLon(center, 0, offsetKm));
    centers.add(_offsetLatLon(center, 90, offsetKm));
    centers.add(_offsetLatLon(center, 180, offsetKm));
    centers.add(_offsetLatLon(center, 270, offsetKm));

    if (radiusKm > 90) {
      final diag = min(radiusKm * 0.35, 18.0);
      centers.add(_offsetLatLon(center, 45, diag));
      centers.add(_offsetLatLon(center, 135, diag));
      centers.add(_offsetLatLon(center, 225, diag));
      centers.add(_offsetLatLon(center, 315, diag));
    }

    return centers;
  }

  LatLon _offsetLatLon(LatLon start, double bearingDeg, double distanceKm) {
    const earthRadiusKm = 6371.0;
    final bearing = _degToRad(bearingDeg);

    final lat1 = _degToRad(start.lat);
    final lon1 = _degToRad(start.lon);
    final angularDistance = distanceKm / earthRadiusKm;

    final lat2 = asin(
      sin(lat1) * cos(angularDistance) +
          cos(lat1) * sin(angularDistance) * cos(bearing),
    );

    final lon2 = lon1 +
        atan2(
          sin(bearing) * sin(angularDistance) * cos(lat1),
          cos(angularDistance) - sin(lat1) * sin(lat2),
        );

    return LatLon(_radToDeg(lat2), _radToDeg(lon2));
  }

  List<_OsmPlace> _dedupePlaces(List<_OsmPlace> input) {
    final byId = <String, _OsmPlace>{};
    final fallback = <String, _OsmPlace>{};

    for (final p in input) {
      if (p.id.isNotEmpty) {
        byId[p.id] = p;
      } else {
        final key =
            '${p.name.trim().toLowerCase()}_${p.lat.toStringAsFixed(4)}_${p.lon.toStringAsFixed(4)}';
        fallback[key] = p;
      }
    }

    return [...byId.values, ...fallback.values];
  }

  bool _looksInteresting(_OsmPlace p) {
    final tags = p.tags;
    final name = p.name.toLowerCase();

// ❌ nevēlamie objekti
    const blockedWords = [
      'traktor',
      'kombain',
      'ekskavator',
      'buldozer',
      'lokomobil',
      'mašīn',
      'iekārta',
      'tehnik',
      'tank',
      'tractor',
      'machine',
      'equipment',
      'mi-', // helikopteri
      'helicopter',
      'helikopter',
    ];

    for (final w in blockedWords) {
      if (name.contains(w)) return false;
    }

    const blockedTourism = {
      'hotel',
      'hostel',
      'guest_house',
      'apartment',
      'camp_site',
      'motel',
      'information',
      'picnic_site',
    };

    const blockedAmenities = {
      'restaurant',
      'cafe',
      'bar',
      'fast_food',
      'pub',
      'biergarten',
      'nightclub',
      'casino',
      'bank',
      'fuel',
      'pharmacy',
      'clinic',
      'hospital',
      'school',
      'parking',
    };

    const blockedShopValues = {
      'mall',
      'supermarket',
      'convenience',
      'clothes',
      'hardware',
    };

    final tourism = (tags['tourism'] ?? '').toLowerCase();
    final amenity = (tags['amenity'] ?? '').toLowerCase();
    final leisure = (tags['leisure'] ?? '').toLowerCase();
    final natural = (tags['natural'] ?? '').toLowerCase();
    final historic = (tags['historic'] ?? '').toLowerCase();
    final shop = (tags['shop'] ?? '').toLowerCase();

    if (blockedTourism.contains(tourism)) return false;
    if (blockedAmenities.contains(amenity)) return false;
    if (blockedShopValues.contains(shop)) return false;

    if (tourism == 'attraction') return true;
    if (tourism == 'museum') return true;
    if (tourism == 'gallery') return true;
    if (tourism == 'viewpoint') return true;

    if (leisure == 'park') return true;

    if (historic.isNotEmpty) return true;
    if (natural.isNotEmpty) return true;

    if (name.contains('castle')) return true;
    if (name.contains('pils')) return true;
    if (name.contains('muiža')) return true;
    if (name.contains('manor')) return true;
    if (name.contains('museum')) return true;
    if (name.contains('muzej')) return true;
    if (name.contains('park')) return true;
    if (name.contains('viewpoint')) return true;
    if (name.contains('skatu')) return true;
    if (name.contains('trail')) return true;
    if (name.contains('taka')) return true;
    if (name.contains('rock')) return true;
    if (name.contains('waterfall')) return true;
    if (name.contains('ūdenskrit')) return true;
    if (name.contains('memorial')) return true;
    if (name.contains('monument')) return true;
    if (name.contains('bazn')) return true;
    if (name.contains('church')) return true;

    return false;
  }

  double _scorePlace(_OsmPlace p, LatLon center) {
    final distKm = _haversineKm(center.lat, center.lon, p.lat, p.lon);

    double score = 0;

    final tourism = (p.tags['tourism'] ?? '').toLowerCase();
    final leisure = (p.tags['leisure'] ?? '').toLowerCase();
    final natural = (p.tags['natural'] ?? '').toLowerCase();
    final historic = (p.tags['historic'] ?? '').toLowerCase();

    if (tourism == 'attraction') score += 40;
    if (tourism == 'museum') score += 10;
    if (tourism == 'gallery') score += 28;
    if (tourism == 'viewpoint') score += 34;
    if (leisure == 'park') score += 25;

    if (historic.isNotEmpty) score += 30;
    if (natural.isNotEmpty) score += 22;

    if (p.name.trim().isNotEmpty) score += 12;
    if (p.tags.containsKey('wikipedia')) score += 16;
    if (p.tags.containsKey('wikidata')) score += 14;
    if (p.tags.containsKey('website')) score += 6;
    if (p.tags.containsKey('image')) score += 5;
    if (p.tags.containsKey('description')) score += 5;
    if (tourism == 'viewpoint') score += 50;
    if (historic.isNotEmpty) score += 45;
    if (natural.isNotEmpty) score += 40;
    if (leisure == 'park') score += 35;

// bonus par interesantiem nosaukumiem
    if (p.name.toLowerCase().contains('castle')) score += 20;
    if (p.name.toLowerCase().contains('pils')) score += 20;
    if (p.name.toLowerCase().contains('muiža')) score += 20;
    if (p.name.toLowerCase().contains('trail')) score += 15;
    if (p.name.toLowerCase().contains('taka')) score += 15;
    if (p.name.toLowerCase().contains('ūdenskrit')) score += 20;
    score -= distKm * 0.05;

    return score;
  }

  Poi _osmPlaceToPoi(_OsmPlace p) {
    final category = _mapCategory(p);

    return Poi(
      id: p.id,
      name: p.name,
      location: LatLon(p.lat, p.lon),
      durationH: _estimateVisitMinutes(category, p) / 60.0,
      categories: {category},
      isIndoor: _inferIndoor(p, category),
    );
  }

  PoiCategory _mapCategory(_OsmPlace p) {
    final tags = p.tags;
    final tourism = (tags['tourism'] ?? '').toLowerCase();
    final leisure = (tags['leisure'] ?? '').toLowerCase();
    final natural = (tags['natural'] ?? '').toLowerCase();
    final historic = (tags['historic'] ?? '').toLowerCase();
    final name = p.name.toLowerCase();

    if (tourism == 'museum' || name.contains('museum') || name.contains('muzej')) {
      return PoiCategory.museum;
    }

    if (tourism == 'viewpoint' ||
        name.contains('viewpoint') ||
        name.contains('lookout') ||
        name.contains('skatu')) {
      return PoiCategory.viewpoint;
    }

    if (leisure == 'park' ||
        natural.isNotEmpty ||
        name.contains('trail') ||
        name.contains('taka') ||
        name.contains('waterfall') ||
        name.contains('rock') ||
        name.contains('beach')) {
      return PoiCategory.nature;
    }

    if (name.contains('beach')) {
      return PoiCategory.beach;
    }

    if (historic.isNotEmpty ||
        tourism == 'attraction' ||
        tourism == 'gallery' ||
        name.contains('castle') ||
        name.contains('pils') ||
        name.contains('muiža') ||
        name.contains('manor') ||
        name.contains('church') ||
        name.contains('bazn')) {
      return PoiCategory.mustSee;
    }

    return PoiCategory.mustSee;
  }

  bool _inferIndoor(_OsmPlace p, PoiCategory category) {
    final tourism = (p.tags['tourism'] ?? '').toLowerCase();
    if (tourism == 'museum') return true;
    if (tourism == 'gallery') return true;
    if (category == PoiCategory.museum) return true;
    return false;
  }

  int _estimateVisitMinutes(PoiCategory category, _OsmPlace p) {
    switch (category) {
      case PoiCategory.museum:
        return 60;
      case PoiCategory.nature:
        return 35;
      case PoiCategory.viewpoint:
        return 20;
      case PoiCategory.beach:
        return 45;
      case PoiCategory.indoor:
        return 60;
      case PoiCategory.food:
        return 45;
      case PoiCategory.city:
        return 40;
      case PoiCategory.mustSee:
        final tourism = (p.tags['tourism'] ?? '').toLowerCase();
        final historic = (p.tags['historic'] ?? '').toLowerCase();

        if (tourism == 'gallery') return 45;
        if (historic.isNotEmpty) return 40;
        return 35;
    }
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _degToRad(double deg) => deg * pi / 180.0;
  double _radToDeg(double rad) => rad * 180.0 / pi;
}

class _OsmPlace {
  _OsmPlace({
    required this.id,
    required this.name,
    required this.lat,
    required this.lon,
    required this.tags,
  });

  final String id;
  final String name;
  final double lat;
  final double lon;
  final Map<String, String> tags;

  static _OsmPlace? fromOverpass(Map<String, dynamic> json) {
    final type = (json['type'] ?? '').toString();
    final osmId = (json['id'] ?? '').toString();

    final tagsRaw = (json['tags'] as Map<String, dynamic>? ?? const {});
    final tags = tagsRaw.map(
          (key, value) => MapEntry(key.toString(), value.toString()),
    );

    final lat = (json['lat'] as num?)?.toDouble() ??
        (json['center']?['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble() ??
        (json['center']?['lon'] as num?)?.toDouble();

    if (lat == null || lon == null) {
      throw const FormatException('OSM elementam nav koordinātu');
    }

    final name = _bestNameFromTags(tags);
    if (name == null || name.trim().isEmpty) {
      return null;
    }

    return _OsmPlace(
      id: 'osm_${type}_$osmId',
      name: name.trim(),
      lat: lat,
      lon: lon,
      tags: tags,
    );
  }

  static String? _bestNameFromTags(Map<String, String> tags) {
    return tags['name:lv'] ??
        tags['name:en'] ??
        tags['name'] ??
        tags['official_name'] ??
        tags['loc_name'];
  }
}