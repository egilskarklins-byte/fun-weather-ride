import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/geo.dart';
import '../models/poi.dart';
import '../models/trip.dart';
import '../models/project.dart';

import '../planner/planner_engine.dart';
import '../services/weather_api_service.dart';
import '../services/places_service.dart';
import '../services/poi_catalog_service.dart';
import '../services/project_storage_service.dart';

import 'results_screen.dart';
import '../state/trip_controller.dart';

class PlannerInputScreen extends StatefulWidget {
  const PlannerInputScreen({super.key});

  @override
  State<PlannerInputScreen> createState() => _PlannerInputScreenState();
}

class _PlannerInputScreenState extends State<PlannerInputScreen> {
  late final TripController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TripController();
  }

  final PlannerEngine _engine = PlannerEngine();
  final WeatherApiService _weatherApi = const WeatherApiService();
  final PlacesService _places = PlacesService();
  final PoiCatalogService _poiCatalog = PoiCatalogService();
  final ProjectStorageService _projectStorage = ProjectStorageService();

  bool _loading = false;

  // -------------------- Start point autocomplete --------------------
  final TextEditingController _startCtrl = TextEditingController();
  final List<PlaceSuggestion> _startSuggestions = [];
  Timer? _startDebounce;
  bool _loadingStartSuggest = false;

  String get _activeStartLabel =>
      _startCtrl.text.trim().isEmpty ? _controller.regionText : _startCtrl.text.trim();

  // -------------------- Must-see --------------------
  final TextEditingController _mustSeeCtrl = TextEditingController();

  // Must-see autocomplete
  final List<PlaceSuggestion> _suggestions = [];
  Timer? _debounce;
  bool _loadingSuggest = false;
  bool _addingMustSee = false;

  // Current loaded project (optional)
  String? _currentProjectId;
  String? _currentProjectName;

  @override
  void dispose() {
    _debounce?.cancel();
    _startDebounce?.cancel();
    _mustSeeCtrl.dispose();
    _startCtrl.dispose();
    super.dispose();
  }

  // -------------------- Distance helpers + warning --------------------
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
    // limits rēķinam "turp + atpakaļ" no controller startPoint
    final kmRoundTrip = (_distanceKm(_controller.startPoint, poi.location) * 2);

    if (kmRoundTrip > _controller.maxKmPerDay) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '⚠️ "${poi.name}" ir ~${kmRoundTrip.round()} km turp/atpakaļ no sākuma punkta — '
                'tas pārsniedz iestatīto ${_controller.maxKmPerDay.round()} km/dienā.',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  // -------------------- Dates --------------------
  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Izvēlies ceļojuma datumus',
    );

    if (picked != null) {
      _controller.setDateRange(picked.start, picked.end);
    }
  }

  String _formatDateRange() {
    final start = _controller.startDate;
    final end = _controller.endDate;

    if (start == null || end == null) return 'Izvēlies datumus';

    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(start.day)}.${two(start.month)}.${start.year} – '
        '${two(end.day)}.${two(end.month)}.${end.year}';
  }

  // -------------------- Start point autocomplete --------------------
  void _onStartChanged(String v) {
    _startDebounce?.cancel();
    _startDebounce = Timer(const Duration(milliseconds: 250), () async {
      final q = v.trim();
      if (q.length < 2) {
        if (!mounted) return;
        setState(() {
          _startSuggestions.clear();
          _loadingStartSuggest = false;
        });
        return;
      }

      if (mounted) setState(() => _loadingStartSuggest = true);

      try {
        final res = await _places.autocomplete(
          input: q,
          languageCode: 'lv',
        );

        if (!mounted) return;
        setState(() {
          _startSuggestions
            ..clear()
            ..addAll(res);
        });
      } finally {
        if (mounted) setState(() => _loadingStartSuggest = false);
      }
    });
  }

  Future<void> _selectStart(PlaceSuggestion s) async {
    // paņemam koordinātes no place details
    final poi = await _places.placeDetailsToPoi(
      placeId: s.placeId,
      languageCode: 'lv',
    );

    if (poi == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Neizdevās ielādēt sākumpunkta koordinātes')),
      );
      return;
    }

    // controller kļūst par patiesības avotu
    _controller.setStartPoint(poi.location, s.description);

    if (!mounted) return;
    setState(() {
      _startCtrl.text = s.description;
      _startSuggestions.clear();
    });

    if (_controller.mustSee.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sākumpunkts uzstādīts: ${poi.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _resetStartToDefault() {
    _controller.resetStartPoint();

    setState(() {
      _startCtrl.clear();
      _startSuggestions.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sākumpunkts atjaunots uz Olaine')),
    );
  }

  // -------------------- Must-see autocomplete --------------------
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

      if (_controller.mustSee.any((p) => p.id == poi.id)) {
        if (!mounted) return;
        setState(() {
          _mustSeeCtrl.clear();
          _suggestions.clear();
        });
        return;
      }

      _controller.addMustSee(poi);

      if (!mounted) return;
      setState(() {
        _mustSeeCtrl.clear();
        _suggestions.clear();
      });

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
          const SnackBar(
            content: Text('Vieta netika atrasta (mēģini izvēlēties no saraksta)'),
          ),
        );
        return;
      }

      if (_controller.mustSee.any((p) => p.id == poi.id)) {
        if (!mounted) return;
        setState(() {
          _mustSeeCtrl.clear();
          _suggestions.clear();
        });
        return;
      }

      _controller.addMustSee(poi);

      if (!mounted) return;
      setState(() {
        _mustSeeCtrl.clear();
        _suggestions.clear();
      });

      _warnIfTooFar(poi);
    } finally {
      if (mounted) setState(() => _addingMustSee = false);
    }
  }

  Widget _section(String t) => Text(
    t,
    style: Theme.of(context)
        .textTheme
        .titleMedium
        ?.copyWith(fontWeight: FontWeight.bold),
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
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Atcelt'),
            ),
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
    if (_controller.mustSee.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nav must-see ko saglabāt')),
      );
      return;
    }

    final name = await _askProjectName(initial: _currentProjectName);
    if (name == null || name.isEmpty) return;

    final id =
        _currentProjectId ?? DateTime.now().millisecondsSinceEpoch.toString();

    final p = _controller.toProject(id: id, name: name);
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
            ),
          ],
        );
      },
    );

    if (selected == null) return;

    _controller.loadFromProject(selected);

    if (!mounted) return;
    setState(() {
      _currentProjectId = selected.id;
      _currentProjectName = selected.name;

      _startCtrl.text = _controller.regionText;

      _mustSeeCtrl.clear();
      _suggestions.clear();
      _startSuggestions.clear();
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
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Atcelt'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Dzēst'),
          ),
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
    _controller.resetAll();

    setState(() {
      _currentProjectId = null;
      _currentProjectName = null;

      _mustSeeCtrl.clear();
      _suggestions.clear();

      _startCtrl.clear();
      _startSuggestions.clear();
    });
  }

  Future<void> _showOptimalDaysDialog() async {
    if (_controller.mustSee.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pievieno vismaz 2 must-see punktus')),
      );
      return;
    }

    final weather = await _weatherApi.getForecastForTrip(
      lat: _controller.startPoint.lat,
      lon: _controller.startPoint.lon,
      startDate: _controller.startDate!,
      daysCount: 30, // dodam rezervi, lai engine var meklēt
    );

    final input = TripInput(
      startDate: _controller.startDate!,
      endDate: _controller.endDate!,
      daysCount: _controller.daysCount,
      mode: _controller.mode,
      transport: _controller.transport,
      fitness: _controller.fitness,
      party: _controller.party,
      regionText: _controller.regionText,
      startPoint: _controller.startPoint,
      returnToStart: _controller.returnToStart,
      includeFillers: _controller.includeFillers,
      maxKmPerDay: _controller.maxKmPerDay.round(),
      mustSee: List<Poi>.from(_controller.mustSee),
    );

    final days = _engine.suggestDaysCountConsideringWeather(
      input: input,
      weatherByDay: weather,
    );


    if (!mounted) return;
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
            child: const Text('Atcelt'),
          ),
          ElevatedButton(
            onPressed: () {
              final start = _controller.startDate!;
              final newEnd = start.add(Duration(days: days - 1));
              _controller.setDateRange(start, newEnd);
              // <<< ŠIS IR SVARĪGĀKAIS
              Navigator.pop(context);

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Dienu skaits uzstādīts: $days')),
              );
            },
            child: const Text('Lietot šo ilgumu'),
          ),
        ],

      ),
    );
  }

  // ====================== Layout helper sections ======================

  Widget _buildDatesSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('📅 Datumi'),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range),
              label: Text(_formatDateRange()),
            ),
            const SizedBox(height: 8),
            Text('Dienu skaits: ${_controller.daysCount}'),
          ],
        ),
      ),
    );
  }

  Widget _buildStartPointSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _section('📍 Sākumpunkts'),
            const SizedBox(height: 8),
            TextField(
              controller: _startCtrl,
              onChanged: _onStartChanged,
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                hintText: 'Ievadi pilsētu vai vietu, no kuras sāksi',
                suffixIcon: _loadingStartSuggest
                    ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
                    : IconButton(
                  tooltip: 'Atjaunot uz Olaine',
                  onPressed: _resetStartToDefault,
                  icon: const Icon(Icons.refresh),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Aktīvais sākums: $_activeStartLabel',
              style: const TextStyle(color: Colors.black54),
            ),
            if (_startSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.black12),
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: _startSuggestions.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final s = _startSuggestions[i];
                    return ListTile(
                      dense: true,
                      title: Text(s.description),
                      onTap: () => _selectStart(s),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ====================== END layout helper sections ======================

  @override
  Widget build(BuildContext context) {
    // (brīdinājums: print productionā nav ideāli, bet atstājam kā tev bija)
    // ignore: avoid_print
    print("BUILD PlannerInputScreen");

    final projectLabel = _currentProjectName == null
        ? 'Nav ielādēts projekts'
        : 'Projekts: $_currentProjectName';

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
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
                Text(projectLabel,
                    style: const TextStyle(color: Colors.black54)),
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
                      onPressed: _currentProjectId == null
                          ? null
                          : _deleteCurrentProject,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),

                _buildDatesSection(),

                const SizedBox(height: 16),
                _section('Ceļojuma režīms'),
                DropdownButtonFormField<TripMode>(
                  value: _controller.mode,
                  items: const [
                    DropdownMenuItem(
                        value: TripMode.singleBase, child: Text('Single base')),
                    DropdownMenuItem(
                        value: TripMode.movingTour, child: Text('Moving tour')),
                  ],
                  onChanged: (v) =>
                      _controller.setMode(v ?? TripMode.singleBase),
                ),

                const SizedBox(height: 16),
                _section('Profils'),
                DropdownButtonFormField<FitnessLevel>(
                  value: _controller.fitness,
                  items: const [
                    DropdownMenuItem(value: FitnessLevel.low, child: Text('Zema')),
                    DropdownMenuItem(
                        value: FitnessLevel.medium, child: Text('Vidēja')),
                    DropdownMenuItem(
                        value: FitnessLevel.high, child: Text('Augsta')),
                  ],
                  onChanged: (v) =>
                      _controller.setFitness(v ?? FitnessLevel.medium),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<TravelParty>(
                  value: _controller.party,
                  items: const [
                    DropdownMenuItem(
                        value: TravelParty.solo, child: Text('Solo')),
                    DropdownMenuItem(
                        value: TravelParty.couple, child: Text('Pāris')),
                    DropdownMenuItem(
                        value: TravelParty.family, child: Text('Ģimene')),
                  ],
                  onChanged: (v) =>
                      _controller.setParty(v ?? TravelParty.solo),
                ),

                const SizedBox(height: 16),
                _section('Transports un km'),
                DropdownButtonFormField<TransportMode>(
                  value: _controller.transport,
                  items: const [
                    DropdownMenuItem(value: TransportMode.car, child: Text('Auto')),
                    DropdownMenuItem(value: TransportMode.bike, child: Text('Velo')),
                  ],
                  onChanged: (v) =>
                      _controller.setTransport(v ?? TransportMode.car),
                ),
                const SizedBox(height: 8),
                Text('Max km dienā: ${_controller.maxKmPerDay.round()}'),
                Slider(
                  min: 30,
                  max: _controller.transport == TransportMode.bike ? 150 : 500,
                  divisions: 20,
                  value: _controller.maxKmPerDay.clamp(
                    30,
                    _controller.transport == TransportMode.bike ? 150 : 500,
                  ),
                  onChanged: (v) => _controller.setMaxKmPerDay(v),
                ),
                const SizedBox(height: 8),

                SwitchListTile(
                  title: const Text('Pēdējā dienā atgriezties sākumpunktā'),
                  subtitle: const Text('Attiecas uz Moving tour režīmu'),
                  value: _controller.returnToStart,
                  onChanged: (v) => _controller.setReturnToStart(v),
                ),

                SwitchListTile(
                  title: const Text('Aizpildīt dienas ar papildus POI'),
                  subtitle: const Text('Pievieno tuvus objektus, ja paliek brīvs laiks'),
                  value: _controller.includeFillers,
                  onChanged: (v) => _controller.setIncludeFillers(v),
                ),

                SwitchListTile(
                  title: const Text('Ignorēt laikapstākļu ietekmi (test mode)'),
                  subtitle: const Text('Must-see sadale tikai pēc km/attāluma'),
                  value: _controller.ignoreWeatherImpact,
                  onChanged: (v) => _controller.setIgnoreWeather(v),
                ),


                _buildStartPointSection(),

                const SizedBox(height: 16),
                _section('Must-see (visā pasaulē)'),
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
                        : (_addingMustSee
                        ? const Icon(Icons.hourglass_top)
                        : const Icon(Icons.search)),
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
                  children: _controller.mustSee
                      .map(
                        (p) => Chip(
                      label: Text(p.name),
                      onDeleted: () => _controller.removeMustSee(p),
                    ),
                  )
                      .toList(),
                ),

                const SizedBox(height: 12),

                OutlinedButton.icon(
                  onPressed: _controller.mustSee.isEmpty ? null : _showOptimalDaysDialog,
                  icon: const Icon(Icons.auto_graph),
                  label: const Text('Aprēķināt optimālo dienu skaitu'),
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _generate,
                    child: _loading
                        ? const CircularProgressIndicator()
                        : const Text('Ģenerēt plānu'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _generate() async {
    final start = _controller.startDate;
    final end = _controller.endDate;

    if (start == null || end == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Izvēlies datumus')),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final input = TripInput(
        startDate: start,
        endDate: end,
        daysCount: _controller.daysCount,
        mode: _controller.mode,
        transport: _controller.transport,
        fitness: _controller.fitness,
        party: _controller.party,
        regionText: _controller.regionText,
        startPoint: _controller.startPoint,

        returnToStart: _controller.returnToStart,
      // pagaidām uzliec true testam
        includeFillers: _controller.includeFillers,

        maxKmPerDay: _controller.maxKmPerDay.round(),
        mustSee: List<Poi>.from(_controller.mustSee),
      );


      final weather = await _weatherApi.getForecastForTrip(
        lat: input.startPoint.lat,
        lon: input.startPoint.lon,
        startDate: input.startDate,
        daysCount: input.daysCount,
      );

      final poiPool = _poiCatalog.catalogForRegion(_controller.regionText);

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
            input: input,
            maxKmPerDay: input.maxKmPerDay,
          ),

        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
