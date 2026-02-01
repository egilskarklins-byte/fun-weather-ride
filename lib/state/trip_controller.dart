import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import '../models/geo.dart';
import '../models/poi.dart';
import '../models/trip.dart';
import '../models/project.dart';

class TripController extends ChangeNotifier {
  TripController();

  // ===================== MUST-SEE =====================
  final List<Poi> _mustSee = [];

  List<Poi> get mustSee => List.unmodifiable(_mustSee);

  void addMustSee(Poi poi) {
    if (_mustSee.any((p) => p.id == poi.id)) return;
    _mustSee.add(poi);
    notifyListeners();
  }

  void removeMustSee(Poi poi) {
    _mustSee.removeWhere((p) => p.id == poi.id);
    notifyListeners();
  }

  void clearMustSee({bool notify = true}) {
    _mustSee.clear();
    if (notify) notifyListeners();
  }

  void setMustSeeAll(Iterable<Poi> pois) {
    _mustSee
      ..clear()
      ..addAll(pois);
    notifyListeners();
  }

  // ===================== DATES =====================
  DateTime? _startDate;
  DateTime? _endDate;

  DateTime? get startDate => _startDate;
  DateTime? get endDate => _endDate;

  void setDateRange(DateTime start, DateTime end) {
    _startDate = start;
    _endDate = end;
    notifyListeners();
  }

  void clearDates({bool notify = true}) {
    _startDate = null;
    _endDate = null;
    if (notify) notifyListeners();
  }

  int get daysCount {
    if (_startDate == null || _endDate == null) return 3;
    return _endDate!.difference(_startDate!).inDays + 1;
  }

  // ===================== PROFILE =====================
  TripMode _mode = TripMode.singleBase;
  TransportMode _transport = TransportMode.car;
  FitnessLevel _fitness = FitnessLevel.medium;
  TravelParty _party = TravelParty.solo;

  TripMode get mode => _mode;
  TransportMode get transport => _transport;
  FitnessLevel get fitness => _fitness;
  TravelParty get party => _party;

  void setMode(TripMode v) {
    if (_mode == v) return;
    _mode = v;
    notifyListeners();
  }

  void setTransport(TransportMode v) {
    if (_transport == v) return;
    _transport = v;
    notifyListeners();
  }

  void setFitness(FitnessLevel v) {
    if (_fitness == v) return;
    _fitness = v;
    notifyListeners();
  }

  void setParty(TravelParty v) {
    if (_party == v) return;
    _party = v;
    notifyListeners();
  }

  void resetProfile({bool notify = true}) {
    _mode = TripMode.singleBase;
    _transport = TransportMode.car;
    _fitness = FitnessLevel.medium;
    _party = TravelParty.solo;
    if (notify) notifyListeners();
  }


  // ===================== KM / RETURN / FILLERS =====================
  double _maxKmPerDay = 0;

  /// Moving tour: pēdējā dienā pievieno atgriešanos startā
  bool _returnToStart = false;

  /// Ja true – engine drīkst pievienot papildus POI
  bool _includeFillers = true;

  double get maxKmPerDay => _maxKmPerDay;
  bool get returnToStart => _returnToStart;
  bool get includeFillers => _includeFillers;


  bool ignoreWeatherImpact = false; // ⭐ ŠEIT PIEVIENO

  void setMaxKmPerDay(double v) {
    if (_maxKmPerDay == v) return;
    _maxKmPerDay = v;
    notifyListeners();
  }

  void setReturnToStart(bool v) {
    if (_returnToStart == v) return;
    _returnToStart = v;
    notifyListeners();
  }

  void setIncludeFillers(bool v) {
    if (_includeFillers == v) return;
    _includeFillers = v;
    notifyListeners();
  }

  void resetTripParams({bool notify = true}) {
    _maxKmPerDay = 0;
    _returnToStart = false;
    _includeFillers = true;
    if (notify) notifyListeners();
  }
  void setIgnoreWeather(bool v) {
    ignoreWeatherImpact = v;
    notifyListeners();
  }

  // ===================== START POINT =====================
  LatLon _startPoint = const LatLon(56.7934, 23.9358);
  String _regionText = 'Olaine, Latvija';

  LatLon get startPoint => _startPoint;
  String get regionText => _regionText;

  void setStartPoint(LatLon point, String label) {
    _startPoint = point;
    _regionText = label;
    notifyListeners();
  }

  void resetStartPoint() {
    _startPoint = const LatLon(56.7934, 23.9358);
    _regionText = 'Olaine, Latvija';
    notifyListeners();
  }

  // ===================== OPTIMAL DAYS =====================
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

  int estimateOptimalDays() {
    if (_mustSee.length < 2) return 1;

    double totalKm = 0;

    for (int i = 1; i < _mustSee.length; i++) {
      totalKm += _distanceKm(
        _mustSee[i - 1].location,
        _mustSee[i].location,
      );
    }

    totalKm += _distanceKm(startPoint, _mustSee.first.location);
    totalKm += _distanceKm(_mustSee.last.location, startPoint);

    return (totalKm / maxKmPerDay).ceil().clamp(1, 30);
  }

  // ===================== PROJECT SUPPORT =====================
  Project toProject({required String id, required String name}) {
    return Project(
      id: id,
      name: name,
      startDate: startDate,
      endDate: endDate,
      mode: mode,
      transport: transport,
      fitness: fitness,
      party: party,
      regionText: regionText,
      startPoint: startPoint,
      maxKmPerDay: maxKmPerDay,
      returnToStart: returnToStart,
      includeFillers: includeFillers,
      mustSee: List<Poi>.from(mustSee),
    );
  }

  void loadFromProject(Project p) {
    _startDate = p.startDate;
    _endDate = p.endDate;

    _mode = p.mode;
    _transport = p.transport;
    _fitness = p.fitness;
    _party = p.party;

    _regionText = p.regionText;
    _startPoint = p.startPoint;

    _maxKmPerDay = p.maxKmPerDay;
    _returnToStart = p.returnToStart;
    _includeFillers = p.includeFillers;

    _mustSee
      ..clear()
      ..addAll(p.mustSee);

    notifyListeners();
  }

  // ===================== FULL RESET =====================
  void resetAll() {
    clearDates(notify: false);
    clearMustSee(notify: false);
    resetProfile(notify: false);
    resetTripParams(notify: false);
    resetStartPoint();
    notifyListeners();
  }
}
