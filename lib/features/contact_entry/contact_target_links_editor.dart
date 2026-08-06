import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../targets/promotion_target.dart';
import '../contact_journal/contact_models.dart';

/// 在接触修订中编辑受控对象关联事实。
///
/// 组件只接收已授权候选资料和关联快照，不读取网络或数据库。阶段 0 确认和
/// 持久化仍由调用者处理；所有领域约束还会在 ContactJournal 和 Backend 复验。
final class ContactTargetLinksEditor extends StatelessWidget {
  const ContactTargetLinksEditor({
    super.key,
    required this.text,
    required this.targetLinks,
    required this.assignedTargets,
    required this.isLoading,
    required this.loadFailed,
    required this.hasLoaded,
    required this.onAdd,
    required this.onRemove,
    required this.onResponseChanged,
    required this.onConsentChanged,
    required this.onRepresentativeChanged,
    required this.onRetry,
  });

  final AppStrings text;
  final List<ContactTargetLink> targetLinks;
  final List<PromotionTargetProfile> assignedTargets;
  final bool isLoading;
  final bool loadFailed;
  final bool hasLoaded;
  final Future<void> Function(PromotionTargetProfile target) onAdd;
  final void Function(String targetId) onRemove;
  final void Function(String targetId, int? responseLevel) onResponseChanged;
  final void Function(String targetId, ContactFollowUpConsent consent)
  onConsentChanged;
  final void Function(String targetId, bool confirmed) onRepresentativeChanged;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final linkedIds = targetLinks.map((link) => link.targetId).toSet();
    final available = assignedTargets
        .where((target) => !linkedIds.contains(target.id))
        .toList(growable: false);
    final targetsById = {
      for (final target in assignedTargets) target.id: target,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.link_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    text.t('contactTargetLinks'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text('${targetLinks.length}'),
              ],
            ),
            const SizedBox(height: 4),
            Text(text.t('contactTargetLinksHelp')),
            const SizedBox(height: 12),
            if (isLoading)
              const LinearProgressIndicator()
            else if (loadFailed)
              Row(
                children: [
                  Expanded(child: Text(text.t('targetCandidatesUnavailable'))),
                  TextButton.icon(
                    onPressed: () => unawaited(onRetry()),
                    icon: const Icon(Icons.refresh_outlined),
                    label: Text(text.t('retry')),
                  ),
                ],
              )
            else if (available.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey('add-contact-target-link-${linkedIds.length}'),
                decoration: InputDecoration(
                  labelText: text.t('addContactTargetLink'),
                  prefixIcon: const Icon(Icons.person_add_alt_outlined),
                ),
                items: [
                  for (final target in available)
                    DropdownMenuItem(
                      value: target.id,
                      child: Text(
                        '${target.displayName} · '
                        '${text.t(target.type == PromotionTargetType.person ? 'targetsPerson' : 'targetsInstitution')}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (targetId) {
                  if (targetId == null) return;
                  final target = targetsById[targetId];
                  if (target != null) unawaited(onAdd(target));
                },
              )
            else if (hasLoaded && targetLinks.isEmpty)
              Text(text.t('noAssignedTargetCandidates')),
            for (final link in targetLinks) ...[
              const SizedBox(height: 12),
              _ContactTargetLinkCard(
                text: text,
                link: link,
                target: targetsById[link.targetId],
                onRemove: () => onRemove(link.targetId),
                onResponseChanged: (level) =>
                    onResponseChanged(link.targetId, level),
                onConsentChanged: (consent) =>
                    onConsentChanged(link.targetId, consent),
                onRepresentativeChanged: (confirmed) =>
                    onRepresentativeChanged(link.targetId, confirmed),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

final class _ContactTargetLinkCard extends StatelessWidget {
  const _ContactTargetLinkCard({
    required this.text,
    required this.link,
    required this.target,
    required this.onRemove,
    required this.onResponseChanged,
    required this.onConsentChanged,
    required this.onRepresentativeChanged,
  });

  final AppStrings text;
  final ContactTargetLink link;
  final PromotionTargetProfile? target;
  final VoidCallback onRemove;
  final ValueChanged<int?> onResponseChanged;
  final ValueChanged<ContactFollowUpConsent> onConsentChanged;
  final ValueChanged<bool> onRepresentativeChanged;

  @override
  Widget build(BuildContext context) {
    final isInstitution = link.targetType == PromotionTargetType.institution;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isInstitution
                      ? Icons.apartment_outlined
                      : Icons.person_outline,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    target?.displayName ?? text.t('linkedTargetUnavailable'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: ValueKey('remove-contact-target-link-${link.targetId}'),
                  tooltip: text.t('removeContactTargetLink'),
                  onPressed: onRemove,
                  icon: const Icon(Icons.link_off_outlined),
                ),
              ],
            ),
            if (isInstitution)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: link.institutionRepresentativeConfirmed,
                title: Text(text.t('institutionRepresentativeConfirmed')),
                subtitle: Text(text.t('institutionRepresentativeHelp')),
                onChanged: (value) => onRepresentativeChanged(value ?? false),
              ),
            const SizedBox(height: 8),
            Text(text.t('targetResponseLevel')),
            const SizedBox(height: 8),
            SegmentedButton<int>(
              segments: [
                for (var level = 0; level <= 4; level++)
                  ButtonSegment(value: level, label: Text('$level')),
              ],
              selected: link.responseLevel == null
                  ? const <int>{}
                  : {link.responseLevel!},
              emptySelectionAllowed: true,
              onSelectionChanged:
                  isInstitution && !link.institutionRepresentativeConfirmed
                  ? null
                  : (selection) => onResponseChanged(
                      selection.isEmpty ? null : selection.single,
                    ),
            ),
            if (isInstitution && !link.institutionRepresentativeConfirmed)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  text.t('institutionResponseRequiresRepresentative'),
                ),
              ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ContactFollowUpConsent>(
              key: ValueKey(
                'target-consent-${link.targetId}-${link.followUpConsent.storageValue}',
              ),
              initialValue: link.followUpConsent,
              decoration: InputDecoration(
                labelText: text.t('targetFollowUpConsent'),
              ),
              items: [
                for (final consent in ContactFollowUpConsent.values)
                  DropdownMenuItem(
                    value: consent,
                    child: Text(
                      text.t('targetConsent.${consent.storageValue}'),
                    ),
                  ),
              ],
              onChanged: (consent) {
                if (consent != null) onConsentChanged(consent);
              },
            ),
          ],
        ),
      ),
    );
  }
}
