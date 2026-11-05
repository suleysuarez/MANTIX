import 'package:clerk_flutter/clerk_flutter.dart';
import 'package:clerk_flutter/src/widgets/authentication/clerk_oauth_panel.dart';
import 'package:clerk_flutter/src/widgets/authentication/clerk_sign_in_panel.dart';
import 'package:clerk_flutter/src/widgets/authentication/clerk_sign_up_panel.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Mantix layout around Clerk's own authentication panels.
///
/// The stock ClerkAuthentication adds a default organization-logo placeholder.
/// Mantix already displays its own logo in the background, so this wrapper
/// keeps Clerk's authentication flow without rendering that duplicate icon.
class MantixClerkAuthentication extends StatefulWidget {
  const MantixClerkAuthentication({super.key});

  @override
  State<MantixClerkAuthentication> createState() =>
      _MantixClerkAuthenticationState();
}

class _MantixClerkAuthenticationState
    extends State<MantixClerkAuthentication> {
  bool _signingUp = false;

  @override
  Widget build(BuildContext context) {
    final authState = ClerkAuth.of(context);
    if (authState.isNotAvailable) return const SizedBox.shrink();

    if (authState.isSigningIn && !authState.isSigningUp) {
      _signingUp = false;
    } else if (authState.isSigningUp) {
      _signingUp = true;
    }

    final env = authState.env;
    final localizations = ClerkAuth.localizationsOf(context);
    final theme = ClerkAuth.themeExtensionOf(context);
    final styles = theme.styles;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 4, 4),
          child: Text(
            _signingUp
                ? localizations.signUpTo(env.display.applicationName)
                : localizations.signInTo(env.display.applicationName),
            textAlign: TextAlign.center,
            style: styles.heading.copyWith(
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            _signingUp
                ? localizations.welcomePleaseFillInTheDetailsToGetStarted
                : localizations.welcomeBackPleaseSignInToContinue,
            textAlign: TextAlign.center,
            style: styles.subheading,
          ),
        ),
        const SizedBox(height: 18),
        if (!_signingUp && env.hasOauthStrategies) ...[
          const ClerkOAuthPanel(),
          const SizedBox(height: 12),
          if (!_signingUp) ...[
            Row(
              children: [
                const Expanded(child: Divider(color: Color(0x5938D6FF))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('or', style: styles.subheading),
                ),
                const Expanded(child: Divider(color: Color(0x5938D6FF))),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ],
        if (_signingUp)
          const ClerkSignUpPanel()
        else
          const ClerkSignInPanel(),
        const SizedBox(height: 8),
          Center(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _signingUp
                        ? localizations.alreadyHaveAnAccount
                        : localizations.dontHaveAnAccount,
                    style: styles.subheading,
                  ),
                  const WidgetSpan(child: SizedBox(width: 6)),
                  TextSpan(
                    text: _signingUp
                        ? localizations.signIn
                        : localizations.signUp,
                    style: styles.subheading.copyWith(color: theme.colors.accent),
                    recognizer: TapGestureRecognizer()
                      ..onTap = () => setState(() => _signingUp = !_signingUp),
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        const SizedBox(height: 12),
        Center(child: Text('Secured by Clerk', style: styles.subtext)),
      ],
    );
  }
}
