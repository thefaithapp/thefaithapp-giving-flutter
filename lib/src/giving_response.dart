import 'dart:convert';

import 'package:http/http.dart' as http;

import 'exceptions.dart';

/// Internal HTTP decoding boundary shared by every authenticated giving call.
Map<String, dynamic> decodeGivingResponse(http.Response response) {
  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    throw _malformed(response.statusCode);
  }

  if (decoded is! Map) throw _malformed(response.statusCode);
  final payload = Map<String, dynamic>.from(decoded);
  final succeeded = response.statusCode >= 200 && response.statusCode < 300;
  if (!succeeded) {
    final message = payload['message'];
    final serverErrorCode = _identifier(payload['error_code']);
    final isPlanDenial =
        serverErrorCode == 'plan_product_unavailable' ||
        serverErrorCode == 'plan_entitlement_required';
    throw GivingException(
      switch (response.statusCode) {
        401 => GivingErrorCode.notAuthenticated,
        403 =>
          isPlanDenial
              ? GivingErrorCode.planAccessDenied
              : GivingErrorCode.forbidden,
        422 => GivingErrorCode.invalidRequest,
        _ => GivingErrorCode.server,
      },
      message is String && message.isNotEmpty
          ? message
          : 'The giving request could not be completed.',
      statusCode: response.statusCode,
      serverErrorCode: serverErrorCode,
      planAccess: response.statusCode == 403 && isPlanDenial
          ? _planAccess(payload['plan_access'], serverErrorCode)
          : null,
    );
  }

  final data = payload['data'];
  if (data is List) return <String, dynamic>{'items': data};
  if (data is Map) return Map<String, dynamic>.from(data);
  throw _malformed(response.statusCode);
}

GivingException _malformed(int statusCode) => GivingException(
  GivingErrorCode.malformedResponse,
  'The giving service returned an invalid response.',
  statusCode: statusCode,
);

String? _identifier(Object? value) =>
    value is String &&
        RegExp(r'^[a-z][a-z0-9_]{0,79}$').stringMatch(value) == value
    ? value
    : null;

GivingPlanAccess? _planAccess(Object? value, String? serverErrorCode) {
  if (value is! Map) return null;
  final type = value['type'];
  if (type != 'product' && type != 'entitlement') return null;
  final expectedType = serverErrorCode == 'plan_product_unavailable'
      ? 'product'
      : 'entitlement';
  if (type != expectedType) return null;
  final key = _identifier(value[type]);
  if (key == null) return null;
  return GivingPlanAccess(
    type: type as String,
    product: type == 'product' ? key : null,
    entitlement: type == 'entitlement' ? key : null,
    currentPlan: _identifier(value['current_plan']),
    recommendedPlan: _identifier(value['recommended_plan']),
  );
}
