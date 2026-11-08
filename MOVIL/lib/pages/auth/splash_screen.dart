import 'package:flutter/material.dart';

/// Se muestra mientras se resuelve la sesión.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(semanticsLabel: 'Cargando'),
      ),
    );
  }
}
