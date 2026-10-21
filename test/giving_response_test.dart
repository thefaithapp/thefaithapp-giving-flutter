import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:thefaithapp_giving/src/giving_response.dart';
import 'package:thefaithapp_giving/thefaithapp_giving.dart';

void main() {
  final planDenial =
      jsonDecode(
            File(
              'test/fixtures/plan-product-unavailable.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;

  GivingException rejection(Object? payload, [int status = 403]) {
    try {
      decodeGivingResponse(http.Response(jsonEncode(payload), status));
    } on GivingException catch (error) {
      return error;
    }
    throw StateError('Expected an API rejection.');
  }

  test('decodes the actual plan product denial without requesting sign-in', () {
    final error = rejection(planDenial);
    expect(error.code, GivingErrorCode.planAccessDenied);
    expect(error.statusCode, 403);
    expect(error.message, planDenial['message']);
    expect(error.serverErrorCode, 'plan_product_unavailable');
    expect(error.planAccess?.type, 'product');
    expect(error.planAccess?.product, 'platform_integrations');
    expect(error.planAccess?.currentPlan, 'free');
    expect(error.planAccess?.recommendedPlan, 'large');
  });

  test('recognizes entitlement denials and retains only typed identifiers', () {
    final error = rejection({
      'error_code': 'plan_entitlement_required',
      'plan_access': {
        'type': 'entitlement',
        'entitlement': 'some_feature',
        'current_plan': 'free',
        'recommended_plan': null,
        'token': 'must-not-be-retained',
      },
      'token': 'must-not-be-retained',
    });
    expect(error.code, GivingErrorCode.planAccessDenied);
    expect(error.serverErrorCode, 'plan_entitlement_required');
    expect(error.planAccess?.type, 'entitlement');
    expect(error.planAccess?.entitlement, 'some_feature');
    expect(error.planAccess?.product, isNull);
    expect(error.planAccess?.currentPlan, 'free');
    expect(error.planAccess?.recommendedPlan, isNull);
  });

  test('other or malformed 403 error codes remain forbidden', () {
    for (final payload in <Map<String, dynamic>>[
      {'message': 'You cannot access this resource.'},
      {
        'error_code': 'another_permission',
        'plan_access': planDenial['plan_access'],
      },
      {
        'error_code': ['plan_product_unavailable'],
        'plan_access': planDenial['plan_access'],
      },
      {
        'error_code': 'plan_product_unavailable\n',
        'plan_access': planDenial['plan_access'],
      },
    ]) {
      final error = rejection(payload);
      expect(error.code, GivingErrorCode.forbidden);
      expect(error.statusCode, 403);
      expect(error.planAccess, isNull);
    }
  });

  test(
    'malformed optional plan context cannot hide the actual plan denial',
    () {
      for (final planAccess in <Object?>[
        null,
        [],
        'raw',
        {'type': 'product'},
        {'type': 'unknown', 'product': 'x'},
        {'type': 'entitlement', 'entitlement': 'some_feature'},
      ]) {
        final error = rejection({...planDenial, 'plan_access': planAccess});
        expect(error.code, GivingErrorCode.planAccessDenied);
        expect(error.serverErrorCode, 'plan_product_unavailable');
        expect(error.planAccess, isNull);
      }
    },
  );

  test('malformed plan identifiers are omitted without copying raw fields', () {
    final error = rejection({
      ...planDenial,
      'plan_access': {
        ...planDenial['plan_access'] as Map<String, dynamic>,
        'current_plan': {'secret': 'not-an-identifier'},
        'recommended_plan': 'large\n',
        'authorization': 'must-not-be-retained',
      },
    });
    expect(error.planAccess?.product, 'platform_integrations');
    expect(error.planAccess?.currentPlan, isNull);
    expect(error.planAccess?.recommendedPlan, isNull);
  });

  test(
    'real API key 401 and misleading plan fields still mean not authenticated',
    () {
      for (final payload in [
        {'error_message': 'Unauthorized - Invalid API key'},
        planDenial,
      ]) {
        final error = rejection(payload, 401);
        expect(error.code, GivingErrorCode.notAuthenticated);
        expect(error.statusCode, 401);
        expect(error.planAccess, isNull);
      }
    },
  );

  test('validation and server status mappings remain unchanged', () {
    expect(
      rejection({'message': 'Check the amount.'}, 422).code,
      GivingErrorCode.invalidRequest,
    );
    expect(
      rejection({'message': 'Try again later.'}, 500).code,
      GivingErrorCode.server,
    );
  });

  test(
    'successful object/list and malformed response behavior is preserved',
    () {
      expect(
        decodeGivingResponse(http.Response('{"data":{"enabled":true}}', 200)),
        {'enabled': true},
      );
      expect(decodeGivingResponse(http.Response('{"data":[1,2]}', 200)), {
        'items': [1, 2],
      });
      for (final body in ['not json', '[]', '{"ok":true}']) {
        expect(
          () => decodeGivingResponse(http.Response(body, 200)),
          throwsA(
            isA<GivingException>().having(
              (e) => e.code,
              'code',
              GivingErrorCode.malformedResponse,
            ),
          ),
        );
      }
    },
  );
}
