import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../targets/promotion_target.dart';

final class PromotionTargetDirectoryPage extends StatefulWidget {
  const PromotionTargetDirectoryPage({
    super.key,
    required this.text,
    required this.gateway,
    required this.idGenerator,
    required this.canCreate,
  });

  final AppStrings text;
  final PromotionTargetGateway gateway;
  final IdGenerator idGenerator;
  final bool canCreate;

  @override
  State<PromotionTargetDirectoryPage> createState() =>
      _PromotionTargetDirectoryPageState();
}

final class _PromotionTargetDirectoryPageState
    extends State<PromotionTargetDirectoryPage> {
  List<PromotionTargetProfile>? _targets;
  PromotionTargetFailureCode? _failure;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          text.t('targetsTitle'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        Text(text.t('targetsPrivacyHelp')),
        const SizedBox(height: 16),
        if (_busy && _targets == null)
          const Center(child: CircularProgressIndicator())
        else if (_targets == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.cloud_off_outlined),
              title: Text(text.t('targetsOnlineRequired')),
              trailing: IconButton(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh_outlined),
              ),
            ),
          )
        else if (_targets!.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.person_off_outlined),
              title: Text(text.t('targetsEmpty')),
              subtitle: Text(text.t('targetsAnonymousDefault')),
            ),
          )
        else
          for (final target in _targets!) _targetCard(text, target),
        if (_failure != null && _targets != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              text.t('targetsOperationFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.canCreate) ...[
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('create-promotion-target'),
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.person_add_alt_1_outlined),
            label: Text(text.t('targetsCreate')),
          ),
        ],
      ],
    );
  }

  Widget _targetCard(AppStrings text, PromotionTargetProfile target) {
    final details = [
      if (target.phone != null) '${text.t('targetsPhone')}: ${target.phone}',
      if (target.email != null) '${text.t('targetsEmail')}: ${target.email}',
    ];
    return Card(
      key: ValueKey('promotion-target-${target.id}'),
      child: ListTile(
        leading: Icon(
          target.type == PromotionTargetType.person
              ? Icons.person_outline
              : Icons.business_outlined,
        ),
        title: Text(target.displayName),
        subtitle: Text(
          [
            target.type == PromotionTargetType.person
                ? text.t('targetsPerson')
                : text.t('targetsInstitution'),
            ...details,
          ].join('\n'),
        ),
      ),
    );
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.loadAssigned();
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        setState(() {
          _targets = value;
          _busy = false;
        });
      case PromotionTargetRejected(:final code):
        setState(() {
          _failure = code;
          _busy = false;
        });
    }
  }

  Future<void> _create() async {
    final input = await showDialog<_TargetInput>(
      context: context,
      builder: (context) => _CreateTargetDialog(text: widget.text),
    );
    if (input == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.create(
      type: input.type,
      displayName: input.displayName,
      phone: input.phone,
      email: input.email,
      requestId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    if (result case PromotionTargetRejected(:final code)) {
      setState(() {
        _failure = code;
        _busy = false;
      });
      return;
    }
    await _load();
  }
}

final class _CreateTargetDialog extends StatefulWidget {
  const _CreateTargetDialog({required this.text});

  final AppStrings text;

  @override
  State<_CreateTargetDialog> createState() => _CreateTargetDialogState();
}

final class _CreateTargetDialogState extends State<_CreateTargetDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  var _type = PromotionTargetType.person;
  var _confirmed = false;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.t('targetsCreate')),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<PromotionTargetType>(
            segments: [
              ButtonSegment(
                value: PromotionTargetType.person,
                label: Text(widget.text.t('targetsPerson')),
              ),
              ButtonSegment(
                value: PromotionTargetType.institution,
                label: Text(widget.text.t('targetsInstitution')),
              ),
            ],
            selected: {_type},
            onSelectionChanged: (value) => setState(() => _type = value.single),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('promotion-target-name'),
            controller: _name,
            maxLength: 200,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsName'),
            ),
            onChanged: (_) => setState(() {}),
          ),
          TextField(
            key: const ValueKey('promotion-target-phone'),
            controller: _phone,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsPhone'),
            ),
          ),
          TextField(
            key: const ValueKey('promotion-target-email'),
            controller: _email,
            maxLength: 320,
            decoration: InputDecoration(
              labelText: widget.text.t('targetsEmail'),
            ),
          ),
          CheckboxListTile(
            key: const ValueKey('promotion-target-purpose-confirmed'),
            value: _confirmed,
            onChanged: (value) => setState(() => _confirmed = value ?? false),
            title: Text(widget.text.t('targetsPurposeConfirmation')),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('confirm-promotion-target'),
        onPressed: _confirmed && _name.text.trim().isNotEmpty
            ? () => Navigator.pop(
                context,
                _TargetInput(
                  type: _type,
                  displayName: _name.text.trim(),
                  phone: _nullable(_phone.text),
                  email: _nullable(_email.text),
                ),
              )
            : null,
        child: Text(widget.text.t('create')),
      ),
    ],
  );
}

final class _TargetInput {
  const _TargetInput({
    required this.type,
    required this.displayName,
    required this.phone,
    required this.email,
  });

  final PromotionTargetType type;
  final String displayName;
  final String? phone;
  final String? email;
}

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
