/// Where the API session token comes from. The real implementation depends on the
/// authentication decision (Phase 0.5); the network layer only knows this interface.
abstract interface class AuthTokenProvider {
  /// The token to send now, or `null` when there is no session. May be cached.
  Future<String?> currentToken();

  /// Asks for a fresh token, skipping any cache. Returns `null` when the session can no
  /// longer be renewed. The network layer calls it once per expired token, however many
  /// requests fail at the same time.
  Future<String?> refreshToken();
}
