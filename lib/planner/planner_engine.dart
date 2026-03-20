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

  bool _isBadWeather(WeatherDay? weather) => _preferIndoorByWeather(weather);

  int _indoorPriority(Poi p) {
    final isIndoorCat = p.categories.contains(PoiCategory.indoor) ||
        p.categories.contains(PoiCategory.museum);
    return (p.isIndoor || isIndoorCat) ? 1 : 0;
  }

  bool _isIndoorPoi(Poi p) => _indoorPriority(p) == 1;

  List<Poi> _prioritizeMustSeeByWeather({
    required List<Poi> todaysMust,
    required WeatherDay? weather,
  }) {
    if (todaysMust.isEmpty) return todaysMust;

    final out = List<Poi>.from(todaysMust);
    final preferIndoor = _preferIndoorByWeather(weather);

    out.sort((a, b) {
      final ai = _indoorPriority(a);
      final bi = _indoorPriority(b);
      return preferIndoor ? (bi - ai) : (ai - bi);
    });

    return out;
  }

  int _mustSeeCapByWeather(int candidateCount, WeatherDay? weather) {
    return candidateCount;
  }

  DayTheme _chooseTheme({
    required WeatherDay? weather,
    required List<Poi> todaysMust,
    required bool fallbackIndoorUsed,
  }) {
    if (fallbackIndoorUsed) return DayTheme.indoor;

    if (todaysMust.isEmpty) {
      return _preferIndoorByWeather(weather) ? DayTheme.indoor : DayTheme.mixed;
    }

    final indoor = todaysMust.where(_isIndoorPoi).length;
    final ratio = indoor / todaysMust.length;

    if (ratio >= 0.60) return DayTheme.indoor;
    if (ratio <= 0.40) return DayTheme.nature;
    return DayTheme.mixed;
  }

  // ===================== REPLAN =====================

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
        if (id.startsWith('base_tmp')) continue;
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

  // ===================== DAY LIMIT HELPERS =====================

  double _effectiveMaxKmForDay({
    required TripInput input,
    required WeatherDay? weather,
  }) {
    double maxKm =
        input.maxKmPerDay.toDouble() * _partyKmMultiplier(input.party);

    if (weather != null && !input.ignoreWeather) {
      if (weather.isRainy || weather.isStormy) {
        maxKm *= 0.80;
      }
      if (weather.windMs >= 12) {
        maxKm *= 0.85;
      }
      if (weather.isCold) {
        maxKm *= 0.90;
      }
    }

    return math.max(30.0, maxKm);
  }

  double _effectiveMaxHoursForDay({
    required TripInput input,
    required WeatherDay? weather,
  }) {
    double maxHours = input.maxHoursPerDay *
        input.fitnessMultiplier() *
        _partyHoursMultiplier(input.party);

    if (weather != null && !input.ignoreWeather) {
      if (weather.isRainy || weather.isStormy) {
        maxHours *= 0.60;
      }
      if (weather.windMs >= 12) {
        maxHours *= 0.75;
      }
      if (weather.isCold) {
        maxHours *= 0.80;
      }
    }

    return math.max(3.0, maxHours);
  }

  // ===================== STEP2 SCORE HELPERS =====================

  double _dayGeoSpreadPenalty({
    required LatLon base,
    required List<Poi> stops,
    required bool movingTour,
  }) {
    if (stops.length <= 1) return 0;

    final pts = stops.map((p) => p.location).toList();
    final c = centroid(pts);

    double spread = 0;
    for (final p in pts) {
      spread += _distKm(c, p);
    }
    spread = spread / pts.length;

    final baseOffset = movingTour ? 0.0 : _distKm(base, c) * 0.10;
    return spread * 1.2 + baseOffset;
  }

  double _dayBalanceScore({
    required LatLon base,
    required List<Poi> stops,
    required bool movingTour,
    required double maxKm,
    required bool hadInitialMustSee,
  }) {
    final km = _estimateSingleDayKm(
      base: base,
      stops: stops,
      movingTour: movingTour,
    );

    final overflow = math.max(0.0, km - maxKm);
    final overflowPenalty = overflow * 20.0;

    final spreadPenalty = _dayGeoSpreadPenalty(
      base: base,
      stops: stops,
      movingTour: movingTour,
    );

    final emptyPenalty = (hadInitialMustSee && stops.isEmpty) ? 5000.0 : 0.0;
    final thinDayPenalty =
    (hadInitialMustSee && stops.length == 1) ? 12.0 : 0.0;

    return overflowPenalty + spreadPenalty + emptyPenalty + thinDayPenalty;
  }

  double _pairBalanceScore({
    required LatLon base,
    required List<Poi> fromStops,
    required List<Poi> toStops,
    required bool movingTour,
    required double fromMaxKm,
    required double toMaxKm,
    required bool fromHadInitialMustSee,
    required bool toHadInitialMustSee,
  }) {
    return _dayBalanceScore(
      base: base,
      stops: fromStops,
      movingTour: movingTour,
      maxKm: fromMaxKm,
      hadInitialMustSee: fromHadInitialMustSee,
    ) +
        _dayBalanceScore(
          base: base,
          stops: toStops,
          movingTour: movingTour,
          maxKm: toMaxKm,
          hadInitialMustSee: toHadInitialMustSee,
        );
  }

  // ===================== STEP2 LOYALTY HELPERS =====================

  double _avgDistanceToGroup(Poi candidate, List<Poi> group) {
    if (group.isEmpty) return double.infinity;
    double sum = 0;
    for (final p in group) {
      sum += _distKm(candidate.location, p.location);
    }
    return sum / group.length;
  }

  bool _passesClusterLoyalty({
    required Poi candidate,
    required int fromDay,
    required int toDay,
    required List<List<Poi>> originalBuckets,
    required List<Poi> currentToList,
  }) {
    final originGroup = List<Poi>.from(originalBuckets[fromDay])
      ..removeWhere((p) => p.id == candidate.id);

    if (originGroup.isEmpty) return true;
    if (currentToList.isEmpty) return true;

    final originAffinity = _avgDistanceToGroup(candidate, originGroup);
    final targetAffinity = _avgDistanceToGroup(candidate, currentToList);

    const double loyaltyMarginKm = 25.0;

    if (targetAffinity > originAffinity + loyaltyMarginKm) {
      return false;
    }

    if (targetAffinity > 70.0) {
      return false;
    }

    return true;
  }

  // ===================== SUGGEST DAYS COUNT =====================

  int suggestDaysCountConsideringWeather({
    required TripInput input,
    required List<WeatherDay> weatherByDay,
  }) {
    final mustSee = input.mustSee;
    if (mustSee.length <= 1) return 1;

    final maxDays = math.min(30, mustSee.length);

    for (int k = 1; k <= maxDays; k++) {
      final endDate = _dayKey(input.startDate).add(Duration(days: k - 1));

      final testInput = TripInput(
        startDate: _dayKey(input.startDate),
        endDate: endDate,
        daysCount: k,
        mode: input.mode,
        transport: input.transport,
        fitness: input.fitness,
        party: input.party,
        regionText: input.regionText,
        startPoint: input.startPoint,
        returnToStart: input.returnToStart,
        includeFillers: input.includeFillers,
        maxKmPerDay: input.maxKmPerDay,
        mustSee: List<Poi>.from(input.mustSee),
      );

      final ok = _canFitAllMustSeeWithWeather(
        input: testInput,
        weatherByDay: weatherByDay,
        daysCount: k,
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

    final buckets = _buildInitialDayBuckets(
      input: input,
      days: days,
      weatherMap: weatherMap,
      mustSee: mustSee,
    );

    final carryOver = <Poi>[];
    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final weather = weatherMap[_dayKey(date)];

      final maxHours = _effectiveMaxHoursForDay(
        input: input,
        weather: weather,
      );
      final maxKm = _effectiveMaxKmForDay(
        input: input,
        weather: weather,
      );
      final maxStops = _maxStopsForProfile(input);

      final raw = (i < buckets.length) ? buckets[i] : <Poi>[];

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
        final estKm = _estimateSingleDayKm(
          base: currentBase,
          stops: todaysMust,
          movingTour: input.mode == TripMode.movingTour,
        );

        final stops = <Poi>[
          Poi(id: 'base_$i', name: 'Sākums', location: currentBase),
          ...todaysMust,
          if (input.mode == TripMode.singleBase)
            Poi(id: 'base_end_$i', name: 'Atpakaļ', location: currentBase),
        ];

        final estHours = _estimateHours(stops);
        return estKm <= maxKm.round() && estHours <= maxHours;
      }

      while (todaysMust.isNotEmpty && !within()) {
        final moved = todaysMust.removeLast();
        leftovers.insert(0, moved);
      }

      final isLast = (i == days.length - 1);
      if (isLast && leftovers.isNotEmpty) {
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

    final orderedClusters = _buildInitialDayBuckets(
      input: input,
      days: days,
      weatherMap: weatherMap,
      mustSee: mustSee,
    );

    final originalBuckets = List<List<Poi>>.generate(
      orderedClusters.length,
          (i) => List<Poi>.from(orderedClusters[i]),
    );

    final hadInitialMustSeeByDay = List<bool>.generate(
      input.daysCount,
          (i) => orderedClusters[i].isNotEmpty,
    );

    final dayBuckets = List.generate(
      input.daysCount,
          (i) => <Poi>[...orderedClusters[i]],
    );

    for (int i = 0; i < dayBuckets.length; i++) {
      print('DAYBUCKET $i: ${dayBuckets[i].map((p) => p.name).toList()}');
    }

    // ==============================
    // STEP 2: SMART BALANCE + CLUSTER LOYALTY
    // ==============================

    double effectiveMaxKm(int dayIndex) {
      final weather = weatherMap[_dayKey(days[dayIndex])];
      return input.ignoreWeather
          ? input.maxKmPerDay.toDouble()
          : _effectiveMaxKmForDay(input: input, weather: weather);
    }

    print('=== STEP2 BALANCE START ===');
    for (int d = 0; d < dayBuckets.length; d++) {
      print('PRE BAL day=$d: ${dayBuckets[d].map((p) => p.name).toList()}');
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

        print(
          'BAL CHECK from=$from fromKm=$fromKm max=${effectiveMaxKm(from).toStringAsFixed(1)} '
              'fromList=${fromList.map((p) => p.name).toList()}',
        );

        if (fromKm <= effectiveMaxKm(from)) continue;

        final toCandidates = <int>[
          if (from - 1 >= 0) from - 1,
          if (from + 1 < dayBuckets.length) from + 1,
        ];

        double bestImprovement = 0;
        int? bestTo;
        int? bestFromIndex;
        bool? bestUseEnd;
        double? bestNewKm;
        double? bestBeforeScore;
        double? bestAfterScore;

        for (final to in toCandidates) {
          final toList = dayBuckets[to];

          final beforeScore = _pairBalanceScore(
            base: input.startPoint,
            fromStops: fromList,
            toStops: toList,
            movingTour: input.mode == TripMode.movingTour,
            fromMaxKm: effectiveMaxKm(from),
            toMaxKm: effectiveMaxKm(to),
            fromHadInitialMustSee: hadInitialMustSeeByDay[from],
            toHadInitialMustSee: hadInitialMustSeeByDay[to],
          );

          for (int i = fromList.length - 1; i >= 0; i--) {
            final candidate = fromList[i];

            if (fromList.length == 1 && hadInitialMustSeeByDay[from]) {
              continue;
            }

            if (!_passesClusterLoyalty(
              candidate: candidate,
              fromDay: from,
              toDay: to,
              originalBuckets: originalBuckets,
              currentToList: toList,
            )) {
              print(
                'BAL SKIP loyalty: "${candidate.name}" from day $from -> day $to',
              );
              continue;
            }

            final newFrom = List<Poi>.from(fromList)..removeAt(i);

            final testToEnd = List<Poi>.from(toList)..add(candidate);
            final testToStart = <Poi>[candidate, ...toList];

            final newKmEnd = _estimateSingleDayKm(
              base: input.startPoint,
              stops: testToEnd,
              movingTour: input.mode == TripMode.movingTour,
            );

            final newKmStart = _estimateSingleDayKm(
              base: input.startPoint,
              stops: testToStart,
              movingTour: input.mode == TripMode.movingTour,
            );

            if (toList.isNotEmpty) {
              final toCent = centroid(toList.map((e) => e.location).toList());
              final distToDay = _distKm(toCent, candidate.location);
              if (distToDay > 80) continue;
            }

            void considerMove({
              required List<Poi> newTo,
              required bool useEnd,
              required double newKmTo,
            }) {
              if (newKmTo > effectiveMaxKm(to)) return;

              final afterScore = _pairBalanceScore(
                base: input.startPoint,
                fromStops: newFrom,
                toStops: newTo,
                movingTour: input.mode == TripMode.movingTour,
                fromMaxKm: effectiveMaxKm(from),
                toMaxKm: effectiveMaxKm(to),
                fromHadInitialMustSee: hadInitialMustSeeByDay[from],
                toHadInitialMustSee: hadInitialMustSeeByDay[to],
              );

              final improvement = beforeScore - afterScore;

              if (improvement > bestImprovement + 0.5) {
                bestImprovement = improvement;
                bestTo = to;
                bestFromIndex = i;
                bestUseEnd = useEnd;
                bestNewKm = newKmTo;
                bestBeforeScore = beforeScore;
                bestAfterScore = afterScore;
              }
            }

            considerMove(
              newTo: testToEnd,
              useEnd: true,
              newKmTo: newKmEnd,
            );

            considerMove(
              newTo: testToStart,
              useEnd: false,
              newKmTo: newKmStart,
            );
          }
        }

        if (bestTo != null &&
            bestFromIndex != null &&
            bestUseEnd != null &&
            bestNewKm != null) {
          final candidate = dayBuckets[from][bestFromIndex!];
          dayBuckets[from].removeAt(bestFromIndex!);

          if (bestUseEnd!) {
            dayBuckets[bestTo!].add(candidate);
          } else {
            dayBuckets[bestTo!].insert(0, candidate);
          }

          print(
            'BAL MOVE: "${candidate.name}" from day $from -> day $bestTo '
                'fromKm=$fromKm newKm(to)=$bestNewKm '
                'scoreBefore=${bestBeforeScore?.toStringAsFixed(1)} '
                'scoreAfter=${bestAfterScore?.toStringAsFixed(1)} '
                'improvement=${bestImprovement.toStringAsFixed(1)}',
          );

          print(
            'AFTER MOVE from=$from: ${dayBuckets[from].map((p) => p.name).toList()}',
          );
          print(
            'AFTER MOVE to=$bestTo: ${dayBuckets[bestTo!].map((p) => p.name).toList()}',
          );

          changed = true;
          break;
        }
      }
    }

    print('=== STEP2 BALANCE END ===');
    for (int d = 0; d < dayBuckets.length; d++) {
      print('POST BAL day=$d: ${dayBuckets[d].map((p) => p.name).toList()}');
    }

    // ==============================
    // STEP 3: BUILD FINAL PLANS
    // ==============================

    final plans = <DayPlan>[];
    final usedPoiIds = <String>{...mustSee.map((e) => e.id)};

    LatLon currentBase = input.startPoint;

    for (int i = 0; i < days.length; i++) {
      final date = days[i];
      final todaysMust = List<Poi>.from(dayBuckets[i]);
      final weather = weatherMap[_dayKey(date)];

      final base = input.mode == TripMode.singleBase
          ? input.startPoint
          : currentBase;

      final maxKm = _effectiveMaxKmForDay(input: input, weather: weather);
      final maxHours = _effectiveMaxHoursForDay(input: input, weather: weather);

      final baseStops = <Poi>[
        Poi(id: 'base_$i', name: 'Sākums', location: base),
        ...todaysMust,
      ];

      if (input.mode == TripMode.singleBase) {
        baseStops.add(
          Poi(id: 'base_end_$i', name: 'Atpakaļ', location: base),
        );
      }

      final hasRemainingMustSeeLater =
      dayBuckets.skip(i + 1).any((e) => e.isNotEmpty);

      final badWeather = !input.ignoreWeather && _isBadWeather(weather);

      bool fallbackIndoorUsed = false;
      List<Poi> finalStops = List<Poi>.from(baseStops);

      if (badWeather && todaysMust.isEmpty && hadInitialMustSeeByDay[i]) {
        final fallbackStops = _buildIndoorFallbackStops(
          base: base,
          maxKm: maxKm,
          maxHours: maxHours,
          maxStops: _maxStopsForProfile(input),
          poiPool: poiPool,
          usedPoiIds: usedPoiIds,
          movingTour: input.mode == TripMode.movingTour,
        );

        final fallbackRealPois = fallbackStops.where((p) {
          return !p.id.startsWith('base_') && !p.id.startsWith('base_tmp');
        }).length;

        if (fallbackRealPois > 0) {
          finalStops = fallbackStops;
          fallbackIndoorUsed = true;
          print('WEATHER FALLBACK DAY $i: '
              '${finalStops.map((p) => p.name).toList()}');
        }
      }

      final allowFillers =
          input.includeFillers && !hasRemainingMustSeeLater && !fallbackIndoorUsed;

      if (allowFillers) {
        finalStops = _fillStopsToHours(
          stops: finalStops,
          maxHours: maxHours,
          maxKm: maxKm,
          maxStops: 12,
          center: centroid(finalStops.map((e) => e.location).toList()),
          poiPool: poiPool,
          usedPoiIds: usedPoiIds,
          movingTour: input.mode == TripMode.movingTour,
          weather: input.ignoreWeather ? null : weather,
        );
      }

      final estKm = _estimateKm(finalStops);
      final estHours = _estimateHours(finalStops);

      print('FINAL DAY $i: km=$estKm stops=${finalStops.map((p) => p.name).toList()}');

      final theme = _chooseTheme(
        weather: input.ignoreWeather ? null : weather,
        todaysMust: todaysMust,
        fallbackIndoorUsed: fallbackIndoorUsed,
      );

      final summary = fallbackIndoorUsed
          ? 'weather fallback indoor day • ~${estHours.toStringAsFixed(1)} h • ~$estKm km'
          : 'must-see: ${todaysMust.length} • ~${estHours.toStringAsFixed(1)} h • ~$estKm km';

      plans.add(
        DayPlan(
          date: date,
          theme: theme,
          base: base,
          mustSee: todaysMust,
          stops: finalStops,
          estKm: estKm,
          estHours: estHours,
          weather: input.ignoreWeather ? null : weather,
          summary: summary,
        ),
      );

      if (input.mode == TripMode.movingTour) {
        final realTravelStops = finalStops.where((p) {
          return !p.id.startsWith('base_') &&
              !p.id.startsWith('base_end_') &&
              !p.id.startsWith('base_tmp');
        }).toList();

        if (realTravelStops.isNotEmpty) {
          currentBase = realTravelStops.last.location;
        }
      }
    }

    return plans;
  }

  // ===================== WEATHER FALLBACK =====================

  List<Poi> _buildIndoorFallbackStops({
    required LatLon base,
    required double maxKm,
    required double maxHours,
    required int maxStops,
    required List<Poi> poiPool,
    required Set<String> usedPoiIds,
    required bool movingTour,
  }) {
    final indoorCandidates = poiPool.where((p) {
      if (usedPoiIds.contains(p.id)) return false;
      if (!_isIndoorPoi(p)) return false;
      return _distKm(base, p.location) <= 60;
    }).toList();

    indoorCandidates.sort((a, b) {
      final pa = _distKm(base, a.location);
      final pb = _distKm(base, b.location);
      return pa.compareTo(pb);
    });

    final out = <Poi>[
      Poi(id: 'base_tmp_start', name: 'Sākums', location: base),
    ];

    if (!movingTour) {
      out.add(Poi(id: 'base_tmp_end', name: 'Atpakaļ', location: base));
    }

    for (final p in indoorCandidates) {
      final insertIndex = movingTour ? out.length : out.length - 1;
      final test = List<Poi>.from(out)..insert(insertIndex, p);

      final km = _estimateKm(test);
      final hours = _estimateHours(test);

      final realStopCount =
          test.where((e) => !e.id.startsWith('base_tmp')).length;

      if (km > maxKm.round()) continue;
      if (hours > maxHours) continue;
      if (realStopCount > maxStops) continue;

      out.insert(insertIndex, p);
      usedPoiIds.add(p.id);
    }

    return out;
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
        final p = _indoorPriority(b) - _indoorPriority(a);
        if (p != 0) return p;
      } else {
        final p = _indoorPriority(a) - _indoorPriority(b);
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

    final route = <Poi>[
      Poi(id: 'base_tmp', name: 'BASE_START', location: base),
      ...stops,
      if (!movingTour)
        Poi(id: 'base_tmp_end', name: 'BASE_END', location: base),
    ];

    return _estimateKm(route).toDouble();
  }

  // ===================== STEP1 BEST-SPLIT =====================

  List<Poi> _buildOrderedMustSeeRoute({
    required List<Poi> mustSee,
    required LatLon origin,
  }) {
    final remaining = List<Poi>.from(mustSee);
    final ordered = <Poi>[];

    LatLon current = origin;

    while (remaining.isNotEmpty) {
      remaining.sort(
            (a, b) =>
            _distKm(current, a.location).compareTo(_distKm(current, b.location)),
      );
      final next = remaining.removeAt(0);
      ordered.add(next);
      current = next.location;
    }

    return ordered;
  }

  double _vectorX(LatLon a, LatLon b) => b.lon - a.lon;
  double _vectorY(LatLon a, LatLon b) => b.lat - a.lat;

  double _antiZigzagPenalty({
    required LatLon base,
    required List<Poi> seg,
  }) {
    if (seg.length < 3) return 0;

    final pts = <LatLon>[base, ...seg.map((e) => e.location)];

    double penalty = 0;

    for (int i = 1; i < pts.length - 1; i++) {
      final p0 = pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];

      final v1x = _vectorX(p0, p1);
      final v1y = _vectorY(p0, p1);
      final v2x = _vectorX(p1, p2);
      final v2y = _vectorY(p1, p2);

      final dot = v1x * v2x + v1y * v2y;
      final n1 = math.sqrt(v1x * v1x + v1y * v1y);
      final n2 = math.sqrt(v2x * v2x + v2y * v2y);

      if (n1 == 0 || n2 == 0) continue;

      final cosTheta = (dot / (n1 * n2)).clamp(-1.0, 1.0);

      // Ja cos < 0, maršruts taisa diezgan asu reversu / zigzag
      if (cosTheta < 0) {
        penalty += (-cosTheta) * 80.0;
      }

      // Pat vidēji asi pagriezieni lai arī saņem nelielu sodu
      if (cosTheta < 0.35) {
        penalty += (0.35 - cosTheta) * 18.0;
      }
    }

    return penalty;
  }

  double _segmentScoreForDay({
    required List<Poi> ordered,
    required int start,
    required int endExclusive,
    required LatLon base,
    required bool movingTour,
    required double maxKm,
  }) {
    final seg = ordered.sublist(start, endExclusive);

    if (seg.isEmpty) {
      return 5000.0;
    }

    final km = _estimateSingleDayKm(
      base: base,
      stops: seg,
      movingTour: movingTour,
    );

    final overflow = math.max(0.0, km - maxKm);
    final overflowPenalty = overflow * 60.0;

    final compactness = _segmentCompactness(seg, base);
    final zigzagPenalty = _antiZigzagPenalty(base: base, seg: seg);

    // Iepriekš bija pārāk vājš
    final thinPenalty = seg.length == 1 ? 120.0 : 0.0;

    return overflowPenalty + compactness + zigzagPenalty + thinPenalty;
  }

  List<List<Poi>> _bestSplitOrderedRoute({
    required List<Poi> ordered,
    required int daysCount,
    required TripInput input,
    required List<DateTime> days,
    required Map<DateTime, WeatherDay> weatherMap,
  }) {
    if (ordered.isEmpty) {
      return List.generate(daysCount, (_) => <Poi>[]);
    }

    final n = ordered.length;
    final k = daysCount;

    if (k >= n) {
      final out = <List<Poi>>[];
      for (final p in ordered) {
        out.add([p]);
      }
      while (out.length < k) {
        out.add(<Poi>[]);
      }
      return out;
    }

    final maxKmByDay = List<double>.generate(k, (i) {
      final weather = weatherMap[_dayKey(days[i])];
      return input.ignoreWeather
          ? input.maxKmPerDay.toDouble()
          : _effectiveMaxKmForDay(input: input, weather: weather);
    });

    const inf = 1e18;
    final dp = List.generate(k + 1, (_) => List<double>.filled(n + 1, inf));
    final cut = List.generate(k + 1, (_) => List<int>.filled(n + 1, -1));

    dp[0][0] = 0;

    for (int day = 1; day <= k; day++) {
      for (int end = 1; end <= n; end++) {
        for (int start = day - 1; start < end; start++) {
          if (dp[day - 1][start] >= inf) continue;

          final segScore = _segmentScoreForDay(
            ordered: ordered,
            start: start,
            endExclusive: end,
            base: input.startPoint,
            movingTour: input.mode == TripMode.movingTour,
            maxKm: maxKmByDay[day - 1],
          );

          final total = dp[day - 1][start] + segScore;
          if (total < dp[day][end]) {
            dp[day][end] = total;
            cut[day][end] = start;
          }
        }
      }
    }

    int bestUsedDays = math.min(k, n);
    double bestScore = dp[bestUsedDays][n];

    for (int used = 1; used <= math.min(k, n); used++) {
      if (dp[used][n] < bestScore) {
        bestScore = dp[used][n];
        bestUsedDays = used;
      }
    }

    final segments = <List<Poi>>[];
    int end = n;
    int day = bestUsedDays;

    while (day > 0 && end > 0) {
      final start = cut[day][end];
      if (start < 0) break;
      segments.insert(0, ordered.sublist(start, end));
      end = start;
      day--;
    }

    while (segments.length < k) {
      segments.add(<Poi>[]);
    }

    return segments;
  }

  List<List<Poi>> _buildInitialDayBuckets({
    required TripInput input,
    required List<DateTime> days,
    required Map<DateTime, WeatherDay> weatherMap,
    required List<Poi> mustSee,
  }) {
    final ordered = _buildOrderedMustSeeRoute(
      mustSee: mustSee,
      origin: input.startPoint,
    );

    final best = _bestSplitOrderedRoute(
      ordered: ordered,
      daysCount: input.daysCount,
      input: input,
      days: days,
      weatherMap: weatherMap,
    );

    final orderedClusters = _orderClustersForwardIfMovingTour(
      clusters: best,
      origin: input.startPoint,
      movingTour: input.mode == TripMode.movingTour,
      allMustSee: mustSee,
    );

    return orderedClusters;
  }

  double _segmentCompactness(List<Poi> segment, LatLon origin) {
    if (segment.isEmpty) return 0;
    if (segment.length == 1) {
      return _distKm(origin, segment.first.location) * 0.5;
    }

    double route = 0;
    LatLon current = origin;
    for (final p in segment) {
      route += _distKm(current, p.location);
      current = p.location;
    }

    final c = centroid(segment.map((e) => e.location).toList());
    double spread = 0;
    for (final p in segment) {
      spread += _distKm(c, p.location);
    }
    spread /= segment.length;

    // Iepriekš bija par vāju
    return route * 1.5 + spread * 4.0;
  }

  // ===================== ORDER CLUSTERS =====================

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