enum GivingFrequency {
  oneTime('one_time', 'One time'),
  weekly('weekly', 'Weekly'),
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  semiAnnual('semi_annual', 'Every six months'),
  annual('annual', 'Annual');

  const GivingFrequency(this.value, this.label);

  final String value;
  final String label;
}

enum GivingPaymentState { pending, succeeded, failed, cancelled }

sealed class GivingTarget {
  const GivingTarget();

  const factory GivingTarget.general() = GeneralGivingTarget;
  const factory GivingTarget.campaign(int campaignId) = CampaignGivingTarget;
}

final class GeneralGivingTarget extends GivingTarget {
  const GeneralGivingTarget();
}

final class CampaignGivingTarget extends GivingTarget {
  const CampaignGivingTarget(this.campaignId);

  final int campaignId;
}

final class SupportedCurrency {
  const SupportedCurrency({
    required this.code,
    required this.name,
    required this.symbol,
  });

  factory SupportedCurrency.fromJson(Map<String, dynamic> json) =>
      SupportedCurrency(
        code: _requiredString(json, 'code'),
        name: _requiredString(json, 'name'),
        symbol: _requiredString(json, 'symbol'),
      );

  final String code;
  final String name;
  final String symbol;
}

final class GivingConfig {
  const GivingConfig({
    required this.defaultPaymentProvider,
    required this.availableProviders,
    required this.defaultCurrency,
    required this.supportedCurrencies,
    required this.coverFeesEnabled,
    this.coverFeesPercentage,
  });

  factory GivingConfig.fromJson(Map<String, dynamic> json) {
    final providers = _stringList(json['available_providers']);
    final currencies = _mapList(
      json['supported_currencies'],
    ).map(SupportedCurrency.fromJson).toList(growable: false);
    return GivingConfig(
      defaultPaymentProvider: json['default_payment_provider'] as String?,
      availableProviders: providers,
      defaultCurrency: (json['default_currency'] as String?) ?? 'USD',
      supportedCurrencies: currencies.isEmpty
          ? const [
              SupportedCurrency(code: 'USD', name: 'US Dollar', symbol: r'$'),
            ]
          : currencies,
      coverFeesEnabled: json['cover_fees_enabled'] == true,
      coverFeesPercentage: _nullableDouble(json['cover_fees_percentage']),
    );
  }

  final String? defaultPaymentProvider;
  final List<String> availableProviders;
  final String defaultCurrency;
  final List<SupportedCurrency> supportedCurrencies;
  final bool coverFeesEnabled;
  final double? coverFeesPercentage;

  /// The platform intentionally returns only the church's active/default method.
  String? get activeProvider =>
      defaultPaymentProvider ??
      (availableProviders.isEmpty ? null : availableProviders.first);
}

final class GivingFund {
  const GivingFund({required this.id, required this.name, this.description});

  factory GivingFund.fromJson(Map<String, dynamic> json) => GivingFund(
    id: _requiredInt(json, 'id'),
    name: _requiredString(json, 'name'),
    description: json['description'] as String?,
  );

  final int id;
  final String name;
  final String? description;
}

final class GivingCampaign {
  const GivingCampaign({
    required this.id,
    required this.title,
    required this.acceptsCash,
    this.description,
    this.imageUrl,
    this.formFields = const [],
  });

  factory GivingCampaign.fromJson(Map<String, dynamic> json) => GivingCampaign(
    id: _requiredInt(json, 'id'),
    title: _requiredString(json, 'title'),
    acceptsCash: json['accepts_cash'] == true,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    formFields: _mapList(
      json['form_fields'],
    ).map(GivingCampaignFormField.fromJson).toList(growable: false),
  );

  final int id;
  final String title;
  final bool acceptsCash;
  final String? description;
  final String? imageUrl;
  final List<GivingCampaignFormField> formFields;
}

/// An additional donor field configured on a campaign.
final class GivingCampaignFormField {
  const GivingCampaignFormField({
    required this.id,
    required this.label,
    required this.name,
    required this.type,
    this.options = const [],
    this.placeholder,
    this.helpText,
    this.required = false,
    this.sortOrder = 0,
  });

  factory GivingCampaignFormField.fromJson(Map<String, dynamic> json) =>
      GivingCampaignFormField(
        id: _requiredInt(json, 'id'),
        label: _requiredString(json, 'label'),
        name: _requiredString(json, 'name'),
        type: _requiredString(json, 'type'),
        options: _stringList(json['options']),
        placeholder: json['placeholder'] as String?,
        helpText: json['help_text'] as String?,
        required: json['required'] == true || json['required'] == 1,
        sortOrder: _optionalInt(json['sort_order']),
      );

  final int id;
  final String label;
  final String name;
  final String type;
  final List<String> options;
  final String? placeholder;
  final String? helpText;
  final bool required;
  final int sortOrder;
}

final class GivingSubscription {
  const GivingSubscription({
    required this.id,
    required this.target,
    required this.amount,
    required this.currency,
    required this.frequency,
    this.provider,
    this.nextPaymentDate,
    this.createdAt,
    this.campaignTitle,
  });

  factory GivingSubscription.fromJson(Map<String, dynamic> json) {
    final source = json['source'];
    final target = switch (source) {
      'giving' => const GivingTarget.general(),
      'campaign' => GivingTarget.campaign(_requiredInt(json, 'campaign_id')),
      _ => throw const FormatException('Subscription source is invalid.'),
    };

    return GivingSubscription(
      id: _requiredInt(json, 'id'),
      target: target,
      amount:
          _nullableDouble(json['amount']) ??
          (throw const FormatException('Subscription amount is invalid.')),
      currency: _requiredString(json, 'currency'),
      frequency: GivingFrequency.values.firstWhere(
        (frequency) => frequency.value == json['frequency'],
        orElse: () => GivingFrequency.oneTime,
      ),
      provider: json['method'] as String?,
      nextPaymentDate: _date(json['next_payment_date']),
      createdAt: _date(json['created_at']),
      campaignTitle: json['campaign_title'] as String?,
    );
  }

  final int id;
  final GivingTarget target;
  final double amount;
  final String currency;
  final GivingFrequency frequency;
  final String? provider;
  final DateTime? nextPaymentDate;
  final DateTime? createdAt;
  final String? campaignTitle;
}

final class GivingAllocation {
  const GivingAllocation({required this.amount, this.fundId});

  final double amount;
  final int? fundId;

  Map<String, Object?> toJson() => <String, Object?>{
    if (fundId != null) 'fund_id': fundId,
    'amount': amount,
  };
}

final class GeneralGivingRequest {
  const GeneralGivingRequest({
    required this.allocations,
    required this.currency,
    this.frequency = GivingFrequency.oneTime,
    this.memo,
    this.coverFees = false,
    this.prayerRoomId,
  });

  final List<GivingAllocation> allocations;
  final String currency;
  final GivingFrequency frequency;
  final String? memo;
  final bool coverFees;
  final int? prayerRoomId;

  Map<String, Object?> toJson(String provider) => <String, Object?>{
    'items': allocations.map((item) => item.toJson()).toList(),
    'currency': currency,
    'frequency': frequency.value,
    'payment_provider': provider,
    'cover_fees': coverFees,
    if (memo != null && memo!.trim().isNotEmpty) 'memo': memo!.trim(),
    if (prayerRoomId != null) 'prayer_room_id': prayerRoomId,
  };
}

final class CampaignGivingRequest {
  const CampaignGivingRequest({
    required this.amount,
    required this.currency,
    this.frequency = GivingFrequency.oneTime,
    this.memo,
    this.coverFees = false,
    this.formFields = const <String, Object?>{},
  });

  final double amount;
  final String currency;
  final GivingFrequency frequency;
  final String? memo;
  final bool coverFees;
  final Map<String, Object?> formFields;

  Map<String, Object?> toJson(String provider) => <String, Object?>{
    'amount': amount,
    'currency': currency,
    'frequency': frequency.value,
    'payment_provider': provider,
    'cover_fees': coverFees,
    if (memo != null && memo!.trim().isNotEmpty) 'memo': memo!.trim(),
    if (formFields.isNotEmpty) 'form_fields': formFields,
  };
}

final class GivingCheckoutSession {
  const GivingCheckoutSession({
    required this.provider,
    required this.donationId,
    this.donationReference,
    this.clientSecret,
    this.ephemeralKey,
    this.customerId,
    this.paymentIntentId,
    this.stripeConnectAccountId,
    this.publishableKey,
    this.approvalUrl,
    this.paypalOrderId,
    this.paypalFlow,
    this.paypalTokenId,
    this.flutterwaveChargeId,
    this.transactionReference,
    this.amount,
    this.currency,
    this.providerData = const <String, Object?>{},
  });

  factory GivingCheckoutSession.fromJson(Map<String, dynamic> json) {
    return GivingCheckoutSession(
      provider: _requiredString(json, 'provider'),
      donationId: _requiredInt(json, 'donation_id'),
      donationReference: json['donation_reference'] as String?,
      clientSecret: json['client_secret'] as String?,
      ephemeralKey: json['ephemeral_key'] as String?,
      customerId: json['customer_id'] as String?,
      paymentIntentId: json['payment_intent_id'] as String?,
      stripeConnectAccountId: json['stripe_connect_account_id'] as String?,
      publishableKey: json['publishable_key'] as String?,
      approvalUrl: _uri(json['approval_url']),
      paypalOrderId: json['paypal_order_id'] as String?,
      paypalFlow: json['paypal_flow'] as String?,
      paypalTokenId: json['paypal_token_id'] as String?,
      flutterwaveChargeId: json['fw_charge_id'] as String?,
      transactionReference: json['tx_ref'] as String?,
      amount: _nullableDouble(json['amount']),
      currency: json['currency'] as String?,
      providerData: Map<String, Object?>.unmodifiable(json),
    );
  }

  final String provider;
  final int donationId;
  final String? donationReference;
  final String? clientSecret;
  final String? ephemeralKey;
  final String? customerId;
  final String? paymentIntentId;
  final String? stripeConnectAccountId;
  final String? publishableKey;
  final Uri? approvalUrl;
  final String? paypalOrderId;
  final String? paypalFlow;
  final String? paypalTokenId;
  final String? flutterwaveChargeId;
  final String? transactionReference;
  final double? amount;
  final String? currency;

  /// The complete provider payload for custom payment handlers.
  /// Treat values such as client secrets and approval URLs as ephemeral.
  final Map<String, Object?> providerData;
}

final class GivingPaymentStatus {
  const GivingPaymentStatus({
    required this.donationId,
    required this.state,
    required this.provider,
  });

  factory GivingPaymentStatus.fromJson(Map<String, dynamic> json) =>
      GivingPaymentStatus(
        donationId: _requiredInt(json, 'donation_id'),
        state: switch (json['status']) {
          'completed' ||
          'donated' ||
          'succeeded' => GivingPaymentState.succeeded,
          'failed' => GivingPaymentState.failed,
          'cancelled' || 'canceled' => GivingPaymentState.cancelled,
          _ => GivingPaymentState.pending,
        },
        provider: (json['provider'] as String?) ?? 'unknown',
      );

  final int donationId;
  final GivingPaymentState state;
  final String provider;
}

final class GivingPaymentResult {
  const GivingPaymentResult({
    required this.donationId,
    required this.provider,
    required this.state,
  });

  final int donationId;
  final String provider;
  final GivingPaymentState state;

  bool get isSuccessful => state == GivingPaymentState.succeeded;
}

int _requiredInt(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is num) return value.toInt();
  throw FormatException('$key is missing.');
}

int _optionalInt(Object? value) => value is num ? value.toInt() : 0;

String _requiredString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('$key is missing.');
}

double? _nullableDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

Uri? _uri(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return Uri.tryParse(value);
}

DateTime? _date(Object? value) {
  if (value is! String || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

List<String> _stringList(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

List<Map<String, dynamic>> _mapList(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false)
    : const <Map<String, dynamic>>[];
