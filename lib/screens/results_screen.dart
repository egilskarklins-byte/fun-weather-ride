import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/plan.dart';
import '../models/poi.dart';

class ResultsScreen extends StatelessWidget {
  final List<DayPlan> plans;

  /// optional limits
  final int? maxKmPerDay;

  const ResultsScreen({
    super.key,
    required this.plans,
    this.maxKmPerDay,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ceļojuma plāns')),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: plans.length,
        itemBuilder: (context, i) {
          final p = plans[i];

          final bool overLimit =
              maxKmPerDay != null && p.estKm > maxKmPerDay!;

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
                  const SizedBox(height: 6),

                  Text(p.summary),
                  const SizedBox(height: 6),
                  Text('~${p.estKm} km • ~${p.estHours.toStringAsFixed(1)} h'),

                  if (p.weather != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '☀ ${p.weather!.tempC}°C   💨 ${p.weather!.windMs} m/s   🌧 ${p.weather!.rainMm} mm',
                      style: const TextStyle(fontSize: 13, color: Colors.black54),
                    ),
                  ],

                  if (overLimit) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade300),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.warning_amber_rounded, color: Colors.red),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Šis maršruts pārsniedz iestatīto limitu '
                                  '(${maxKmPerDay} km/dienā), jo must-see vietas '
                                  'atrodas pārāk tālu viena no otras.',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(height: 20),

                  ...p.stops.map((s) => Text('• ${s.name}')).toList(),

                  // =============================
                  // DEBUG OVERLAY
                  // =============================
                  if (p.debugWeatherScore != null ||
                      (p.debugPenalties?.isNotEmpty ?? false) ||
                      (p.debugMoved?.isNotEmpty ?? false)) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'DEBUG',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),

                          if (p.debugWeatherScore != null)
                            Text('Weather score: ${p.debugWeatherScore!.toStringAsFixed(2)}'),

                          if (p.debugMoved != null && p.debugMoved!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text('Moved POI:'),
                            ...p.debugMoved!.map((e) => Text('  → $e')),
                          ],

                          if (p.debugPenalties != null && p.debugPenalties!.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            const Text('Penalties:'),
                            ...p.debugPenalties!.entries.map(
                                  (e) => Text('  ${e.key}: ${e.value.toStringAsFixed(2)}'),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],

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
