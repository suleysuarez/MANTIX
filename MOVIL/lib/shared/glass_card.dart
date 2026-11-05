import 'dart:ui';
import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(AuthTokens.cardRadius));
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                AuthTokens.glassFillTop.withValues(alpha: 0.45),
                AuthTokens.glassFillBottom.withValues(alpha: 0.35),
              ],
            ),
            border: Border.all(
              color: AuthTokens.glassBorder.withValues(alpha: 0.35),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}