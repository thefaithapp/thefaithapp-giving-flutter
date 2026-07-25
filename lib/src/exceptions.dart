/// Categories of failure exposed by the giving package.
enum GivingErrorCode {
  notAuthenticated,
  invalidRequest,
  unavailable,
  server,
  malformedResponse,
  unsupportedPaymentProvider,
  paymentFailed,
}

/// A safe, user-presentable giving failure.
final class GivingException implements Exception {
  const GivingException(this.code, this.message, {this.statusCode});

  final GivingErrorCode code;
  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
