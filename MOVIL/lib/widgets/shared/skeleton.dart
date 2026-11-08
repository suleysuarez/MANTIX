import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';

/// Bloque gris que parpadea suave mientras carga. Con «reducir movimiento»
/// activado en el sistema se queda quieto.
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 16, this.radius = AppRadius.sm});

  final double? width;
  final double height;
  final double radius;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool? _animating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animate = !MediaQuery.disableAnimationsOf(context);
    if (animate == _animating) return;
    _animating = animate;
    if (animate) {
      _controller.repeat(reverse: true);
    } else {
      _controller
        ..stop()
        ..value = 0.5;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (_, _) => Opacity(
          opacity: 0.45 + 0.4 * _controller.value,
          child: Container(
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              color: AppColors.grey,
              borderRadius: BorderRadius.circular(widget.radius),
            ),
          ),
        ),
      ),
    );
  }
}

/// Lista de tarjetas en esqueleto, la carga típica de un listado.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.itemCount = 6, this.itemHeight = 72});

  final int itemCount;
  final double itemHeight;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Cargando contenido',
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        padding: AppSpacing.page,
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
        itemBuilder: (_, _) => Skeleton(height: itemHeight, radius: AppRadius.md),
      ),
    );
  }
}
