import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/plan.dart';
import '../models/poi.dart';
import '../planner/planner_engine.dart';
import '../services/weather_api_service.dart';
import '../services/poi_catalog_service.dart';
import '../models/trip.dart';
import '../models/weather.dart';

class ResultsScreen extends StatefulWidget {
  final List<DayPlan> plans;
  final TripInput input;
  final List<WeatherDay> weatherByDay;
  final List<Poi> poiPool;
  final int? maxKmPerDay;

  const ResultsScreen({
    super.key,
    required this.plans,
    required this.input,
    required this.weatherByDay,
    required this.poiPool,
    this.maxKmPerDay,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late List<DayPlan> _plans;

  final Set<String> _visitedPoiIds = <String>{};
  final Set<String> _skippedPoiIds = <String>{};

  final PlannerEngine _engine = PlannerEngine();

  final WeatherApiService _weatherApi = const WeatherApiService();
  final PoiCatalogService _poiCatalog = PoiCatalogService();

  bool _replanning = false;

  @override
  void initState() {
    super.initState();
    _plans = List<DayPlan>.from(widget.plans);
  }

  Future<void> _replanFromDay({
    required DateTime fromDate,
  }) async {
    final newPlans = _engine.replanFromDay(
      originalInput: widget.input,
      existingPlans: _plans,
      fromDate: fromDate,
      newWeatherByDay: widget.weatherByDay,
      poiPool: widget.poiPool,
      visitedPoiIds: _visitedPoiIds,
      skippedPoiIds: _skippedPoiIds,
    );

    if (!mounted) return;

    setState(() {
      _plans = newPlans;
    });
  }

  Future<void> _markVisited({
    required Poi poi,
    required DateTime fromDate,
  }) async {
    _skippedPoiIds.remove(poi.id);
    _visitedPoiIds.add(poi.id);
    await _replanFromDay(fromDate: fromDate);
  }

  Future<void> _markSkipped({
    required Poi poi,
    required DateTime fromDate,
  }) async {
    _visitedPoiIds.remove(poi.id);
    _skippedPoiIds.add(poi.id);
    await _replanFromDay(fromDate: fromDate);
  }
  // ================= MUST-SEE CONSISTENCY =================

  Set<String> get _selectedMustSeeIds =>
      widget.input.mustSee.map((p) => p.id).toSet();

  Set<String> get _plannedMustSeeIds {
    final ids = <String>{};

    for (final d in _plans) {
      for (final p in d.mustSee) {
        ids.add(p.id);
      }
    }

    return ids;
  }

  List<Poi> get _missingMustSee {
    final planned = _plannedMustSeeIds;

    return widget.input.mustSee
        .where((p) => !planned.contains(p.id))
        .toList();
  }

  int get _selectedMustSeeCount => _selectedMustSeeIds.length;

  int get _plannedMustSeeCount => _plannedMustSeeIds.length;

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    final missing = _missingMustSee;
    final hasMissing = missing.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ceļojuma plāns'),
        actions: [
          IconButton(
            tooltip: 'Pārrēķināt no šodienas',
            icon: const Icon(Icons.refresh),
            onPressed: _replanning ? null : _replanFromToday,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [

          // ================= MUST-SEE SUMMARY =================

          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),

              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  Text(
                    'Must-see kopsavilkums',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),

                  const SizedBox(height: 8),

                  Text('Izvēlēti: $_selectedMustSeeCount'),

                  Text('Ieplānoti: $_plannedMustSeeCount'),

                  const SizedBox(height: 12),

                  if (hasMissing) ...[

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.10),

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: Colors.orange.shade400,
                        ),
                      ),

                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [

                          const Text(
                            '⚠️ Ne visi must-see tika ieplānoti šajā periodā.',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 6),

                          Text(
                            'Neieplānoti: ${missing.length}',
                          ),

                          const SizedBox(height: 6),

                          Text(
                            widget.input.ignoreWeather
                                ? 'Iemesls: km / stundu limiti vai dienu skaits.'
                                : 'Iemesls: weather + limiti. Vari palielināt dienu skaitu vai limitus.',
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 10),

                    Text(
                      'Neieplānotie must-see:',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),

                    const SizedBox(height: 6),

                    ...missing.take(10).map(
                          (p) => Text('• ${p.name}'),
                    ),

                    if (missing.length > 10)
                      Text('…un vēl ${missing.length - 10}'),

                  ] else ...[

                    Container(
                      width: double.infinity,

                      padding: const EdgeInsets.all(12),

                      decoration: BoxDecoration(
                        color: Colors.green.withValues(alpha: 0.08),

                        borderRadius: BorderRadius.circular(12),

                        border: Border.all(
                          color: Colors.green.shade300,
                        ),
                      ),

                      child: const Text(
                        '✅ Visi must-see ir ieplānoti.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // ================= DAY CARDS =================

          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _plans.length,
            itemBuilder: (context, i) {

              final p = _plans[i];

              final overLimit =
                  widget.maxKmPerDay != null &&
                      p.estKm > widget.maxKmPerDay!;

              final visibleStops = p.stops
                  .where((s) => !_isSyntheticPoi(s))
                  .toList();
              return Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),

                child: Padding(
                  padding: const EdgeInsets.all(16),

                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Text(
                        'Diena ${i + 1} • ${_formatDate(p.date)}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),

                      // ================= WEATHER (FIXED) =================

                      if (!widget.input.ignoreWeather &&
                          p.weather != null) ...[

                        const SizedBox(height: 4),

                        Text(
                          _formatWeather(p.weather!),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                      ],

                      const SizedBox(height: 6),

                      Text(p.summary),

                      Text(
                        '~${p.estKm} km • ~${p.estHours.toStringAsFixed(1)} h',
                      ),

                      if (overLimit) ...[

                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.all(10),

                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.08),

                            borderRadius: BorderRadius.circular(10),

                            border: Border.all(
                              color: Colors.red.shade300,
                            ),
                          ),

                          child: const Text(
                            '⚠️ Dienas slodze pārsniedz iestatīto limitu',
                          ),
                        ),
                      ],

                      const Divider(height: 20),

                      ...p.stops
                          .where((s) => !_isSyntheticPoi(s))
                          .map((s) {

                        final isVisited = _visitedPoiIds.contains(s.id);
                        final isSkipped = _skippedPoiIds.contains(s.id);

                        return Row(
                          children: [

                            Expanded(
                              child: Text('• ${s.name}'),
                            ),

                            IconButton(
                              icon: Icon(
                                Icons.check_circle,
                                color: isVisited
                                    ? Colors.green
                                    : Colors.grey,
                              ),

                              onPressed: () async {
                                await _markVisited(
                                  poi: s,
                                  fromDate: p.date,
                                );
                              },
                            ),

                            IconButton(
                              icon: Icon(
                                Icons.cancel,
                                color: isSkipped
                                    ? Colors.red
                                    : Colors.grey,
                              ),

                              onPressed: () async {
                                await _markSkipped(
                                  poi: s,
                                  fromDate: p.date,
                                );
                              },
                            ),
                          ],
                        );
                      }),

                      const SizedBox(height: 12),

                      Align(
                        alignment: Alignment.centerRight,

                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.navigation),

                          label: const Text('Atvērt Google Maps'),

                          onPressed: () =>
                              _openInGoogleMaps(p.stops)
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ================= WEATHER FORMAT =================

  bool _isSyntheticPoi(Poi poi) {
    final id = poi.id.toLowerCase();
    return id.startsWith('base_') ||
        id.startsWith('base_end_') ||
        id.startsWith('base_tmp_') ||
        id.startsWith('return_home_');
  }
  String _formatWeather(WeatherDay w) {
    final t = '${w.tempC.round()}°C';

    final rain =
    w.rainMm > 0
        ? ' · 🌧 ${w.rainMm.toStringAsFixed(1)} mm'
        : '';

    final wind =
        ' · 💨 ${w.windMs.toStringAsFixed(1)} m/s';

    return '$t$rain$wind · ${w.description}';
  }

  // ================= REPLAN =================

  Future<void> _replanFromToday() async {

    setState(() {
      _replanning = true;
    });

    try {

      final today = DateTime.now();

      final weather =
      await _weatherApi.getForecastForTrip(
        lat: widget.input.startPoint.lat,
        lon: widget.input.startPoint.lon,
        startDate: today,
        daysCount: widget.input.daysCount,
      );

      final poiPool =
      _poiCatalog.catalogForRegion(
        widget.input.regionText,
      );

      final newPlans =
      _engine.replanFromDay(
        originalInput: widget.input,
        existingPlans: _plans,
        fromDate: today,
        newWeatherByDay: weather,
        poiPool: poiPool,
        visitedPoiIds: _visitedPoiIds,
        skippedPoiIds: _skippedPoiIds,
      );

      if (!mounted) return;

      setState(() {
        _plans = newPlans;
      });

    } finally {

      if (mounted) {
        setState(() {
          _replanning = false;
        });
      }
    }
  }

  // ================= GOOGLE MAPS =================

  Future<void> _openInGoogleMaps(
      List<Poi> stops) async {

    if (stops.length < 2) return;

    final origin = stops.first.location;

    final dest = stops.last.location;

    final waypoints =
    stops.length > 2
        ? stops
        .sublist(1, stops.length - 1)
        .map(
            (p) =>
        '${p.location.lat},${p.location.lon}')
        .join('|')
        : '';

    final uri =
    Uri.https(
      'www.google.com',
      '/maps/dir/',
      {
        'api': '1',
        'origin':
        '${origin.lat},${origin.lon}',
        'destination':
        '${dest.lat},${dest.lon}',
        if (waypoints.isNotEmpty)
          'waypoints': waypoints,
        'travelmode': 'driving',
      },
    );

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  // ================= DATE FORMAT =================

  String _formatDate(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
