import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart' as stripe;
import 'package:flutter_test/flutter_test.dart';
import 'package:thefaithapp_giving/src/giving_api.dart';
import 'package:thefaithapp_giving/src/payment/hosted_payment_handler.dart';
import 'package:thefaithapp_giving/src/payment/stripe_payment_handler.dart';
import 'package:thefaithapp_giving/thefaithapp_giving.dart';

void main() {
  for (final permission in [null, false, true, 'true', 1]) {
    test(
      'recurring giving requires explicit server permission: $permission',
      () {
        expect(
          GivingConfig.fromJson({
            'recurring_giving_enabled': permission,
          }).recurringGivingEnabled,
          permission == true,
        );
      },
    );
  }

  for (final campaign in [false, true]) {
    testWidgets('disabled recurring choices are hidden: campaign=$campaign', (
      tester,
    ) async {
      final api = _FakeGivingApi(recurringGivingEnabled: false);
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [_TestPaymentHandler()],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: campaign
                ? GivingView.campaign(giving: giving, campaignId: 42)
                : GivingView.general(giving: giving),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Frequency'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '10',
      );
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(
        campaign
            ? api.campaignRequest?.frequency
            : api.generalRequest?.frequency,
        GivingFrequency.oneTime,
      );
    });
  }

  test('hosted callbacks require exact HTTPS origin, path and donation', () {
    final origin = Uri.parse('https://api.thefaithapp.com');
    const paths = {'/paypal/giving/success'};

    expect(
      isTrustedGivingCallback(
        Uri.parse(
          'https://api.thefaithapp.com/paypal/giving/success?donation_id=9',
        ),
        origin,
        9,
        paths,
      ),
      isTrue,
    );
    for (final callback in [
      'http://api.thefaithapp.com/paypal/giving/success?donation_id=9',
      'https://api.thefaithapp.com.evil.test/paypal/giving/success?donation_id=9',
      'https://api.thefaithapp.com/paypal/giving/success/extra?donation_id=9',
      'https://api.thefaithapp.com/paypal/giving/success?donation_id=10',
      'https://api.thefaithapp.com/untrusted?next=/paypal/giving/success&donation_id=9',
    ]) {
      expect(
        isTrustedGivingCallback(Uri.parse(callback), origin, 9, paths),
        isFalse,
        reason: callback,
      );
    }
  });

  test('hosted callbacks allow exact loopback HTTP only for local QA', () {
    const paths = {'/paypal/giving/success'};
    expect(
      isTrustedGivingCallback(
        Uri.parse('http://127.0.0.1:8002/paypal/giving/success?donation_id=9'),
        Uri.parse('http://127.0.0.1:8002'),
        9,
        paths,
      ),
      isTrue,
    );
    expect(
      isTrustedGivingCallback(
        Uri.parse(
          'http://api.example.test/paypal/giving/success?donation_id=9',
        ),
        Uri.parse('http://api.example.test'),
        9,
        paths,
      ),
      isFalse,
    );
  });

  testWidgets(
    'general giving uses the authenticated API and registered handler',
    (tester) async {
      final api = _FakeGivingApi();
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [_TestPaymentHandler()],
      );
      late BuildContext context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (value) {
              context = value;
              return const SizedBox();
            },
          ),
        ),
      );

      final result = await giving.give(
        context,
        const GeneralGivingRequest(
          allocations: [GivingAllocation(fundId: 7, amount: 25)],
          currency: 'USD',
        ),
      );

      expect(result.state, GivingPaymentState.succeeded);
      expect(api.generalRequest?.allocations.single.fundId, 7);
      expect(api.statusTarget, isA<GeneralGivingTarget>());
      final body = api.generalRequest!.toJson('testpay');
      expect(body, isNot(contains('member_id')));
      expect(body, isNot(contains('client_id')));
    },
  );

  testWidgets('campaign giving shares orchestration but preserves its target', (
    tester,
  ) async {
    final api = _FakeGivingApi();
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: const [_TestPaymentHandler()],
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (value) {
            context = value;
            return const SizedBox();
          },
        ),
      ),
    );

    final result = await giving.giveToCampaign(
      context,
      42,
      const CampaignGivingRequest(amount: 30, currency: 'UGX'),
    );

    expect(result.state, GivingPaymentState.succeeded);
    expect(api.campaignId, 42);
    expect(api.campaignRequest?.amount, 30);
    expect(api.statusTarget, isA<CampaignGivingTarget>());
    expect((api.statusTarget as CampaignGivingTarget).campaignId, 42);
    final body = api.campaignRequest!.toJson('testpay');
    expect(body, isNot(contains('member_id')));
    expect(body, isNot(contains('client_id')));
  });

  testWidgets(
    'general view renders amount, currency, fund and recurring fields',
    (tester) async {
      final giving = TheFaithAppGiving.testing(
        api: _FakeGivingApi(),
        paymentHandlers: const [_TestPaymentHandler()],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: GivingView.general(giving: giving)),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Currency'), findsOneWidget);
      expect(find.text('Fund'), findsOneWidget);
      expect(find.text('Frequency'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Stripe'), findsNothing);
      expect(find.text('PayPal'), findsNothing);
    },
  );

  testWidgets('campaign view renders API rich text as readable plain text', (
    tester,
  ) async {
    final giving = TheFaithAppGiving.testing(
      api: _FakeGivingApi(
        campaignDescription: '<p>The <strong>orphans</strong> &amp; carers</p>',
      ),
      paymentHandlers: const [_TestPaymentHandler()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GivingView.campaign(giving: giving, campaignId: 42),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('The orphans & carers'), findsOneWidget);
    expect(
      find.text('<p>The <strong>orphans</strong> &amp; carers</p>'),
      findsNothing,
    );
  });

  testWidgets('general giving rejects missing, invalid and duplicate funds', (
    tester,
  ) async {
    final api = _FakeGivingApi();
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: const [_TestPaymentHandler()],
    );
    final context = await _pumpContext(tester);

    for (final request in <GeneralGivingRequest>[
      const GeneralGivingRequest(allocations: [], currency: 'USD'),
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 0)],
        currency: 'USD',
      ),
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: double.infinity)],
        currency: 'USD',
      ),
      const GeneralGivingRequest(
        allocations: [
          GivingAllocation(fundId: 7, amount: 10),
          GivingAllocation(fundId: 7, amount: 20),
        ],
        currency: 'USD',
      ),
    ]) {
      await expectLater(
        giving.give(context, request),
        throwsA(
          isA<GivingException>().having(
            (error) => error.code,
            'code',
            GivingErrorCode.invalidRequest,
          ),
        ),
      );
    }

    expect(api.generalCheckoutCalls, 0);
  });

  testWidgets(
    'campaign giving rejects invalid ids and amounts before checkout',
    (tester) async {
      final api = _FakeGivingApi();
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [_TestPaymentHandler()],
      );
      final context = await _pumpContext(tester);

      for (final scenario in <(int, double)>[
        (0, 10),
        (42, 0),
        (42, double.nan),
      ]) {
        await expectLater(
          giving.giveToCampaign(
            context,
            scenario.$1,
            CampaignGivingRequest(amount: scenario.$2, currency: 'USD'),
          ),
          throwsA(
            isA<GivingException>().having(
              (error) => error.code,
              'code',
              GivingErrorCode.invalidRequest,
            ),
          ),
        );
      }

      expect(api.campaignCheckoutCalls, 0);
    },
  );

  testWidgets('unavailable and unregistered providers fail before checkout', (
    tester,
  ) async {
    final context = await _pumpContext(tester);
    const request = GeneralGivingRequest(
      allocations: [GivingAllocation(amount: 10)],
      currency: 'USD',
    );
    final unavailableApi = _FakeGivingApi(
      defaultProvider: null,
      availableProviders: const [],
    );
    final unsupportedApi = _FakeGivingApi(
      defaultProvider: 'unregistered',
      availableProviders: const ['unregistered'],
    );

    await expectLater(
      TheFaithAppGiving.testing(api: unavailableApi).give(context, request),
      throwsA(
        isA<GivingException>().having(
          (error) => error.code,
          'code',
          GivingErrorCode.unavailable,
        ),
      ),
    );
    await expectLater(
      TheFaithAppGiving.testing(api: unsupportedApi).give(context, request),
      throwsA(
        isA<GivingException>().having(
          (error) => error.code,
          'code',
          GivingErrorCode.unsupportedPaymentProvider,
        ),
      ),
    );

    expect(unavailableApi.generalCheckoutCalls, 0);
    expect(unsupportedApi.generalCheckoutCalls, 0);
  });

  testWidgets(
    'status polling stops on success and respects its attempt limit',
    (tester) async {
      final context = await _pumpContext(tester);
      const request = GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      );
      final successfulApi = _FakeGivingApi(
        statusStates: const [
          GivingPaymentState.pending,
          GivingPaymentState.pending,
          GivingPaymentState.succeeded,
        ],
      );
      final successfulGiving = TheFaithAppGiving.testing(
        api: successfulApi,
        paymentHandlers: const [_TestPaymentHandler()],
        maxStatusPollAttempts: 3,
      );
      final pendingApi = _FakeGivingApi(
        statusStates: const [GivingPaymentState.pending],
      );
      final pendingGiving = TheFaithAppGiving.testing(
        api: pendingApi,
        paymentHandlers: const [_TestPaymentHandler()],
        maxStatusPollAttempts: 2,
      );

      expect(
        (await successfulGiving.give(context, request)).state,
        GivingPaymentState.succeeded,
      );
      expect(successfulApi.statusCalls, 3);
      expect(
        (await pendingGiving.give(context, request)).state,
        GivingPaymentState.pending,
      );
      expect(pendingApi.statusCalls, 2);
    },
  );

  for (final scenario in [
    (donationId: 999, provider: 'testpay'),
    (donationId: 101, provider: 'paypal'),
  ]) {
    testWidgets('rejects status for another checkout $scenario', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final api = _FakeGivingApi(
        statusDonationId: scenario.donationId,
        statusProvider: scenario.provider,
      );
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [_TestPaymentHandler()],
      );
      await expectLater(
        giving.give(
          context,
          const GeneralGivingRequest(
            allocations: [GivingAllocation(amount: 10)],
            currency: 'USD',
          ),
        ),
        throwsA(
          isA<GivingException>().having(
            (error) => error.code,
            'code',
            GivingErrorCode.malformedResponse,
          ),
        ),
      );
      expect(api.statusCalls, 1);
      expect(api.abandonedDonationIds, [101]);
    });
  }

  testWidgets('loads funds while giving configuration is still pending', (
    tester,
  ) async {
    final configReady = Completer<void>();
    final api = _FakeGivingApi(configReady: configReady);
    final giving = TheFaithAppGiving.testing(api: api);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GivingView.general(giving: giving)),
      ),
    );
    expect(api.fundsCalls, 1);
    expect(find.text('Continue'), findsNothing);
    configReady.complete();
    await tester.pumpAndSettle();
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('custom handlers can replace a built-in provider', (
    tester,
  ) async {
    final api = _FakeGivingApi(
      defaultProvider: 'stripe',
      availableProviders: const ['stripe'],
    );
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: const [
        _FixedResultPaymentHandler('stripe', GivingPaymentState.failed),
      ],
    );
    final context = await _pumpContext(tester);

    final result = await giving.give(
      context,
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      ),
    );

    expect(result.provider, 'stripe');
    expect(result.state, GivingPaymentState.failed);
  });

  test('invalid polling and provider configuration is rejected', () {
    expect(
      () => TheFaithAppGiving.testing(
        api: _FakeGivingApi(),
        statusPollInterval: const Duration(milliseconds: -1),
      ),
      throwsArgumentError,
    );
    expect(
      () => TheFaithAppGiving.testing(
        api: _FakeGivingApi(),
        paymentHandlers: const [
          _FixedResultPaymentHandler(' ', GivingPaymentState.succeeded),
        ],
      ),
      throwsArgumentError,
    );
  });

  testWidgets(
    'checkout and handler results must preserve provider and donation identity',
    (tester) async {
      final context = await _pumpContext(tester);
      const request = GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      );
      final mismatchedCheckoutApi = _FakeGivingApi(
        checkoutProvider: 'different-provider',
      );

      await expectLater(
        TheFaithAppGiving.testing(
          api: mismatchedCheckoutApi,
          paymentHandlers: const [_TestPaymentHandler()],
        ).give(context, request),
        throwsA(
          isA<GivingException>().having(
            (error) => error.code,
            'code',
            GivingErrorCode.malformedResponse,
          ),
        ),
      );
      expect(mismatchedCheckoutApi.abandonedDonationIds, [101]);

      final mismatchedResultApi = _FakeGivingApi();
      await expectLater(
        TheFaithAppGiving.testing(
          api: mismatchedResultApi,
          paymentHandlers: const [
            _FixedResultPaymentHandler(
              'testpay',
              GivingPaymentState.succeeded,
              resultDonationId: 999,
              resultProvider: 'different-provider',
            ),
          ],
        ).give(context, request),
        throwsA(
          isA<GivingException>().having(
            (error) => error.code,
            'code',
            GivingErrorCode.malformedResponse,
          ),
        ),
      );
      expect(mismatchedResultApi.abandonedDonationIds, [101]);
    },
  );

  testWidgets(
    'Stripe cancellation preserves an authoritative failed checkout result',
    (tester) async {
      final api = _FakeGivingApi(
        defaultProvider: 'stripe',
        availableProviders: const ['stripe'],
        statusStates: const [GivingPaymentState.failed],
      );
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: [
          StripeGivingPaymentHandler(
            paymentSheetPresenter:
                ({
                  required session,
                  required merchantDisplayName,
                  required style,
                }) async {
                  throw const stripe.StripeException(
                    error: stripe.LocalizedErrorMessage(
                      code: stripe.FailureCode.Canceled,
                      localizedMessage: 'Payment cancelled',
                    ),
                  );
                },
          ),
        ],
      );
      final context = await _pumpContext(tester);

      final result = await giving.give(
        context,
        const GeneralGivingRequest(
          allocations: [GivingAllocation(amount: 10)],
          currency: 'USD',
        ),
      );

      expect(result.state, GivingPaymentState.failed);
      expect(api.statusCalls, 1);
      expect(api.abandonCalls, 0);
    },
  );

  testWidgets('Stripe user cancellation remains cancelled while pending', (
    tester,
  ) async {
    final api = _FakeGivingApi(
      defaultProvider: 'stripe',
      availableProviders: const ['stripe'],
      statusStates: const [GivingPaymentState.pending],
    );
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: [
        StripeGivingPaymentHandler(
          paymentSheetPresenter:
              ({
                required session,
                required merchantDisplayName,
                required style,
              }) async {
                throw const stripe.StripeException(
                  error: stripe.LocalizedErrorMessage(
                    code: stripe.FailureCode.Canceled,
                  ),
                );
              },
        ),
      ],
    );
    final context = await _pumpContext(tester);

    final result = await giving.give(
      context,
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      ),
    );

    expect(result.state, GivingPaymentState.cancelled);
    expect(api.statusCalls, 1);
    expect(api.abandonCalls, 1);
  });

  testWidgets('Stripe presentation failures remain failed while pending', (
    tester,
  ) async {
    final api = _FakeGivingApi(
      defaultProvider: 'stripe',
      availableProviders: const ['stripe'],
      statusStates: const [GivingPaymentState.pending],
    );
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: [
        StripeGivingPaymentHandler(
          paymentSheetPresenter:
              ({
                required session,
                required merchantDisplayName,
                required style,
              }) async {
                throw const stripe.StripeException(
                  error: stripe.LocalizedErrorMessage(
                    code: stripe.FailureCode.Failed,
                  ),
                );
              },
        ),
      ],
    );
    final context = await _pumpContext(tester);

    final result = await giving.give(
      context,
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      ),
    );

    expect(result.state, GivingPaymentState.failed);
    expect(api.statusCalls, 1);
    expect(api.abandonCalls, 0);
  });

  test(
    'recurring campaign gifts can be listed and cancelled by target',
    () async {
      const campaignSubscription = GivingSubscription(
        id: 91,
        target: GivingTarget.campaign(42),
        amount: 25,
        currency: 'USD',
        frequency: GivingFrequency.monthly,
        provider: 'stripe',
        campaignTitle: 'School meals',
      );
      final api = _FakeGivingApi(subscriptions: const [campaignSubscription]);
      final giving = TheFaithAppGiving.testing(api: api);

      final subscriptions = await giving.getSubscriptions();
      await giving.cancelSubscription(subscriptions.single);

      expect(subscriptions.single.campaignTitle, 'School meals');
      expect(api.cancelledSubscriptionId, 91);
      expect(api.cancelledSubscriptionTarget, isA<CampaignGivingTarget>());
      expect(
        (api.cancelledSubscriptionTarget as CampaignGivingTarget).campaignId,
        42,
      );
    },
  );

  testWidgets(
    'cancelled checkouts are abandoned for general and campaign giving',
    (tester) async {
      final api = _FakeGivingApi();
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [
          _FixedResultPaymentHandler('testpay', GivingPaymentState.cancelled),
        ],
      );
      final context = await _pumpContext(tester);

      expect(
        (await giving.give(
          context,
          const GeneralGivingRequest(
            allocations: [GivingAllocation(amount: 10)],
            currency: 'USD',
          ),
        )).state,
        GivingPaymentState.cancelled,
      );
      expect(
        (await giving.giveToCampaign(
          context,
          42,
          const CampaignGivingRequest(amount: 10, currency: 'USD'),
        )).state,
        GivingPaymentState.cancelled,
      );

      expect(api.abandonedTargets, hasLength(2));
      expect(api.abandonedTargets.first, isA<GeneralGivingTarget>());
      expect(api.abandonedTargets.last, isA<CampaignGivingTarget>());
      expect(api.abandonedDonationIds, [101, 202]);
    },
  );

  testWidgets(
    'abandonment reporting is best effort when the device is offline',
    (tester) async {
      final api = _FakeGivingApi(abandonThrows: true);
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [
          _FixedResultPaymentHandler('testpay', GivingPaymentState.cancelled),
        ],
      );
      final context = await _pumpContext(tester);

      final result = await giving.give(
        context,
        const GeneralGivingRequest(
          allocations: [GivingAllocation(amount: 10)],
          currency: 'USD',
        ),
      );

      expect(result.state, GivingPaymentState.cancelled);
      expect(api.abandonCalls, 1);
    },
  );

  testWidgets('failed hosted checkouts are abandoned for early cleanup', (
    tester,
  ) async {
    final api = _FakeGivingApi(
      defaultProvider: 'flutterwave',
      availableProviders: const ['flutterwave'],
    );
    final giving = TheFaithAppGiving.testing(
      api: api,
      paymentHandlers: const [
        _FixedResultPaymentHandler('flutterwave', GivingPaymentState.failed),
      ],
    );
    final context = await _pumpContext(tester);

    final result = await giving.give(
      context,
      const GeneralGivingRequest(
        allocations: [GivingAllocation(amount: 10)],
        currency: 'USD',
      ),
    );

    expect(result.state, GivingPaymentState.failed);
    expect(api.abandonedDonationIds, [101]);
  });

  test(
    'requests serialize every frequency and omit caller-owned identities',
    () {
      for (final frequency in GivingFrequency.values) {
        final general = GeneralGivingRequest(
          allocations: const [GivingAllocation(fundId: 7, amount: 25)],
          currency: 'USD',
          frequency: frequency,
          memo: '  building fund  ',
          coverFees: true,
          prayerRoomId: 19,
        ).toJson('stripe');
        final campaign = CampaignGivingRequest(
          amount: 30,
          currency: 'USD',
          frequency: frequency,
          memo: '  outreach  ',
          coverFees: true,
          formFields: const {'shirt_size': 'M'},
        ).toJson('stripe');

        expect(general['frequency'], frequency.value);
        expect(general['memo'], 'building fund');
        expect(general['cover_fees'], isTrue);
        expect(general['prayer_room_id'], 19);
        expect(campaign['frequency'], frequency.value);
        expect(campaign['memo'], 'outreach');
        expect(campaign['cover_fees'], isTrue);
        expect(campaign['form_fields'], const {'shirt_size': 'M'});
        expect(general, isNot(contains('member_id')));
        expect(general, isNot(contains('client_id')));
        expect(campaign, isNot(contains('member_id')));
        expect(campaign, isNot(contains('client_id')));
      }
    },
  );

  test('status parsing maps platform states to the public result states', () {
    for (final scenario in <(String, GivingPaymentState)>[
      ('completed', GivingPaymentState.succeeded),
      ('donated', GivingPaymentState.succeeded),
      ('succeeded', GivingPaymentState.succeeded),
      ('failed', GivingPaymentState.failed),
      ('cancelled', GivingPaymentState.cancelled),
      ('canceled', GivingPaymentState.cancelled),
      ('pending', GivingPaymentState.pending),
      ('unknown', GivingPaymentState.pending),
    ]) {
      final status = GivingPaymentStatus.fromJson({
        'donation_id': 1,
        'provider': 'stripe',
        'status': scenario.$1,
      });
      expect(status.state, scenario.$2, reason: scenario.$1);
    }
  });

  test('campaign subscription parsing preserves its cancellation target', () {
    final subscription = GivingSubscription.fromJson({
      'id': 91,
      'source': 'campaign',
      'campaign_id': 42,
      'campaign_title': 'School meals',
      'amount': '25.00',
      'currency': 'USD',
      'frequency': 'monthly',
      'method': 'stripe',
      'next_payment_date': '2026-08-20',
      'created_at': '2026-07-20T12:00:00Z',
    });

    expect(subscription.id, 91);
    expect(subscription.frequency, GivingFrequency.monthly);
    expect(subscription.nextPaymentDate, DateTime(2026, 8, 20));
    expect(subscription.target, isA<CampaignGivingTarget>());
    expect((subscription.target as CampaignGivingTarget).campaignId, 42);
  });

  test('campaign parsing preserves configured donor form fields', () {
    final campaign = GivingCampaign.fromJson({
      'id': 42,
      'title': 'School meals',
      'accepts_cash': true,
      'form_fields': [
        {
          'id': 8,
          'label': 'Dietary requirements',
          'name': 'dietary_requirements',
          'type': 'textarea',
          'placeholder': 'Tell us what we should know',
          'help_text': 'Do not include medical records.',
          'required': true,
          'sort_order': 2,
          'options': <String>[],
        },
      ],
    });

    expect(campaign.formFields, hasLength(1));
    expect(campaign.formFields.single.name, 'dietary_requirements');
    expect(campaign.formFields.single.type, 'textarea');
    expect(campaign.formFields.single.required, isTrue);
    expect(campaign.formFields.single.sortOrder, 2);
  });

  testWidgets(
    'campaign view validates and submits configured donor form fields',
    (tester) async {
      const fields = [
        GivingCampaignFormField(
          id: 8,
          label: 'Dietary requirements',
          name: 'dietary_requirements',
          type: 'textarea',
          required: true,
        ),
        GivingCampaignFormField(
          id: 9,
          label: 'I agree',
          name: 'consent',
          type: 'checkbox',
          required: true,
        ),
      ];
      final api = _FakeGivingApi(campaignFormFields: fields);
      final giving = TheFaithAppGiving.testing(
        api: api,
        paymentHandlers: const [_TestPaymentHandler()],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GivingView.campaign(giving: giving, campaignId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Additional information'), findsOneWidget);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Amount'),
        '25',
      );
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('This field is required.'), findsNWidgets(2));
      expect(api.campaignCheckoutCalls, 0);

      await tester.enterText(
        find.widgetWithText(TextFormField, 'Dietary requirements *'),
        '  Vegetarian  ',
      );
      await tester.ensureVisible(find.text('I agree *'));
      await tester.tap(find.text('I agree *'));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(api.campaignCheckoutCalls, 1);
      expect(api.campaignRequest?.formFields, {
        'dietary_requirements': 'Vegetarian',
        'consent': true,
      });
    },
  );

  testWidgets('general view adds and removes split-fund allocations', (
    tester,
  ) async {
    final giving = TheFaithAppGiving.testing(
      api: _FakeGivingApi(
        funds: const [
          GivingFund(id: 7, name: 'General fund'),
          GivingFund(id: 8, name: 'Missions'),
        ],
      ),
      paymentHandlers: const [_TestPaymentHandler()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GivingView.general(giving: giving)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Split across another fund'), findsOneWidget);
    expect(find.byTooltip('Remove'), findsNothing);
    await tester.tap(find.text('Split across another fund'));
    await tester.pump();
    expect(find.byTooltip('Remove'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Remove').first);
    await tester.pump();
    expect(find.byTooltip('Remove'), findsNothing);
  });

  testWidgets('giving selectors fit on a narrow phone with long fund names', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final giving = TheFaithAppGiving.testing(
      api: _FakeGivingApi(
        funds: const [
          GivingFund(
            id: 7,
            name: 'Church building and community outreach fund',
          ),
        ],
      ),
      paymentHandlers: const [_TestPaymentHandler()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: GivingView.general(giving: giving)),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('prayer-room view hides recurring and memo controls', (
    tester,
  ) async {
    final giving = TheFaithAppGiving.testing(
      api: _FakeGivingApi(coverFeesEnabled: true),
      paymentHandlers: const [_TestPaymentHandler()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GivingView.general(
            giving: giving,
            prayerRoomId: 19,
            showMemo: false,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Frequency'), findsNothing);
    expect(find.text('Memo (optional)'), findsNothing);
    expect(find.text('Help cover processing fees'), findsOneWidget);
    expect(find.text('2.5%'), findsOneWidget);
  });

  testWidgets('campaign view rejects campaigns that do not accept cash', (
    tester,
  ) async {
    Object? reportedError;
    final giving = TheFaithAppGiving.testing(
      api: _FakeGivingApi(campaignAcceptsCash: false),
      paymentHandlers: const [_TestPaymentHandler()],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GivingView.campaign(
            giving: giving,
            campaignId: 42,
            onError: (error, _) => reportedError = error,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('This campaign does not accept cash gifts.'),
      findsOneWidget,
    );
    expect(
      reportedError,
      isA<GivingException>().having(
        (error) => error.code,
        'code',
        GivingErrorCode.unavailable,
      ),
    );
  });
}

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext context;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    ),
  );
  return context;
}

final class _TestPaymentHandler implements GivingPaymentHandler {
  const _TestPaymentHandler();

  @override
  String get provider => 'testpay';

  @override
  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  ) async {
    final status = await checkout.waitForAuthoritativeStatus();
    return GivingPaymentResult(
      donationId: checkout.session.donationId,
      provider: provider,
      state: status.state,
    );
  }
}

final class _FixedResultPaymentHandler implements GivingPaymentHandler {
  const _FixedResultPaymentHandler(
    this.provider,
    this.state, {
    this.resultDonationId,
    this.resultProvider,
  });

  @override
  final String provider;
  final GivingPaymentState state;
  final int? resultDonationId;
  final String? resultProvider;

  @override
  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  ) async => GivingPaymentResult(
    donationId: resultDonationId ?? checkout.session.donationId,
    provider: resultProvider ?? provider,
    state: state,
  );
}

final class _FakeGivingApi implements GivingApi {
  _FakeGivingApi({
    this.campaignDescription,
    this.campaignAcceptsCash = true,
    this.defaultProvider = 'testpay',
    this.availableProviders = const ['testpay'],
    this.coverFeesEnabled = true,
    this.recurringGivingEnabled = true,
    this.funds = const [GivingFund(id: 7, name: 'General fund')],
    this.campaignFormFields = const [],
    this.statusStates = const [GivingPaymentState.succeeded],
    this.abandonThrows = false,
    this.subscriptions = const [],
    this.checkoutProvider,
    this.statusProvider,
    this.statusDonationId,
    this.configReady,
  }) : assert(statusStates.isNotEmpty);

  final String? campaignDescription;
  final bool campaignAcceptsCash;
  final String? defaultProvider;
  final List<String> availableProviders;
  final bool coverFeesEnabled;
  final bool recurringGivingEnabled;
  final List<GivingFund> funds;
  final List<GivingCampaignFormField> campaignFormFields;
  final List<GivingPaymentState> statusStates;
  final bool abandonThrows;
  final List<GivingSubscription> subscriptions;
  final String? checkoutProvider;
  final String? statusProvider;
  final int? statusDonationId;
  final Completer<void>? configReady;
  int fundsCalls = 0;
  GeneralGivingRequest? generalRequest;
  CampaignGivingRequest? campaignRequest;
  int? campaignId;
  GivingTarget? statusTarget;
  int generalCheckoutCalls = 0;
  int campaignCheckoutCalls = 0;
  int statusCalls = 0;
  int abandonCalls = 0;
  final List<GivingTarget> abandonedTargets = [];
  final List<int> abandonedDonationIds = [];
  GivingTarget? cancelledSubscriptionTarget;
  int? cancelledSubscriptionId;

  @override
  Uri get apiOrigin => Uri.parse('https://api.thefaithapp.com');

  @override
  Future<void> abandonCheckout(GivingTarget target, int donationId) async {
    abandonCalls++;
    abandonedTargets.add(target);
    abandonedDonationIds.add(donationId);
    if (abandonThrows) throw Exception('offline');
  }

  @override
  Future<void> capturePayPal(
    GivingTarget target,
    GivingCheckoutSession session,
  ) async {}

  @override
  Future<void> cancelSubscription(
    GivingTarget target,
    int subscriptionId,
  ) async {
    cancelledSubscriptionTarget = target;
    cancelledSubscriptionId = subscriptionId;
  }

  @override
  Future<GivingCheckoutSession> checkoutCampaign(
    int campaignId,
    CampaignGivingRequest request,
    String provider,
  ) async {
    campaignCheckoutCalls++;
    this.campaignId = campaignId;
    campaignRequest = request;
    return GivingCheckoutSession(
      provider: checkoutProvider ?? provider,
      donationId: 202,
      clientSecret: provider == 'stripe' ? 'pi_campaign_secret_test' : null,
      publishableKey: provider == 'stripe' ? 'pk_test_campaign' : null,
      stripeConnectAccountId: provider == 'stripe' ? 'acct_campaign' : null,
    );
  }

  @override
  Future<GivingCheckoutSession> checkoutGeneral(
    GeneralGivingRequest request,
    String provider,
  ) async {
    generalCheckoutCalls++;
    generalRequest = request;
    return GivingCheckoutSession(
      provider: checkoutProvider ?? provider,
      donationId: 101,
      clientSecret: provider == 'stripe' ? 'pi_giving_secret_test' : null,
      publishableKey: provider == 'stripe' ? 'pk_test_giving' : null,
      stripeConnectAccountId: provider == 'stripe' ? 'acct_giving' : null,
    );
  }

  @override
  void close() {}

  @override
  Future<GivingCampaign> getCampaign(int campaignId) async => GivingCampaign(
    id: campaignId,
    title: 'School supplies',
    acceptsCash: campaignAcceptsCash,
    description: campaignDescription,
    formFields: campaignFormFields,
  );

  @override
  Future<GivingConfig> getConfig() async {
    await configReady?.future;
    return GivingConfig(
      defaultPaymentProvider: defaultProvider,
      availableProviders: availableProviders,
      defaultCurrency: 'USD',
      supportedCurrencies: const [
        SupportedCurrency(code: 'USD', name: 'US Dollar', symbol: r'$'),
      ],
      coverFeesEnabled: coverFeesEnabled,
      recurringGivingEnabled: recurringGivingEnabled,
      coverFeesPercentage: coverFeesEnabled ? 2.5 : null,
    );
  }

  @override
  Future<List<GivingFund>> getFunds() async {
    fundsCalls++;
    return funds;
  }

  @override
  Future<List<GivingSubscription>> getSubscriptions() async => subscriptions;

  @override
  Future<GivingPaymentStatus> getStatus(
    GivingTarget target,
    int donationId,
  ) async {
    statusTarget = target;
    final index = statusCalls < statusStates.length
        ? statusCalls
        : statusStates.length - 1;
    statusCalls++;
    return GivingPaymentStatus(
      donationId: statusDonationId ?? donationId,
      state: statusStates[index],
      provider:
          statusProvider ?? checkoutProvider ?? defaultProvider ?? 'testpay',
    );
  }

  @override
  Future<void> verifyFlutterwave(
    GivingTarget target,
    GivingCheckoutSession session,
    String transactionId,
  ) async {}
}
