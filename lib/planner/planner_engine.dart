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

      if (weather != null && !input.ignoreWeather) {
        // slikts laiks = mazāka dienas kapacitāte
        if (weather.isRainy || weather.isStormy) {
          maxHours *= 0.60;
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

      final prioritized = input.ignoreWeather
          ? merged
          : _prioritizeMustSeeByWeather(
        todaysMust: merged,
        weather: weather,
      );

      int cap = input.ignoreWeather
          ? prioritized.length
          : _mustSeeCapByWeather(prioritized.length, weather);

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
        final estKm = _estimateSingleDayKm(
          base: currentBase,
          stops: todaysMust,
          movingTour: input.mode == TripMode.movingTour,
        );

        final estHours = _estimateHours(stops);

        // ================= DIAGNOSTIC =================
        print('------------------------------');
        print('DAY $i');
        print('ignoreWeather=${input.ignoreWeather}');
        print('maxKm=$maxKm');
        print('usedKm=$estKm');
        print('maxHours=$maxHours');
        print('usedHours=$estHours');
        print('mustSeeCount=${todaysMust.length}');
        print('------------------------------');
        // =============================================

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
          currentBase =
          todaysMust.isNotEmpty ? todaysMust.last.location : currentBase;
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

    final weatherMap = {
      for (final w in weatherByDay) _dayKey(w.date): w,
    };

    final mustSee = List<Poi>.from(input.mustSee);

    // ==============================
    // STEP 1: GEO CLUSTER
    // ==============================

    final clusters = _clusterMustSeeByGeo(
      mustSee,
      k: input.daysCount,
      origin: input.startPoint,
    );

    final dayBuckets = List.generate(
      input.daysCount,
          (i) => <Poi>[...clusters[i]],
    );

    // ==============================
    // STEP 2: BALANCE BETWEEN DAYS
    // ==============================

    double effectiveMaxKm(int dayIndex) {
      if (input.ignoreWeather) return input.maxKmPerDay.toDouble();

      final w = weatherMap[_dayKey(days[dayIndex])];

      double km = input.maxKmPerDay.toDouble();

      if (w != null) {
        if (w.isRainy || w.isStormy) km *= 0.8;
        if (w.windMs >= 12) km *= 0.85;
        if (w.isCold) km *= 0.9;
      }

      return km;
    }

    bool changed = true;

    while (changed) {
      changed = false;

      for (int from = 0; from < dayBuckets.length; from++) {
        final fromList = dayBuckets[from];

        if (fromList.isEmpty) continue;

        final fromKm = _estimateSingleDayKm(
          base: input.startPoint,
          stops: fromList,
          movingTour: input.mode == TripMode.movingTour,
        );

        if (fromKm <= effectiveMaxKm(from)) continue;

        for (int to = 0; to < dayBuckets.length; to++) {
          if (to == from) continue;

          final toList = dayBuckets[to];

          for (int i = fromList.length - 1; i >= 0; i--) {
            final candidate = fromList[i];

            final newTo = [...toList, candidate];

            final newKm = _estimateSingleDayKm(
              base: input.startPoint,
              stops: newTo,
              movingTour: input.mode == TripMode.movingTour,
            );

            if (newKm <= effectiveMaxKm(to)) {
              fromList.removeAt(i);
              dayBuckets[to].add(candidate);
              changed = true;
              break;
            }
          }

          if (changed) break;
        }

        if (changed) break;
      }
    }

    // ==============================
    // STEP 3: BUILD FINAL PLANS
    // ==============================

    final plans = <DayPlan>[];

    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final todaysMust = dayBuckets[i];

      final weather = weatherMap[_dayKey(date)];

      final base = input.mode == TripMode.singleBase
          ? input.startPoint
          : currentBase;

      final stops = <Poi>[
        Poi(id: 'base_$i', name: 'Sākums', location: base),
        ...todaysMust,
      ];

      if (input.mode == TripMode.singleBase) {
        stops.add(
          Poi(id: 'base_end_$i', name: 'Atpakaļ', location: base),
        );
      }

      final estKm = _estimateKm(stops);
      final estHours = _estimateHours(stops);

      final hasRemainingMustSeeLater =
      dayBuckets.skip(i + 1).any((e) => e.isNotEmpty);

      final allowFillers =
          input.includeFillers && !hasRemainingMustSeeLater;

      final filledStops = allowFillers
          ? _fillStopsToHours(
        stops: stops,
        maxHours: input.maxHoursPerDay,
        maxKm: input.maxKmPerDay.toDouble(),
        maxStops: 12,
        center: centroid(stops.map((e) => e.location).toList()),
        poiPool: poiPool,
        usedPoiIds: {...mustSee.map((e) => e.id)},
        movingTour: input.mode == TripMode.movingTour,
        weather: input.ignoreWeather ? null : weather,
      )
          : stops;

      plans.add(
        DayPlan(
          date: date,
          theme: DayTheme.mixed,
          base: base,
          mustSee: todaysMust,
          stops: filledStops,
          estKm: estKm,
          estHours: estHours,
          weather: input.ignoreWeather ? null : weather,
          summary:
          'must-see: ${todaysMust.length} • ~${estHours.toStringAsFixed(1)} h • ~$estKm km',
        ),
      );

      if (input.mode == TripMode.movingTour && todaysMust.isNotEmpty) {
        currentBase = todaysMust.last.location;
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
  double _estimateSingleDayKm({
    required LatLon base,
    required List<Poi> stops,
    required bool movingTour,
  }) {
    if (stops.isEmpty) return 0;

    // single base: turp + atpakaļ katram
    if (!movingTour) {
      double km = 0;
      for (final p in stops) {
        km += 2 * _distKm(base, p.location);
      }
      return km;
    }

    // moving tour: secīgi no punkta uz punktu
    double km = 0;
    LatLon current = base;

    for (final p in stops) {
      km += _distKm(current, p.location);
      current = p.location;
    }

    return km;
  }

  // ===================== GEO CLUSTERING =====================

  List<List<Poi>> _clusterMustSeeByGeo(
      List<Poi> mustSee, {
        required int k,
        required LatLon origin,
      }) {
    if (mustSee.isEmpty) {
      return List.generate(k, (_) => []);
    }

    // ============================
    // STEP 1 — build route order (nearest neighbor)
    // ============================

    final remaining = List<Poi>.from(mustSee);
    final ordered = <Poi>[];

    LatLon current = origin;

    while (remaining.isNotEmpty) {
      remaining.sort(
            (a, b) =>
            _distKm(current, a.location)
                .compareTo(_distKm(current, b.location)),
      );

      final next = remaining.removeAt(0);
      ordered.add(next);
      current = next.location;
    }

    // ============================
    // STEP 2 — split evenly into days
    // ============================

    final clusters = List.generate(k, (_) => <Poi>[]);

    final baseSize = ordered.length ~/ k;
    final extra = ordered.length % k;

    int index = 0;

    for (int day = 0; day < k; day++) {
      final size = baseSize + (day < extra ? 1 : 0);

      for (int i = 0; i < size; i++) {
        if (index < ordered.length) {
          clusters[day].add(ordered[index]);
          index++;
        }
      }
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
