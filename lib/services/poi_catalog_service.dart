import '../models/poi.dart';
import '../models/geo.dart';

class PoiCatalogService {
  const PoiCatalogService();

  List<Poi> catalogForRegion(String region) {
    return [
      Poi(
        id: '1',
        name: 'Muzejs',
        location: const LatLon(56.95, 24.10),
        categories: {PoiCategory.museum, PoiCategory.indoor},
        isIndoor: true,
      ),
      Poi(
        id: '2',
        name: 'Pludmale',
        location: const LatLon(56.97, 24.12),
        categories: {PoiCategory.beach, PoiCategory.nature},
      ),
      Poi(
        id: '3',
        name: 'Skatu punkts',
        location: const LatLon(56.93, 24.08),
        categories: {PoiCategory.viewpoint},
      ),
    ];
  }
}
