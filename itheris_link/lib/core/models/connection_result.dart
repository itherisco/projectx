// ============================================================================
// CONNECTION RESULT - Result model for connection attempts
// ============================================================================

/// Result of a connection attempt
class ConnectionResult {
  final bool isSuccess;
  final String? sessionId;
  final String? error;
  final String? sovereignKey;

  ConnectionResult({
    required this.isSuccess,
    this.sessionId,
    this.error,
    this.sovereignKey,
  });
}
