import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../targets/promotion_target.dart';

final class TargetInstitutionRelationshipPanel extends StatefulWidget {
  const TargetInstitutionRelationshipPanel({
    super.key,
    required this.text,
    required this.gateway,
    required this.idGenerator,
    required this.targets,
    required this.canManage,
  });

  final AppStrings text;
  final PromotionTargetGateway gateway;
  final IdGenerator idGenerator;
  final List<PromotionTargetProfile> targets;
  final bool canManage;

  @override
  State<TargetInstitutionRelationshipPanel> createState() =>
      _TargetInstitutionRelationshipPanelState();
}

final class _TargetInstitutionRelationshipPanelState
    extends State<TargetInstitutionRelationshipPanel> {
  List<TargetInstitutionRelationship>? _relationships;
  PromotionTargetFailureCode? _failure;
  var _busy = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final people = widget.targets
        .where((target) => target.type == PromotionTargetType.person)
        .toList();
    final institutions = widget.targets
        .where((target) => target.type == PromotionTargetType.institution)
        .toList();
    return Column(
      key: const ValueKey('target-institution-relationships'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 32),
        Text(
          widget.text.t('targetInstitutionRelationshipsTitle'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(widget.text.t('targetInstitutionRelationshipsHelp')),
        const SizedBox(height: 12),
        if (_busy && _relationships == null)
          const Center(child: CircularProgressIndicator())
        else if (_relationships == null)
          _failureCard()
        else if (_relationships!.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.hub_outlined),
              title: Text(widget.text.t('targetInstitutionRelationshipsEmpty')),
            ),
          )
        else
          for (final relationship in _relationships!)
            _relationshipCard(relationship),
        if (_failure != null && _relationships != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              widget.text.t('targetInstitutionRelationshipsFailed'),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        if (widget.canManage &&
            people.isNotEmpty &&
            institutions.isNotEmpty) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('create-target-institution-relationship'),
            onPressed: _busy ? null : () => _create(people, institutions),
            icon: const Icon(Icons.add_link_outlined),
            label: Text(widget.text.t('targetInstitutionRelationshipsCreate')),
          ),
        ],
      ],
    );
  }

  Widget _failureCard() => Card(
    child: ListTile(
      leading: const Icon(Icons.cloud_off_outlined),
      title: Text(widget.text.t('targetInstitutionRelationshipsFailed')),
      trailing: IconButton(
        onPressed: _busy ? null : _load,
        icon: const Icon(Icons.refresh_outlined),
      ),
    ),
  );

  Widget _relationshipCard(TargetInstitutionRelationship relationship) {
    final person = _target(relationship.personTargetId);
    final institution = _target(relationship.institutionTargetId);
    if (person == null || institution == null) return const SizedBox.shrink();
    return Card(
      key: ValueKey('target-institution-relationship-${relationship.id}'),
      child: ListTile(
        leading: const Icon(Icons.account_tree_outlined),
        title: Text('${person.displayName} ↔ ${institution.displayName}'),
        subtitle: Text(
          [
            widget.text.t(
              'targetInstitutionRelationshipKind.${relationship.kind.storageValue}',
            ),
            if (relationship.roleDescription != null)
              relationship.roleDescription!,
            '${widget.text.t('targetInstitutionRelationshipStarted')}: '
                '${_date(relationship.startedAtUtc)}',
            if (relationship.endedAtUtc != null)
              '${widget.text.t('targetInstitutionRelationshipEnded')}: '
                  '${_date(relationship.endedAtUtc!)}',
            '${widget.text.t('targetInstitutionRelationshipHistory')}: '
                '${relationship.history.length}',
          ].join('\n'),
        ),
        trailing:
            widget.canManage &&
                relationship.status ==
                    TargetInstitutionRelationshipStatus.active
            ? IconButton(
                key: ValueKey('end-target-institution-${relationship.id}'),
                tooltip: widget.text.t('targetInstitutionRelationshipEnd'),
                onPressed: _busy ? null : () => _end(relationship),
                icon: const Icon(Icons.link_off_outlined),
              )
            : null,
      ),
    );
  }

  PromotionTargetProfile? _target(String id) {
    for (final target in widget.targets) {
      if (target.id == id) return target;
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.loadInstitutionRelationships();
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        setState(() {
          _relationships = value;
          _busy = false;
        });
      case PromotionTargetRejected(:final code):
        setState(() {
          _failure = code;
          _busy = false;
        });
      case PromotionTargetConflict():
        setState(() {
          _failure = PromotionTargetFailureCode.conflict;
          _busy = false;
        });
    }
  }

  Future<void> _create(
    List<PromotionTargetProfile> people,
    List<PromotionTargetProfile> institutions,
  ) async {
    final input = await showDialog<_InstitutionRelationshipInput>(
      context: context,
      builder: (context) => _InstitutionRelationshipDialog(
        text: widget.text,
        people: people,
        institutions: institutions,
      ),
    );
    if (input == null || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.createInstitutionRelationship(
      personTargetId: input.personTargetId,
      institutionTargetId: input.institutionTargetId,
      kind: input.kind,
      roleDescription: input.roleDescription,
      mutationId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        setState(() {
          _relationships = [value, ...?_relationships];
          _busy = false;
        });
      case PromotionTargetRejected(:final code):
        setState(() {
          _failure = code;
          _busy = false;
        });
      case PromotionTargetConflict():
        await _load();
        if (mounted) {
          setState(() => _failure = PromotionTargetFailureCode.conflict);
        }
    }
  }

  Future<void> _end(TargetInstitutionRelationship relationship) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.text.t('targetInstitutionRelationshipEnd')),
        content: Text(widget.text.t('targetInstitutionRelationshipEndHelp')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(widget.text.t('cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-end-target-institution-relationship'),
            onPressed: () => Navigator.pop(context, true),
            child: Text(widget.text.t('targetInstitutionRelationshipEnd')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _busy = true;
      _failure = null;
    });
    final result = await widget.gateway.endInstitutionRelationship(
      relationshipId: relationship.id,
      expectedRevision: relationship.revisionNumber,
      mutationId: widget.idGenerator.next(),
    );
    if (!mounted) return;
    switch (result) {
      case PromotionTargetSuccess(:final value):
        setState(() {
          _relationships = _relationships
              ?.map((candidate) => candidate.id == value.id ? value : candidate)
              .toList();
          _busy = false;
        });
      case PromotionTargetRejected(:final code):
        if (code == PromotionTargetFailureCode.conflict) {
          await _load();
          if (mounted) {
            setState(() => _failure = code);
          }
        } else {
          setState(() {
            _failure = code;
            _busy = false;
          });
        }
      case PromotionTargetConflict():
        await _load();
        if (mounted) {
          setState(() => _failure = PromotionTargetFailureCode.conflict);
        }
    }
  }
}

final class _InstitutionRelationshipDialog extends StatefulWidget {
  const _InstitutionRelationshipDialog({
    required this.text,
    required this.people,
    required this.institutions,
  });

  final AppStrings text;
  final List<PromotionTargetProfile> people;
  final List<PromotionTargetProfile> institutions;

  @override
  State<_InstitutionRelationshipDialog> createState() =>
      _InstitutionRelationshipDialogState();
}

final class _InstitutionRelationshipDialogState
    extends State<_InstitutionRelationshipDialog> {
  late String _personTargetId;
  late String _institutionTargetId;
  var _kind = TargetInstitutionRelationshipKind.employmentRepresentative;
  final _role = TextEditingController();

  @override
  void initState() {
    super.initState();
    _personTargetId = widget.people.first.id;
    _institutionTargetId = widget.institutions.first.id;
  }

  @override
  void dispose() {
    _role.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _kind != TargetInstitutionRelationshipKind.other ||
      _role.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.text.t('targetInstitutionRelationshipsCreate')),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              key: const ValueKey('institution-relationship-person'),
              initialValue: _personTargetId,
              decoration: InputDecoration(
                labelText: widget.text.t('targetInstitutionRelationshipPerson'),
              ),
              items: [
                for (final target in widget.people)
                  DropdownMenuItem(
                    value: target.id,
                    child: Text(target.displayName),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _personTargetId = value ?? _personTargetId),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const ValueKey('institution-relationship-institution'),
              initialValue: _institutionTargetId,
              decoration: InputDecoration(
                labelText: widget.text.t(
                  'targetInstitutionRelationshipInstitution',
                ),
              ),
              items: [
                for (final target in widget.institutions)
                  DropdownMenuItem(
                    value: target.id,
                    child: Text(target.displayName),
                  ),
              ],
              onChanged: (value) => setState(
                () => _institutionTargetId = value ?? _institutionTargetId,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<TargetInstitutionRelationshipKind>(
              key: const ValueKey('institution-relationship-kind'),
              initialValue: _kind,
              decoration: InputDecoration(
                labelText: widget.text.t('targetInstitutionRelationshipKind'),
              ),
              items: [
                for (final kind in TargetInstitutionRelationshipKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(
                      widget.text.t(
                        'targetInstitutionRelationshipKind.${kind.storageValue}',
                      ),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _kind = value ?? _kind),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('institution-relationship-role'),
              controller: _role,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: widget.text.t('targetInstitutionRelationshipRole'),
                helperText: widget.text.t(
                  'targetInstitutionRelationshipRoleHelp',
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.text.t('cancel')),
      ),
      FilledButton(
        key: const ValueKey('save-target-institution-relationship'),
        onPressed: _canSave
            ? () => Navigator.pop(
                context,
                _InstitutionRelationshipInput(
                  personTargetId: _personTargetId,
                  institutionTargetId: _institutionTargetId,
                  kind: _kind,
                  roleDescription: _nullable(_role.text),
                ),
              )
            : null,
        child: Text(widget.text.t('save')),
      ),
    ],
  );
}

final class _InstitutionRelationshipInput {
  const _InstitutionRelationshipInput({
    required this.personTargetId,
    required this.institutionTargetId,
    required this.kind,
    required this.roleDescription,
  });

  final String personTargetId;
  final String institutionTargetId;
  final TargetInstitutionRelationshipKind kind;
  final String? roleDescription;
}

String _date(DateTime value) =>
    value.toUtc().toIso8601String().substring(0, 10);

String? _nullable(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}
