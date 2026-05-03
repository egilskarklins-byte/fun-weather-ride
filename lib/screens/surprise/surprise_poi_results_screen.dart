import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/geo.dart';
import '../../models/poi.dart';
import '../../services/simple_route_builder.dart';

class SurprisePoiResultsScreen extends StatefulWidget {
  final List<Poi> pois;
  final LatLon start;

  const SurprisePoiResultsScreen({
    super.key,
    required this.pois,
    required this.start,
  });

  @override
  State<SurprisePoiResultsScreen> createState() =>
      _SurprisePoiResultsScreenState();
}

class _SurprisePoiResultsScreenState extends State<SurprisePoiResultsScreen> {
  final Map<String, double> _selectedDurations = {};

  double get totalHours {
    return _selectedDurations.values.fold(0.0, (a, b) => a + b);
  }

  Future<void> _selectDuration(Poi poi) async {
    final result = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(poi.name),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _optionButton('Uzmest aci (~15 min)', 0.25),
              _optionButton('Ātri izskriet (~45 min)', 0.75),
              _optionButton('Iepazīt nopietni (~90 min)', 1.5),
            ],
          ),
        );
      },
    );

    if (result != null) {
      setState(() {
        _selectedDurations[poi.id] = result;
      });
    }
  }

  Widget _optionButton(String text, double value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: ElevatedButton(
        onPressed: () {
          Navigator.pop(context, value);
        },
        child: Text(text),
      ),
    );
  }

  Future<void> _generateRoute() async {
    final selectedPois = widget.pois
        .where((p) => _selectedDurations.containsKey(p.id))
        .toList();

    if (selectedPois.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vispirms izvēlies vismaz vienu POI'),
        ),
      );
      return;
    }

    final ordered = SimpleRouteBuilder.buildRoute(
      start: widget.start,
      pois: selectedPois,
      returnToStart: true,
    );

    final url = _buildGoogleMapsDirectionsUrl(
      start: widget.start,
      route: ordered,
    );

    final uri = Uri.parse(url);

    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Neizdevās atvērt Google Maps'),
        ),
      );
    }
  }

  String _buildGoogleMapsDirectionsUrl({
    required LatLon start,
    required List<Poi> route,
  }) {
    final waypoints = <String>[];

    for (final poi in route) {
      final isReturnToStart = poi.location.lat == start.lat &&
          poi.location.lon == start.lon;

      if (isReturnToStart) {
        continue;
      }

      waypoints.add('${poi.location.lat},${poi.location.lon}');
    }

    final queryParameters = <String, String>{
      'api': '1',
      'origin': '${start.lat},${start.lon}',
      'destination': '${start.lat},${start.lon}',
      'travelmode': 'driving',
    };

    if (waypoints.isNotEmpty) {
      queryParameters['waypoints'] = waypoints.join('|');
    }

    return Uri.https(
      'www.google.com',
      '/maps/dir/',
      queryParameters,
    ).toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Izvēlies POI'),
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.green.withValues(alpha: 0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Kopējais laiks:'),
                Text('${totalHours.toStringAsFixed(1)} h'),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 12),
              itemCount: widget.pois.length,
              itemBuilder: (context, index) {
                final poi = widget.pois[index];
                final isSelected = _selectedDurations.containsKey(poi.id);

                return ListTile(
                  title: Text(poi.name),
                  subtitle: Text(formatCategory(poi)),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (val) async {
                      if (val == true) {
                        await _selectDuration(poi);
                      } else {
                        setState(() {
                          _selectedDurations.remove(poi.id);
                        });
                      }
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _generateRoute,
            child: const Text('Atvērt Google Maps'),
          ),
        ),
      ),
    );
  }
}

String formatCategory(Poi poi) {
  if (poi.categories.contains(PoiCategory.nature)) return 'Daba';
  if (poi.categories.contains(PoiCategory.museum)) return 'Muzejs';
  if (poi.categories.contains(PoiCategory.mustSee)) return 'Must see';
  return 'Cits';
}