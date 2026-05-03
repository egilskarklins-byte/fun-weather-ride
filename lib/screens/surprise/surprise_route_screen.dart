import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/geo.dart';
import '../../models/poi.dart';
import 'route_map_screen.dart';

class SurpriseRouteScreen extends StatelessWidget {
  final List<Poi> route;
  final LatLon start;
  final String apiKey;

  const SurpriseRouteScreen({
    super.key,
    required this.route,
    required this.start,
    required this.apiKey,
  });

  Future<void> _openInGoogleMaps(List<Poi> route) async {
    if (route.isEmpty) return;

    final origin = '${start.lat},${start.lon}';
    final destination =
        '${route.last.location.lat},${route.last.location.lon}';

    String waypoints = '';
    if (route.length > 1) {
      final middle = route.sublist(0, route.length - 1);
      waypoints = middle
          .map((p) => '${p.location.lat},${p.location.lon}')
          .join('|');
    }

    final url =
        'https://www.google.com/maps/dir/?api=1'
        '&origin=$origin'
        '&destination=$destination'
        '&travelmode=driving'
        '${waypoints.isNotEmpty ? '&waypoints=$waypoints' : ''}';

    final uri = Uri.parse(url);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Nevar atvērt Google Maps';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ģenerētais maršruts'),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: route.length,
        separatorBuilder: (_, __) => const Divider(),
        itemBuilder: (context, index) {
          final poi = route[index];

          return ListTile(
            leading: CircleAvatar(
              child: Text('${index + 1}'),
            ),
            title: Text(poi.name),
            subtitle: Text(_formatCategory(poi)),
          );
        },
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await _openInGoogleMaps(route);
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$e')),
                    );
                  }
                },
                child: const Text('Atvērt Google Maps'),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RouteMapScreen(
                        route: route,
                        start: start,
                        apiKey: apiKey,
                      ),
                    ),
                  );
                },
                child: const Text('Skatīt kartē'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatCategory(Poi poi) {
  if (poi.categories.contains(PoiCategory.nature)) return 'Daba';
  if (poi.categories.contains(PoiCategory.museum)) return 'Muzejs';
  if (poi.categories.contains(PoiCategory.mustSee)) return 'Must see';
  return 'Cits';
}