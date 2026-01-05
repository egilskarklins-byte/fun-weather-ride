import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// planner imports
import 'core/planner/planner_engine.dart';
import 'core/planner/planner_input.dart';
import 'core/planner/must_see.dart';
import 'core/planner/weather_day.dart';

void main() {
  runApp(const FunWeatherRideApp());
}

class FunWeatherRideApp extends StatelessWidget {
  const FunWeatherRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'FunWeather Ride',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const InputScreen(),
    );
  }
}

/// =======================
/// INPUT SCREEN
/// =======================
class InputScreen extends StatefulWidget {
  const InputScreen({super.key});

  @override
  State<InputScreen> createState() => _InputScreenState();
}

class _InputScreenState extends State<InputScreen> {
  int days = 3;
  int maxHours = 6;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trip setup')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('Days'),
              Slider(
                value: days.toDouble(),
                min: 1,
                max: 7,
                divisions: 6,
                label: '$days',
                onChanged: (v) => setState(() => days = v.round()),
              ),
              const Text('Max hours per day'),
              Slider(
                value: maxHours.toDouble(),
                min: 2,
                max: 10,
                divisions: 8,
                label: '$maxHours',
                onChanged: (v) => setState(() => maxHours = v.round()),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            PlannerScreen(days: days, maxHours: maxHours),
                      ),
                    );
                  },
                  child: const Text('Generate plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// =======================
/// PLANNER SCREEN
/// =======================
class PlannerScreen extends StatelessWidget {
  final int days;
  final int maxHours;

  const PlannerScreen({
    super.key,
    required this.days,
    required this.maxHours,
  });

  PlannerInput _input() {
    return PlannerInput(
      days: days,
      maxHoursPerDay: maxHours,
      mustSee: [
        MustSee(
          name: 'Old Town',
          hours: 2,
          lat: 56.9496,
          lng: 24.1052,
        ),
        MustSee(
          name: 'Museum',
          hours: 3,
          lat: 56.9558,
          lng: 24.1133,
        ),
      ],
      weather: List.generate(
        days,
            (i) => i == 0
            ? WeatherDay.sunny()
            : i == 1
            ? WeatherDay.cloudy()
            : WeatherDay.rainy(),
      ),
      mode: TripMode.singleBase,
      startLocation: 'Riga',
    );
  }

  @override
  Widget build(BuildContext context) {
    final plan = PlannerEngine().plan(_input());

    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: SafeArea(
        child: ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: plan.length,
          itemBuilder: (context, index) {
            final day = plan[index];
            return Card(
              child: ListTile(
                title: Text('Day ${day.dayIndex + 1}'),
                subtitle: Text(day.theme.toString()),
                trailing: const Icon(Icons.map),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MapScreen(day: day),
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

/// =======================
/// MAP SCREEN
/// =======================
class MapScreen extends StatelessWidget {
  final dynamic day;

  const MapScreen({super.key, required this.day});

  Future<void> _openGoogleMaps() async {
    final List<String> points = [];

    for (final m in day.mustSee) {
      points.add('${m.lat},${m.lng}');
    }
    for (final p in day.poi) {
      points.add('${p.lat},${p.lng}');
    }

    if (points.isEmpty) return;

    final uri = Uri.parse(
      'https://www.google.com/maps/dir/${points.join('/')}',
    );

    await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Route')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Route points',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text('Must see'),
              ...day.mustSee
                  .map<Widget>((m) => Text('• ${m.name}'))
                  .toList(),
              const SizedBox(height: 8),
              const Text('Extra places'),
              ...day.poi.map<Widget>((p) => Text('• ${p.name}')).toList(),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.map),
                  label: const Text('Open in Google Maps'),
                  onPressed: _openGoogleMaps,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
