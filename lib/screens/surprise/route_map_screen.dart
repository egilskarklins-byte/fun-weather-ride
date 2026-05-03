import 'package:flutter/material.dart';

import '../../models/geo.dart';
import '../../models/poi.dart';

class RouteMapScreen extends StatelessWidget {
  final List<Poi> route;
  final LatLon start;
  final String apiKey;

  const RouteMapScreen({
    super.key,
    required this.route,
    required this.start,
    required this.apiKey,
  });

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Text(
          'Kartes ekrāns pagaidām ir atslēgts. Maršrutu atveram ārējā Google Maps.',
        ),
      ),
    );
  }
}