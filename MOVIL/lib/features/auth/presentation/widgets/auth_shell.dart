import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';

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
    return math.max(0, logoBottom + AuthTokens.logoClearance - safeTop);
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final screenSize = MediaQuery.sizeOf(context);
    final safeTop = MediaQuery.paddingOf(context).top;

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
              // Do not flash the card over the logo while decoding dimensions.
              if (!snapshot.hasData && !snapshot.hasError) {
                return const SizedBox.expand();
              }
              final top = snapshot.hasData
                  ? _contentTop(
                      screenSize: screenSize,
                      imageSize: snapshot.data!,
                      safeTop: safeTop,
                    )
                  : AuthTokens.logoClearance;

              return SafeArea(
                child: SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(24, top, 24, 20 + keyboard),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AuthTokens.maxCardWidth,
                      ),
                      child: widget.child,
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
