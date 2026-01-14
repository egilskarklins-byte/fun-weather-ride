import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/poi.dart';
import '../models/trip.dart';
import '../models/plan.dart';
import '../models/project.dart';

import '../planner/planner_engine.dart';
import '../services/weather_api_service.dart';
import '../services/places_service.dart';
import '../services/poi_catalog_service.dart';
import '../services/project_storage_service.dart';
import 'results_screen.dart';

class PlannerInputScreen extends StatefulWidget {
  const PlannerInputScreen({super.key});

  @override
  State<PlannerInputScreen> createState() => _PlannerInputScreenState();
}

class _PlannerInputScreenState extends State<PlannerInputScreen> {
  DateTime? _start;
  DateTime? _end;

  TripMode _mode = TripMode.singleBase;
  TransportMode _transport = TransportMode.car;
  FitnessLevel _fitness = FitnessLevel.medium;
  TravelParty _party = TravelParty.solo;

  String _regionText = 'Olaine, Latvija';
  LatLon _startPoint = const LatLon(56.7934, 23.9358);


  double _maxKmPerDay = 180;

  final _engine = PlannerEngine();

  final _weatherApi = const WeatherApiService();
  final _places = PlacesService();
  final _poiCatalog = PoiCatalogService();

  final _projectStorage = ProjectStorageService();

  bool _loading = false;

  // Must-see
  final List<Poi> _mustSee = [];
  final TextEditingController _mustSeeCtrl = TextEditingController();

  // Autocomplete UI state
  final List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _loadingSuggest = false;
  bool _addingMustSee = false;

  // Current loaded project (optional)
  String? _currentProjectId;
  String? _currentProjectName;

  int get _daysCount {
    if (_start == null || _end == null) return 3;
    return _end!.difference(_start!).inDays + 1;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _mustSeeCtrl.dispose();
    super.dispose();
  }

  // -------------------- NEW: distance + warning --------------------
  double _distanceKm(LatLon a, LatLon b) {
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

  void _warnIfTooFar(Poi poi) {
    // limitu rēķinam "turp + atpakaļ" no startPoint (bāzes)
    final kmRoundTrip = (_distanceKm(_startPoint, poi.location) * 2);

    if (kmRoundTrip > _maxKmPerDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ "${poi.name}" ir ~${kmRoundTrip.round()} km turp/atpakaļ no sākuma punkta — tas pārsniedz iestatīto ${_maxKmPerDay.round()} km/dienā.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
  // ------------------ END NEW ------------------

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Izvēlies ceļojuma datumus',
    );
    if (picked != null) {
      setState(() {
        _start = picked.start;
        _end = picked.end;
      });
    }
  }

  String _formatDateRange() {
    if (_start == null || _end == null) return 'Izvēlies datumus';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(_start!.day)}.${two(_start!.month)}.${_start!.year} – '
        '${two(_end!.day)}.${two(_end!.month)}.${_end!.year}';
  }

  void _onMustSeeChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final q = v.trim();
      if (q.length < 2) {
        if (mounted) setState(() => _suggestions.clear());
        return;
      }

      setState(() => _loadingSuggest = true);
      try {
        final res = await _places.autocomplete(
          input: q,
          languageCode: 'lv',
        );
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

  Future<void> _addSuggestion(PlaceSuggestion s) async {
    setState(() => _addingMustSee = true);
    try {
      final poi = await _places.placeDetailsToPoi(
        placeId: s.placeId,
        languageCode: 'lv',
      );

      if (poi == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Neizdevās ielādēt vietas koordinātes')),
        );
        return;
      }

      if (_mustSee.any((p) => p.id == poi.id)) {
        if (!mounted) return;
        setState(() {
          _mustSeeCtrl.clear();
          _suggestions.clear();
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _mustSee.add(poi);
        _mustSeeCtrl.clear();
        _suggestions.clear();
      });

      // NEW: warning pie pievienošanas
      _warnIfTooFar(poi);
    } finally {
      if (mounted) setState(() => _addingMustSee = false);
    }
  }

  Future<void> _addMustSeeFallbackByText() async {
    final q = _mustSeeCtrl.text.trim();
    if (q.isEmpty) return;

    setState(() => _addingMustSee = true);
    try {
      final poi = await _places.textSearchToPoi(query: q, languageCode: 'lv');

      if (poi == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vieta netika atrasta (mēģini izvēlēties no saraksta)')),
        );
        return;
      }

      if (_mustSee.any((p) => p.id == poi.id)) {
        if (!mounted) return;
        setState(() {
          _mustSeeCtrl.clear();
          _suggestions.clear();
        });
        return;
      }

      if (!mounted) return;
      setState(() {
        _mustSee.add(poi);
        _mustSeeCtrl.clear();
        _suggestions.clear();
      });

      // NEW: warning pie pievienošanas
      _warnIfTooFar(poi);
    } finally {
      if (mounted) setState(() => _addingMustSee = false);
    }
  }

  Widget _section(String t) => Text(
    t,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );

  Future<String?> _askProjectName({String? initial}) async {
    return showDialog<String>(
      context: context,
      builder: (c) {
        final ctrl = TextEditingController(text: initial ?? '');
        return AlertDialog(
          title: const Text('Projekta nosaukums'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(
              hintText: 'piem: Latvijas roadtrip / Kuldīga detalizēti',
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c), child: const Text('Atcelt')),
            TextButton(
              onPressed: () => Navigator.pop(c, ctrl.text.trim()),
              child: const Text('Saglabāt'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveProject() async {
    if (_mustSee.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nav must-see ko saglabāt')),
      );
      return;
    }

    final name = await _askProjectName(initial: _currentProjectName);
    if (name == null || name.isEmpty) return;

    final id = _currentProjectId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final p = Project(
      id: id,
      name: name,
      startDate: _start,
      endDate: _end,
      mode: _mode,
      transport: _transport,
      fitness: _fitness,
      party: _party,
      regionText: _regionText,
      startPoint: _startPoint,
      maxKmPerDay: _maxKmPerDay,
      mustSee: List<Poi>.from(_mustSee),
    );

    await _projectStorage.upsert(p);

    if (!mounted) return;
    setState(() {
      _currentProjectId = id;
      _currentProjectName = name;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Projekts saglabāts')),
    );
  }

  Future<void> _loadProject() async {
    final projects = await _projectStorage.load();
    if (projects.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nav saglabātu projektu')),
      );
      return;
    }

    final selected = await showDialog<Project>(
      context: context,
      builder: (c) {
        return SimpleDialog(
          title: const Text('Izvēlies projektu'),
          children: [
            ...projects.map((p) {
              return SimpleDialogOption(
                onPressed: () => Navigator.pop(c, p),
                child: Row(
                  children: [
                    Expanded(child: Text(p.name)),
                    Text(
                      '${p.mustSee.length}',
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Piezīme: lai dzēstu projektu, turpini zemāk ar “Dzēst projektu” (pēc ielādes).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.black54),
              ),
            ),
          ],
        );
      },
    );

    if (selected == null) return;

    if (!mounted) return;
    setState(() {
      _currentProjectId = selected.id;
      _currentProjectName = selected.name;

      _start = selected.startDate;
      _end = selected.endDate;

      _mode = selected.mode;
      _transport = selected.transport;
      _fitness = selected.fitness;
      _party = selected.party;

      _regionText = selected.regionText;
      _startPoint = selected.startPoint;

      _maxKmPerDay = selected.maxKmPerDay;

      _mustSee
        ..clear()
        ..addAll(selected.mustSee);

      _mustSeeCtrl.clear();
      _suggestions.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Ielādēts projekts: ${selected.name}')),
    );
  }

  Future<void> _deleteCurrentProject() async {
    if (_currentProjectId == null) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Dzēst projektu?'),
        content: Text('Dzēst: ${_currentProjectName ?? ''}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Atcelt')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Dzēst')),
        ],
      ),
    );

    if (ok != true) return;

    await _projectStorage.deleteById(_currentProjectId!);

    if (!mounted) return;
    setState(() {
      _currentProjectId = null;
      _currentProjectName = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Projekts dzēsts')),
    );
  }

  void _newProjectClear() {
    setState(() {
      _currentProjectId = null;
      _currentProjectName = null;

      // atstājam region/startPoint kā ir
      _start = null;
      _end = null;
      _mode = TripMode.singleBase;
      _transport = TransportMode.car;
      _fitness = FitnessLevel.medium;
      _party = TravelParty.solo;
      _maxKmPerDay = 180;

      _mustSee.clear();
      _mustSeeCtrl.clear();
      _suggestions.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final projectLabel = _currentProjectName == null ? 'Nav ielādēts projekts' : 'Projekts: $_currentProjectName';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Plānot maršrutu'),
        actions: [
          IconButton(
            tooltip: 'Jauns projekts',
            onPressed: _newProjectClear,
            icon: const Icon(Icons.note_add),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(projectLabel, style: const TextStyle(color: Colors.black54)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saveProject,
                    icon: const Icon(Icons.save),
                    label: const Text('Saglabāt'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loadProject,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Ielādēt'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Dzēst ielādēto projektu',
                  onPressed: _currentProjectId == null ? null : _deleteCurrentProject,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),

            const SizedBox(height: 16),
            _section('Datumi'),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(_formatDateRange()),
            ),
            const SizedBox(height: 8),
            Text('Dienu skaits: $_daysCount'),

            const SizedBox(height: 16),
            _section('Ceļojuma režīms'),
            DropdownButtonFormField<TripMode>(
              initialValue: _mode,
              items: const [
                DropdownMenuItem(value: TripMode.singleBase, child: Text('Single base')),
                DropdownMenuItem(value: TripMode.movingTour, child: Text('Moving tour')),
              ],
              onChanged: (v) => setState(() => _mode = v ?? TripMode.singleBase),
            ),

            const SizedBox(height: 16),
            _section('Profils'),
            DropdownButtonFormField<FitnessLevel>(
              initialValue: _fitness,
              items: const [
                DropdownMenuItem(value: FitnessLevel.low, child: Text('Zema')),
                DropdownMenuItem(value: FitnessLevel.medium, child: Text('Vidēja')),
                DropdownMenuItem(value: FitnessLevel.high, child: Text('Augsta')),
              ],
              onChanged: (v) => setState(() => _fitness = v ?? FitnessLevel.medium),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<TravelParty>(
              initialValue: _party,
              items: const [
                DropdownMenuItem(value: TravelParty.solo, child: Text('Solo')),
                DropdownMenuItem(value: TravelParty.couple, child: Text('Pāris')),
                DropdownMenuItem(value: TravelParty.family, child: Text('Ģimene')),
              ],
              onChanged: (v) => setState(() => _party = v ?? TravelParty.solo),
            ),

            const SizedBox(height: 16),
            _section('Transports un km'),
            DropdownButtonFormField<TransportMode>(
              initialValue: _transport,
              items: const [
                DropdownMenuItem(value: TransportMode.car, child: Text('Auto')),
                DropdownMenuItem(value: TransportMode.bike, child: Text('Velo')),
              ],
              onChanged: (v) => setState(() => _transport = v ?? TransportMode.car),
            ),
            const SizedBox(height: 8),
            Text('Max km dienā: ${_maxKmPerDay.round()}'),
            Slider(
              min: 30,
              max: _transport == TransportMode.bike ? 150 : 500,
              divisions: 20,
              value: _maxKmPerDay.clamp(30, _transport == TransportMode.bike ? 150 : 500),
              onChanged: (v) => setState(() => _maxKmPerDay = v),
            ),

            const SizedBox(height: 16),
            _section ('Must-see (visā pasaulē)'),
            TextField(
              controller: _mustSeeCtrl,
              onChanged: _onMustSeeChanged,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Ieraksti vietas nosaukumu un izvēlies no saraksta',
                suffixIcon: _loadingSuggest
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : (_addingMustSee ? const Icon(Icons.hourglass_top) : const Icon(Icons.search)),
              ),
            ),
            if (_suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                  color: Theme.of(context).cardColor,
                ),
                constraints: const BoxConstraints(maxHeight: 220),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(s.description),
                      onTap: _addingMustSee ? null : () => _addSuggestion(s),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _addingMustSee ? null : _addMustSeeFallbackByText,
              child: const Text('Pievienot must-see'),
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

            OutlinedButton.icon(
              onPressed: _mustSee.isEmpty ? null : _estimateOptimalDays,
              icon: const Icon(Icons.auto_graph),
              label: const Text('Aprēķināt optimālo dienu skaitu'),
            ),

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _generate,
                child: _loading ? const CircularProgressIndicator() : const Text('Ģenerēt plānu'),
              ),
            ),
          ],
        ),
      ),
    );
  }
  void _estimateOptimalDays() {
    if (_mustSee.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pievieno vismaz 2 must-see punktus')),
      );
      return;
    }

    // vienkāršs heuristisks aprēķins (pagaidu MVP algoritms)
    double totalKm = 0;

    for (int i = 1; i < _mustSee.length; i++) {
      totalKm += _distanceKm(
        _mustSee[i - 1].location,
        _mustSee[i].location,
      );
    }

    // pieskaitām arī turp-atpakaļ no starta
    totalKm += _distanceKm(_startPoint, _mustSee.first.location);
    totalKm += _distanceKm(_mustSee.last.location, _startPoint);

    final days = (totalKm / _maxKmPerDay).ceil().clamp(1, 30);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Ieteicamais ceļojuma ilgums'),
        content: Text(
          'Balstoties uz attālumiem starp izvēlētajiem must-see punktiem, '
              'ieteicamais ilgums ir apmēram $days dienas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _generate() async {
    if (_start == null || _end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Izvēlies datumus')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final input = TripInput(
        startDate: _start!,
        endDate: _end!,
        daysCount: _daysCount,
        mode: _mode,
        transport: _transport,
        fitness: _fitness,
        party: _party,
        regionText: _regionText,
        startPoint: _startPoint,
        maxKmPerDay: _maxKmPerDay.round(),
        mustSee: List<Poi>.from(_mustSee),
      );

      final weather = await _weatherApi.getForecastForTrip(
        lat: input.startPoint.lat,
        lon: input.startPoint.lon,
        startDate: input.startDate,
        daysCount: input.daysCount,
      );

      final poiPool = _poiCatalog.catalogForRegion(_regionText);

      final plans = _engine.buildPlan(
        input: input,
        weatherByDay: weather,
        poiPool: poiPool,
      );

      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ResultsScreen(
            plans: plans,
            maxKmPerDay: input.maxKmPerDay,
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
