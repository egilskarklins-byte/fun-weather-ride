enum WeatherType { sunny, cloudy, rainy }

class WeatherDay {
  final WeatherType type;

  const WeatherDay._(this.type);

  factory WeatherDay.sunny() =>
      const WeatherDay._(WeatherType.sunny);

  factory WeatherDay.cloudy() =>
      const WeatherDay._(WeatherType.cloudy);

  factory WeatherDay.rainy() =>
      const WeatherDay._(WeatherType.rainy);
}
