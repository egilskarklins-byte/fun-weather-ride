import 'dart:math' as math;

import '../models/geo.dart';
import '../models/plan.dart';
import '../models/poi.dart';
import '../models/trip.dart';
import '../models/weather.dart';

class PlannerEngine {
  final Map<String, double> _distCache = {};

  String _k(LatLon a, LatLon b) {
    double r(double x) => (x * 10000).roundToDouble() / 10000;
    final a1 = '${r(a.lat)},${r(a.lon)}';
    final b1 = '${r(b.lat)},${r(b.lon)}';
    return (a1.compareTo(b1) <= 0) ? '$a1|$b1' : '$b1|$a1';
  }

  double _distKm(LatLon a, LatLon b) {
    final key = _k(a, b);
    final hit = _distCache[key];
    if (hit != null) return hit;
    final d = haversineKm(a, b);
    _distCache[key] = d;
    return d;
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _datesBetween(DateTime start, int daysCount) {
    final d0 = DateTime(start.year, start.month, start.day);
    return List.generate(daysCount, (i) => d0.add(Duration(days: i)));
  }

  // ===================== WEATHER HELPERS =====================

  bool _preferIndoorByWeather(WeatherDay? weather) {
    if (weather == null) return false;
    return weather.isRainy ||
        weather.isStormy ||
        weather.isCold ||
        weather.windMs >= 12;
  }

  int _indoorPriority(Poi p) {
    final isIndoorCat = p.categories.contains(PoiCategory.indoor) ||
        p.categories.contains(PoiCategory.museum);
    return (p.isIndoor || isIndoorCat) ? 1 : 0;
  }

  bool _isIndoorPoi(Poi p) => _indoorPriority(p) == 1;

  /// Nekad nemet ārā must-see: tikai pārkārto secību (indoor/outdoor) atkarībā no laika.
  List<Poi> _prioritizeMustSeeByWeather({
    required List<Poi> todaysMust,
    required WeatherDay? weather,
  }) {
    if (todaysMust.isEmpty) return todaysMust;

    final out = List<Poi>.from(todaysMust);
    final preferIndoor = _preferIndoorByWeather(weather);

    // Slikts laiks => indoor pirmais. Labs => outdoor pirmais.
    out.sort((a, b) {
      final ai = _indoorPriority(a);
      final bi = _indoorPriority(b);
      return preferIndoor ? (bi - ai) : (ai - bi);
    });

    return out;
  }

  /// Weather nedrīkst "samazināt must-see skaitu".
  /// Weather ietekmē maxKm/maxHours un theme/priority, bet must-see izkārtojumu pa dienām atstājam ģeogrāfijai.
  int _mustSeeCapByWeather(int candidateCount, WeatherDay? weather) {
    return candidateCount;
  }

  DayTheme _chooseTheme({
    required WeatherDay? weather,
    required List<Poi> todaysMust,
  }) {
    if (todaysMust.isEmpty) {
      // ja nav must-see, balstāmies tikai uz weather
      return _preferIndoorByWeather(weather) ? DayTheme.indoor : DayTheme.mixed;
    }

    final indoor = todaysMust.where(_isIndoorPoi).length;
    final ratio = indoor / todaysMust.length;

    if (ratio >= 0.60) return DayTheme.indoor;
    if (ratio <= 0.40) return DayTheme.nature;
    return DayTheme.mixed;
  }

  // ===================== REPLAN (DOES NOT REMOVE ANYTHING) =====================

  List<DayPlan> replanFromDay({
    required TripInput originalInput,
    required List<DayPlan> existingPlans,
    required DateTime fromDate,
    required List<WeatherDay> newWeatherByDay,
    required List<Poi> poiPool,
    Set<String> visitedPoiIds = const {},
    Set<String> skippedPoiIds = const {},
    LatLon? currentLocation,
  }) {
    if (existingPlans.isEmpty) return [];

    final fromKey = _dayKey(fromDate);

    int idx = -1;
    for (int i = 0; i < existingPlans.length; i++) {
      if (_dayKey(existingPlans[i].date) == fromKey) {
        idx = i;
        break;
      }
    }

    if (idx < 0) return existingPlans;

    final prefix = existingPlans.sublist(0, idx);

    final remainingDays = math.max(0, originalInput.daysCount - idx);
    if (remainingDays == 0) return prefix;

    final alreadyVisited = <String>{...visitedPoiIds};
    alreadyVisited.addAll(_collectVisitedPoiIdsFromPlans(prefix));

    final remainingMustSee = originalInput.mustSee.where((p) {
      if (alreadyVisited.contains(p.id)) return false;
      if (skippedPoiIds.contains(p.id)) return false;
      return true;
    }).toList();

    LatLon replStartPoint;
    if (originalInput.mode == TripMode.singleBase) {
      replStartPoint = originalInput.startPoint;
    } else {
      final plannedBase = existingPlans[idx].base;
      replStartPoint = currentLocation ?? plannedBase;
    }

    final newStartDate = _dayKey(existingPlans[idx].date);
    final newEndDate = newStartDate.add(Duration(days: remainingDays - 1));

    final newInput = TripInput(
      startDate: newStartDate,
      endDate: newEndDate,
      daysCount: remainingDays,
      mode: originalInput.mode,
      transport: originalInput.transport,
      fitness: originalInput.fitness,
      party: originalInput.party,
      regionText: originalInput.regionText,
      startPoint: replStartPoint,
      returnToStart: originalInput.returnToStart,
      includeFillers: originalInput.includeFillers,
      maxKmPerDay: originalInput.maxKmPerDay,
      mustSee: remainingMustSee,
    );

    final newSegment = buildPlan(
      input: newInput,
      weatherByDay: newWeatherByDay,
      poiPool: poiPool,
    );

    return [...prefix, ...newSegment];
  }

  Set<String> _collectVisitedPoiIdsFromPlans(List<DayPlan> plans) {
    final out = <String>{};

    for (final d in plans) {
      for (final p in d.mustSee) {
        out.add(p.id);
      }

      for (final s in d.stops) {
        final id = s.id;
        if (id.startsWith('base_')) continue;
        if (id.startsWith('base_end_')) continue;
        if (id.startsWith('return_home_')) continue;
        out.add(id);
      }
    }

    return out;
  }

  // ===================== PROFILE IMPACT =====================

  double _partyHoursMultiplier(TravelParty party) {
    return switch (party) {
      TravelParty.solo => 1.0,
      TravelParty.couple => 0.95,
      TravelParty.family => 0.85,
    };
  }

  double _partyKmMultiplier(TravelParty party) {
    return switch (party) {
      TravelParty.solo => 1.0,
      TravelParty.couple => 0.98,
      TravelParty.family => 0.92,
    };
  }

  int _maxStopsForProfile(TripInput input) {
    int base = switch (input.transport) {
      TransportMode.car => 8,
      TransportMode.bike => 6,
    };

    base += switch (input.fitness) {
      FitnessLevel.low => -2,
      FitnessLevel.medium => 0,
      FitnessLevel.high => 2,
    };

    base += switch (input.party) {
      TravelParty.solo => 0,
      TravelParty.couple => 0,
      TravelParty.family => -1,
    };

    return base.clamp(3, 12);
  }

  // ===================== NEW: SUGGEST DAYS COUNT WITH WEATHER =====================

  int suggestDaysCountConsideringWeather({
    required TripInput input,
    required List<WeatherDay> weatherByDay,
  }) {
    final mustSee = input.mustSee;
    if (mustSee.length <= 1) return 1;

    final maxDays = math.min(30, mustSee.length);

    // Pre-calc distance matrix
    final distances = _buildDistanceMatrix(mustSee);

    for (int k = 1; k <= maxDays; k++) {
      final ok = _canFitMustSeeIntoDays(
        mustSee: mustSee,
        distances: distances,
        days: k,
        input: input,
        weatherByDay: weatherByDay,
      );

      if (ok) return k;
    }

    return maxDays;
  }


  bool _canFitAllMustSeeWithWeather({
    required TripInput input,
    required List<WeatherDay> weatherByDay,
    required int daysCount,
  }) {
    final days = _datesBetween(input.startDate, daysCount);

    final weatherMap = <DateTime, WeatherDay>{
      for (final w in weatherByDay) _dayKey(w.date): w,
    };

    final mustSee = List<Poi>.from(input.mustSee);

    final clusters = _clusterMustSeeByGeo(
      mustSee,
      k: math.min(input.daysCount, mustSee.length),
      origin: input.startPoint,
    );

    final orderedClusters = _orderClustersForwardIfMovingTour(
      clusters: clusters,
      origin: input.startPoint,
      movingTour: input.mode == TripMode.movingTour,
      allMustSee: mustSee,
    );

    final carryOver = <Poi>[];
    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];

      double maxHours = input.maxHoursPerDay *
          input.fitnessMultiplier() *
          _partyHoursMultiplier(input.party);

      double maxKm =
          input.maxKmPerDay.toDouble() * _partyKmMultiplier(input.party);

      final maxStops = _maxStopsForProfile(input);

      if (weather != null) {
        // SLIKTS LAIKS = reāli samazinam dienas kapacitāti
        if (weather.isRainy || weather.isStormy) {
          maxHours *= 0.60; // bija 0.75
          maxKm *= 0.70;
        }

        if (weather.windMs >= 12) {
          maxHours *= 0.75;
          maxKm *= 0.80;
        }

        if (weather.isCold) {
          maxHours *= 0.80;
          maxKm *= 0.85;
        }
      }


      maxHours = math.max(3.0, maxHours);
      maxKm = math.max(30.0, maxKm);

      final raw = (i < orderedClusters.length) ? orderedClusters[i] : <Poi>[];

      final merged = <Poi>[...carryOver, ...raw];
      carryOver.clear();

      final prioritized = _prioritizeMustSeeByWeather(
        todaysMust: merged,
        weather: weather,
      );

      int cap = _mustSeeCapByWeather(prioritized.length, weather);
      cap = math.min(cap, maxStops);

      var todaysMust = prioritized.take(cap).toList();
      var leftovers = prioritized.skip(cap).toList();

      bool within() {
        final stops = <Poi>[
          Poi(id: 'base_$i', name: 'Sākums', location: currentBase),
          ...todaysMust,
          if (input.mode == TripMode.singleBase)
            Poi(id: 'base_end_$i', name: 'Atpakaļ', location: currentBase),
        ];
        final estKm = _estimateKm(stops);
        final estHours = _estimateHours(stops);
        return estKm <= maxKm.round() && estHours <= maxHours;
      }

      while (todaysMust.isNotEmpty && !within()) {
        final moved = todaysMust.removeLast();
        leftovers.insert(0, moved);
      }

      final isLast = (i == days.length - 1);
      if (isLast && leftovers.isNotEmpty) {
        // nevar ietilpt šajā daysCount, vajag vairāk dienu
        return false;
      }


      carryOver.addAll(leftovers);

      if (todaysMust.length > maxStops) return false;

      if (input.mode == TripMode.movingTour) {
        if (!(input.returnToStart && isLast)) {
          currentBase = todaysMust.isNotEmpty ? todaysMust.last.location : currentBase;
        }
      }
    }

    return carryOver.isEmpty;
  }

  // ===================== BUILD PLAN =====================

  List<DayPlan> buildPlan({
    required TripInput input,
    required List<WeatherDay> weatherByDay,
    required List<Poi> poiPool,
  }) {
    final days = _datesBetween(input.startDate, input.daysCount);

    final weatherMap = <DateTime, WeatherDay>{
      for (final w in weatherByDay) _dayKey(w.date): w,
    };

    final mustSee = List<Poi>.from(input.mustSee);

    final clusters = _clusterMustSeeByGeo(
      mustSee,
      k: math.min(input.daysCount, mustSee.length),
      origin: input.startPoint,
    );

    final orderedClusters = _orderClustersForwardIfMovingTour(
      clusters: clusters,
      origin: input.startPoint,
      movingTour: input.mode == TripMode.movingTour,
      allMustSee: mustSee,
    );

    final usedPoiIds = <String>{...mustSee.map((e) => e.id)};
    final plans = <DayPlan>[];

    LatLon currentBase = input.startPoint;

    // carryOver = must-see kas neietilpa šodien un jāpārceļ uz nākamo dienu
    final carryOver = <Poi>[];

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];

      // ====== PROFILE impact ======
      double maxHours = input.maxHoursPerDay *
          input.fitnessMultiplier() *
          _partyHoursMultiplier(input.party);

      double maxKm =
          input.maxKmPerDay.toDouble() * _partyKmMultiplier(input.party);

      final maxStops = _maxStopsForProfile(input);

      // ====== WEATHER penalty (kapacitātes samazinājums) ======
      if (weather != null) {
        if (weather.isRainy || weather.isStormy) {
          maxHours *= 0.75;
          maxKm *= 0.80;
        }
        if (weather.isCold) {
          maxHours *= 0.90;
          maxKm *= 0.90;
        }
        if (weather.windMs >= 12) {
          maxHours *= 0.90;
          maxKm *= 0.90;
        }
      }

      maxHours = math.max(3.0, maxHours);
      maxKm = math.max(30.0, maxKm);

      // ====== MUST-SEE: merge carryOver + today's cluster ======
      final rawMust = (i < orderedClusters.length) ? orderedClusters[i] : <Poi>[];

      final mergedMust = <Poi>[...carryOver, ...rawMust];
      carryOver.clear();

      // ✅ reorder by weather, NEVER remove
      final prioritized = _prioritizeMustSeeByWeather(
        todaysMust: mergedMust,
        weather: weather,
      );

      int cap = _mustSeeCapByWeather(prioritized.length, weather);

      // "normālais" cap pēc profila (bet mēs neizmetam – tikai pārliekam)
      cap = math.min(cap, maxStops);

      var todaysMust = prioritized.take(cap).toList();
      var leftovers = prioritized.skip(cap).toList();

      bool withinLimits(List<Poi> stops) {
        final estKm = _estimateKm(stops);
        final estHours = _estimateHours(stops);
        return estKm <= maxKm.round() && estHours <= maxHours;
      }

      List<Poi> buildStopsForMust(List<Poi> must) {
        final basePoi = Poi(id: 'base_$i', name: 'Sākums', location: currentBase);
        final stops = <Poi>[basePoi, ...must];
        if (input.mode == TripMode.singleBase) {
          stops.add(Poi(id: 'base_end_$i', name: 'Atpakaļ', location: currentBase));
        }
        return stops;
      }

      bool forcedBecauseNoDays = false;

      // km/stundas fit: ja pārsniedz, pārliekam must-see uz nākamo dienu (neizmetam)
      while (todaysMust.isNotEmpty && !withinLimits(buildStopsForMust(todaysMust))) {
        final moved = todaysMust.removeLast();
        leftovers.insert(0, moved);
      }

      // ✅ Svarīgi: ja šodien sanāk 0 must-see, bet vēl ir leftovers,
      // ieliekam vismaz 1 un BRĪDINĀM (citādi būs tukša diena).
      if (todaysMust.isEmpty && leftovers.isNotEmpty) {
        todaysMust.add(leftovers.removeAt(0));
        forcedBecauseNoDays = true;
      }

      final isLastDay = (i == days.length - 1);

      if (!isLastDay) {
        carryOver.addAll(leftovers);
      } else {
        // pēdējā dienā NEKRAUJAM visu virsū – ja neietilpst, vienkārši brīdinām
        if (leftovers.isNotEmpty) {
          forcedBecauseNoDays = true;
          // bet NEPIEVIENOJAM leftovers pie todaysMust
        }

      }

      final theme = _chooseTheme(weather: weather, todaysMust: todaysMust);

      final center = centroid([
        currentBase,
        ...todaysMust.map((e) => e.location),
      ]);

      final stops = buildStopsForMust(todaysMust);

      // filler tikai, ja vairs nav must-see “rindā”
      final hasRemainingMustSeeLater =
          orderedClusters.skip(i + 1).any((c) => c.isNotEmpty) || carryOver.isNotEmpty;

      final allowFillers = input.includeFillers && !hasRemainingMustSeeLater;

      final filled = allowFillers
          ? _fillStopsToHours(
        stops: stops,
        maxHours: maxHours,
        maxKm: maxKm,
        maxStops: maxStops,
        center: center,
        poiPool: poiPool,
        usedPoiIds: usedPoiIds,
        movingTour: input.mode == TripMode.movingTour,
        weather: weather,
      )
          : stops;

      // Moving tour: pēdējā dienā (ja checkbox ieslēgts) pievienojam atgriešanos uz startu
      if (input.mode == TripMode.movingTour && input.returnToStart && isLastDay) {
        filled.add(
          Poi(
            id: 'return_home_$i',
            name: 'Atpakaļ uz sākumu',
            location: input.startPoint,
          ),
        );
      }

      final estKm = _estimateKm(filled);
      final estHours = _estimateHours(filled);

      final exceeds = (estKm > maxKm.round()) || (estHours > maxHours);

      // ✅ Brīdinājums, ja:
      // - sliktā laika dēļ samazinājās kapacitāte
      // - vai mēs bijām spiesti ielikt must-see, lai nebūtu tukša diena
      // - vai reāli pārsniedz km/stundas
      final overloadWarning = exceeds || forcedBecauseNoDays;

      final summaryBase =
          'must-see: ${todaysMust.length} • ~${estHours.toStringAsFixed(1)} h • ~$estKm km';

      plans.add(
        DayPlan(
          date: date,
          theme: theme,
          base: currentBase,
          mustSee: todaysMust,
          stops: filled,
          estKm: estKm,
          estHours: estHours,
          weather: weather,
          summary: overloadWarning
              ? '⚠️ Slikts laiks / limiti — must-see ir ielikti, bet diena var būt par smagu. '
              'Iesaku vairāk dienu vai mazāku km limitu. $summaryBase'
              : summaryBase,
        ),
      );

      // Moving tour bāze nākamajai dienai = pēdējā pietura (ignorējam return_home pēdējā dienā)
      if (input.mode == TripMode.movingTour) {
        if (!(input.returnToStart && isLastDay)) {
          currentBase = filled.last.location;
        }
      }
    }

    return plans;
  }

  // ===================== FILL WITH POI =====================

  List<Poi> _fillStopsToHours({
    required List<Poi> stops,
    required double maxHours,
    required double maxKm,
    required int maxStops,
    required LatLon center,
    required List<Poi> poiPool,
    required Set<String> usedPoiIds,
    required bool movingTour,
    required WeatherDay? weather,
  }) {
    final out = List<Poi>.from(stops);

    final candidates = poiPool.where((p) {
      if (usedPoiIds.contains(p.id)) return false;
      return _distKm(center, p.location) <= 90;
    }).toList();

    final preferIndoor = _preferIndoorByWeather(weather);

    candidates.sort((a, b) {
      if (preferIndoor) {
        final p = _indoorPriority(b) - _indoorPriority(a); // indoor first
        if (p != 0) return p;
      } else {
        final p = _indoorPriority(a) - _indoorPriority(b); // outdoor first
        if (p != 0) return p;
      }
      return _distKm(center, a.location).compareTo(_distKm(center, b.location));
    });

    for (final p in candidates) {
      if (out.length >= maxStops + 2) break;

      final idx = _bestInsertionIndex(out, p);
      if (idx == null) continue;

      final test = List<Poi>.from(out)..insert(idx, p);
      final newKm = _estimateKm(test);
      final newHours = _estimateHours(test);

      if (newKm > maxKm.round() || newHours > maxHours) continue;

      out.insert(idx, p);
      usedPoiIds.add(p.id);
    }

    return out;
  }

  int? _bestInsertionIndex(List<Poi> stops, Poi p) {
    if (stops.length < 2) return null;

    int bestIdx = 1;
    double bestDelta = double.infinity;

    for (int i = 1; i < stops.length; i++) {
      final a = stops[i - 1].location;
      final b = stops[i].location;

      final before = _distKm(a, b);
      final after = _distKm(a, p.location) + _distKm(p.location, b);
      final delta = after - before;

      if (delta < bestDelta) {
        bestDelta = delta;
        bestIdx = i;
      }
    }

    return bestIdx;
  }

  int _estimateKm(List<Poi> stops) {
    if (stops.length < 2) return 0;
    double km = 0;
    for (int i = 1; i < stops.length; i++) {
      km += _distKm(stops[i - 1].location, stops[i].location);
    }
    return (km * 1.1).round();
  }

  double _estimateHours(List<Poi> stops) {
    final km = _estimateKm(stops);
    final drive = km / 50.0;
    final visit = stops.fold<double>(0, (s, p) => s + p.durationH);
    return drive + visit;
  }

  // ===================== GEO CLUSTERING =====================

  List<List<Poi>> _clusterMustSeeByGeo(
      List<Poi> mustSee, {
        required int k,
        required LatLon origin,
      }) {
    if (k <= 0) return [];
    if (mustSee.isEmpty) return List.generate(k, (_) => <Poi>[]);

    if (mustSee.length <= k) {
      final out = List.generate(k, (_) => <Poi>[]);
      for (int i = 0; i < mustSee.length; i++) {
        out[i].add(mustSee[i]);
      }
      return out;
    }

    final sortedByOrigin = List<Poi>.from(mustSee)
      ..sort((a, b) =>
          _distKm(origin, a.location).compareTo(_distKm(origin, b.location)));

    final seeds = <Poi>[sortedByOrigin.first];

    while (seeds.length < k) {
      Poi best = mustSee.first;
      double bestMinDist = -1;

      for (final p in mustSee) {
        double minD = double.infinity;
        for (final s in seeds) {
          minD = math.min(minD, _distKm(p.location, s.location));
        }
        if (minD > bestMinDist) {
          bestMinDist = minD;
          best = p;
        }
      }

      if (seeds.contains(best)) break;
      seeds.add(best);
    }

    final clusters = List.generate(k, (_) => <Poi>[]);

    for (int i = 0; i < seeds.length; i++) {
      clusters[i].add(seeds[i]);
    }

    final remaining = mustSee.where((p) => !seeds.contains(p)).toList();

    for (final p in remaining) {
      int bestIdx = 0;
      double best = double.infinity;

      for (int i = 0; i < clusters.length; i++) {
        final c = centroid(clusters[i].map((e) => e.location).toList());
        final d = _distKm(c, p.location);
        if (d < best) {
          best = d;
          bestIdx = i;
        }
      }

      clusters[bestIdx].add(p);
    }
// ===================== BALANCE MUST-SEE ACROSS DAYS =====================
// lai must-see sadalās vienmērīgi, nevis 1 diena = 1 punkts, cita = 6
    clusters.sort((a, b) => b.length.compareTo(a.length));

    while (true) {
      final maxCluster = clusters.first;
      final minCluster = clusters.last;

      if (maxCluster.length - minCluster.length <= 1) break;

      minCluster.add(maxCluster.removeLast());
      clusters.sort((a, b) => b.length.compareTo(a.length));
    }

    return clusters;
  }


  List<List<Poi>> _orderClustersForwardIfMovingTour({
    required List<List<Poi>> clusters,
    required LatLon origin,
    required bool movingTour,
    required List<Poi> allMustSee,
  }) {
    final nonEmpty = clusters.where((c) => c.isNotEmpty).toList();
    final emptyCount = clusters.length - nonEmpty.length;

    if (nonEmpty.isEmpty) return clusters;

    if (!movingTour) {
      nonEmpty.sort((a, b) {
        final ca = centroid(a.map((e) => e.location).toList());
        final cb = centroid(b.map((e) => e.location).toList());
        return _distKm(origin, ca).compareTo(_distKm(origin, cb));
      });
    } else {
      final axisPoint = _farthestPointFrom(
        origin,
        allMustSee.map((e) => e.location).toList(),
      ) ??
          origin;

      double score(LatLon p) {
        final dOrigin = _distKm(origin, p);
        final dAxis = _distKm(axisPoint, p);
        return dOrigin - 0.35 * dAxis;
      }

      nonEmpty.sort((a, b) {
        final ca = centroid(a.map((e) => e.location).toList());
        final cb = centroid(b.map((e) => e.location).toList());
        return score(ca).compareTo(score(cb));
      });
    }

    for (int i = 0; i < emptyCount; i++) {
      nonEmpty.add(<Poi>[]);
    }

    return nonEmpty;
  }

  LatLon? _farthestPointFrom(LatLon origin, List<LatLon> points) {
    if (points.isEmpty) return null;
    LatLon best = points.first;
    double bestD = -1;
    for (final p in points) {
      final d = _distKm(origin, p);
      if (d > bestD) {
        bestD = d;
        best = p;
      }
    }
    return best;
  }
  Map<String, double> _buildDistanceMatrix(List<Poi> pois) {
    final map = <String, double>{};

    for (int i = 0; i < pois.length; i++) {
      for (int j = i + 1; j < pois.length; j++) {
        final a = pois[i];
        final b = pois[j];
        final d = _haversine(a.location, b.location);
        map['$i-$j'] = d;
        map['$j-$i'] = d;
      }
    }
    return map;
  }

  bool _canFitMustSeeIntoDays({
    required List<Poi> mustSee,
    required Map<String, double> distances,
    required int days,
    required TripInput input,
    required List<WeatherDay> weatherByDay,
  }) {
    final maxKm = input.maxKmPerDay.toDouble();
    final buckets = List.generate(days, (_) => <Poi>[]);

    for (int i = 0; i < mustSee.length; i++) {
      buckets[i % days].add(mustSee[i]);
    }

    for (final day in buckets) {
      if (day.isEmpty) continue;

      final km = input.mode == TripMode.singleBase
          ? _estimateSingleBaseKm(input.startPoint, day)
          : _estimateMovingTourKm(day);

      if (km > maxKm * 1.15) return false;
    }

    return true;
  }

  double _estimateSingleBaseKm(LatLon base, List<Poi> pois) {
    double total = 0;
    for (final p in pois) {
      total += 2 * _haversine(base, p.location);
    }
    return total;
  }

  double _estimateMovingTourKm(List<Poi> pois) {
    if (pois.length < 2) return 0;

    double total = 0;
    for (int i = 0; i < pois.length - 1; i++) {
      total += _haversine(pois[i].location, pois[i + 1].location);
    }
    return total;
  }

  double _haversine(LatLon a, LatLon b) {
    const earthRadius = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLon = _deg2rad(b.lon - a.lon);

    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.lat)) *
            math.cos(_deg2rad(b.lat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
    return earthRadius * c;
  }

  double _deg2rad(double deg) => deg * math.pi / 180.0;

}
