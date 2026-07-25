import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;

import '../exceptions.dart';
import '../models.dart';
import 'payment_handler.dart';

typedef GivingStripePaymentSheetPresenter =
    Future<void> Function({
      required GivingCheckoutSession session,
      required String merchantDisplayName,
      required ThemeMode style,
    });

final class StripeGivingPaymentHandler implements GivingPaymentHandler {
  const StripeGivingPaymentHandler({
    this.generalMerchantName = 'Church Giving',
    this.campaignMerchantName = 'Campaign Donation',
    this.paymentSheetPresenter = _presentStripePaymentSheet,
  });

  final String generalMerchantName;
  final String campaignMerchantName;
  final GivingStripePaymentSheetPresenter paymentSheetPresenter;

  @override
  String get provider => 'stripe';

  @override
  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  ) async {
    final session = checkout.session;
    final publishableKey = session.publishableKey;
    final clientSecret = session.clientSecret;
    if (publishableKey == null || clientSecret == null) {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'Stripe checkout is missing required configuration.',
      );
    }

    final themeMode = Theme.of(context).brightness == Brightness.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    try {
      await paymentSheetPresenter(
        session: session,
        merchantDisplayName: checkout.target is CampaignGivingTarget
            ? campaignMerchantName
            : generalMerchantName,
        style: themeMode,
      );
    } on stripe.StripeException catch (error) {
      GivingPaymentState? authoritativeState;
      try {
        final status = await checkout.getAuthoritativeStatus();
        if (status.state != GivingPaymentState.pending) {
          authoritativeState = status.state;
        }
      } on Object {
        // The provider error still gives us a safe local result when the
        // advisory status refresh is temporarily unavailable.
      }
      return GivingPaymentResult(
        donationId: session.donationId,
        provider: provider,
        state:
            authoritativeState ??
            (error.error.code == stripe.FailureCode.Canceled
                ? GivingPaymentState.cancelled
                : GivingPaymentState.failed),
      );
    }

    // PaymentSheet returning is not proof of settlement. Only the platform's
    // webhook-driven donation status is authoritative.
    final status = await checkout.waitForAuthoritativeStatus();
    return GivingPaymentResult(
      donationId: session.donationId,
      provider: provider,
      state: status.state,
    );
  }
}

Future<void> _presentStripePaymentSheet({
  required GivingCheckoutSession session,
  required String merchantDisplayName,
  required ThemeMode style,
}) async {
  stripe.Stripe.publishableKey = session.publishableKey!;
  stripe.Stripe.stripeAccountId = session.stripeConnectAccountId;
  await stripe.Stripe.instance.applySettings();
  await stripe.Stripe.instance.initPaymentSheet(
    paymentSheetParameters: stripe.SetupPaymentSheetParameters(
      paymentIntentClientSecret: session.clientSecret,
      customerEphemeralKeySecret: session.ephemeralKey,
      customerId: session.customerId,
      merchantDisplayName: merchantDisplayName,
      style: style,
    ),
  );
  await stripe.Stripe.instance.presentPaymentSheet();
}
