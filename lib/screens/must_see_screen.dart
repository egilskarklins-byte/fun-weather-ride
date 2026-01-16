import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/poi.dart';
import '../services/places_service.dart';

class MustSeeScreen extends StatefulWidget {
  final LatLon startPoint;
  final double maxKmPerDay;
  final List<Poi> initialMustSee;
  final void Function(List<Poi>) onDone;

  const MustSeeScreen({
    super.key,
    required this.startPoint,
    required this.maxKmPerDay,
    required this.initialMustSee,
    required this.onDone,
  });

  @override
  State<MustSeeScreen> createState() => _MustSeeScreenState();
}

class _MustSeeScreenState extends State<MustSeeScreen> {
  final _places = PlacesService();
  final _ctrl = TextEditingController();
  Timer? _debounce;

  final List<Poi> _mustSee = [];
  final List<PlaceSuggestion> _suggestions = [];

  bool _loadingSuggest = false;

  @override
  void initState() {
    super.initState();
    _mustSee.addAll(widget.initialMustSee);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  double _deg2rad(double d) => d * math.pi / 180;
  double _distanceKm(LatLon a, LatLon b) {
    const r = 6371.0;
    final dLat = _deg2rad(b.lat - a.lat);
    final dLon = _deg2rad(b.lon - a.lon);
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_deg2rad(a.lat)) *
            math.cos(_deg2rad(b.lat)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return r * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
  }

  void _warnIfTooFar(Poi poi) {
    final km = _distanceKm(widget.startPoint, poi.location) * 2;
    if (km > widget.maxKmPerDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ "${poi.name}" ~${km.round()} km turp/atpakaļ (pārsniedz ${widget.maxKmPerDay.round()} km)',
          ),
        ),
      );
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      if (v.length < 2) return;

      setState(() => _loadingSuggest = true);
      try {
        final res = await _places.autocomplete(input: v, languageCode: 'lv');
        if (!mounted) return;
        setState(() {
          _suggestions
            ..clear()
            ..addAll(res);
        });
      } finally {
        if (mounted) setState(() => _loadingSuggest = false);
      }
    });
  }

  Future<void> _select(PlaceSuggestion s) async {
    final poi = await _places.placeDetailsToPoi(
      placeId: s.placeId,
      languageCode: 'lv',
    );
    if (poi == null) return;

    if (_mustSee.any((p) => p.id == poi.id)) return;

    setState(() {
      _mustSee.add(poi);
      _ctrl.clear();
      _suggestions.clear();
    });

    _warnIfTooFar(poi);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Must-see izvēle')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Meklē vietu...',
              ),
            ),
            if (_suggestions.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: _suggestions.length,
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      title: Text(s.description),
                      onTap: () => _select(s),
                    );
                  },
                ),
              ),
            Wrap(
              spacing: 8,
              children: _mustSee
                  .map((p) => Chip(
                label: Text(p.name),
                onDeleted: () => setState(() => _mustSee.remove(p)),
              ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                widget.onDone(_mustSee);
                Navigator.pop(context);
              },
              child: const Text('Saglabāt must-see'),
            ),
          ],
        ),
      ),
    );
  }
}
