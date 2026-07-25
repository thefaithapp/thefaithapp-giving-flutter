import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../exceptions.dart';
import '../models.dart';
import 'payment_handler.dart';

final class PayPalGivingPaymentHandler implements GivingPaymentHandler {
  const PayPalGivingPaymentHandler();

  @override
  String get provider => 'paypal';

  @override
  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  ) async {
    final approvalUrl = checkout.session.approvalUrl;
    if (approvalUrl == null || approvalUrl.scheme != 'https') {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'PayPal checkout URL is unavailable.',
      );
    }
    final isCampaign = checkout.target is CampaignGivingTarget;
    final state = await Navigator.of(context).push<GivingPaymentState>(
      MaterialPageRoute(
        builder: (_) => _HostedGivingPage(
          title: 'PayPal',
          approvalUrl: approvalUrl,
          apiOrigin: checkout.apiOrigin,
          donationId: checkout.session.donationId,
          successPaths: isCampaign
              ? const {'/paypal/campaigns/success'}
              : const {
                  '/paypal/giving/success',
                  '/paypal/giving/billing-approved',
                },
          cancelPaths: isCampaign
              ? const {'/paypal/campaigns/cancel'}
              : const {'/paypal/giving/cancel'},
          onApproved: (_) async {
            await checkout.capturePayPal();
            return (await checkout.waitForAuthoritativeStatus()).state;
          },
        ),
      ),
    );
    return GivingPaymentResult(
      donationId: checkout.session.donationId,
      provider: provider,
      state: state ?? GivingPaymentState.cancelled,
    );
  }
}

final class FlutterwaveGivingPaymentHandler implements GivingPaymentHandler {
  const FlutterwaveGivingPaymentHandler();

  @override
  String get provider => 'flutterwave';

  @override
  Future<GivingPaymentResult> present(
    BuildContext context,
    GivingCheckoutContext checkout,
  ) async {
    final approvalUrl = checkout.session.approvalUrl;
    if (approvalUrl == null || approvalUrl.scheme != 'https') {
      throw const GivingException(
        GivingErrorCode.malformedResponse,
        'Flutterwave checkout URL is unavailable.',
      );
    }
    final callbackPath = checkout.target is CampaignGivingTarget
        ? '/flutterwave/campaigns/callback'
        : '/flutterwave/giving/callback';
    final state = await Navigator.of(context).push<GivingPaymentState>(
      MaterialPageRoute(
        builder: (_) => _HostedGivingPage(
          title: 'Flutterwave',
          approvalUrl: approvalUrl,
          apiOrigin: checkout.apiOrigin,
          donationId: checkout.session.donationId,
          successPaths: {callbackPath},
          cancelPaths: const <String>{},
          onApproved: (callback) async {
            final callbackStatus = callback.queryParameters['status'];
            if (callbackStatus == 'cancelled' || callbackStatus == 'failed') {
              return callbackStatus == 'cancelled'
                  ? GivingPaymentState.cancelled
                  : GivingPaymentState.failed;
            }
            final transactionId =
                callback.queryParameters['transaction_id'] ??
                callback.queryParameters['id'];
            if (transactionId == null || transactionId.isEmpty) {
              throw const GivingException(
                GivingErrorCode.paymentFailed,
                'Flutterwave did not return a transaction identifier.',
              );
            }
            await checkout.verifyFlutterwave(transactionId);
            return (await checkout.waitForAuthoritativeStatus()).state;
          },
        ),
      ),
    );
    return GivingPaymentResult(
      donationId: checkout.session.donationId,
      provider: provider,
      state: state ?? GivingPaymentState.cancelled,
    );
  }
}

typedef _HostedApproval = Future<GivingPaymentState> Function(Uri callback);

final class _HostedGivingPage extends StatefulWidget {
  const _HostedGivingPage({
    required this.title,
    required this.approvalUrl,
    required this.apiOrigin,
    required this.donationId,
    required this.successPaths,
    required this.cancelPaths,
    required this.onApproved,
  });

  final String title;
  final Uri approvalUrl;
  final Uri apiOrigin;
  final int donationId;
  final Set<String> successPaths;
  final Set<String> cancelPaths;
  final _HostedApproval onApproved;

  @override
  State<_HostedGivingPage> createState() => _HostedGivingPageState();
}

final class _HostedGivingPageState extends State<_HostedGivingPage> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => _loading = true);
          },
          onPageFinished: (_) {
            if (mounted) setState(() => _loading = false);
          },
          onNavigationRequest: _onNavigationRequest,
        ),
      )
      ..loadRequest(widget.approvalUrl);
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final callback = Uri.tryParse(request.url);
    if (callback == null ||
        !isTrustedGivingCallback(
          callback,
          widget.apiOrigin,
          widget.donationId,
          {...widget.successPaths, ...widget.cancelPaths},
        )) {
      return NavigationDecision.navigate;
    }
    if (widget.cancelPaths.contains(callback.path)) {
      Navigator.of(context).pop(GivingPaymentState.cancelled);
      return NavigationDecision.prevent;
    }
    if (widget.successPaths.contains(callback.path)) {
      _complete(callback);
      return NavigationDecision.prevent;
    }
    return NavigationDecision.navigate;
  }

  Future<void> _complete(Uri callback) async {
    if (_finishing) return;
    setState(() => _finishing = true);
    try {
      final state = await widget.onApproved(callback);
      if (mounted) Navigator.of(context).pop(state);
    } on Object {
      if (mounted) Navigator.of(context).pop(GivingPaymentState.failed);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.title),
      leading: IconButton(
        icon: const Icon(Icons.close),
        onPressed: () =>
            Navigator.of(context).pop(GivingPaymentState.cancelled),
      ),
    ),
    body: Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading || _finishing)
          const ColoredBox(
            color: Color(0x99FFFFFF),
            child: Center(child: CircularProgressIndicator()),
          ),
      ],
    ),
  );
}

@visibleForTesting
bool isTrustedGivingCallback(
  Uri callback,
  Uri apiOrigin,
  int donationId,
  Set<String> allowedPaths,
) {
  final callbackScheme = callback.scheme.toLowerCase();
  final callbackHost = callback.host.toLowerCase();
  final isLoopback =
      callbackHost == 'localhost' ||
      callbackHost == '127.0.0.1' ||
      callbackHost == '::1';
  final isSecureTransport =
      callbackScheme == 'https' || (callbackScheme == 'http' && isLoopback);
  if (!isSecureTransport ||
      callbackScheme != apiOrigin.scheme.toLowerCase() ||
      callback.host.toLowerCase() != apiOrigin.host.toLowerCase() ||
      callback.port != apiOrigin.port ||
      !allowedPaths.contains(callback.path)) {
    return false;
  }
  return callback.queryParameters['donation_id'] == donationId.toString();
}
