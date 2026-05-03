import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as lm;

import '../../models/geo.dart';

class PickStartOnMapScreen extends StatefulWidget {
  const PickStartOnMapScreen({
    super.key,
    required this.initial,
  });

  final LatLon initial;

  @override
  State<PickStartOnMapScreen> createState() => _PickStartOnMapScreenState();
}

class _PickStartOnMapScreenState extends State<PickStartOnMapScreen> {
  late final MapController _mapController;
  late lm.LatLng _mapCenter;
  bool _moving = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _mapCenter = lm.LatLng(widget.initial.lat, widget.initial.lon);
  }

  void _confirmSelection() {
    Navigator.pop(
      context,
      LatLon(_mapCenter.latitude, _mapCenter.longitude),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Izvēlies sākumpunktu kartē'),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _mapCenter,
              initialZoom: 12,
              onPositionChanged: (position, hasGesture) {
                final center = position.center;
                if (center != null) {
                  _mapCenter = center;
                }
              },
              onMapEvent: (event) {
                if (event is MapEventMoveStart) {
                  if (!_moving) {
                    setState(() {
                      _moving = true;
                    });
                  }
                }

                if (event is MapEventMoveEnd || event is MapEventFlingAnimationEnd) {
                  if (_moving) {
                    setState(() {
                      _moving = false;
                    });
                  }
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.fun_weather_ride',
              ),
            ],
          ),
          IgnorePointer(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_pin,
                    size: 52,
                    color: _moving ? Colors.redAccent : Colors.red,
                  ),
                  const SizedBox(height: 28),
                ],
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Card(
              elevation: 3,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pārbīdi karti, lai sarkanais pin būtu virs vēlamā sākumpunkta.',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Centrs: ${_mapCenter.latitude.toStringAsFixed(5)}, ${_mapCenter.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: ElevatedButton.icon(
              onPressed: _confirmSelection,
              icon: const Icon(Icons.check_circle_outline),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Izvēlēties šo punktu'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}