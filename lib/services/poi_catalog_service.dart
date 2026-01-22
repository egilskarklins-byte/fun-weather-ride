import '../models/poi.dart';
import '../models/geo.dart';

class PoiCatalogService {
  const PoiCatalogService();

  List<Poi> catalogForRegion(String region) {
    // Test POI katalogs ar reālām koordinātēm dažādās vietās ap Rīgu
    return [
      // ===== CENTRS =====
      Poi(
        id: 'c1',
        name: 'Latvijas Nacionālais mākslas muzejs',
        location: const LatLon(56.9570, 24.1127),
        categories: {PoiCategory.museum, PoiCategory.indoor},
        isIndoor: true,
      ),
      Poi(
        id: 'c2',
        name: 'Vecrīga',
        location: const LatLon(56.9496, 24.1052),
        categories: {PoiCategory.city},
      ),
      Poi(
        id: 'c3',
        name: 'Bastejkalns',
        location: const LatLon(56.9528, 24.1076),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 'c4',
        name: 'Rīgas Doms',
        location: const LatLon(56.9492, 24.1050),
        categories: {PoiCategory.museum, PoiCategory.indoor},
        isIndoor: true,
      ),
      Poi(
        id: 'c5',
        name: 'Centrāltirgus',
        location: const LatLon(56.9429, 24.1148),
        categories: {PoiCategory.food},
      ),

      // ===== JŪRMALA =====
      Poi(
        id: 'j1',
        name: 'Majori pludmale',
        location: const LatLon(56.9722, 23.8043),
        categories: {PoiCategory.beach, PoiCategory.nature},
      ),
      Poi(
        id: 'j2',
        name: 'Dzintaru mežaparks',
        location: const LatLon(56.9766, 23.8117),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 'j3',
        name: 'Jūrmalas brīvdabas muzejs',
        location: const LatLon(56.9986, 23.9366),
        categories: {PoiCategory.museum},
      ),

      // ===== SIGULDA =====
      Poi(
        id: 's1',
        name: 'Siguldas pilsdrupas',
        location: const LatLon(57.1539, 24.8534),
        categories: {PoiCategory.viewpoint},
      ),
      Poi(
        id: 's2',
        name: 'Gūtmaņala',
        location: const LatLon(57.1634, 24.8513),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 's3',
        name: 'Turaidas pils',
        location: const LatLon(57.1811, 24.8538),
        categories: {PoiCategory.museum},
      ),
      Poi(
        id: 's4',
        name: 'Siguldas trošu tilts',
        location: const LatLon(57.1544, 24.8522),
        categories: {PoiCategory.viewpoint},
      ),

      // ===== CĒSIS =====
      Poi(
        id: 'ce1',
        name: 'Cēsu pils',
        location: const LatLon(57.3122, 25.2752),
        categories: {PoiCategory.museum},
      ),
      Poi(
        id: 'ce2',
        name: 'Cīrulīšu dabas takas',
        location: const LatLon(57.3220, 25.2435),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 'ce3',
        name: 'Žagarkalns',
        location: const LatLon(57.3325, 25.2674),
        categories: {PoiCategory.viewpoint},
      ),

      // ===== OGRĒ =====
      Poi(
        id: 'o1',
        name: 'Ogres Zilie kalni',
        location: const LatLon(56.8148, 24.6143),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 'o2',
        name: 'Ogres promenāde',
        location: const LatLon(56.8166, 24.6081),
        categories: {PoiCategory.city},
      ),

      // ===== SALASPILS =====
      Poi(
        id: 'sa1',
        name: 'Salaspils botāniskais dārzs',
        location: const LatLon(56.8583, 24.3567),
        categories: {PoiCategory.nature},
      ),
      Poi(
        id: 'sa2',
        name: 'Salaspils memoriāls',
        location: const LatLon(56.8589, 24.3684),
        categories: {PoiCategory.museum},
      ),

      // ===== TUKUMS =====
      Poi(
        id: 't1',
        name: 'Tukuma pils tornis',
        location: const LatLon(56.9672, 23.1557),
        categories: {PoiCategory.viewpoint},
      ),
      Poi(
        id: 't2',
        name: 'Durbe muiža',
        location: const LatLon(56.9785, 23.1674),
        categories: {PoiCategory.museum},
      ),

      // ===== LIMBAŽI =====
      Poi(
        id: 'l1',
        name: 'Limbāžu vecpilsēta',
        location: const LatLon(57.5123, 24.7147),
        categories: {PoiCategory.city},
      ),

      // ===== VENTSPILS =====
      Poi(
        id: 'v1',
        name: 'Ventspils pludmale',
        location: const LatLon(57.3922, 21.5644),
        categories: {PoiCategory.beach},
      ),
      Poi(
        id: 'v2',
        name: 'Ventspils Livonijas pils',
        location: const LatLon(57.3948, 21.5632),
        categories: {PoiCategory.museum},
      ),

      // ===== KULDĪGA =====
      Poi(
        id: 'k1',
        name: 'Ventas rumba',
        location: const LatLon(56.9681, 21.9685),
        categories: {PoiCategory.viewpoint, PoiCategory.nature},
      ),
      Poi(
        id: 'k2',
        name: 'Kuldīgas vecpilsēta',
        location: const LatLon(56.9687, 21.9702),
        categories: {PoiCategory.city},
      ),

      // ===== BONUS: tālāki testi =====
      Poi(
        id: 'x1',
        name: 'Alūksnes pils',
        location: const LatLon(57.4213, 27.0486),
        categories: {PoiCategory.museum},
      ),
      Poi(
        id: 'x2',
        name: 'Daugavpils cietoksnis',
        location: const LatLon(55.8756, 26.5076),
        categories: {PoiCategory.museum},
      ),
      Poi(
        id: 'x3',
        name: 'Kolkasrags',
        location: const LatLon(57.7533, 22.5881),
        categories: {PoiCategory.nature},
      ),
    ];
  }
}
