import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const BaronsApp());
}

class BaronsApp extends StatelessWidget {
  const BaronsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Barona audio gids',
      theme: ThemeData(
        primarySwatch: Colors.brown,
      ),
      home: const HomeScreen(),
    );
  }
}