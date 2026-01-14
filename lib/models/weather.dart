class WeatherDay {
  final DateTime date;
  final double tempC;
  final double windMs;
  final double rainMm;
  final String description;

  const WeatherDay({
    required this.date,
    required this.tempC,
    required this.windMs,
    required this.rainMm,
    required this.description,
  });

  bool get isRainy => rainMm >= 1.0;
  bool get isStormy => windMs >= 12.0;
  bool get isCold => tempC <= 2.0;
}
