import 'package:flutter/material.dart';

import '../../app_session/app_session.dart';
import '../../identity/identity_session.dart';
import '../../l10n/app_strings.dart';
import '../../targets/personal_target_merge_directory.dart';
import '../../targets/personal_target_merge_projection.dart';
import '../../targets/promotion_target.dart';
import 'personal_target_merge_directory_read_controller.dart';
import 'personal_target_merge_projection_panel.dart';

final class PersonalTargetMergeDirectoryPanel extends StatefulWidget {
  const PersonalTargetMergeDirectoryPanel({
    super.key,
    required this.text,
    required this.identitySession,
    required this.appSession,
    required this.directoryGateway,
    required this.projectionGateway,
  });

  final AppStrings text;
  final IdentitySession identitySession;
  final AppSession appSession;
  final PersonalTargetMergeDirectoryGateway directoryGateway;
  final PersonalTargetMergeProjectionGateway projectionGateway;

  @override
  State<PersonalTargetMergeDirectoryPanel> createState() =>
      _PersonalTargetMergeDirectoryPanelState();
}

final class _PersonalTargetMergeDirectoryPanelState
    extends State<PersonalTargetMergeDirectoryPanel> {
  late PersonalTargetMergeDirectoryReadController _controller;

  @override
  void initState() {
    super.initState();
    _createController();
  }

  void _createController() {
    _controller = PersonalTargetMergeDirectoryReadController(
      identitySession: widget.identitySession,
      appSession: widget.appSession,
      gateway: widget.directoryGateway,
    );
  }

  @override
  void didUpdateWidget(PersonalTargetMergeDirectoryPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.identitySession, widget.identitySession) ||
        !identical(oldWidget.appSession, widget.appSession) ||
        !identical(oldWidget.directoryGateway, widget.directoryGateway) ||
        !identical(oldWidget.projectionGateway, widget.projectionGateway)) {
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

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _controller,
    builder: (context, _) {
      final directory = _controller.directory;
      final selectedId = _controller.selectedGenerationId;
      final failure = _controller.failure;
      final selected = selectedId == null
          ? null
          : directory!.items.firstWhere(
              (item) => item.generationId == selectedId,
            );
      return Column(
        key: const ValueKey('merge-directory-panel'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_t('mergeDirectoryHelp')),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('merge-directory-read'),
                onPressed: _controller.loading
                    ? null
                    : () => _controller.read(),
                icon: const Icon(Icons.refresh_outlined),
                label: Text(
                  _t(
                    directory == null
                        ? 'mergeDirectoryRead'
                        : 'mergeDirectoryRefresh',
                  ),
                ),
              ),
              if (directory?.nextCursor case final String cursor)
                OutlinedButton.icon(
                  key: const ValueKey('merge-directory-next'),
                  onPressed: _controller.loading
                      ? null
                      : () => _controller.read(afterGenerationId: cursor),
                  icon: const Icon(Icons.navigate_next),
                  label: Text(_t('mergeDirectoryNext')),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_controller.loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(_t('mergeDirectoryLoading')),
          ] else if (failure != null)
            Semantics(
              liveRegion: true,
              child: Text(
                _t(
                  failure ==
                          PersonalTargetMergeDirectoryFailure.requestInvalidated
                      ? 'mergeDirectoryInvalidated'
                      : 'mergeDirectoryFailed',
                ),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            )
          else if (directory == null)
            Text(_t('mergeDirectoryNotRead'))
          else if (directory.items.isEmpty)
            Text(_t('mergeDirectoryEmpty'))
          else ...[
            Text(_t('mergeDirectorySnapshotHelp')),
            const SizedBox(height: 16),
            Text(_t('mergeDirectorySelect')),
            const SizedBox(height: 8),
            Semantics(
              label: _t('mergeDirectorySelect'),
              child: DropdownButtonFormField<String>(
                key: ObjectKey(directory),
                isExpanded: true,
                isDense: false,
                itemHeight: null,
                initialValue: selectedId,
                decoration: const InputDecoration(),
                items: [
                  for (final item in directory.items)
                    DropdownMenuItem(
                      value: item.generationId,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          '${_t(item.targetType == PromotionTargetType.person ? 'targetsPerson' : 'targetsInstitution')} · ${item.generationId}',
                          softWrap: true,
                        ),
                      ),
                    ),
                ],
                onChanged: _controller.selectGeneration,
              ),
            ),
          ],
          if (selected != null) ...[
            const SizedBox(height: 16),
            Text(
              '${_t('mergeProjectionRetainedId')}: ${selected.retainedTargetId}',
            ),
            Text(
              '${_t('mergeProjectionEarlierDue')}: ${selected.reviewDueAtUtc.toUtc().toIso8601String()}',
            ),
            for (final member in selected.memberTargetIds)
              Text('${_t('mergeProjectionSourceId')}: $member'),
            const Divider(height: 32),
            PersonalTargetMergeProjectionPanel(
              key: ValueKey(selected.generationId),
              text: widget.text,
              identitySession: widget.identitySession,
              appSession: widget.appSession,
              gateway: widget.projectionGateway,
              generationId: selected.generationId,
            ),
          ],
        ],
      );
    },
  );
}
