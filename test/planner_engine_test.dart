import 'package:flutter_test/flutter_test.dart';
import 'package:fun_weather_ride/core/planner/planner_engine.dart';
import 'package:fun_weather_ride/core/planner/planner_input.dart';
import 'package:fun_weather_ride/core/planner/must_see.dart';
import 'package:fun_weather_ride/core/planner/weather_day.dart';

void main() {
  test('planner distributes must-see items across days', () {
    final engine = PlannerEngine();

    final input = PlannerInput(
      days: 2,
      maxHoursPerDay: 8,
      mustSee: [
        MustSee(name: 'A', hours: 2, lat: 56.95, lng: 24.10),
        MustSee(name: 'B', hours: 2, lat: 56.96, lng: 24.11),
        MustSee(name: 'C', hours: 2, lat: 56.97, lng: 24.12),
      ],
      weather: [
        WeatherDay.sunny(),
        WeatherDay.cloudy(),
      ],
      mode: TripMode.singleBase,
      startLocation: 'Riga',
    );

    final plan = engine.plan(input);

    expect(plan.length, 2);
    expect(plan[0].mustSee.length, 2);
    expect(plan[1].mustSee.length, 1);
  });
}
