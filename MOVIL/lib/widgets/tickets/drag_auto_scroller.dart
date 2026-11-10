import 'dart:async';

import 'package:flutter/widgets.dart';

/// Desplaza una lista cuando se arrastra una tarjeta cerca de su borde superior o inferior,
/// para poder llegar a un estado que está fuera de la pantalla.
class DragAutoScroller {
  DragAutoScroller({required this.controller, this.edge = 90, this.step = 14});

  final ScrollController controller;

  /// Franja (en píxeles) junto a cada borde donde empieza el desplazamiento.
  final double edge;

  /// Píxeles por tic (cada 16 ms) en el borde mismo.
  final double step;

  Timer? _timer;
  double _speed = 0;

  /// Velocidad con signo para un dedo a [position] dentro de [top]–[bottom]: negativa arriba,
  /// positiva abajo y cero fuera de las franjas.
  double speedFor(double position, double top, double bottom) {
    if (position < top + edge) return -step * ((top + edge - position) / edge).clamp(0.0, 1.0);
    if (position > bottom - edge) return step * ((position - (bottom - edge)) / edge).clamp(0.0, 1.0);
    return 0;
  }

  /// Llamar en cada movimiento del arrastre con la posición vertical global del dedo y los
  /// límites verticales globales de la zona que se desplaza.
  void update(double position, double top, double bottom) {
    _speed = speedFor(position, top, bottom);
    if (_speed == 0) {
      _stopTimer();
      return;
    }
    _timer ??= Timer.periodic(const Duration(milliseconds: 16), (_) => _tick());
  }

  void _tick() {
    if (!controller.hasClients || _speed == 0) {
      _stopTimer();
      return;
    }
    final position = controller.position;
    final target = (position.pixels + _speed).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target == position.pixels) return;
    controller.jumpTo(target);
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Al soltar o cancelar el arrastre.
  void stop() {
    _speed = 0;
    _stopTimer();
  }
}
