import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:thefaithapp_auth/thefaithapp_auth.dart';

import 'exceptions.dart';
import 'giving_response.dart';
import 'models.dart';

/// Network boundary used by the SDK. Production instances are always backed
/// by [TheFaithAppAuth]; this interface exists for deterministic package tests.
abstract interface class GivingApi {
  Uri get apiOrigin;

  Future<GivingConfig> getConfig();
  Future<List<GivingFund>> getFunds();
  Future<GivingCampaign> getCampaign(int campaignId);
  Future<List<GivingSubscription>> getSubscriptions();
  Future<void> cancelSubscription(GivingTarget target, int subscriptionId);
  Future<GivingCheckoutSession> checkoutGeneral(
    GeneralGivingRequest request,
    String provider,
  );
  Future<GivingCheckoutSession> checkoutCampaign(
    int campaignId,
    CampaignGivingRequest request,
    String provider,
  );
  Future<GivingPaymentStatus> getStatus(GivingTarget target, int donationId);
  Future<void> abandonCheckout(GivingTarget target, int donationId);
  Future<void> capturePayPal(
    GivingTarget target,
    GivingCheckoutSession session,
  );
  Future<void> verifyFlutterwave(
    GivingTarget target,
    GivingCheckoutSession session,
    String transactionId,
  );
  void close();
}

final class AuthenticatedGivingApi implements GivingApi {
  AuthenticatedGivingApi(this._auth) : _client = _auth.authorizedClient();

  final TheFaithAppAuth _auth;
  final http.Client _client;

  @override
  Uri get apiOrigin => _auth.apiUri('/');

  @override
  Future<GivingConfig> getConfig() async =>
      GivingConfig.fromJson(await _getData('/v1/giving/config'));

  @override
  Future<List<GivingFund>> getFunds() async {
    final data = await _getData('/v1/giving/funds');
    final raw = data['items'];
    if (raw is! List) {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'The giving funds response was invalid.',
      );
    }
    return raw
        .whereType<Map>()
        .map((item) => GivingFund.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  @override
  Future<GivingCampaign> getCampaign(int campaignId) async =>
      GivingCampaign.fromJson(await _getData('/v1/campaigns/$campaignId'));

  @override
  Future<List<GivingSubscription>> getSubscriptions() async {
    final data = await _getData('/v1/giving/subscriptions');
    final raw = data['items'];
    if (raw is! List) {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'The recurring gifts response was invalid.',
      );
    }
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              GivingSubscription.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  @override
  Future<void> cancelSubscription(
    GivingTarget target,
    int subscriptionId,
  ) async {
    final path = switch (target) {
      GeneralGivingTarget() =>
        '/v1/giving/subscriptions/$subscriptionId/cancel',
      CampaignGivingTarget(:final campaignId) =>
        '/v1/campaigns/$campaignId/subscriptions/$subscriptionId/cancel',
    };
    await _postData(path, const <String, Object?>{});
  }

  @override
  Future<GivingCheckoutSession> checkoutGeneral(
    GeneralGivingRequest request,
    String provider,
  ) async => GivingCheckoutSession.fromJson(
    await _postData('/v1/giving/checkout', request.toJson(provider)),
  );

  @override
  Future<GivingCheckoutSession> checkoutCampaign(
    int campaignId,
    CampaignGivingRequest request,
    String provider,
  ) async => GivingCheckoutSession.fromJson(
    await _postData(
      '/v1/campaigns/$campaignId/checkout',
      request.toJson(provider),
    ),
  );

  @override
  Future<GivingPaymentStatus> getStatus(
    GivingTarget target,
    int donationId,
  ) async {
    final path = switch (target) {
      GeneralGivingTarget() => '/v1/giving/checkouts/$donationId/status',
      CampaignGivingTarget(:final campaignId) =>
        '/v1/campaigns/$campaignId/checkouts/$donationId/status',
    };
    return GivingPaymentStatus.fromJson(await _getData(path));
  }

  @override
  Future<void> abandonCheckout(GivingTarget target, int donationId) async {
    final path = switch (target) {
      GeneralGivingTarget() => '/v1/giving/checkouts/$donationId/abandon',
      CampaignGivingTarget(:final campaignId) =>
        '/v1/campaigns/$campaignId/checkouts/$donationId/abandon',
    };
    await _postData(path, const <String, Object?>{});
  }

  @override
  Future<void> capturePayPal(
    GivingTarget target,
    GivingCheckoutSession session,
  ) async {
    final path = switch (target) {
      GeneralGivingTarget() => '/v1/giving/paypal/capture',
      CampaignGivingTarget(:final campaignId) =>
        '/v1/campaigns/$campaignId/paypal/capture',
    };
    await _postData(path, <String, Object?>{
      'donation_id': session.donationId,
      'paypal_flow': session.paypalFlow ?? 'order',
      if (session.paypalOrderId != null)
        'paypal_order_id': session.paypalOrderId,
      if (session.paypalTokenId != null)
        'paypal_token_id': session.paypalTokenId,
      if (session.paypalSubscriptionId != null)
        'paypal_subscription_id': session.paypalSubscriptionId,
    });
  }

  @override
  Future<void> verifyFlutterwave(
    GivingTarget target,
    GivingCheckoutSession session,
    String transactionId,
  ) async {
    final path = switch (target) {
      GeneralGivingTarget() => '/v1/giving/flutterwave/verify',
      CampaignGivingTarget(:final campaignId) =>
        '/v1/campaigns/$campaignId/flutterwave/verify',
    };
    await _postData(path, <String, Object?>{
      'donation_id': session.donationId,
      'transaction_id': transactionId,
    });
  }

  Future<Map<String, dynamic>> _getData(String path) async {
    await _requireSession();
    final response = await _client.get(_auth.apiUri(path));
    return decodeGivingResponse(response);
  }

  Future<Map<String, dynamic>> _postData(
    String path,
    Map<String, Object?> body,
  ) async {
    await _requireSession();
    final response = await _client.post(
      _auth.apiUri(path),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    return decodeGivingResponse(response);
  }

  Future<void> _requireSession() async {
    final session = await _auth.currentSession();
    if (session == null || session.isExpired) {
      throw const GivingException(
        GivingErrorCode.notAuthenticated,
        'Sign in before making a gift.',
      );
    }
  }

  @override
  void close() => _client.close();
}
