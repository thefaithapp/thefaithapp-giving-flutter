import 'package:flutter/material.dart';

import '../models.dart';

typedef GivingStatusCallback = Future<GivingPaymentStatus> Function();
typedef GivingPayPalCaptureCallback = Future<void> Function();
typedef GivingFlutterwaveVerifyCallback =
    Future<void> Function(String transactionId);

/// The narrow capabilities a payment method receives for one checkout.
/// It deliberately exposes no member ID, client ID, bearer token, or API key.
final class GivingCheckoutContext {
  const GivingCheckoutContext({
    required this.session,
    required this.target,
    required this.apiOrigin,
    required GivingStatusCallback waitForStatus,
    required GivingStatusCallback getStatus,
    required GivingPayPalCaptureCallback capturePayPal,
    required GivingFlutterwaveVerifyCallback verifyFlutterwave,
  }) : _waitForStatus = waitForStatus,
       _getStatus = getStatus,
       _capturePayPal = capturePayPal,
       _verifyFlutterwave = verifyFlutterwave;

  final GivingCheckoutSession session;
  final GivingTarget target;
  final Uri apiOrigin;
  final GivingStatusCallback _waitForStatus;
  final GivingStatusCallback _getStatus;
  final GivingPayPalCaptureCallback _capturePayPal;
  final GivingFlutterwaveVerifyCallback _verifyFlutterwave;

  Future<GivingPaymentStatus> waitForAuthoritativeStatus() => _waitForStatus();
  Future<GivingPaymentStatus> getAuthoritativeStatus() => _getStatus();
  Future<void> capturePayPal() => _capturePayPal();
  Future<void> verifyFlutterwave(String transactionId) =>
      _verifyFlutterwave(transactionId);
}

/// A pluggable presentation adapter for a payment method.
///
/// New payment methods can be added without changing the giving form or API
/// orchestration. Implementations must not persist or log checkout secrets.
abstract interface class GivingPaymentHandler {
  String get provider;

  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  );
}
