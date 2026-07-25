import 'package:flutter/material.dart';
import 'package:thefaithapp_auth/thefaithapp_auth.dart';
import 'package:thefaithapp_giving/thefaithapp_giving.dart';

void main() => runApp(const GivingExampleApp());

class GivingExampleApp extends StatefulWidget {
  const GivingExampleApp({super.key});

  @override
  State<GivingExampleApp> createState() => _GivingExampleAppState();
}

class _GivingExampleAppState extends State<GivingExampleApp> {
  static const _campaignId = int.fromEnvironment('THEFAITHAPP_CAMPAIGN_ID');
  final _auth = TheFaithAppAuth(
    apiKey: const String.fromEnvironment(
      'THEFAITHAPP_API_KEY',
      defaultValue: 'your-client-key',
    ),
  );
  late final TheFaithAppGiving _giving = TheFaithAppGiving(auth: _auth);
  bool _signedIn = false;

  @override
  void dispose() {
    _giving.dispose();
    _auth.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'TheFaithApp Giving',
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(
      appBar: AppBar(title: const Text('Giving example')),
      body: _signedIn
          ? _givingViews()
          : Center(
              child: FilledButton(
                onPressed: _signIn,
                child: const Text('Sign in to give'),
              ),
            ),
    ),
  );

  Widget _givingViews() {
    if (_campaignId < 1) return GivingView.general(giving: _giving);
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'General'),
              Tab(text: 'Campaign'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                GivingView.general(giving: _giving),
                GivingView.campaign(giving: _giving, campaignId: _campaignId),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    await _auth.signIn();
    if (mounted) setState(() => _signedIn = true);
  }
}
