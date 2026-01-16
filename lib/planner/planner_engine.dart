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

  // ===================== WEATHER SCORING =====================

  /// Jo lielāks skaitlis, jo sliktāk šim POI dotajā laikā.
  /// Izmantojam MUST-SEE pārkārtošanai un filler kandidātu šķirošanai.
  double _poiWeatherPenalty(Poi poi, WeatherDay? weather) {
    if (weather == null) return 0.0;

    double penalty = 0.0;

    final isViewpoint = poi.categories.contains(PoiCategory.viewpoint);
    final isBeach = poi.categories.contains(PoiCategory.beach);
    final isNature = poi.categories.contains(PoiCategory.nature);

    if (weather.isRainy || weather.isStormy) {
      if (!poi.isIndoor) penalty += 3.0;
      if (isBeach) penalty += 2.0;
      if (isNature) penalty += 1.0;
    }

    if (weather.isCold) {
      if (isBeach) penalty += 3.0;
      if (!poi.isIndoor) penalty += 1.0;
    }

    if (weather.windMs >= 12) {
      if (isViewpoint) penalty += 3.0;
      if (isBeach) penalty += 1.5;
      if (isNature && !poi.isIndoor) penalty += 1.0;
    }

    return penalty;
  }

  /// 0.20..1.0 (1 = ļoti laba diena outdoor)
  double _dayWeatherScore(WeatherDay? w) {
    if (w == null) return 1.0;

    double score = 1.0;
    if (w.isRainy) score -= 0.30;
    if (w.isStormy) score -= 0.40;
    if (w.isCold) score -= 0.20;
    if (w.windMs >= 12) score -= 0.20;

    return score.clamp(0.20, 1.0);
  }

  bool _isWeatherSensitive(Poi p) {
    // weather-sensitive = outdoor (indoor nav jēgas bīdīt prom no lietus)
    if (p.isIndoor) return false;

    final isViewpoint = p.categories.contains(PoiCategory.viewpoint);
    final isBeach = p.categories.contains(PoiCategory.beach);
    final isNature = p.categories.contains(PoiCategory.nature);

    return isViewpoint || isBeach || isNature || !p.isIndoor;
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
    final usedPoiIds = <String>{...mustSee.map((e) => e.id)};
    final plans = <DayPlan>[];

    LatLon currentBase = input.startPoint;

    // ✅ movingTour: sagatavojam vienotu must-see secību (nevis 1 klasteris = 1 diena)
    final movingTourQueue = (input.mode == TripMode.movingTour)
        ? _buildMovingTourSequence(mustSee: mustSee, origin: input.startPoint)
        : <Poi>[];

    // ✅ singleBase: vienreiz izveidojam geo klasterus + pārbalansējam pēc weather starp DIENĀM
    List<List<Poi>>? singleBaseClusters;
    if (input.mode == TripMode.singleBase) {
      final clusters = _clusterMustSeeByGeo(
        mustSee,
        k: input.daysCount,
        origin: input.startPoint,
      );

      final orderedClusters = _orderClustersForwardIfMovingTour(
        clusters: clusters,
        origin: input.startPoint,
        movingTour: false,
        allMustSee: mustSee,
      );

      singleBaseClusters = _rebalanceSingleBaseClustersByWeather(
        clusters: orderedClusters,
        days: days,
        weatherMap: weatherMap,
        origin: input.startPoint,
      );
    }

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];

      // debug (vari atstāt izstrādē)
      // ignore: avoid_print
      print('DAY $i | date=$date | '
          'rain=${weather?.rainMm}, '
          'wind=${weather?.windMs}, '
          'temp=${weather?.tempC}');

      // ====== PROFILE impact ======
      double maxHours = input.maxHoursPerDay *
          input.fitnessMultiplier() *
          _partyHoursMultiplier(input.party);

      double maxKm =
          input.maxKmPerDay.toDouble() * _partyKmMultiplier(input.party);

      final maxStops = _maxStopsForProfile(input);

      // ====== WEATHER penalty (dienas budžets) ======
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

      // ===============================
      // MUST-SEE izvēle šai dienai
      // ===============================

      List<Poi> todaysMust;
      if (input.mode == TripMode.singleBase) {
        // ✅ SingleBase: ņemam no jau pārbalansētajiem klasteriem (starp DIENĀM)
        final src = singleBaseClusters ?? <List<Poi>>[];
        todaysMust = (i < src.length) ? List<Poi>.from(src[i]) : <Poi>[];

        // ✅ papildus: sakārtojam dienas iekšienē pēc "distance + weather penalty"
        final center = centroid([
          input.startPoint,
          ...todaysMust.map((e) => e.location),
        ]);

        todaysMust.sort((a, b) {
          final da = _distKm(center, a.location);
          final db = _distKm(center, b.location);
          final pa = _poiWeatherPenalty(a, weather);
          final pb = _poiWeatherPenalty(b, weather);
          final sa = da + pa * 30.0;
          final sb = db + pb * 30.0;
          return sa.compareTo(sb);
        });

        // debug: kādi penalty šodien
        // ignore: avoid_print
        print('--- DAY $i (${weather?.description ?? '—'}) singleBase MUST ---');
        for (final p in todaysMust) {
          // ignore: avoid_print
          print('${p.name} penalty=${_poiWeatherPenalty(p, weather)}');
        }
      } else {
        // ✅ Moving tour: sabalansējam pa dienām pēc maxKm/maxHours + weather-aware
        todaysMust = _takeMustSeeForDayMovingTour(
          dayIndex: i,
          daysCount: days.length,
          currentBase: currentBase,
          queue: movingTourQueue,
          maxKm: maxKm,
          maxHours: maxHours,
          weather: weather,
        );
      }

      // centrs filler POI meklēšanai (ap bāzi + todaysMust)
      final center = centroid([
        currentBase,
        ...todaysMust.map((e) => e.location),
      ]);

      // sākuma pietura
      final stops = <Poi>[
        Poi(id: 'base_$i', name: 'Sākums', location: currentBase),
        ...todaysMust,
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
        weather: weather,
      );

      // ✅ Moving tour: pēdējā dienā (ja checkbox ieslēgts) pievienojam atgriešanos uz startu
      final isLastDay = (i == days.length - 1);
      if (input.mode == TripMode.movingTour &&
          input.returnToStart &&
          isLastDay) {
        filled.add(
          Poi(
            id: 'return_home_$i',
            name: 'Atpakaļ uz sākumu',
            location: input.startPoint,
            durationH: 0.0,
            categories: const {PoiCategory.city},
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
          mustSee: todaysMust.where((p) => !p.isOvernightStop).toList(),
          stops: filled,
          estKm: estKm,
          estHours: estHours,
          weather: weather,
          summary:
          'must-see: ${todaysMust.where((p) => !p.isOvernightStop).length} • ~${estHours.toStringAsFixed(1)} h • ~$estKm km',
          hasOvernightStops: filled.any((p) => p.isOvernightStop),
          debugWeatherScore: null,
          debugPenalties: null,
          debugMoved: const [],


        ),
      );

      // ✅ Moving tour bāze nākamajai dienai = pēdējā pietura
      // (izņemot "atpakaļ uz sākumu" pēdējā dienā)
      if (input.mode == TripMode.movingTour) {
        if (!(input.returnToStart && isLastDay)) {
          currentBase = filled.last.location;
        }
      }
    }

    return plans;
  }

  // ===================== SINGLE BASE WEATHER REBALANCE =====================

  /// Pēc sākotnējās geo klasterēšanas mēģina pārbīdīt weather-sensitive POI
  /// no sliktām dienām uz labākām dienām (singleBase režīmā).
  ///
  /// Saglabā:
  /// - aptuveni līdzīgu POI skaitu katrā dienā (cap)
  /// - nepārbīda “jau labos” indoor uz citu dienu bez jēgas
  List<List<Poi>> _rebalanceSingleBaseClustersByWeather({
    required List<List<Poi>> clusters,
    required List<DateTime> days,
    required Map<DateTime, WeatherDay> weatherMap,
    required LatLon origin,
  }) {
    final out = List<List<Poi>>.generate(
      clusters.length,
          (i) => List<Poi>.from(clusters[i]),
    );

    if (out.length != days.length) return out;

    // dienu score
    final scores = <int, double>{};
    for (int i = 0; i < days.length; i++) {
      final w = weatherMap[_dayKey(days[i])];
      scores[i] = _dayWeatherScore(w);
    }

    // sliktākās dienas pirmās
    final dayIdxByWorst = List<int>.generate(days.length, (i) => i)
      ..sort((a, b) => (scores[a] ?? 1.0).compareTo(scores[b] ?? 1.0));

    // labākās dienas pirmās
    final dayIdxByBest = List<int>.generate(days.length, (i) => i)
      ..sort((a, b) => (scores[b] ?? 1.0).compareTo(scores[a] ?? 1.0));

    // kapacitāte: sākotnējais izmērs +1, ja diena laba (dodam vairāk outdoor dienā ar labu laiku)
    final cap = <int, int>{};
    for (int i = 0; i < out.length; i++) {
      final base = out[i].length;
      final s = scores[i] ?? 1.0;
      final extra = (s >= 0.80) ? 1 : 0;
      cap[i] = max(1, base + extra);
    }

    // pārbīde no sliktām uz labām
    for (final fromDay in dayIdxByWorst) {
      final wFrom = weatherMap[_dayKey(days[fromDay])];
      final scoreFrom = scores[fromDay] ?? 1.0;

      // tikai ja tiešām slikta diena
      if (scoreFrom > 0.70) continue;

      final list = out[fromDay];

      // pārbīdāmie: jutīgi + augsts penalty tieši šajā dienā
      final movable = list
          .where((p) => _isWeatherSensitive(p))
          .toList()
        ..sort((a, b) => _poiWeatherPenalty(b, wFrom).compareTo(
          _poiWeatherPenalty(a, wFrom),
        ));

      for (final p in movable) {
        // ja šis POI pat sliktā laikā nav tik slikts, nav vērts bīdīt
        final penFrom = _poiWeatherPenalty(p, wFrom);
        if (penFrom < 2.0) continue;

        int? bestTarget;
        double bestTargetScore = -1;

        for (final toDay in dayIdxByBest) {

          // 👇 JAUNS BLOKS (ieliec šo)
          final centerFrom = centroid(out[fromDay].map((e) => e.location).toList());
          final centerTo   = centroid(out[toDay].map((e) => e.location).toList());

          // Ja dienas ir pārāk tālu viena no otras – NEĻAUJAM pārbīdīt
          if (_distKm(centerFrom, centerTo) > 120) continue;

          // esošais kods paliek
          if (toDay == fromDay) continue;

          final wTo = weatherMap[_dayKey(days[toDay])];
          final sTo = scores[toDay] ?? 1.0;

          // vajag būt būtiski labākai par fromDay
          if (sTo <= scoreFrom + 0.15) continue;

          // kapacitāte
          if (out[toDay].length >= (cap[toDay] ?? out[toDay].length + 1)) {
            continue;
          }

          // ja target dienā šim POI penalty ir liels, nav jēgas bīdīt
          final penTo = _poiWeatherPenalty(p, wTo);
          if (penTo >= penFrom) continue; // jābūt labāk nekā bija
          if (penTo >= 3.0) continue; // ļoti slikti arī target

          // izvēlamies labāko target
          if (sTo > bestTargetScore) {
            bestTargetScore = sTo;
            bestTarget = toDay;
          }
        }

        if (bestTarget == null) continue;

        // pārvietojam
        if (out[fromDay].remove(p)) {
          out[bestTarget].add(p);
        }
      }
    }

    // pēc pārbīdes: sakārtojam katru dienu “loģiski” pēc attāluma no origin + (mazs) penalty
    for (int i = 0; i < out.length; i++) {
      final w = weatherMap[_dayKey(days[i])];
      final list = out[i];
      list.sort((a, b) {
        final da = _distKm(origin, a.location);
        final db = _distKm(origin, b.location);
        final pa = _poiWeatherPenalty(a, w);
        final pb = _poiWeatherPenalty(b, w);
        final sa = da + pa * 10.0;
        final sb = db + pb * 10.0;
        return sa.compareTo(sb);
      });
    }

    return out;
  }

  // ===================== MOVING TOUR MUST-SEE ALLOCATION =====================

  /// Uztaisa vienu secību no mustSee (pietiekami stabilu movingTour gadījumam).
  /// Mēs lietojam "nearest-next" no pašreizējā punkta.
  List<Poi> _buildMovingTourSequence({
    required List<Poi> mustSee,
    required LatLon origin,
  }) {
    final remaining = List<Poi>.from(mustSee);
    final out = <Poi>[];
    LatLon cur = origin;

    while (remaining.isNotEmpty) {
      remaining.sort((a, b) =>
          _distKm(cur, a.location).compareTo(_distKm(cur, b.location)));
      final next = remaining.removeAt(0);
      out.add(next);
      cur = next.location;
    }

    return out;
  }

  /// Paņem mustSee šai dienai, ievērojot maxKm/maxHours.
  /// ✅ Weather-aware: izvēloties nākamo, mēs ņemam vērā penalty par sliktu laiku.
  /// Ja nākamais mustSee ir tik tālu, ka vienā dienā nav iespējams → ieliek "Nakts pieturu".
  List<Poi> _takeMustSeeForDayMovingTour({
    required int dayIndex,
    required int daysCount,
    required LatLon currentBase,
    required List<Poi> queue,
    required double maxKm,
    required double maxHours,
    required WeatherDay? weather,
  }) {
    if (queue.isEmpty) return <Poi>[];

    final out = <Poi>[];
    LatLon cur = currentBase;

    // lai nepazustu mustSee līdz pēdējai dienai:
    final daysLeft = (daysCount - dayIndex);
    final mustLeft = queue.length;
    final shouldTakeAtLeastOne = mustLeft >= daysLeft;

    // Ja pirmais segments jau ir pārāk garš -> overnight stop
    final first = queue.first;
    final d0 = _distKm(cur, first.location);
    if (d0 > maxKm) {
      out.add(_makeOvernightStop(from: cur, to: first.location, dayIndex: dayIndex));
      return out;
    }

    double kmAcc = 0.0;
    double hoursAcc = 0.0;

    bool tookAnyRealMust = false;

    while (queue.isNotEmpty) {
      final next = _pickNextMustSeeWeatherAware(
        current: cur,
        queue: queue,
        weather: weather,
      );
      if (next == null) break;

      final legKm = _distKm(cur, next.location);
      final newKm = kmAcc + legKm;

      final driveH = (legKm / 50.0) * 1.1;
      final newHours = hoursAcc + driveH + next.durationH;

      if (newKm > maxKm || newHours > maxHours) {
        break;
      }

      queue.remove(next);
      out.add(next);

      kmAcc = newKm;
      hoursAcc = newHours;
      cur = next.location;
      tookAnyRealMust = true;

      if (shouldTakeAtLeastOne && tookAnyRealMust) {
        // turpinām, ja ietilpst
      }
    }

    // Ja tomēr nepaņēmām nevienu, paņemam vismaz 1 (ja var)
    if (!tookAnyRealMust && queue.isNotEmpty) {
      final next = queue.first;
      final legKm = _distKm(currentBase, next.location);
      if (legKm <= maxKm) {
        queue.removeAt(0);
        out.add(next);
      }
    }

    return out;
  }

  Poi? _pickNextMustSeeWeatherAware({
    required LatLon current,
    required List<Poi> queue,
    required WeatherDay? weather,
  }) {
    if (queue.isEmpty) return null;

    // Ņemam tuvākos N, lai nelēktu pāri visai valstij tikai laikapstākļu dēļ
    final sortedByDist = List<Poi>.from(queue)
      ..sort((a, b) => _distKm(current, a.location)
          .compareTo(_distKm(current, b.location)));

    final int n = min(6, sortedByDist.length);
    final candidates = sortedByDist.take(n).toList();

    Poi best = candidates.first;
    double bestScore = double.infinity;

    for (final p in candidates) {
      final d = _distKm(current, p.location);
      final penalty = _poiWeatherPenalty(p, weather);

      // 1 penalty punkts ~ 25 km
      final score = d + penalty * 25.0;

      if (score < bestScore) {
        bestScore = score;
        best = p;
      }
    }

    return best;
  }

  Poi _makeOvernightStop({
    required LatLon from,
    required LatLon to,
    required int dayIndex,
  }) {
    // interpolācija
    LatLon mid = _interpolate(from, to, 0.55);

    return Poi(
      id: 'overnight_${dayIndex}_${mid.lat.toStringAsFixed(5)}_${mid.lon.toStringAsFixed(5)}',
      name: 'Nakts pietura (ieteikta,pievienojiet must see sarakstā)',
      location: mid,
      durationH: 0.0,
      categories: const {PoiCategory.city},
      isIndoor: true,
      isOvernightStop: true,
    );
  }

  LatLon _interpolate(LatLon a, LatLon b, double t) {
    final lat = a.lat + (b.lat - a.lat) * t;
    final lon = a.lon + (b.lon - a.lon) * t;
    return LatLon(lat, lon);
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

    // weather-aware filler: lietū dod priekšroku indoor
    candidates.sort((a, b) {
      final da = _distKm(center, a.location);
      final db = _distKm(center, b.location);
      final pa = _poiWeatherPenalty(a, weather);
      final pb = _poiWeatherPenalty(b, weather);

      final sa = da + pa * 15.0;
      final sb = db + pb * 15.0;
      return sa.compareTo(sb);
    });

    for (final p in candidates) {
      // maxStops = POI skaits (neskaitot start/end).
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

  // ===================== GEO CLUSTERING (singleBase) =====================

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
}
