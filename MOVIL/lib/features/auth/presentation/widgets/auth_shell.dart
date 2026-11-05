import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';

class AuthShell extends StatelessWidget {
  const AuthShell({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      backgroundColor: AuthTokens.bgDeep,
      resizeToAvoidBottomInset: false, // el fondo no se mueve con el teclado
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Imagen única (fondo + logo), fija.
          Image.asset(
            'assets/images/login.webp',
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            errorBuilder: (_, _, _) => const Center(
              child: Text(
                'MANTIX',
                style: TextStyle(
                  color: AuthTokens.textPrimary,
                  fontSize: 36,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          // Degradado sutil solo abajo, para legibilidad. No toca el logo.
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.center,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Color(0x99050B1A)],
                ),
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: EdgeInsets.fromLTRB(
                24,
                size.height * AuthTokens.logoZone, // deja libre el logo
                24,
                20 + keyboard,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: AuthTokens.maxCardWidth,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}