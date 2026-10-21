/// Categories of failure exposed by the giving package.
enum GivingErrorCode {
  notAuthenticated,
  invalidRequest,
  unavailable,
  server,
  malformedResponse,
  unsupportedPaymentProvider,
  paymentFailed,
  planAccessDenied,
  forbidden,
}

/// Allowlisted plan identifiers returned by the API, without raw response data.
final class GivingPlanAccess {
  const GivingPlanAccess({
    required this.type,
    this.product,
    this.entitlement,
    this.currentPlan,
    this.recommendedPlan,
  });

  final String type;
  final String? product;
  final String? entitlement;
  final String? currentPlan;
  final String? recommendedPlan;
}

/// A safe, user-presentable giving failure.
final class GivingException implements Exception {
  const GivingException(
    this.code,
    this.message, {
    this.statusCode,
    this.serverErrorCode,
    this.planAccess,
  });

  final GivingErrorCode code;
  final String message;
  final int? statusCode;
  final String? serverErrorCode;
  final GivingPlanAccess? planAccess;

  @override
  String toString() => message;
}
