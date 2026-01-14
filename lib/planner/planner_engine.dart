import 'dart:math';
import '../models/geo.dart';
import '../models/plan.dart';
import '../models/poi.dart';
import '../models/trip.dart';
import '../models/weather.dart';

class PlannerEngine {
  PlannerEngine();

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

  List<DayPlan> buildPlan({
    required TripInput input,
    required List<WeatherDay> weatherByDay,
    required List<Poi> poiPool,
  }) {
    final days = _datesBetween(input.startDate, input.daysCount);
    final weatherMap = {for (final w in weatherByDay) _dayKey(w.date): w};

    final themes = <DateTime, DayTheme>{};
    for (final d in days) {
      final w = weatherMap[_dayKey(d)];
      themes[d] = _themeFromWeather(w);
    }

    final mustSee = List<Poi>.from(input.mustSee);

    final clusters = _clusterMustSeeByGeo(
      mustSee,
      k: input.daysCount,
      origin: input.startPoint,
    );

    final orderedClusters = _orderClustersForwardIfMovingTour(
      clusters: clusters,
      origin: input.startPoint,
      movingTour: input.mode == TripMode.movingTour,
    );

    final usedPoiIds = <String>{...mustSee.map((e) => e.id)};
    final plans = <DayPlan>[];

    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];
      final theme = themes[date] ?? DayTheme.mixed;

      // --- max HOURS (independent from km) ---
      double maxHours = input.maxHoursPerDay * input.fitnessMultiplier();

      // --- max KM (from slider) ---
      double maxKm = input.maxKmPerDay.toDouble();

      // weather penalty (applies to BOTH time tolerance and distance tolerance)
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

      maxHours = max(3.0, maxHours);
      maxKm = max(30.0, maxKm);

      final todaysMust = (i < orderedClusters.length) ? orderedClusters[i] : <Poi>[];

      final center = centroid([
        currentBase,
        ...todaysMust.map((e) => e.location),
      ]);

      final stops = <Poi>[
        Poi(id: 'base_$i', name: 'Sākums', location: currentBase),
        ...todaysMust,
      ];
      if (input.mode == TripMode.singleBase) {
        stops.add(Poi(id: 'base_end_$i', name: 'Atpakaļ', location: currentBase));
      }

      final filled = _fillStopsToHours(
        stops: stops,
        maxHours: maxHours,
        maxKm: maxKm,
        theme: theme,
        center: center,
        poiPool: poiPool,
        usedPoiIds: usedPoiIds,
        movingTour: input.mode == TripMode.movingTour,
        forwardOrigin: input.startPoint,
        forwardAxisPoint: _axisPointForForwardOrdering(input.startPoint, mustSee),
        dayStartBase: currentBase,
      );

      final estKm = _estimateKm(filled);
      final estHours = _estimateHours(filled);

      plans.add(DayPlan(
        date: date,
        theme: theme,
        base: currentBase,
        mustSee: todaysMust,
        stops: filled,
        estKm: estKm,
        estHours: estHours,
        weather: weather,
        summary: _summary(theme, weather, estKm, estHours, todaysMust.length),
      ));

      if (input.mode == TripMode.movingTour) {
        final last = _lastRealStop(filled);
        currentBase = last.location;
      }
    }

    return plans;
  }

  // ---------------- Core rules ----------------

  DayTheme _themeFromWeather(WeatherDay? w) {
    if (w == null) return DayTheme.mixed;
    if (w.isStormy || w.isRainy) return DayTheme.indoor;
    if (!w.isCold && w.rainMm < 0.5 && w.windMs < 8) return DayTheme.nature;
    return DayTheme.mixed;
  }

  List<DateTime> _datesBetween(DateTime start, int daysCount) {
    final d0 = DateTime(start.year, start.month, start.day);
    return List.generate(daysCount, (i) => d0.add(Duration(days: i)));
  }

  DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  // ---------------- MUST-SEE clustering ----------------

  List<List<Poi>> _clusterMustSeeByGeo(List<Poi> mustSee, {required int k, required LatLon origin}) {
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
      Poi best = sortedByOrigin.first;
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

    void assignAll() {
      for (int i = 0; i < clusters.length; i++) {
        final keep = clusters[i].where((p) => seeds.contains(p)).toList();
        clusters[i]
          ..clear()
          ..addAll(keep);
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

    assignAll();
    assignAll();
    assignAll();

    return clusters;
  }

  List<List<Poi>> _orderClustersForwardIfMovingTour({
    required List<List<Poi>> clusters,
    required LatLon origin,
    required bool movingTour,
  }) {
    final nonEmpty = clusters.where((c) => c.isNotEmpty).toList();
    final emptyCount = clusters.length - nonEmpty.length;

    if (!movingTour) {
      nonEmpty.sort((a, b) {
        final ca = centroid(a.map((e) => e.location).toList());
        final cb = centroid(b.map((e) => e.location).toList());
        return _distKm(origin, ca).compareTo(_distKm(origin, cb));
      });
    }

    for (int i = 0; i < emptyCount; i++) {
      nonEmpty.add(<Poi>[]);
    }

    return nonEmpty;
  }

  LatLon _axisPointForForwardOrdering(LatLon origin, List<Poi> mustSee) {
    if (mustSee.isEmpty) return origin;
    final points = mustSee.map((e) => e.location).toList();
    return _farthestPointFrom(origin, points) ?? origin;
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

  // ---------------- Fill with POI ----------------

  List<Poi> _fillStopsToHours({
    required List<Poi> stops,
    required double maxHours,
    required double maxKm,
    required DayTheme theme,
    required LatLon center,
    required List<Poi> poiPool,
    required Set<String> usedPoiIds,
    required bool movingTour,
    required LatLon forwardOrigin,
    required LatLon forwardAxisPoint,
    required LatLon dayStartBase,
  }) {
    final out = List<Poi>.from(stops);

    final candidates = poiPool.where((p) {
      if (usedPoiIds.contains(p.id)) return false;
      final dist = _distKm(center, p.location);
      if (dist > 90) return false;
      return true;
    }).toList();

    candidates.sort((a, b) => _distKm(center, a.location).compareTo(_distKm(center, b.location)));

    double currentHours = _estimateHours(out);
    int currentKm = _estimateKm(out);

    final targetHours = maxHours * 0.92;
    final targetKm = (maxKm * 0.95).round();

    for (final p in candidates) {
      if (currentHours >= targetHours || currentKm >= targetKm) break;

      final idx = _bestInsertionIndex(out, p);
      if (idx == null) continue;

      final test = List<Poi>.from(out)..insert(idx, p);
      final newKm = _estimateKm(test);
      final newHours = _estimateHours(test);

      // strict hard limits:
      if (newHours > maxHours) continue;
      if (newKm > maxKm.round()) continue;

      // accept if it improves filling (either km or hours), without breaking limits
      final improves = (newKm > currentKm) || (newHours > currentHours);
      if (!improves) continue;

      out.insert(idx, p);
      usedPoiIds.add(p.id);
      currentHours = newHours;
      currentKm = newKm;
    }

    return _orderRoute(out, movingTour: movingTour);
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

  List<Poi> _orderRoute(List<Poi> stops, {required bool movingTour}) {
    if (stops.length <= 3) return stops;

    final start = stops.first;
    final tail = stops.sublist(1);

    Poi? fixedLast;
    if (!movingTour && tail.isNotEmpty) {
      fixedLast = tail.last;
    }

    final items = List<Poi>.from(tail);
    if (fixedLast != null) items.removeLast();

    final ordered = <Poi>[start];
    var cur = start;

    while (items.isNotEmpty) {
      items.sort((a, b) => _distKm(cur.location, a.location).compareTo(_distKm(cur.location, b.location)));
      final next = items.removeAt(0);
      ordered.add(next);
      cur = next;
    }

    if (fixedLast != null) ordered.add(fixedLast);
    return ordered;
  }

  Poi _lastRealStop(List<Poi> stops) {
    for (int i = stops.length - 1; i >= 0; i--) {
      final s = stops[i];
      if (!s.name.toLowerCase().contains('atpakaļ')) return s;
    }
    return stops.last;
  }

  // ---------------- Estimates ----------------

  int _estimateKm(List<Poi> stops) {
    if (stops.length < 2) return 0;
    double km = 0;
    for (int i = 1; i < stops.length; i++) {
      km += _distKm(stops[i - 1].location, stops[i].location);
    }
    // detour factor (roads aren't straight lines)
    km *= 1.10;
    return km.round();
  }

  double _estimateHours(List<Poi> stops) {
    final km = _estimateKm(stops).toDouble();
    final driveH = km / 50.0;
    final visitH = stops.map((e) => e.durationH).fold(0.0, (a, b) => a + b);
    return driveH + visitH;
  }

  String _summary(DayTheme theme, WeatherDay? w, int km, double hours, int mustCount) {
    final t = switch (theme) {
      DayTheme.indoor => 'Indoor (muzeji/telpas)',
      DayTheme.nature => 'Daba/jūra/meži',
      DayTheme.mixed => 'Jaukts',
    };
    final ww = (w == null) ? '' : ' • ${w.description} ${w.tempC.toStringAsFixed(0)}°C';
    final hh = hours.toStringAsFixed(hours >= 10 ? 0 : 1);
    return '$t$ww • must-see: $mustCount • ~$hh h • ~$km km';
  }
}
