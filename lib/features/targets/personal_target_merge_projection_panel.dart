import 'package:flutter/material.dart';

import '../../app_session/app_session.dart';
import '../../identity/identity_session.dart';
import '../../l10n/app_strings.dart';
import '../../targets/personal_target_merge_projection.dart';
import '../../targets/promotion_target.dart';
import 'personal_target_merge_projection_read_controller.dart';

final class PersonalTargetMergeProjectionPanel extends StatefulWidget {
  const PersonalTargetMergeProjectionPanel({
    super.key,
    required this.text,
    required this.identitySession,
    required this.appSession,
    required this.gateway,
    required this.generationId,
  });

  final AppStrings text;
  final IdentitySession identitySession;
  final AppSession appSession;
  final PersonalTargetMergeProjectionGateway gateway;
  final String generationId;

  @override
  State<PersonalTargetMergeProjectionPanel> createState() =>
      _PersonalTargetMergeProjectionPanelState();
}

final class _PersonalTargetMergeProjectionPanelState
    extends State<PersonalTargetMergeProjectionPanel> {
  late PersonalTargetMergeProjectionReadController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = PersonalTargetMergeProjectionReadController(
      identitySession: widget.identitySession,
      appSession: widget.appSession,
      gateway: widget.gateway,
    );
  }

  @override
  void didUpdateWidget(PersonalTargetMergeProjectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.generationId != widget.generationId ||
        !identical(oldWidget.identitySession, widget.identitySession) ||
        !identical(oldWidget.appSession, widget.appSession) ||
        !identical(oldWidget.gateway, widget.gateway)) {
      _controller.dispose();
      _createController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _t(String key) => widget.text.t(key);
  String _value(Object? value) =>
      value?.toString() ?? _t('mergeProjectionMissing');
  String _utc(DateTime? value) =>
      value == null ? _value(null) : value.toUtc().toIso8601String();

  Widget _field(String label, Object? value) => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text('$label: ${_value(value)}', softWrap: true),
  );

  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 4),
    child: Semantics(
      header: true,
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    ),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final projection = _controller.projection;
      final failure = _controller.failure;
      return Column(
        key: const ValueKey('merge-projection-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              _t('mergeProjectionTitle'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 8),
          Text(_t('mergeProjectionSnapshotHelp')),
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: FilledButton.icon(
              key: const ValueKey('merge-projection-read'),
              onPressed: _controller.loading
                  ? null
                  : () => _controller.read(widget.generationId),
              icon: const Icon(Icons.refresh_outlined),
              label: Text(
                _t(
                  failure != null
                      ? 'mergeProjectionRetry'
                      : projection != null
                      ? 'mergeProjectionReload'
                      : 'mergeProjectionRead',
                ),
              ),
            ),
          ),
          if (_controller.loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_t('mergeProjectionLoading')),
          ] else if (failure != null) ...[
            const SizedBox(height: 12),
            Text(
              _t(
                failure ==
                        PersonalTargetMergeProjectionFailure.requestInvalidated
                    ? 'mergeProjectionInvalidated'
                    : 'mergeProjectionFailed',
              ),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ] else if (projection == null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_t('mergeProjectionEmpty')),
            )
          else
            _projection(projection),
        ],
      );
    },
  );

  Widget _projection(PersonalTargetMergeProjection projection) => Column(
    key: ObjectKey(projection),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _heading(_t('mergeProjectionDisplay')),
      _displayField(
        projection,
        'targetsName',
        projection.displayName,
        projection.displayNameSourceTargetId,
      ),
      _displayField(
        projection,
        'phone',
        projection.phone,
        projection.phoneSourceTargetId,
      ),
      _displayField(
        projection,
        'email',
        projection.email,
        projection.emailSourceTargetId,
      ),
      _field(_t('mergeProjectionRetainedId'), projection.retainedTargetId),
      _field(_t('mergeProjectionGeneration'), projection.generationId),
      _field(_t('mergeProjectionEarlierDue'), _utc(projection.reviewDueAtUtc)),
      for (var index = 0; index < projection.sources.length; index++)
        _source(projection.sources[index], index + 1),
    ],
  );

  String _sourceLabel(int number) =>
      widget.text.format('mergeProjectionSource', {'number': number});

  Widget _displayField(
    PersonalTargetMergeProjection projection,
    String label,
    String? value,
    String sourceId,
  ) {
    final index = projection.sources.indexWhere(
      (source) => source.targetId == sourceId,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${_t(label)}: ${_value(value)}'),
          Text(
            '${_sourceLabel(index + 1)} · $sourceId',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _source(PersonalTargetMergeProjectionSource source, int number) {
    final profile = source.profile;
    final relationship = source.projectRelationship;
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            key: ValueKey('merge-projection-source-$number'),
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: Text(
                  _sourceLabel(number),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              _field(_t('mergeProjectionSourceId'), source.targetId),
              _field(
                _t('mergeProjectionType'),
                _t(
                  profile.targetType == PromotionTargetType.person
                      ? 'targetsPerson'
                      : 'targetsInstitution',
                ),
              ),
              _field(_t('targetsName'), profile.displayName),
              _field(_t('phone'), profile.phone),
              _field(_t('email'), profile.email),
              _field(_t('mergeProjectionCreated'), _utc(profile.createdAtUtc)),
              _field(_t('mergeProjectionDue'), _utc(source.reviewDueAtUtc)),
              _heading(_t('mergeProjectionProjectRelationship')),
              if (relationship == null)
                Text(_t('targetsNoProjectRelationship'))
              else ...[
                _field(_t('mergeProjectionProjectId'), relationship.projectId),
                _field(_t('targetsRelationshipStage'), relationship.stage),
                _field(
                  _t('mergeProjectionDisplayStage'),
                  relationship.displayStage,
                ),
                _field(
                  _t('targetsRelationshipLifecycle'),
                  _t(
                    'targetsLifecycle.${relationship.lifecycleStatus.storageValue}',
                  ),
                ),
                _field(_t('targetsFollowUpNote'), relationship.followUpNote),
                _field(
                  _t('mergeProjectionRevision'),
                  relationship.revisionNumber,
                ),
                _field(
                  _t('mergeProjectionUpdated'),
                  _utc(relationship.updatedAtUtc),
                ),
                _heading(_t('mergeProjectionAliases')),
                if (relationship.stageAliases.isEmpty)
                  Text(_t('mergeProjectionNoAliases')),
                for (final alias in relationship.stageAliases)
                  _field(
                    '${_t('targetsRelationshipStage')} ${alias.stage} · '
                    '${_t('mergeProjectionDisplayStage')} ${alias.displayStage}',
                    alias.displayName,
                  ),
              ],
              const SizedBox(height: 16),
              _facts(
                key: 'merge-projection-contacts-$number',
                title: _t('mergeProjectionContacts'),
                count: source.contactLinks.length,
                children: [
                  for (final link in source.contactLinks) ...[
                    _field(_t('mergeProjectionContactId'), link.contactId),
                    _field(
                      _t('mergeProjectionSourceId'),
                      link.promotionTargetId,
                    ),
                    _field(_t('mergeProjectionRevision'), link.revisionNumber),
                    _field(_t('targetResponseLevel'), link.responseLevel),
                    _field(
                      _t('targetFollowUpConsent'),
                      _t('targetConsent.${link.followUpConsent.storageValue}'),
                    ),
                    _field(
                      _t('institutionRepresentativeConfirmed'),
                      _t(
                        link.institutionRepresentativeConfirmed
                            ? 'mergeProjectionYes'
                            : 'mergeProjectionNo',
                      ),
                    ),
                    _field(
                      _t('mergeProjectionConfirmedEntry'),
                      _t(
                        link.confirmedProjectEntry
                            ? 'mergeProjectionYes'
                            : 'mergeProjectionNo',
                      ),
                    ),
                    _field(
                      _t('mergeProjectionGeneration'),
                      link.mergeGenerationId ?? _t('mergeProjectionNoBinding'),
                    ),
                    const Divider(height: 24),
                  ],
                ],
              ),
              _facts(
                key: 'merge-projection-institutions-$number',
                title: _t('targetInstitutionRelationshipsTitle'),
                count: source.institutionRelationships.length,
                children: [
                  Text(_t('mergeProjectionCurrentFacts')),
                  for (final relation in source.institutionRelationships) ...[
                    _field(_t('mergeProjectionRelationshipId'), relation.id),
                    _field(
                      _t('targetInstitutionRelationshipPerson'),
                      relation.personTargetId,
                    ),
                    _field(
                      _t('targetInstitutionRelationshipInstitution'),
                      relation.institutionTargetId,
                    ),
                    _field(
                      _t('targetInstitutionRelationshipKind'),
                      _t(
                        'targetInstitutionRelationshipKind.${relation.kind.storageValue}',
                      ),
                    ),
                    _field(
                      _t('targetInstitutionRelationshipRole'),
                      relation.roleDescription,
                    ),
                    _field(
                      _t('targetInstitutionRelationshipStarted'),
                      _utc(relation.startedAtUtc),
                    ),
                    _field(
                      _t('targetInstitutionRelationshipEnded'),
                      _utc(relation.endedAtUtc),
                    ),
                    _field(
                      _t('mergeProjectionRelationshipStatus'),
                      _t(
                        relation.status ==
                                TargetInstitutionRelationshipStatus.active
                            ? 'mergeProjectionRelationshipActive'
                            : 'mergeProjectionRelationshipEnded',
                      ),
                    ),
                    _field(
                      _t('mergeProjectionRevision'),
                      relation.revisionNumber,
                    ),
                    const Divider(height: 24),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _facts({
    required String key,
    required String title,
    required int count,
    required List<Widget> children,
  }) => ExpansionTile(
    key: ValueKey(key),
    tilePadding: EdgeInsets.zero,
    title: Text('$title ($count)'),
    expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
    expansionAnimationStyle: MediaQuery.disableAnimationsOf(context)
        ? AnimationStyle.noAnimation
        : null,
    children: count == 0 ? [Text(_t('mergeProjectionNoFacts'))] : children,
  );
}
