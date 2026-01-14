import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/geo.dart';
import '../models/poi.dart';

class PlaceSuggestion {
  final String placeId;
  final String description;

  const PlaceSuggestion({
    required this.placeId,
    required this.description,
  });
}

class PlacesService {
  static const String _apiKey = 'AIzaSyBXUdUPuEI9poi_ZQCmlBffsMOfphXHWV8';

  Future<List<PlaceSuggestion>> autocomplete({
    required String input,
    String? languageCode,
    String? components,
  }) async {
    final q = input.trim();
    if (q.length < 2) return const [];

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/autocomplete/json', {
      'input': q,
      'key': _apiKey,
      if (languageCode != null) 'language': languageCode,
      if (components != null) 'components': components,
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) return const [];

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final preds = (data['predictions'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    return preds
        .map((p) => PlaceSuggestion(
      placeId: p['place_id'] as String,
      description: p['description'] as String,
    ))
        .toList();
  }

  Future<Poi?> placeDetailsToPoi({
    required String placeId,
    String? languageCode,
  }) async {
    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/details/json', {
      'place_id': placeId,
      'fields': 'place_id,name,geometry,types',
      'key': _apiKey,
      if (languageCode != null) 'language': languageCode,
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final result = data['result'];
    if (result == null) return null;

    final name = (result['name'] as String?)?.trim();
    final geom = result['geometry'] as Map<String, dynamic>?;
    final loc = geom?['location'] as Map<String, dynamic>?;
    if (name == null || loc == null) return null;

    final lat = (loc['lat'] as num).toDouble();
    final lon = (loc['lng'] as num).toDouble();

    final types = ((result['types'] as List?) ?? const []).map((e) => e.toString()).toList();
    final cats = _mapTypesToCategories(types);

    return Poi(
      id: result['place_id'] as String,
      name: name,
      location: LatLon(lat, lon),
      durationH: _defaultDurationFromCats(cats),
      categories: cats,
      isIndoor: cats.contains(PoiCategory.museum) || cats.contains(PoiCategory.indoor),
    );
  }

  Future<Poi?> textSearchToPoi({
    required String query,
    String? languageCode,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return null;

    final uri = Uri.https('maps.googleapis.com', '/maps/api/place/textsearch/json', {
      'query': q,
      'key': _apiKey,
      if (languageCode != null) 'language': languageCode,
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) return null;

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final results = (data['results'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
    if (results.isEmpty) return null;

    final r = results.first;
    final placeId = r['place_id'] as String?;
    if (placeId == null) return null;

    return placeDetailsToPoi(placeId: placeId, languageCode: languageCode);
  }

  Set<PoiCategory> _mapTypesToCategories(List<String> types) {
    final t = types.toSet();
    final out = <PoiCategory>{};

    if (t.contains('museum')) out.add(PoiCategory.museum);
    if (t.contains('art_gallery')) out.add(PoiCategory.indoor);
    if (t.contains('aquarium')) out.add(PoiCategory.indoor);
    if (t.contains('shopping_mall')) out.add(PoiCategory.indoor);

    if (t.contains('park')) out.add(PoiCategory.nature);
    if (t.contains('natural_feature')) out.add(PoiCategory.nature);
    if (t.contains('tourist_attraction')) out.add(PoiCategory.viewpoint);

    if (t.contains('restaurant') || t.contains('cafe')) out.add(PoiCategory.food);

    if (t.contains('locality') || t.contains('neighborhood')) out.add(PoiCategory.city);

    out.add(PoiCategory.mustSee);

    return out;
  }

  double _defaultDurationFromCats(Set<PoiCategory> cats) {
    if (cats.contains(PoiCategory.museum)) return 2.0;
    if (cats.contains(PoiCategory.indoor)) return 1.5;
    if (cats.contains(PoiCategory.nature) || cats.contains(PoiCategory.beach)) return 2.5;
    return 1.5;
  }
}
