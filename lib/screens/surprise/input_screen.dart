import 'package:flutter/material.dart';

import '../../models/geo.dart';
import '../../services/places_service.dart';
import '../../services/surprise_poi_service.dart';
import 'pick_start_on_map_screen.dart';
import 'surprise_poi_results_screen.dart';

class SurpriseInputScreen extends StatefulWidget {
  const SurpriseInputScreen({super.key});

  @override
  State<SurpriseInputScreen> createState() => _SurpriseInputScreenState();
}

class _SurpriseInputScreenState extends State<SurpriseInputScreen> {
  final PlacesService _places = PlacesService();

  static const LatLon _defaultStart = LatLon(56.9496, 24.1052);
  static const String _defaultStartLabel = 'Rīga';

  LatLon start = _defaultStart;
  String startLabel = _defaultStartLabel;
  double radiusKm = 50;
  bool _loading = false;

  Future<void> _pickStartPoint() async {
    final ctrl = TextEditingController();
    final suggestions = <PlaceSuggestion>[];

    PlaceSuggestion? selectedSuggestion;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> searchSuggestions(String value) async {
              final items = await _places.autocomplete(
                input: value,
                languageCode: 'lv',
              );

              setDialogState(() {
                suggestions
                  ..clear()
                  ..addAll(items);
              });
            }

            return AlertDialog(
              title: const Text('Mainīt sākumpunktu'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Ieraksti pilsētu vai vietu',
                      ),
                      onChanged: (value) {
                        searchSuggestions(value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: suggestions.isEmpty
                          ? const SizedBox.shrink()
                          : ListView.builder(
                        shrinkWrap: true,
                        itemCount: suggestions.length,
                        itemBuilder: (context, index) {
                          final item = suggestions[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(item.description),
                            onTap: () {
                              selectedSuggestion = item;
                              Navigator.pop(dialogContext);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Atcelt'),
                ),
              ],
            );
          },
        );
      },
    );

    if (selectedSuggestion == null) return;

    try {
      final poi = await _places.placeDetailsToPoi(
        placeId: selectedSuggestion!.placeId,
        languageCode: 'lv',
      );

      if (poi == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Neizdevās atrast šo vietu')),
        );
        return;
      }

      setState(() {
        start = poi.location;
        startLabel = poi.name;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kļūda: $e')),
      );
    }
  }

  Future<void> _pickStartOnMap() async {
    final result = await Navigator.push<LatLon>(
      context,
      MaterialPageRoute(
        builder: (_) => PickStartOnMapScreen(initial: start),
      ),
    );

    if (result == null) return;

    try {
      final name = await _places.reverseGeocode(
        location: result,
        languageCode: 'lv',
      );

      if (!mounted) return;

      setState(() {
        start = result;
        startLabel = name ??
            'Kartes punkts (${result.lat.toStringAsFixed(4)}, ${result.lon.toStringAsFixed(4)})';
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        start = result;
        startLabel =
        'Kartes punkts (${result.lat.toStringAsFixed(4)}, ${result.lon.toStringAsFixed(4)})';
      });
    }
  }

  void _setRadius(double value) {
    setState(() {
      radiusKm = value;
    });
  }

  Future<void> _loadPois() async {
    setState(() => _loading = true);

    try {
      final pois = await SurprisePoiService(
        apiKey: 'AIzaSyApwGhn9nkghaInEmcEL-Vh0RF9wePWZXE',
      ).fetchPoisInRadius(
        center: start,
        radiusKm: radiusKm,
      );

      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => SurprisePoiResultsScreen(
            pois: pois,
            start: start,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kļūda: $e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildQuickRadiusChip(double value) {
    final selected = radiusKm.round() == value.round();

    return ChoiceChip(
      label: Text('${value.toInt()} km'),
      selected: selected,
      onSelected: (_) => _setRadius(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Surprise Ride'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sākumpunkts',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    startLabel,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Lat: ${start.lat.toStringAsFixed(5)}, Lon: ${start.lon.toStringAsFixed(5)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickStartPoint,
                        icon: const Icon(Icons.search),
                        label: const Text('Meklēt sākumpunktu'),
                      ),
                      ElevatedButton.icon(
                        onPressed: _loading ? null : _pickStartOnMap,
                        icon: const Icon(Icons.map),
                        label: const Text('Izvēlēties kartē'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Meklēšanas rādiuss',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      '${radiusKm.toInt()} km',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Slider(
                    value: radiusKm,
                    min: 10,
                    max: 150,
                    divisions: 14,
                    label: '${radiusKm.toInt()} km',
                    onChanged: _loading
                        ? null
                        : (v) {
                      _setRadius(v);
                    },
                  ),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildQuickRadiusChip(20),
                      _buildQuickRadiusChip(50),
                      _buildQuickRadiusChip(100),
                      _buildQuickRadiusChip(150),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Lielākam rādiusam tiek izmantoti vairāki meklēšanas centri, lai rezultāti tiešām mainītos.',
                    style: TextStyle(color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Card(
            elevation: 1,
            color: Colors.blueGrey.withOpacity(0.06),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Kas tiks meklēts',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'App meklēs interesantus POI ap "$startLabel" aptuveni ${radiusKm.toInt()} km rādiusā.',
                    style: const TextStyle(fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Pēc tam varēsi izvēlēties POI un uzģenerēt maršrutu ar atgriešanos sākumpunktā.',
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _loadPois,
              icon: _loading
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
                  : const Icon(Icons.travel_explore),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  _loading ? 'Meklē POI...' : 'Atrast POI',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(
              child: Text(
                'Notiek POI meklēšana. Tas var aizņemt dažas sekundes.',
                style: TextStyle(color: Colors.black54),
              ),
            ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}