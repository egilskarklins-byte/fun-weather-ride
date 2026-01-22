import 'dart:math';

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

  // ===================== REPLAN (NEW, DOES NOT REMOVE ANYTHING) =====================
  /// Re-plan from a specific day (inclusive) using new weather forecast.
  ///
  /// - Keeps existing plans before [fromDate] unchanged.
  /// - Rebuilds plans from [fromDate] forward using [newWeatherByDay].
  /// - Excludes already-visited POIs (based on existing plans before [fromDate] + [visitedPoiIds]).
  /// - Also excludes [skippedPoiIds] (user marked as skipped).
  /// - For movingTour, you can pass [currentLocation] to continue from real location.
  ///
  /// IMPORTANT: This does NOT modify buildPlan() or your data models.
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

    // find index in existingPlans by date
    int idx = -1;
    for (int i = 0; i < existingPlans.length; i++) {
      if (_dayKey(existingPlans[i].date) == fromKey) {
        idx = i;
        break;
      }
    }

    // If the date is not found, do nothing (safe behavior)
    if (idx < 0) return existingPlans;

    // Keep previous days unchanged
    final prefix = existingPlans.sublist(0, idx);

    // determine remaining day count
    final remainingDays = max(0, originalInput.daysCount - idx);
    if (remainingDays == 0) return prefix;

    // collect what was already visited in prefix (must-see + any stop that is not a base/return marker)
    final alreadyVisited = <String>{...visitedPoiIds};
    alreadyVisited.addAll(_collectVisitedPoiIdsFromPlans(prefix));

    // remaining must-see = original must-see minus visited/skipped
    final remainingMustSee = originalInput.mustSee.where((p) {
      if (alreadyVisited.contains(p.id)) return false;
      if (skippedPoiIds.contains(p.id)) return false;
      return true;
    }).toList();

    // choose replanning start point
    LatLon replStartPoint;
    if (originalInput.mode == TripMode.singleBase) {
      // singleBase remains the same base
      replStartPoint = originalInput.startPoint;
    } else {
      // movingTour: continue from real location if provided, otherwise use planned base of that day,
      // otherwise fallback to last stop of previous day, otherwise original start
      final plannedBase = existingPlans[idx].base; // LatLon vai LatLon? (atkarīgs no modeļa)
      final fallback = prefix.isNotEmpty
          ? prefix.last.stops.last.location
          : originalInput.startPoint;

      replStartPoint = currentLocation ?? (plannedBase ?? fallback);
    }

    // recompute start/end for the remaining segment
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
      maxKmPerDay: originalInput.maxKmPerDay,
      // keep your hours logic as is
      mustSee: remainingMustSee,
    );

    // build new segment
    final newSegment = buildPlan(
      input: newInput,
      weatherByDay: newWeatherByDay,
      poiPool: poiPool,
    );

    // stitch together
    return [...prefix, ...newSegment];
  }

  Set<String> _collectVisitedPoiIdsFromPlans(List<DayPlan> plans) {
    final out = <String>{};

    for (final d in plans) {
      // mustSee
      for (final p in d.mustSee) {
        out.add(p.id);
      }

      // stops - filter out synthetic ids we create in engine
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
    // “stops” = cik daudz POI pa dienu (neskaitot start + atpakaļ).
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

    // ✅ GEO clustering
    final clusters = _clusterMustSeeByGeo(
      mustSee,
      k: input.daysCount,
      origin: input.startPoint,
    );

    // ✅ ordering (moving tour goes “forward”)
    final orderedClusters = _orderClustersForwardIfMovingTour(
      clusters: clusters,
      origin: input.startPoint,
      movingTour: input.mode == TripMode.movingTour,
      allMustSee: mustSee,
    );

    final usedPoiIds = <String>{...mustSee.map((e) => e.id)};
    final plans = <DayPlan>[];

    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];

      // ====== PROFILE impact ======
      double maxHours = input.maxHoursPerDay *
          input.fitnessMultiplier() *
          _partyHoursMultiplier(input.party);

      double maxKm = input.maxKmPerDay.toDouble() * _partyKmMultiplier(input.party);

      final maxStops = _maxStopsForProfile(input);

      final todaysMust = List<Poi>.from(
        (i < orderedClusters.length) ? orderedClusters[i] : <Poi>[],
      );

      if (weather != null) {
        if (weather.isStormy) {
          // ļoti slikts laiks → atstājam tikai 1 must-see
          while (todaysMust.length > 1) {
            todaysMust.removeLast();
          }
        } else if (weather.isRainy) {
          // lietus → samazinām must-see skaitu
          if (todaysMust.length > 1) {
            todaysMust.removeLast();
          }
        }
      }



// ====== WEATHER penalty ======
      if (weather != null) {
        if (weather.isRainy || weather.isStormy) {
          maxHours *= 0.75;
          maxKm *= 0.80;

          // 👇 ŠIS ir kritiskais replanning efekts
          if (todaysMust.length > 1) {
            todaysMust.removeLast();
          }
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

      maxHours = max(3.0, maxHours);
      maxKm = max(30.0, maxKm);

      // ================= WEATHER-AWARE must-see ordering (NEW) =================
      // Lietus dienā: indoor pa priekšu. Sausā dienā: outdoor pa priekšu.
      final adjustedMust = List<Poi>.from(todaysMust);
      if (weather != null) {
        if (weather.isRainy || weather.isStormy) {
          adjustedMust.sort((a, b) {
            if (a.isIndoor && !b.isIndoor) return -1;
            if (!a.isIndoor && b.isIndoor) return 1;
            return 0;
          });
        } else {
          adjustedMust.sort((a, b) {
            if (!a.isIndoor && b.isIndoor) return -1;
            if (a.isIndoor && !b.isIndoor) return 1;
            return 0;
          });
        }
      }
      // =======================================================================

      final center = centroid([
        currentBase,
        ...adjustedMust.map((e) => e.location),
      ]);

      final stops = <Poi>[
        Poi(id: 'base_$i', name: 'Sākums', location: currentBase),
        ...adjustedMust,
      ];

      // Single base vienmēr atgriežas tajā pašā dienā
      if (input.mode == TripMode.singleBase) {
        stops.add(
          Poi(id: 'base_end_$i', name: 'Atpakaļ', location: currentBase),
        );
      }

      final filled = _fillStopsToHours(
        stops: stops,
        maxHours: maxHours,
        maxKm: maxKm,
        maxStops: maxStops,
        center: center,
        poiPool: poiPool,
        usedPoiIds: usedPoiIds,
        movingTour: input.mode == TripMode.movingTour,
      );

      // ✅ Moving tour: pēdējā dienā (ja checkbox ieslēgts) pievienojam atgriešanos uz startu
      final isLastDay = (i == days.length - 1);
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

      plans.add(
        DayPlan(
          date: date,
          theme: DayTheme.mixed,
          base: currentBase,
          mustSee: adjustedMust,
          stops: filled,
          estKm: estKm,
          estHours: estHours,
          weather: weather,
          summary:
          'must-see: ${adjustedMust.length} • ~${estHours.toStringAsFixed(1)} h • ~$estKm km',
        ),
      );

      // ✅ Moving tour bāze nākamajai dienai = pēdējā reālā pietura (nevis "atpakaļ uz sākumu")
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
  }) {
    final out = List<Poi>.from(stops);

    final candidates = poiPool.where((p) {
      if (usedPoiIds.contains(p.id)) return false;
      return _distKm(center, p.location) <= 90;
    }).toList();

    candidates.sort(
          (a, b) => _distKm(center, a.location).compareTo(_distKm(center, b.location)),
    );

    for (final p in candidates) {
      // maxStops = POI skaits (neskaitot start/end).
      // out ietver start un (singleBase) atpakaļ.
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
      ..sort((a, b) => _distKm(origin, a.location).compareTo(_distKm(origin, b.location)));

    final seeds = <Poi>[sortedByOrigin.first];
    while (seeds.length < k) {
      Poi best = mustSee.first;
      double bestMinDist = -1;

      for (final p in mustSee) {
        double minD = double.infinity;
        for (final s in seeds) {
          minD = min(minD, _distKm(p.location, s.location));
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

    for (int round = 0; round < 3; round++) {
      for (int i = 0; i < clusters.length; i++) {
        clusters[i].retainWhere(seeds.contains);
      }

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
      final axisPoint =
          _farthestPointFrom(origin, allMustSee.map((e) => e.location).toList()) ?? origin;

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
} // <-- ŠIS AIZVER class PlannerEngine
