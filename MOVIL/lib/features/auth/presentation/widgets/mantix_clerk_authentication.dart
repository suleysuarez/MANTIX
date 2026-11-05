import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:flutter/material.dart';

/// Uses Clerk's public authentication UI inside Mantix's glass-card layout.
///
/// Clerk remains responsible for sign-in, sign-up, OAuth, verification,
/// password recovery, and session state. Mantix customizes the appearance
/// through the surrounding Theme rather than importing SDK implementation
/// files from `src/`.
class MantixClerkAuthentication extends StatelessWidget {
  const MantixClerkAuthentication({super.key});

  @override
  Widget build(BuildContext context) {
    return const ClerkAuthentication();
  }
}
