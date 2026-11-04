import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/auth/clerk_auth_provider.dart';
import 'core/routing/app_router.dart';
import 'core/theme/app_theme.dart';

class MantixApp extends ConsumerWidget {
  const MantixApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clerk = ref.watch(clerkAuthStateProvider);
    return MaterialApp.router(
      title: 'Mantix',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('es'),
      supportedLocales: const [Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // Los widgets de Clerk necesitan su estado en el árbol, por encima del router.
      builder: clerk == null
          ? null
          : (context, child) => ClerkAuth(
                authState: clerk,
                child: ClerkErrorListener(child: child ?? const SizedBox.shrink()),
              ),
    );
  }
}
