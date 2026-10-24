import 'package:flutter/material.dart';
import 'package:thefaithapp_auth/thefaithapp_auth.dart';

import 'exceptions.dart';
import 'giving_api.dart';
import 'models.dart';
import 'payment/hosted_payment_handler.dart';
import 'payment/payment_handler.dart';
import 'payment/stripe_payment_handler.dart';

/// Authenticated entry point for general and campaign giving.
///
/// Member and client identifiers are never accepted by this SDK. The
/// authorized auth client supplies credentials, and the platform derives both
/// identities from those credentials on every request.
final class TheFaithAppGiving {
  TheFaithAppGiving({
    required TheFaithAppAuth auth,
    Iterable<GivingPaymentHandler> paymentHandlers = const [],
    Duration statusPollInterval = const Duration(seconds: 1),
    int maxStatusPollAttempts = 12,
  }) : this._(
         AuthenticatedGivingApi(auth),
         paymentHandlers,
         statusPollInterval: statusPollInterval,
         maxStatusPollAttempts: maxStatusPollAttempts,
       );

  @visibleForTesting
  TheFaithAppGiving.testing({
    required GivingApi api,
    Iterable<GivingPaymentHandler> paymentHandlers = const [],
    Duration statusPollInterval = Duration.zero,
    int maxStatusPollAttempts = 1,
  }) : this._(
         api,
         paymentHandlers,
         statusPollInterval: statusPollInterval,
         maxStatusPollAttempts: maxStatusPollAttempts,
       );

  TheFaithAppGiving._(
    this._api,
    Iterable<GivingPaymentHandler> customHandlers, {
    required this.statusPollInterval,
    required this.maxStatusPollAttempts,
  }) {
    if (maxStatusPollAttempts < 1) {
      throw ArgumentError.value(
        maxStatusPollAttempts,
        'maxStatusPollAttempts',
        'Must be at least one.',
      );
    }
    if (statusPollInterval < Duration.zero) {
      throw ArgumentError.value(
        statusPollInterval,
        'statusPollInterval',
        'Must not be negative.',
      );
    }
    for (final handler in const <GivingPaymentHandler>[
      StripeGivingPaymentHandler(),
      PayPalGivingPaymentHandler(),
      FlutterwaveGivingPaymentHandler(),
    ]) {
      _registerHandler(handler);
    }
    for (final handler in customHandlers) {
      _registerHandler(handler);
    }
  }

  final GivingApi _api;
  final Map<String, GivingPaymentHandler> _handlers = {};
  final Duration statusPollInterval;
  final int maxStatusPollAttempts;

  Future<GivingConfig> getConfig() => _api.getConfig();
  Future<List<GivingFund>> getFunds() => _api.getFunds();
  Future<GivingCampaign> getCampaign(int campaignId) =>
      _api.getCampaign(campaignId);
  Future<List<GivingSubscription>> getSubscriptions() =>
      _api.getSubscriptions();
  Future<void> cancelSubscription(GivingSubscription subscription) =>
      _api.cancelSubscription(subscription.target, subscription.id);

  Future<GivingPaymentResult> give(
    BuildContext context,
    GeneralGivingRequest request,
  ) async {
    _validateGeneralRequest(request);
    const target = GivingTarget.general();
    final provider = await _activeProvider();
    final session = await _api.checkoutGeneral(request, provider);
    await _validateCheckoutSession(target, provider, session);
    if (!context.mounted) {
      await _bestEffortAbandon(target, session.donationId);
      return GivingPaymentResult(
        donationId: session.donationId,
        provider: session.provider,
        state: GivingPaymentState.cancelled,
      );
    }
    return _present(context, target, session);
  }

  Future<GivingPaymentResult> giveToCampaign(
    BuildContext context,
    int campaignId,
    CampaignGivingRequest request,
  ) async {
    if (campaignId < 1 || !request.amount.isFinite || request.amount < 1) {
      throw const GivingException(
        GivingErrorCode.invalidRequest,
        'Enter a valid campaign gift amount.',
      );
    }
    final target = GivingTarget.campaign(campaignId);
    final provider = await _activeProvider();
    final session = await _api.checkoutCampaign(campaignId, request, provider);
    await _validateCheckoutSession(target, provider, session);
    if (!context.mounted) {
      await _bestEffortAbandon(target, session.donationId);
      return GivingPaymentResult(
        donationId: session.donationId,
        provider: session.provider,
        state: GivingPaymentState.cancelled,
      );
    }
    return _present(context, target, session);
  }

  Future<String> _activeProvider() async {
    final provider = (await _api.getConfig()).activeProvider;
    if (provider == null || provider.isEmpty) {
      throw const GivingException(
        GivingErrorCode.unavailable,
        'Giving is not currently available for this church.',
      );
    }
    if (!_handlers.containsKey(provider)) {
      throw GivingException(
        GivingErrorCode.unsupportedPaymentProvider,
        'No payment handler is registered for $provider.',
      );
    }
    return provider;
  }

  Future<GivingPaymentResult> _present(
    BuildContext context,
    GivingTarget target,
    GivingCheckoutSession session,
  ) async {
    final handler = _handlers[session.provider];
    if (handler == null) {
      await _bestEffortAbandon(target, session.donationId);
      throw GivingException(
        GivingErrorCode.unsupportedPaymentProvider,
        'No payment handler is registered for ${session.provider}.',
      );
    }
    try {
      final result = await handler.present(
        context,
        GivingCheckoutContext(
          session: session,
          target: target,
          apiOrigin: _api.apiOrigin,
          waitForStatus: () => _waitForStatus(target, session),
          getStatus: () => _getStatus(target, session),
          capturePayPal: () => _api.capturePayPal(target, session),
          verifyFlutterwave: (transactionId) =>
              _api.verifyFlutterwave(target, session, transactionId),
        ),
      );
      if (result.donationId != session.donationId ||
          result.provider != session.provider) {
        throw const GivingException(
          GivingErrorCode.malformedResponse,
          'The payment handler returned a result for a different checkout.',
        );
      }
      if (result.state == GivingPaymentState.cancelled ||
          (result.state == GivingPaymentState.failed &&
              session.provider == 'flutterwave')) {
        await _bestEffortAbandon(target, session.donationId);
      }
      return result;
    } on Object {
      await _bestEffortAbandon(target, session.donationId);
      rethrow;
    }
  }

  Future<void> _bestEffortAbandon(GivingTarget target, int donationId) async {
    try {
      await _api.abandonCheckout(target, donationId);
    } on Object {
      // Checkout expiry on the platform remains the fallback when the app is
      // offline or terminates before this advisory request can be delivered.
    }
  }

  void _registerHandler(GivingPaymentHandler handler) {
    final provider = handler.provider;
    if (provider.isEmpty || provider.trim() != provider) {
      throw ArgumentError.value(
        provider,
        'paymentHandlers',
        'Provider identifiers must be non-empty and contain no leading or '
            'trailing whitespace.',
      );
    }
    _handlers[provider] = handler;
  }

  Future<void> _validateCheckoutSession(
    GivingTarget target,
    String expectedProvider,
    GivingCheckoutSession session,
  ) async {
    if (session.donationId > 0 && session.provider == expectedProvider) return;
    if (session.donationId > 0) {
      await _bestEffortAbandon(target, session.donationId);
    }
    throw const GivingException(
      GivingErrorCode.malformedResponse,
      'The giving service returned an invalid checkout session.',
    );
  }

  Future<GivingPaymentStatus> _waitForStatus(
    GivingTarget target,
    GivingCheckoutSession session,
  ) async {
    late GivingPaymentStatus status;
    for (var attempt = 0; attempt < maxStatusPollAttempts; attempt++) {
      status = await _getStatus(target, session);
      if (status.state != GivingPaymentState.pending) return status;
      if (attempt + 1 < maxStatusPollAttempts &&
          statusPollInterval > Duration.zero) {
        await Future<void>.delayed(statusPollInterval);
      }
    }
    return status;
  }

  Future<GivingPaymentStatus> _getStatus(
    GivingTarget target,
    GivingCheckoutSession session,
  ) async {
    final status = await _api.getStatus(target, session.donationId);
    if (status.donationId != session.donationId ||
        (status.provider != session.provider && status.provider != 'unknown')) {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'The giving service returned a status for a different checkout.',
      );
    }
    return status;
  }

  void _validateGeneralRequest(GeneralGivingRequest request) {
    if (request.allocations.isEmpty ||
        request.allocations.any(
          (item) => !item.amount.isFinite || item.amount < 1,
        )) {
      throw const GivingException(
        GivingErrorCode.invalidRequest,
        'Enter a valid gift amount for every fund.',
      );
    }
    final selectedFundIds = request.allocations
        .map((item) => item.fundId)
        .whereType<int>()
        .toList(growable: false);
    if (selectedFundIds.toSet().length != selectedFundIds.length) {
      throw const GivingException(
        GivingErrorCode.invalidRequest,
        'Each fund can only be selected once.',
      );
    }
  }

  void dispose() => _api.close();
}
