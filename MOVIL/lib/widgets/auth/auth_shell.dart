import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/app_colors.dart';

class AuthShell extends StatefulWidget {
  const AuthShell({super.key, required this.child});
  final Widget child;

  @override
  State<AuthShell> createState() => _AuthShellState();
}

class _AuthShellState extends State<AuthShell> {
  late final Future<Size> _backgroundSize = _readBackgroundSize();

  Future<Size> _readBackgroundSize() async {
    final data = await rootBundle.load('assets/images/login.webp');
    final codec = await ui.instantiateImageCodec(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    try {
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      return size;
    } finally {
      codec.dispose();
    }
  }

  /// Y (desde el borde superior de la pantalla) donde empieza la zona de la tarjeta:
  /// justo debajo del logo y nunca por encima del área segura.
  double _contentTop({
    required Size screenSize,
    required Size imageSize,
    required double safeTop,
  }) {
    // BoxFit.cover uses the larger axis ratio. With topCenter alignment there
    // is no vertical offset, so this is the logo's rendered bottom edge.
    final scale = math.max(
      screenSize.width / imageSize.width,
      screenSize.height / imageSize.height,
    );
    final logoBottom =
        imageSize.height * scale * AuthTokens.logoBottomFraction;
    return math.max(safeTop, logoBottom + AuthTokens.logoClearance);
  }

  double _fallbackContentTop({
    required Size screenSize,
    required double safeTop,
  }) {
    // Keep the scroll view in the tree while the image dimensions are loading.
    // This estimate leaves room for the logo and is replaced by the exact
    // image-based position as soon as decoding completes.
    return math.max(
      safeTop,
      screenSize.height * AuthTokens.logoBottomFraction +
          AuthTokens.logoClearance,
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      backgroundColor: AuthTokens.bgDeep,
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
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
          FutureBuilder<Size>(
            future: _backgroundSize,
            builder: (context, snapshot) {
              final top = snapshot.hasData
                  ? _contentTop(
                      screenSize: screenSize,
                      imageSize: snapshot.data!,
                      safeTop: safeTop,
                    )
                  : _fallbackContentTop(
                      screenSize: screenSize,
                      safeTop: safeTop,
                    );

              // La zona desplazable empieza bajo el logo y se recorta ahí: aunque el
              // contenido sea más alto (teclado abierto, fuente grande), nunca sube
              // por encima del borde inferior del logo. Si cabe, no se mueve.
              return Positioned(
                left: 0,
                right: 0,
                top: top,
                bottom: 0,
                child: ClipRect(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(
                      24,
                      0,
                      24,
                      20 + safeBottom + keyboard,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: AuthTokens.maxCardWidth,
                        ),
                        child: widget.child,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
