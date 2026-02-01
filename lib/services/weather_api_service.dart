import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/weather.dart';

class WeatherApiService {
  static const _apiKey = String.fromEnvironment('OPENWEATHER_API_KEY');
  const WeatherApiService();

  Future<List<WeatherDay>> getForecastForTrip({
    required double lat,
    required double lon,
    required DateTime startDate,
    required int daysCount,
  }) async {
    // ================= MOCK MODE =================
    if (_apiKey.isEmpty) {
      print('WEATHER API: USING MOCK DATA');

      return List.generate(daysCount, (i) {
        final d = DateTime(startDate.year, startDate.month, startDate.day)
            .add(Duration(days: i));

        switch (i % 5) {
          case 0:
            return WeatherDay(
              date: d,
              tempC: 22,
              windMs: 3,
              rainMm: 0,
              description: 'Saulains (MOCK)',
            );
          case 1:
            return WeatherDay(
              date: d,
              tempC: 14,
              windMs: 6,
              rainMm: 5,
              description: 'Lietus (MOCK)',
            );
          case 2:
            return WeatherDay(
              date: d,
              tempC: 9,
              windMs: 16,
              rainMm: 12,
              description: 'Vētra (MOCK)',
            );
          case 3:
            return WeatherDay(
              date: d,
              tempC: -2,
              windMs: 11,
              rainMm: 1,
              description: 'Auksts + vējš (MOCK)',
            );
          default:
            return WeatherDay(
              date: d,
              tempC: 20,
              windMs: 4,
              rainMm: 0,
              description: 'Ideāls laiks (MOCK)',
            );
        }
      });
    }

    // ================= REAL API =================
    print('WEATHER API: USING REAL OPENWEATHER API');

    final uri = Uri.https('api.openweathermap.org', '/data/2.5/forecast', {
      'lat': '$lat',
      'lon': '$lon',
      'appid': _apiKey,
      'units': 'metric',
      'lang': 'lv',
    });

    final resp = await http.get(uri);
    if (resp.statusCode != 200) {
      throw Exception('OpenWeather HTTP ${resp.statusCode}: ${resp.body}');
    }

    final data = jsonDecode(resp.body) as Map<String, dynamic>;
    final list = (data['list'] as List).cast<Map<String, dynamic>>();

    DateTime dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

    final byDay = <DateTime, _Agg>{};
    for (final item in list) {
      final dt = DateTime.fromMillisecondsSinceEpoch(
        (item['dt'] as int) * 1000,
        isUtc: true,
      ).toLocal();
      final key = dayKey(dt);

      final main = item['main'] as Map<String, dynamic>;
      final temp = (main['temp'] as num).toDouble();

      final wind = ((item['wind']?['speed'] ?? 0) as num).toDouble();
      final rain = ((item['rain']?['3h'] ?? 0) as num).toDouble();

      final weatherArr = (item['weather'] as List).cast<Map<String, dynamic>>();
      final desc = weatherArr.isNotEmpty
          ? (weatherArr.first['description'] as String)
          : '—';

      byDay.putIfAbsent(key, () => _Agg());
      byDay[key]!.add(temp: temp, wind: wind, rain: rain, desc: desc);
    }

    final out = <WeatherDay>[];
    for (int i = 0; i < daysCount; i++) {
      final d = dayKey(startDate.add(Duration(days: i)));
      final agg = byDay[d];
      if (agg == null) {
        out.add(WeatherDay(
          date: d,
          tempC: 8,
          windMs: 5,
          rainMm: 0,
          description: 'Nav datu',
        ));
      } else {
        out.add(WeatherDay(
          date: d,
          tempC: agg.avgTemp,
          windMs: agg.maxWind,
          rainMm: agg.sumRain,
          description: agg.topDesc,
        ));
      }
    }

    return out;
  }
}

class _Agg {
  double _tempSum = 0;
  int _n = 0;
  double maxWind = 0;
  double sumRain = 0;
  final Map<String, int> _descFreq = {};

  void add({
    required double temp,
    required double wind,
    required double rain,
    required String desc,
  }) {
    _tempSum += temp;
    _n++;
    if (wind > maxWind) maxWind = wind;
    sumRain += rain;
    _descFreq[desc] = (_descFreq[desc] ?? 0) + 1;
  }

  double get avgTemp => _n == 0 ? 0 : _tempSum / _n;

  String get topDesc {
    if (_descFreq.isEmpty) return '—';
    return _descFreq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }
}
