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
  final int? maxKmPerDay;

  const ResultsScreen({
    super.key,
    required this.plans,
    required this.input,
    this.maxKmPerDay,
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  late List<DayPlan> _plans;

  final Set<String> _visited = {};
  final Set<String> _skipped = {};

  final PlannerEngine _engine = PlannerEngine();
  final WeatherApiService _weatherApi = const WeatherApiService();
  final PoiCatalogService _poiCatalog = PoiCatalogService();

  bool _replanning = false;

  @override
  void initState() {
    super.initState();
    _plans = List.of(widget.plans);
  }

  @override
  Widget build(BuildContext context) {
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
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _plans.length,
        itemBuilder: (context, i) {
          final p = _plans[i];
          final overLimit =
              widget.maxKmPerDay != null && p.estKm > widget.maxKmPerDay!;

          return Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diena ${i + 1} • ${_d(p.date)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),

                  // ===== WEATHER ROW =====
                  if (p.weather != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      _formatWeather(p.weather!),
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],

                  const SizedBox(height: 6),

                  Text(p.summary),
                  Text('~${p.estKm} km • ~${p.estHours.toStringAsFixed(1)} h'),

                  if (overLimit) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: const Text(
                        '⚠️ Dienas slodze pārsniedz iestatīto limitu',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],

                  const Divider(height: 20),

                  ...p.stops.map((s) {
                    final isVisited = _visited.contains(s.id);
                    final isSkipped = _skipped.contains(s.id);

                    return Row(
                      children: [
                        Expanded(child: Text('• ${s.name}')),
                        IconButton(
                          tooltip: 'Apmeklēts',
                          icon: Icon(
                            Icons.check_circle,
                            color: isVisited ? Colors.green : Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _visited.add(s.id);
                              _skipped.remove(s.id);
                            });
                          },
                        ),
                        IconButton(
                          tooltip: 'Izlaists',
                          icon: Icon(
                            Icons.cancel,
                            color: isSkipped ? Colors.red : Colors.grey,
                          ),
                          onPressed: () {
                            setState(() {
                              _skipped.add(s.id);
                              _visited.remove(s.id);
                            });
                          },
                        ),
                      ],
                    );
                  }),

                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () => _openInGoogleMaps(p.stops),
                      icon: const Icon(Icons.navigation),
                      label: const Text('Atvērt Google Maps'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ================= WEATHER FORMAT =================

  String _formatWeather(WeatherDay w) {
    final t = '${w.tempC.round()}°C';
    final rain = w.rainMm > 0 ? ' · 🌧 ${w.rainMm.toStringAsFixed(1)} mm' : '';
    final wind = ' · 💨 ${w.windMs.toStringAsFixed(1)} m/s';
    return '$t$rain$wind · ${w.description}';
  }

  // ================= REPLAN =================

  Future<void> _replanFromToday() async {
    setState(() => _replanning = true);

    try {
      final today = DateTime.now();

      final weather = await _weatherApi.getForecastForTrip(
        lat: widget.input.startPoint.lat,
        lon: widget.input.startPoint.lon,
        startDate: today,
        daysCount: widget.input.daysCount,
      );

      final poiPool = _poiCatalog.catalogForRegion(widget.input.regionText);

      List<DayPlan> newPlans;
      try {
        newPlans = _engine.replanFromDay(
          originalInput: widget.input,
          existingPlans: _plans,
          fromDate: today,
          newWeatherByDay: weather,
          poiPool: poiPool,
          visitedPoiIds: _visited,
          skippedPoiIds: _skipped,
        );
      } catch (_) {
        newPlans = _plans;
      }

      if (!mounted) return;

      setState(() {
        _plans = newPlans;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Plāns pārrēķināts')),
      );
    } finally {
      if (mounted) setState(() => _replanning = false);
    }
  }

  // ================= UTILS =================

  String _d(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _openInGoogleMaps(List<Poi> stops) async {
    if (stops.length < 2) return;

    final origin = stops.first.location;
    final dest = stops.last.location;

    final waypoints = stops.length > 2
        ? stops
        .sublist(1, stops.length - 1)
        .map((p) => '${p.location.lat},${p.location.lon}')
        .join('|')
        : '';

    final uri = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'origin': '${origin.lat},${origin.lon}',
      'destination': '${dest.lat},${dest.lon}',
      if (waypoints.isNotEmpty) 'waypoints': waypoints,
      'travelmode': 'driving',
    });

    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}
