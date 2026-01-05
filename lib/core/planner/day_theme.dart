import 'weather_day.dart';

enum DayTheme {
  nature,
  city,
  indoor,
  free,
}

class DayThemeResolver {
  static DayTheme fromWeather(WeatherDay weather) {
    switch (weather.type) {
      case WeatherType.sunny:
        return DayTheme.nature;
      case WeatherType.cloudy:
        return DayTheme.city;
      case WeatherType.rainy:
        return DayTheme.indoor;
    }
  }
}
