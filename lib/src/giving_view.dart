import 'package:flutter/material.dart';

import 'exceptions.dart';
import 'giving_client.dart';
import 'models.dart';

typedef GivingCompletedCallback = void Function(GivingPaymentResult result);
typedef GivingErrorCallback =
    void Function(Object error, StackTrace stackTrace);

/// Copy used by [GivingView]. Supply this to localize or adjust the UI.
final class GivingStrings {
  const GivingStrings({
    this.generalTitle = 'Give',
    this.campaignTitle = 'Give to campaign',
    this.amount = 'Amount',
    this.fund = 'Fund',
    this.currency = 'Currency',
    this.frequency = 'Frequency',
    this.memo = 'Memo (optional)',
    this.coverFees = 'Help cover processing fees',
    this.additionalInformation = 'Additional information',
    this.addFund = 'Split across another fund',
    this.remove = 'Remove',
    this.submit = 'Continue',
    this.requiredField = 'This field is required.',
    this.selectDate = 'Select date',
    this.loading = 'Loading giving options…',
    this.processing = 'Preparing secure checkout…',
    this.unavailable = 'Giving is not currently available.',
    this.pending = 'Your payment is processing. It will appear once confirmed.',
    this.success = 'Thank you. Your gift was confirmed.',
    this.cancelled = 'Payment cancelled.',
    this.failed = 'Payment could not be confirmed.',
  });

  final String generalTitle;
  final String campaignTitle;
  final String amount;
  final String fund;
  final String currency;
  final String frequency;
  final String memo;
  final String coverFees;
  final String additionalInformation;
  final String addFund;
  final String remove;
  final String submit;
  final String requiredField;
  final String selectDate;
  final String loading;
  final String processing;
  final String unavailable;
  final String pending;
  final String success;
  final String cancelled;
  final String failed;
}

/// A complete authenticated giving form for either general giving or a cash
/// campaign donation. The church's active/default payment method is rendered;
/// donors are not asked to choose between differently configured providers.
final class GivingView extends StatefulWidget {
  const GivingView.general({
    super.key,
    required this.giving,
    this.prayerRoomId,
    this.strings = const GivingStrings(),
    this.onCompleted,
    this.onError,
    this.allowRecurring = true,
    this.showMemo = true,
    this.padding = const EdgeInsets.all(20),
  }) : target = const GeneralGivingTarget();

  GivingView.campaign({
    super.key,
    required this.giving,
    required int campaignId,
    this.strings = const GivingStrings(),
    this.onCompleted,
    this.onError,
    this.allowRecurring = true,
    this.showMemo = true,
    this.padding = const EdgeInsets.all(20),
  }) : target = CampaignGivingTarget(campaignId),
       prayerRoomId = null;

  final TheFaithAppGiving giving;
  final GivingTarget target;
  final int? prayerRoomId;
  final GivingStrings strings;
  final GivingCompletedCallback? onCompleted;
  final GivingErrorCallback? onError;
  final bool allowRecurring;
  final bool showMemo;
  final EdgeInsetsGeometry padding;

  @override
  State<GivingView> createState() => _GivingViewState();
}

final class _GivingViewState extends State<GivingView> {
  final _formKey = GlobalKey<FormState>();
  final _memoController = TextEditingController();
  final List<_AllocationInput> _allocations = [_AllocationInput()];
  final Map<String, Object?> _campaignFieldValues = {};
  GivingConfig? _config;
  List<GivingFund> _funds = const [];
  GivingCampaign? _campaign;
  GivingFrequency _frequency = GivingFrequency.oneTime;
  String? _currency;
  Object? _loadError;
  bool _coverFees = false;
  bool _loading = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final (config, funds, campaign) = await (
        widget.giving.getConfig(),
        widget.target is GeneralGivingTarget
            ? widget.giving.getFunds()
            : Future.value(const <GivingFund>[]),
        switch (widget.target) {
          CampaignGivingTarget(:final campaignId) => widget.giving.getCampaign(
            campaignId,
          ),
          GeneralGivingTarget() => Future<GivingCampaign?>.value(),
        },
      ).wait;
      if (campaign != null && !campaign.acceptsCash) {
        throw const GivingException(
          GivingErrorCode.unavailable,
          'This campaign does not accept cash gifts.',
        );
      }
      if (!mounted) return;
      setState(() {
        _config = config;
        _funds = funds;
        _campaign = campaign;
        _currency =
            config.supportedCurrencies.any(
              (currency) => currency.code == config.defaultCurrency,
            )
            ? config.defaultCurrency
            : config.supportedCurrencies.first.code;
        _loading = false;
      });
    } on Object catch (error, stack) {
      widget.onError?.call(error, stack);
      if (!mounted) return;
      setState(() {
        _loadError = error;
        _loading = false;
      });
    }
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final config = _config;
    final currency = _currency;
    if (config == null || currency == null) return;
    setState(() => _submitting = true);
    try {
      final GivingPaymentResult result;
      switch (widget.target) {
        case GeneralGivingTarget():
          result = await widget.giving.give(
            context,
            GeneralGivingRequest(
              allocations: _allocations
                  .map(
                    (input) => GivingAllocation(
                      amount: _parseAmount(input.amount.text)!,
                      fundId: input.fundId,
                    ),
                  )
                  .toList(growable: false),
              currency: currency,
              frequency:
                  widget.allowRecurring &&
                      widget.prayerRoomId == null &&
                      config.recurringGivingEnabled
                  ? _frequency
                  : GivingFrequency.oneTime,
              memo: _memoController.text,
              coverFees: _coverFees,
              prayerRoomId: widget.prayerRoomId,
            ),
          );
        case CampaignGivingTarget(:final campaignId):
          result = await widget.giving.giveToCampaign(
            context,
            campaignId,
            CampaignGivingRequest(
              amount: _parseAmount(_allocations.first.amount.text)!,
              currency: currency,
              frequency: widget.allowRecurring && config.recurringGivingEnabled
                  ? _frequency
                  : GivingFrequency.oneTime,
              memo: _memoController.text,
              coverFees: _coverFees,
              formFields: _campaignFormValues(),
            ),
          );
      }
      widget.onCompleted?.call(result);
      if (mounted) _showResult(result);
    } on Object catch (error, stack) {
      widget.onError?.call(error, stack);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showResult(GivingPaymentResult result) {
    final message = switch (result.state) {
      GivingPaymentState.succeeded => widget.strings.success,
      GivingPaymentState.pending => widget.strings.pending,
      GivingPaymentState.cancelled => widget.strings.cancelled,
      GivingPaymentState.failed => widget.strings.failed,
    };
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _memoController.dispose();
    for (final allocation in _allocations) {
      allocation.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Center(
        child: Semantics(
          label: widget.strings.loading,
          child: const CircularProgressIndicator(),
        ),
      );
    }
    if (_loadError != null) {
      return Center(child: Text(_loadError.toString()));
    }
    final config = _config!;
    final campaignFields =
        _campaign?.formFields ?? const <GivingCampaignFormField>[];
    if (config.activeProvider == null) {
      return Center(child: Text(widget.strings.unavailable));
    }
    return SingleChildScrollView(
      padding: widget.padding,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _campaign?.title ?? widget.strings.generalTitle,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (_campaign?.description case final description?) ...[
              const SizedBox(height: 8),
              Text(_plainTextFromHtml(description)),
            ],
            const SizedBox(height: 20),
            for (var index = 0; index < _allocations.length; index++)
              _allocationFields(index),
            if (widget.target is GeneralGivingTarget &&
                _funds.length > _allocations.length)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addAllocation,
                  icon: const Icon(Icons.add),
                  label: Text(widget.strings.addFund),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              decoration: InputDecoration(labelText: widget.strings.currency),
              items: config.supportedCurrencies
                  .map(
                    (currency) => DropdownMenuItem(
                      value: currency.code,
                      child: Text(
                        '${currency.code} — ${currency.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _currency = value),
            ),
            if (widget.allowRecurring &&
                widget.prayerRoomId == null &&
                config.recurringGivingEnabled) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<GivingFrequency>(
                initialValue: _frequency,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: widget.strings.frequency,
                ),
                items: GivingFrequency.values
                    .map(
                      (frequency) => DropdownMenuItem(
                        value: frequency,
                        child: Text(
                          frequency.label,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) {
                  if (value != null) setState(() => _frequency = value);
                },
              ),
            ],
            if (widget.showMemo) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _memoController,
                decoration: InputDecoration(labelText: widget.strings.memo),
                maxLength: 500,
                maxLines: 2,
              ),
            ],
            if (campaignFields.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text(
                widget.strings.additionalInformation,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              for (final field in campaignFields) _campaignFormField(field),
            ],
            if (config.coverFeesEnabled)
              CheckboxListTile(
                value: _coverFees,
                contentPadding: EdgeInsets.zero,
                title: Text(widget.strings.coverFees),
                subtitle: config.coverFeesPercentage == null
                    ? null
                    : Text('${config.coverFeesPercentage}%'),
                onChanged: (value) =>
                    setState(() => _coverFees = value ?? false),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child: _submitting
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 12),
                        Text(widget.strings.processing),
                      ],
                    )
                  : Text(widget.strings.submit),
            ),
          ],
        ),
      ),
    );
  }

  Widget _allocationFields(int index) {
    final allocation = _allocations[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.target is GeneralGivingTarget && _funds.isNotEmpty) ...[
            Expanded(
              child: DropdownButtonFormField<int>(
                initialValue: allocation.fundId ?? 0,
                isExpanded: true,
                decoration: InputDecoration(labelText: widget.strings.fund),
                items: [
                  const DropdownMenuItem<int>(value: 0, child: Text('General')),
                  ..._funds.map(
                    (fund) => DropdownMenuItem<int>(
                      value: fund.id,
                      child: Text(fund.name, overflow: TextOverflow.ellipsis),
                    ),
                  ),
                ],
                onChanged: (value) =>
                    allocation.fundId = value == 0 ? null : value,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: TextFormField(
              controller: allocation.amount,
              decoration: InputDecoration(labelText: widget.strings.amount),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofillHints: const [AutofillHints.transactionAmount],
              validator: (value) {
                final amount = _parseAmount(value ?? '');
                return amount == null || amount < 1
                    ? 'Enter an amount of at least 1'
                    : null;
              },
            ),
          ),
          if (_allocations.length > 1)
            IconButton(
              tooltip: widget.strings.remove,
              onPressed: () => _removeAllocation(index),
              icon: const Icon(Icons.remove_circle_outline),
            ),
        ],
      ),
    );
  }

  void _addAllocation() => setState(() {
    _allocations.add(_AllocationInput());
  });

  void _removeAllocation(int index) => setState(() {
    _allocations.removeAt(index).dispose();
  });

  Widget _campaignFormField(GivingCampaignFormField field) {
    final label = '${field.label}${field.required ? ' *' : ''}';
    final decoration = InputDecoration(
      labelText: label,
      hintText: field.placeholder,
      helperText: field.helpText,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: switch (field.type) {
        'select' => DropdownButtonFormField<String>(
          initialValue: _campaignFieldValues[field.name] as String?,
          decoration: decoration,
          items: field.options
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(growable: false),
          validator: (value) => _requiredCampaignFieldError(field, value),
          onChanged: (value) =>
              setState(() => _campaignFieldValues[field.name] = value),
        ),
        'checkbox' => FormField<bool>(
          initialValue: _campaignFieldValues[field.name] == true,
          validator: (value) => field.required && value != true
              ? widget.strings.requiredField
              : null,
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CheckboxListTile(
                value: state.value ?? false,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(label),
                subtitle: field.helpText == null ? null : Text(field.helpText!),
                onChanged: (value) {
                  final selected = value ?? false;
                  state.didChange(selected);
                  setState(() => _campaignFieldValues[field.name] = selected);
                },
              ),
              if (state.errorText case final error?)
                Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        'radio' => FormField<String>(
          initialValue: _campaignFieldValues[field.name] as String?,
          validator: (value) => _requiredCampaignFieldError(field, value),
          builder: (state) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.bodyLarge),
              if (field.helpText case final help?)
                Text(help, style: Theme.of(context).textTheme.bodySmall),
              RadioGroup<String>(
                groupValue: state.value,
                onChanged: (value) {
                  state.didChange(value);
                  setState(() => _campaignFieldValues[field.name] = value);
                },
                child: Column(
                  children: [
                    for (final option in field.options)
                      RadioListTile<String>(
                        value: option,
                        title: Text(option),
                        contentPadding: EdgeInsets.zero,
                      ),
                  ],
                ),
              ),
              if (state.errorText case final error?)
                Text(
                  error,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
        'date' => FormField<String>(
          initialValue: _campaignFieldValues[field.name] as String?,
          validator: (value) => _requiredCampaignFieldError(field, value),
          builder: (state) => InkWell(
            onTap: () async {
              final now = DateTime.now();
              final current = DateTime.tryParse(state.value ?? '');
              final selected = await showDatePicker(
                context: context,
                initialDate: current ?? now,
                firstDate: DateTime(1900),
                lastDate: DateTime(now.year + 100),
              );
              if (selected == null) return;
              final value =
                  '${selected.year.toString().padLeft(4, '0')}-'
                  '${selected.month.toString().padLeft(2, '0')}-'
                  '${selected.day.toString().padLeft(2, '0')}';
              state.didChange(value);
              setState(() => _campaignFieldValues[field.name] = value);
            },
            child: InputDecorator(
              decoration: decoration.copyWith(errorText: state.errorText),
              isEmpty: state.value == null || state.value!.isEmpty,
              child: Text(
                state.value ?? widget.strings.selectDate,
                style: state.value == null
                    ? Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).hintColor,
                      )
                    : null,
              ),
            ),
          ),
        ),
        _ => TextFormField(
          initialValue: _campaignFieldValues[field.name]?.toString(),
          decoration: decoration,
          maxLines: field.type == 'textarea' ? 3 : 1,
          keyboardType: switch (field.type) {
            'number' => const TextInputType.numberWithOptions(decimal: true),
            'email' => TextInputType.emailAddress,
            'tel' => TextInputType.phone,
            _ => TextInputType.text,
          },
          validator: (value) => _requiredCampaignFieldError(field, value),
          onChanged: (value) => _campaignFieldValues[field.name] = value,
        ),
      },
    );
  }

  String? _requiredCampaignFieldError(
    GivingCampaignFormField field,
    Object? value,
  ) {
    if (!field.required) return null;
    return value == null || (value is String && value.trim().isEmpty)
        ? widget.strings.requiredField
        : null;
  }

  Map<String, Object?> _campaignFormValues() {
    final fields = _campaign?.formFields ?? const <GivingCampaignFormField>[];
    return <String, Object?>{
      for (final field in fields)
        if (_campaignFieldValues[field.name] case final value?
            when value is! String || value.trim().isNotEmpty)
          field.name: value is String ? value.trim() : value,
    };
  }
}

String _plainTextFromHtml(String value) {
  final withLineBreaks = value
      .replaceAll(RegExp(r'<\s*br\s*/?\s*>', caseSensitive: false), '\n')
      .replaceAll(
        RegExp(r'</\s*(?:p|div|li|h[1-6])\s*>', caseSensitive: false),
        '\n',
      );
  final withoutTags = withLineBreaks.replaceAll(RegExp(r'<[^>]*>'), '');
  final decoded = withoutTags
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
  return decoded
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
}

final class _AllocationInput {
  final TextEditingController amount = TextEditingController();
  int? fundId;

  void dispose() => amount.dispose();
}

double? _parseAmount(String value) {
  final normalized = value.trim().replaceAll(',', '');
  final amount = double.tryParse(normalized);
  return amount != null && amount.isFinite ? amount : null;
}
