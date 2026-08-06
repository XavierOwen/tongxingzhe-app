import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/app_controller.dart';
import '../../app_session/session_context_gateway.dart';
import '../../device/device_time_zone.dart';
import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../contact_entry/contact_channel_label.dart';
import '../contact_journal/contact_journal.dart';
import '../contact_journal/contact_models.dart';

/// 保存一次未获回应的直接联络。
///
/// 尝试没有触达人数、兴趣或问卷控件。UI 结构与独立数据库表共同防止它进入
/// 已发生互动的统计口径。
final class ContactAttemptEntryScreen extends StatefulWidget {
  const ContactAttemptEntryScreen({
    super.key,
    required this.controller,
    required this.clock,
    required this.timeZoneProvider,
    required this.context,
    required this.contactJournal,
    required this.deviceId,
  });

  final AppController controller;
  final AppClock clock;
  final DeviceTimeZoneProvider timeZoneProvider;
  final TrustedSessionContext context;
  final ContactJournal contactJournal;
  final String deviceId;

  @override
  State<ContactAttemptEntryScreen> createState() =>
      _ContactAttemptEntryScreenState();
}

final class _ContactAttemptEntryScreenState
    extends State<ContactAttemptEntryScreen> {
  final TextEditingController _detailController = TextEditingController();
  DateTime? _occurredAtUtc;
  String? _occurredTimeZone;
  ContactChannel? _channel;
  String? _failureCode;
  var _isSaving = false;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  @override
  void dispose() {
    _detailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    final occurredAtUtc = _occurredAtUtc;
    final occurredTimeZone = _occurredTimeZone;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: text.t('cancel'),
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close),
        ),
        title: Text(text.t('recordContactAttempt')),
      ),
      body: occurredAtUtc == null || occurredTimeZone == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
              children: [
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(text.t('contactAttemptMeaning')),
                    subtitle: Text(text.t('contactAttemptExclusions')),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  text.t('chooseContactChannel'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final channel in ContactChannel.values)
                      ChoiceChip(
                        label: Text(contactChannelLabel(text, channel)),
                        selected: _channel == channel,
                        onSelected: (_) => setState(() {
                          _channel = channel;
                          if (channel != ContactChannel.otherDirect) {
                            _detailController.clear();
                          }
                          _failureCode = null;
                        }),
                      ),
                  ],
                ),
                if (_channel == ContactChannel.otherDirect) ...[
                  const SizedBox(height: 16),
                  TextField(
                    key: const ValueKey('attempt-channel-detail'),
                    controller: _detailController,
                    decoration: InputDecoration(
                      labelText: text.t('otherChannelDetail'),
                      helperText: text.t('otherChannelDetailHelp'),
                    ),
                    onChanged: (_) => setState(() => _failureCode = null),
                  ),
                ],
                const SizedBox(height: 16),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.schedule_outlined),
                  title: Text(text.t('occurredAt')),
                  subtitle: Text(occurredAtUtc.toIso8601String()),
                  trailing: IconButton(
                    key: const ValueKey('edit-attempt-occurred-at'),
                    tooltip: text.t('editOccurredAt'),
                    onPressed: _editOccurredAt,
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.public_outlined),
                  title: Text(text.t('occurredTimeZone')),
                  subtitle: Text(occurredTimeZone),
                ),
                if (_failureCode != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    text.t(_failureCode!),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _canSave ? _save : null,
            icon: _isSaving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.phone_missed_outlined),
            label: Text(text.t('saveContactAttempt')),
          ),
        ),
      ),
    );
  }

  bool get _canSave {
    if (_isSaving ||
        _occurredAtUtc == null ||
        _occurredTimeZone == null ||
        _channel == null) {
      return false;
    }
    return _channel != ContactChannel.otherDirect ||
        _detailController.text.trim().isNotEmpty;
  }

  Future<void> _initialize() async {
    try {
      final timeZone = await widget.timeZoneProvider.currentIanaTimeZone();
      if (!mounted) {
        return;
      }
      setState(() {
        _occurredAtUtc = widget.clock.now().toUtc();
        _occurredTimeZone = timeZone;
      });
    } on DeviceTimeZoneException catch (error) {
      if (mounted) {
        setState(() => _failureCode = error.code);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _failureCode = 'device_time_zone_unavailable');
      }
    }
  }

  Future<void> _editOccurredAt() async {
    final current = _occurredAtUtc!.toLocal();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (date == null || !mounted) {
      return;
    }
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (time == null || !mounted) {
      return;
    }
    setState(() {
      _occurredAtUtc = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      ).toUtc();
      _failureCode = null;
    });
  }

  Future<void> _save() async {
    setState(() {
      _isSaving = true;
      _failureCode = null;
    });
    try {
      await widget.contactJournal.recordContactAttempt(
        ContactAttemptSubmission(
          appUserId: widget.context.appUserId,
          workspaceId: widget.context.workspace.id,
          projectId: widget.context.project.id,
          deviceId: widget.deviceId,
          occurredAtUtc: _occurredAtUtc!,
          occurredTimeZone: _occurredTimeZone!,
          channel: _channel!,
          channelDetail: _channel == ContactChannel.otherDirect
              ? _detailController.text.trim()
              : null,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ContactValidationException catch (error) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _failureCode = error.code;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSaving = false;
          _failureCode = 'contact_attempt_save_failed';
        });
      }
    }
  }
}
