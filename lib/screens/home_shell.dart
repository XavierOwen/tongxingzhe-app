import 'dart:math';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_controller.dart';
import '../l10n/app_strings.dart';
import '../models/conversation_record.dart';
import '../services/heart_rate_service.dart';
import '../services/location_service.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.controller});

  final AppController controller;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    final destinations = [
      _Destination(Icons.edit_location_alt_outlined, text.t('record')),
      _Destination(Icons.list_alt_outlined, text.t('records')),
      _Destination(Icons.bar_chart_outlined, text.t('analytics')),
      _Destination(Icons.admin_panel_settings_outlined, text.t('admin')),
      _Destination(Icons.settings_outlined, text.t('settings')),
    ];
    final pages = [
      QuickRecordView(controller: widget.controller),
      RecordsView(controller: widget.controller),
      AnalyticsView(controller: widget.controller),
      AdminView(controller: widget.controller),
      SettingsView(controller: widget.controller),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(text.t('appTitle')),
        actions: [
          IconButton(
            tooltip: text.t('theme'),
            onPressed: _cycleThemeMode,
            icon: Icon(_themeIcon(widget.controller.themeMode)),
          ),
          TextButton(
            onPressed: () {
              widget.controller.setLocale(
                widget.controller.localeCode == 'zh' ? 'en' : 'zh',
              );
            },
            child: Text(widget.controller.localeCode == 'zh' ? 'EN' : '中'),
          ),
          IconButton(
            tooltip: text.t('logout'),
            onPressed: widget.controller.logout,
            icon: const Icon(Icons.logout_outlined),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return Row(
              children: [
                NavigationRail(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (value) {
                    setState(() => _selectedIndex = value);
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final destination in destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.icon),
                        label: Text(destination.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: pages[_selectedIndex]),
              ],
            );
          }

          return pages[_selectedIndex];
        },
      ),
      bottomNavigationBar: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 900) {
            return const SizedBox.shrink();
          }
          return NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (value) {
              setState(() => _selectedIndex = value);
            },
            destinations: [
              for (final destination in destinations)
                NavigationDestination(
                  icon: Icon(destination.icon),
                  label: destination.label,
                ),
            ],
          );
        },
      ),
    );
  }

  void _cycleThemeMode() {
    final next = switch (widget.controller.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    widget.controller.setThemeMode(next);
  }

  IconData _themeIcon(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto_outlined,
      ThemeMode.light => Icons.light_mode_outlined,
      ThemeMode.dark => Icons.dark_mode_outlined,
    };
  }
}

class _Destination {
  const _Destination(this.icon, this.label);

  final IconData icon;
  final String label;
}

class _ContactDraft {
  _ContactDraft({String value = ''})
    : channel = 'wechat',
      controller = TextEditingController(text: value);

  String channel;
  final TextEditingController controller;

  ConversationContact? toContact() {
    final trimmed = controller.text.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return ConversationContact(channel: channel, value: trimmed);
  }

  void dispose() {
    controller.dispose();
  }
}

class QuickRecordView extends StatefulWidget {
  const QuickRecordView({super.key, required this.controller});

  final AppController controller;

  @override
  State<QuickRecordView> createState() => _QuickRecordViewState();
}

class _QuickRecordViewState extends State<QuickRecordView> {
  final _locationService = LocationService();
  final _heartRateService = HeartRateService();
  final _personNameController = TextEditingController();
  final _englishNameController = TextEditingController();
  final _manualPlaceController = TextEditingController();
  final List<_ContactDraft> _contactDrafts = [_ContactDraft()];
  final _notesController = TextEditingController();

  DateTime _recordTime = DateTime.now();
  LocationSnapshot? _location;
  double? _averageHeartRate;
  String _heartRateStatusKey = 'heartRateUnavailable';
  bool _loadingLocation = false;
  bool _loadingHeartRate = false;
  late String _areaName;
  String _gender = 'unknown';
  String _identity = 'student';
  String _ageRange = 'unknown';
  int _relationshipLevel = 1;
  int _interestLevel = 2;

  @override
  void initState() {
    super.initState();
    _areaName = widget.controller.areaName;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _captureLocation();
      }
    });
  }

  @override
  void dispose() {
    _personNameController.dispose();
    _englishNameController.dispose();
    _manualPlaceController.dispose();
    for (final draft in _contactDrafts) {
      draft.dispose();
    }
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.controller.localeCode);
    final availableAreas = widget.controller.availableAreas;
    if (!availableAreas.contains(_areaName)) {
      _areaName = availableAreas.first;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          text.t('newRecord'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        _InfoStrip(
          icon: Icons.schedule_outlined,
          label: text.t('recordTime'),
          value: _formatDateTime(_recordTime),
        ),
        const SizedBox(height: 12),
        _InfoStrip(
          icon: Icons.location_city_outlined,
          label: text.t('city'),
          value: widget.controller.cityName,
        ),
        const SizedBox(height: 12),
        _InfoStrip(
          icon: Icons.map_outlined,
          label: text.t('area'),
          value: _areaName,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.my_location_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text.t('location'),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _loadingLocation ? null : _captureLocation,
                      icon: _loadingLocation
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh_outlined),
                      label: Text(text.t('refreshLocation')),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(_locationStatus(text)),
                if (_location?.hasPosition == true) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${text.t('coordinates')}: '
                    '${_location!.latitude!.toStringAsFixed(5)}, '
                    '${_location!.longitude!.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _areaName,
                  decoration: InputDecoration(
                    labelText: text.t('area'),
                    prefixIcon: const Icon(Icons.map_outlined),
                  ),
                  items: [
                    for (final area in availableAreas)
                      DropdownMenuItem(value: area, child: Text(area)),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _areaName = value);
                      widget.controller.setAreaName(value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _manualPlaceController,
                  decoration: InputDecoration(
                    labelText: text.t('manualPlace'),
                    hintText: text.t('manualPlaceHint'),
                    prefixIcon: const Icon(Icons.place_outlined),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: text.t('personInfo'),
          children: [
            TextField(
              controller: _personNameController,
              decoration: InputDecoration(
                labelText: text.t('personName'),
                hintText: text.t('personNameHint'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _englishNameController,
              decoration: InputDecoration(
                labelText: text.t('englishName'),
                hintText: text.t('englishNameHint'),
                prefixIcon: const Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 16),
            _HeartRateTile(
              text: text,
              value: _averageHeartRate,
              statusKey: _heartRateStatusKey,
              loading: _loadingHeartRate,
              onTap: () => _requestHeartRate(text),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: text.t('identity'),
          children: [
            Text(text.t('gender')),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              selected: {_gender},
              onSelectionChanged: (selected) {
                setState(() => _gender = selected.first);
              },
              segments: [
                for (final option in genderOptions)
                  ButtonSegment(
                    value: option,
                    label: Text(text.option('gender', option)),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _OptionDropdown(
              label: text.t('identity'),
              value: _identity,
              values: identityOptions,
              group: 'identity',
              text: text,
              onChanged: (value) => setState(() => _identity = value),
            ),
            const SizedBox(height: 16),
            _OptionDropdown(
              label: text.t('ageRange'),
              value: _ageRange,
              values: ageRangeOptions,
              group: 'age',
              text: text,
              onChanged: (value) => setState(() => _ageRange = value),
            ),
            const SizedBox(height: 16),
            _RelationshipSlider(
              value: _relationshipLevel,
              text: text,
              onChanged: (value) => setState(() => _relationshipLevel = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: text.t('contacts'),
          children: [
            for (var i = 0; i < _contactDrafts.length; i++) ...[
              _ContactDraftRow(
                draft: _contactDrafts[i],
                text: text,
                canRemove: _contactDrafts.length > 1,
                onChanged: () => setState(() {}),
                onRemove: () => _removeContactDraft(i),
              ),
              if (i != _contactDrafts.length - 1) const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addContactDraft,
                icon: const Icon(Icons.add_outlined),
                label: Text(text.t('addContact')),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Section(
          title: text.t('interest'),
          children: [
            Text(text.t('interestHelp')),
            const SizedBox(height: 8),
            _InterestSlider(
              value: _interestLevel,
              text: text,
              onChanged: (value) => setState(() => _interestLevel = value),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // The removed prayer field is not represented in the form anymore.
        // New records only save this optional notes field as free text.
        TextField(
          controller: _notesController,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: text.t('notes'),
            hintText: text.t('notesHint'),
            alignLabelWithHint: true,
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(text.t('save')),
        ),
        const SizedBox(height: 32),
      ],
    );
  }

  String _locationStatus(AppStrings text) {
    if (_loadingLocation) {
      return text.t('gettingLocation');
    }
    if (_location == null) {
      return text.t('locationMissing');
    }
    final error = _location!.error;
    if (error != null) {
      return text.t(error);
    }
    final accuracy = _location!.accuracyMeters;
    if (accuracy == null) {
      return text.t('locationReady');
    }
    return '${text.t('locationReady')} · ${text.t('locationAccuracy')} '
        '±${accuracy.toStringAsFixed(0)}m';
  }

  Future<void> _captureLocation() async {
    setState(() => _loadingLocation = true);
    final result = await _locationService.captureCurrentPosition();
    if (!mounted) {
      return;
    }
    setState(() {
      _location = result;
      _loadingLocation = false;
    });
  }

  void _addContactDraft() {
    setState(() => _contactDrafts.add(_ContactDraft()));
  }

  void _removeContactDraft(int index) {
    final draft = _contactDrafts.removeAt(index);
    draft.dispose();
    setState(() {});
  }

  Future<void> _save() async {
    final text = AppStrings(widget.controller.localeCode);
    if (widget.controller.cityName.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(text.t('requiredCity'))));
      return;
    }

    final record = ConversationRecord(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      createdAt: _recordTime,
      cityName: widget.controller.cityName,
      areaName: _areaName,
      teamName: widget.controller.teamName,
      recorderName: widget.controller.recorderName,
      collectorUserId: widget.controller.currentUser?.userId ?? '',
      personName: _personNameController.text.trim(),
      englishName: _englishNameController.text.trim(),
      averageHeartRate: _averageHeartRate,
      latitude: _location?.latitude,
      longitude: _location?.longitude,
      locationAccuracyMeters: _location?.accuracyMeters,
      locationError: _location?.error,
      manualPlaceName: _manualPlaceController.text.trim(),
      gender: _gender,
      identity: _identity,
      ageRange: _ageRange,
      relationshipLevel: _relationshipLevel,
      interestLevel: _interestLevel,
      contacts: _contactDrafts
          .map((draft) => draft.toContact())
          .whereType<ConversationContact>()
          .toList(),
      // The app stores interest as 0..4. `attitudeLevel` is kept only as a
      // legacy compatibility score for older chart code and data exports.
      attitudeLevel: _interestLevel - 2,
      notes: _notesController.text.trim(),
      isLocationVerified: false,
    );

    await widget.controller.addRecord(record);
    if (!mounted) {
      return;
    }
    _personNameController.clear();
    _englishNameController.clear();
    _manualPlaceController.clear();
    for (final draft in _contactDrafts) {
      draft.dispose();
    }
    _contactDrafts
      ..clear()
      ..add(_ContactDraft());
    _notesController.clear();
    setState(() {
      _recordTime = DateTime.now();
      _gender = 'unknown';
      _identity = 'student';
      _ageRange = 'unknown';
      _relationshipLevel = 1;
      _interestLevel = 2;
      _averageHeartRate = null;
      _heartRateStatusKey = 'heartRateUnavailable';
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('savedMessage'))));
  }

  Future<void> _requestHeartRate(AppStrings text) async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.t('heartRatePermission')),
        content: Text(text.t('heartRatePermissionBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.t('heartRateRead')),
          ),
        ],
      ),
    );
    if (allowed != true) {
      setState(() => _heartRateStatusKey = 'heartRateDenied');
      return;
    }
    setState(() => _loadingHeartRate = true);
    final snapshot = await _heartRateService.readAverageHeartRate();
    if (!mounted) {
      return;
    }
    setState(() {
      _averageHeartRate = snapshot.value;
      _heartRateStatusKey = snapshot.statusKey;
      _loadingHeartRate = false;
    });
  }
}

class RecordsView extends StatefulWidget {
  const RecordsView({super.key, required this.controller});

  final AppController controller;

  @override
  State<RecordsView> createState() => _RecordsViewState();
}

class _RecordsViewState extends State<RecordsView> {
  final _searchController = TextEditingController();
  String _identityFilter = 'all';
  String _areaFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final text = AppStrings(widget.controller.localeCode);
        final areas =
            widget.controller.visibleRecords
                .map((record) => record.areaName)
                .toSet()
                .toList()
              ..sort();
        final records = widget.controller.visibleRecords.where((record) {
          final matchesIdentity =
              _identityFilter == 'all' || record.identity == _identityFilter;
          final matchesArea =
              _areaFilter == 'all' || record.areaName == _areaFilter;
          final query = _searchController.text.trim().toLowerCase();
          final haystack = [
            record.cityName,
            record.areaName,
            record.personName,
            record.englishName,
            record.manualPlaceName,
            record.correctedPlaceName ?? '',
            record.contacts.map((contact) => contact.value).join(' '),
            record.notes,
            record.identity,
            record.relationshipKey,
            text.option('relationship', record.relationshipKey),
            record.interestKey,
            text.option('interest', record.interestKey),
            record.recorderName,
          ].join(' ').toLowerCase();
          return matchesIdentity &&
              matchesArea &&
              (query.isEmpty || haystack.contains(query));
        }).toList();

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchController,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: text.t('search'),
                prefixIcon: const Icon(Icons.search_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: _identityFilter,
                    decoration: InputDecoration(labelText: text.t('identity')),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(text.t('all')),
                      ),
                      for (final value in identityOptions)
                        DropdownMenuItem(
                          value: value,
                          child: Text(text.option('identity', value)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _identityFilter = value);
                      }
                    },
                  ),
                ),
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: areas.contains(_areaFilter)
                        ? _areaFilter
                        : 'all',
                    decoration: InputDecoration(labelText: text.t('area')),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(text.t('all')),
                      ),
                      for (final area in areas)
                        DropdownMenuItem(value: area, child: Text(area)),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _areaFilter = value);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _AccessScopeBanner(controller: widget.controller, text: text),
            const SizedBox(height: 16),
            if (records.isEmpty)
              _EmptyState(
                icon: Icons.list_alt_outlined,
                message: text.t('noRecords'),
              )
            else
              for (final record in records) ...[
                RecordListCard(
                  record: record,
                  text: text,
                  onDelete: () => _confirmDelete(record),
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(ConversationRecord record) async {
    final text = AppStrings(widget.controller.localeCode);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.t('delete')),
        content: Text(_formatDateTime(record.createdAt)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.t('delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.deleteRecord(record.id);
    }
  }
}

class AnalyticsView extends StatelessWidget {
  const AnalyticsView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final text = AppStrings(controller.localeCode);
        final records = controller.visibleRecords;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _StatTile(
                  icon: Icons.today_outlined,
                  label: text.t('today'),
                  value: controller.countToday().toString(),
                ),
                _StatTile(
                  icon: Icons.people_alt_outlined,
                  label: text.t('total'),
                  value: records.length.toString(),
                ),
                _StatTile(
                  icon: Icons.sentiment_satisfied_alt_outlined,
                  label: text.t('positiveAttitudes'),
                  value: controller.countPositiveAttitudes().toString(),
                ),
                _StatTile(
                  icon: Icons.block_outlined,
                  label: text.t('rejected'),
                  value: controller.countRejected().toString(),
                ),
                _StatTile(
                  icon: Icons.contact_phone_outlined,
                  label: text.t('contactRate'),
                  value: _formatPercent(controller.contactRate()),
                ),
                _StatTile(
                  icon: Icons.location_searching_outlined,
                  label: text.t('reviewQueue'),
                  value: controller.recordsNeedingReview.length.toString(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (records.isEmpty)
              _EmptyState(
                icon: Icons.bar_chart_outlined,
                message: text.t('noRecords'),
              )
            else ...[
              _DailyTrendChart(records: records, text: text),
              const SizedBox(height: 16),
              _HourChart(records: records, text: text),
              const SizedBox(height: 16),
              _AreaChart(records: records, text: text),
              const SizedBox(height: 16),
              _IdentityChart(records: records, text: text),
              const SizedBox(height: 16),
              _RelationshipChart(records: records, text: text),
              const SizedBox(height: 16),
              _InterestChart(records: records, text: text),
              const SizedBox(height: 16),
              _ChartBuilderPreview(text: text),
            ],
          ],
        );
      },
    );
  }
}

class AdminView extends StatelessWidget {
  const AdminView({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final text = AppStrings(controller.localeCode);
        if (!controller.canUseAdminMode) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _EmptyState(
                icon: Icons.lock_outline,
                message: text.t('noAdminPermission'),
              ),
            ],
          );
        }
        if (!controller.adminMode) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _EmptyState(
                icon: Icons.admin_panel_settings_outlined,
                message: text.t('adminModeNeeded'),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => controller.setAdminMode(true),
                icon: const Icon(Icons.lock_open_outlined),
                label: Text(text.t('adminMode')),
              ),
            ],
          );
        }

        final records = controller.recordsNeedingReview;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: controller.adminMode,
              onChanged: controller.setAdminMode,
              title: Text(text.t('adminMode')),
            ),
            _ManagerSummarySection(controller: controller, text: text),
            const SizedBox(height: 16),
            const SizedBox(height: 8),
            if (records.isEmpty)
              _EmptyState(
                icon: Icons.verified_outlined,
                message: text.t('noReview'),
              )
            else
              for (final record in records) ...[
                AdminRecordTile(
                  key: ValueKey(record.id),
                  controller: controller,
                  record: record,
                  text: text,
                ),
                const SizedBox(height: 12),
              ],
          ],
        );
      },
    );
  }
}

class _ManagerSummarySection extends StatelessWidget {
  const _ManagerSummarySection({required this.controller, required this.text});

  final AppController controller;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final records = controller.visibleRecords;
    final activeAreas = records.map((record) => record.areaName).toSet().length;

    return _Section(
      title: text.t('managerDashboard'),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _StatTile(
              icon: Icons.people_alt_outlined,
              label: text.t('total'),
              value: records.length.toString(),
            ),
            _StatTile(
              icon: Icons.map_outlined,
              label: text.t('byArea'),
              value: activeAreas.toString(),
            ),
            _StatTile(
              icon: Icons.sentiment_very_satisfied_outlined,
              label: text.t('positiveAttitudes'),
              value: controller.countPositiveAttitudes().toString(),
            ),
            _StatTile(
              icon: Icons.contact_phone_outlined,
              label: text.t('contactRate'),
              value: _formatPercent(controller.contactRate()),
            ),
          ],
        ),
      ],
    );
  }
}

class SettingsView extends StatefulWidget {
  const SettingsView({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final text = AppStrings(widget.controller.localeCode);
        final user = widget.controller.currentUser;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (user != null) ...[
              _Section(
                title: text.t('account'),
                children: [
                  _DetailRow(label: text.t('username'), value: user.username),
                  _DetailRow(
                    label: text.t('displayName'),
                    value: user.displayName,
                  ),
                  _DetailRow(label: text.t('email'), value: user.email),
                  _DetailRow(label: text.t('phone'), value: user.phone),
                  _DetailRow(
                    label: text.t('birthday'),
                    value: _formatBirthday(user.birthday),
                  ),
                  _DetailRow(
                    label: text.t('gender'),
                    value: text.option('gender', user.gender),
                  ),
                  _DetailRow(
                    label: text.t('occupation'),
                    value: user.occupation.isEmpty ? '-' : user.occupation,
                  ),
                  _DetailRow(
                    label: text.t('promoterAgeBand'),
                    value: text.option('promoterAge', user.ageBand),
                  ),
                  _DetailRow(label: text.t('role'), value: '${user.roleLevel}'),
                  _DetailRow(
                    label: text.t('allowedCities'),
                    value: user.cityNames.join(', '),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _showChangePasswordDialog,
                        icon: const Icon(Icons.lock_reset_outlined),
                        label: Text(text.t('changePassword')),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: widget.controller.logout,
                        icon: const Icon(Icons.logout_outlined),
                        label: Text(text.t('logout')),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],
            _Section(
              title: text.t('settings'),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: widget.controller.localeCode,
                  decoration: InputDecoration(labelText: text.t('language')),
                  items: const [
                    DropdownMenuItem(value: 'zh', child: Text('中文')),
                    DropdownMenuItem(value: 'en', child: Text('English')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      widget.controller.setLocale(value);
                    }
                  },
                ),
                const SizedBox(height: 16),
                Text(text.t('theme')),
                const SizedBox(height: 8),
                SegmentedButton<ThemeMode>(
                  selected: {widget.controller.themeMode},
                  onSelectionChanged: (selected) {
                    widget.controller.setThemeMode(selected.first);
                  },
                  segments: [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text(text.t('theme.system')),
                      icon: const Icon(Icons.brightness_auto_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text(text.t('theme.light')),
                      icon: const Icon(Icons.light_mode_outlined),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text(text.t('theme.dark')),
                      icon: const Icon(Icons.dark_mode_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: widget.controller.cityName,
                  decoration: InputDecoration(labelText: text.t('city')),
                  onChanged: widget.controller.setCityName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: widget.controller.teamName,
                  decoration: InputDecoration(labelText: text.t('team')),
                  onChanged: widget.controller.setTeamName,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: widget.controller.recorderName,
                  decoration: InputDecoration(labelText: text.t('workerName')),
                  onChanged: widget.controller.setRecorderName,
                ),
                const SizedBox(height: 8),
                if (widget.controller.canUseAdminMode)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: widget.controller.adminMode,
                    onChanged: widget.controller.setAdminMode,
                    title: Text(text.t('adminMode')),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: text.t('privacy'),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _copySummary,
                      icon: const Icon(Icons.content_copy_outlined),
                      label: Text(text.t('copySummary')),
                    ),
                    OutlinedButton.icon(
                      onPressed: _addDemoData,
                      icon: const Icon(Icons.auto_graph_outlined),
                      label: Text(text.t('addDemoData')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _clearData,
                      icon: const Icon(Icons.delete_sweep_outlined),
                      label: Text(text.t('clearData')),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _resetDemoData,
                      icon: const Icon(Icons.restart_alt_outlined),
                      label: Text(text.t('resetDemoData')),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        );
      },
    );
  }

  Future<void> _copySummary() async {
    final text = AppStrings(widget.controller.localeCode);
    await Clipboard.setData(
      ClipboardData(text: widget.controller.buildAnonymousSummary()),
    );
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('summaryCopied'))));
  }

  Future<void> _addDemoData() async {
    final text = AppStrings(widget.controller.localeCode);
    await widget.controller.addDemoData();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(text.t('demoAdded'))));
  }

  Future<void> _resetDemoData() async {
    await widget.controller.clearRecords();
    await widget.controller.addDemoData();
  }

  Future<void> _clearData() async {
    final text = AppStrings(widget.controller.localeCode);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(text.t('clearData')),
        content: Text(text.t('clearDataConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(text.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(text.t('clear')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.controller.clearRecords();
    }
  }

  Future<void> _showChangePasswordDialog() async {
    final text = AppStrings(widget.controller.localeCode);
    final currentController = TextEditingController();
    final newController = TextEditingController();
    final confirmController = TextEditingController();
    try {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(text.t('changePassword')),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: text.t('currentPassword'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newController,
                  obscureText: true,
                  decoration: InputDecoration(labelText: text.t('newPassword')),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: confirmController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: text.t('confirmPassword'),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(text.t('cancel')),
            ),
            FilledButton(
              onPressed: () async {
                if (newController.text != confirmController.text) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(text.t('passwordMismatch'))),
                  );
                  return;
                }
                final result = await widget.controller.changePassword(
                  currentPassword: currentController.text,
                  newPassword: newController.text,
                );
                if (!context.mounted) {
                  return;
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(text.t(result.messageKey))),
                );
                if (result.success) {
                  Navigator.pop(context);
                }
              },
              child: Text(text.t('save')),
            ),
          ],
        ),
      );
    } finally {
      currentController.dispose();
      newController.dispose();
      confirmController.dispose();
    }
  }
}

class AdminRecordTile extends StatefulWidget {
  const AdminRecordTile({
    super.key,
    required this.controller,
    required this.record,
    required this.text,
  });

  final AppController controller;
  final ConversationRecord record;
  final AppStrings text;

  @override
  State<AdminRecordTile> createState() => _AdminRecordTileState();
}

class _AdminRecordTileState extends State<AdminRecordTile> {
  late final TextEditingController _placeController;
  late final TextEditingController _latitudeController;
  late final TextEditingController _longitudeController;
  late bool _verified;

  @override
  void initState() {
    super.initState();
    _placeController = TextEditingController(
      text: widget.record.correctedPlaceName ?? widget.record.manualPlaceName,
    );
    _latitudeController = TextEditingController(
      text: _coordinateText(widget.record.displayLatitude),
    );
    _longitudeController = TextEditingController(
      text: _coordinateText(widget.record.displayLongitude),
    );
    _verified = widget.record.isLocationVerified;
  }

  @override
  void dispose() {
    _placeController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.location_searching_outlined),
        title: Text(
          widget.record.displayPlaceName.isEmpty
              ? widget.text.t('locationMissing')
              : widget.record.displayPlaceName,
        ),
        subtitle: Text(
          '${_formatDateTime(widget.record.createdAt)} · '
          '${widget.record.areaName} · '
          '${widget.text.option('identity', widget.record.identity)} · '
          '${widget.text.option('relationship', widget.record.relationshipKey)}',
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          TextField(
            controller: _placeController,
            decoration: InputDecoration(
              labelText: widget.text.t('correctPlace'),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.text.t('correctLatitude'),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _longitudeController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: InputDecoration(
                    labelText: widget.text.t('correctLongitude'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _verified,
            onChanged: (value) => setState(() => _verified = value),
            title: Text(widget.text.t('verified')),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.verified_outlined),
              label: Text(widget.text.t('saveCorrection')),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final place = _placeController.text.trim();
    final latitudeText = _latitudeController.text.trim();
    final longitudeText = _longitudeController.text.trim();
    final latitude = double.tryParse(latitudeText);
    final longitude = double.tryParse(longitudeText);

    final updated = widget.record.copyWith(
      correctedPlaceName: place,
      clearCorrectedPlaceName: place.isEmpty,
      correctedLatitude: latitude,
      clearCorrectedLatitude: latitudeText.isEmpty,
      correctedLongitude: longitude,
      clearCorrectedLongitude: longitudeText.isEmpty,
      isLocationVerified: _verified,
      correctedAt: DateTime.now(),
    );

    await widget.controller.updateRecord(updated);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.text.t('correctionSaved'))));
  }
}

class RecordListCard extends StatelessWidget {
  const RecordListCard({
    super.key,
    required this.record,
    required this.text,
    required this.onDelete,
  });

  final ConversationRecord record;
  final AppStrings text;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final location = record.displayPlaceName.isEmpty
        ? text.t('locationMissing')
        : record.displayPlaceName;

    return Card(
      child: ExpansionTile(
        leading: Icon(
          record.needsLocationReview
              ? Icons.location_searching_outlined
              : Icons.place_outlined,
        ),
        title: Text(location),
        subtitle: Text(
          '${_formatDateTime(record.createdAt)} · '
          '${record.areaName} · '
          '${text.option('identity', record.identity)} · '
          '${text.option('relationship', record.relationshipKey)} · '
          '${text.option('interest', record.interestKey)}',
        ),
        trailing: IconButton(
          tooltip: text.t('delete'),
          onPressed: onDelete,
          icon: const Icon(Icons.delete_outline),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          _DetailRow(label: text.t('city'), value: record.cityName),
          _DetailRow(label: text.t('area'), value: record.areaName),
          if (record.personName.isNotEmpty)
            _DetailRow(label: text.t('personName'), value: record.personName),
          if (record.englishName.isNotEmpty)
            _DetailRow(label: text.t('englishName'), value: record.englishName),
          _DetailRow(
            label: text.t('gender'),
            value: text.option('gender', record.gender),
          ),
          _DetailRow(
            label: text.t('ageRange'),
            value: text.option('age', record.ageRange),
          ),
          _DetailRow(
            label: text.t('relationship'),
            value: text.option('relationship', record.relationshipKey),
          ),
          _DetailRow(
            label: text.t('interest'),
            value: text.option('interest', record.interestKey),
          ),
          if (record.averageHeartRate != null)
            _DetailRow(
              label: text.t('averageHeartRate'),
              value: record.averageHeartRate!.toStringAsFixed(0),
            ),
          _DetailRow(
            label: text.t('contacts'),
            value: _contactLine(record, text),
          ),
          if (record.displayLatitude != null && record.displayLongitude != null)
            _DetailRow(
              label: text.t('coordinates'),
              value:
                  '${record.displayLatitude!.toStringAsFixed(5)}, '
                  '${record.displayLongitude!.toStringAsFixed(5)}',
            ),
          if (record.notes.isNotEmpty)
            _DetailRow(label: text.t('notes'), value: record.notes),
        ],
      ),
    );
  }

  String _contactLine(ConversationRecord record, AppStrings text) {
    if (record.contacts.isEmpty) {
      return text.t('noContact');
    }
    return record.contacts
        .map(
          (contact) =>
              '${text.option('contact', contact.channel)}: ${contact.value}',
        )
        .join('\n');
  }
}

class _HourChart extends StatelessWidget {
  const _HourChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final counts = List<int>.filled(24, 0);
    for (final record in records) {
      counts[record.createdAt.hour]++;
    }
    final maxCount = max(1, counts.reduce(max));
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byHour'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxCount.toDouble() + 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        reservedSize: 36,
                        showTitles: true,
                        interval: _countAxisInterval(maxCount),
                        getTitlesWidget: (value, meta) =>
                            _countAxisTitle(context, value),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        interval: 3,
                        getTitlesWidget: (value, meta) {
                          final hour = value.toInt();
                          if (!_isWholeChartValue(value) ||
                              hour < 0 ||
                              hour > 23) {
                            return const SizedBox.shrink();
                          }
                          if (hour % 3 != 0) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('$hour'),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (var hour = 0; hour < 24; hour++)
                      BarChartGroupData(
                        x: hour,
                        barRods: [
                          BarChartRodData(
                            toY: counts[hour].toDouble(),
                            width: 9,
                            borderRadius: BorderRadius.circular(3),
                            color: color,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DailyTrendChart extends StatelessWidget {
  const _DailyTrendChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final dayCounts = <DateTime, int>{};
    for (final record in records) {
      final day = DateTime(
        record.createdAt.year,
        record.createdAt.month,
        record.createdAt.day,
      );
      dayCounts[day] = (dayCounts[day] ?? 0) + 1;
    }
    final days = dayCounts.keys.toList()..sort();
    final maxCount = max(1, dayCounts.values.reduce(max));
    final spots = [
      for (var i = 0; i < days.length; i++)
        FlSpot(i.toDouble(), (dayCounts[days[i]] ?? 0).toDouble()),
    ];
    final labelStride = max(1, (days.length / 4).ceil());
    final maxX = max(1, days.length - 1).toDouble();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byDay'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final chartWidth = max(
                  constraints.maxWidth,
                  days.length * 76.0,
                );

                return _horizontalChartViewport(
                  width: chartWidth,
                  height: 240,
                  child: LineChart(
                    LineChartData(
                      // The small x padding prevents first/last date labels
                      // from being centered exactly on the chart edge.
                      minX: -0.25,
                      maxX: maxX + 0.25,
                      minY: 0,
                      maxY: maxCount.toDouble() + 1,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            reservedSize: 36,
                            showTitles: true,
                            interval: _countAxisInterval(maxCount),
                            getTitlesWidget: (value, meta) =>
                                _countAxisTitle(context, value),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 38,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              final shouldShow =
                                  index == 0 ||
                                  index == days.length - 1 ||
                                  index % labelStride == 0;
                              if (!_isWholeChartValue(value) ||
                                  index < 0 ||
                                  index >= days.length ||
                                  !shouldShow) {
                                return const SizedBox.shrink();
                              }
                              final day = days[index];
                              return Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: SizedBox(
                                  width: 48,
                                  child: Text(
                                    '${day.month}/${day.day}',
                                    textAlign: TextAlign.center,
                                    maxLines: 1,
                                    overflow: TextOverflow.visible,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          barWidth: 3,
                          color: Theme.of(context).colorScheme.primary,
                          dotData: const FlDotData(show: true),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AreaChart extends StatelessWidget {
  const _AreaChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.areaName] = (counts[record.areaName] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxCount = max(1, entries.map((entry) => entry.value).reduce(max));
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byArea'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final rotateLabels = constraints.maxWidth < entries.length * 96;
                final categoryWidth = rotateLabels ? 100.0 : 112.0;
                final chartWidth = max(
                  constraints.maxWidth,
                  entries.length * categoryWidth,
                );

                return _horizontalChartViewport(
                  width: chartWidth,
                  height: rotateLabels ? 300 : 250,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      minY: 0,
                      maxY: maxCount.toDouble() + 1,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        leftTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: rotateLabels ? 96 : 60,
                            interval: 1,
                            getTitlesWidget: (value, meta) {
                              final index = value.toInt();
                              if (!_isWholeChartValue(value) ||
                                  index < 0 ||
                                  index >= entries.length) {
                                return const SizedBox.shrink();
                              }
                              return _categoryAxisTitle(
                                context,
                                label: entries[index].key,
                                rotated: rotateLabels,
                              );
                            },
                          ),
                        ),
                      ),
                      barGroups: [
                        for (var i = 0; i < entries.length; i++)
                          BarChartGroupData(
                            x: i,
                            barRods: [
                              BarChartRodData(
                                toY: entries[i].value.toDouble(),
                                width: rotateLabels ? 26 : 32,
                                borderRadius: BorderRadius.circular(4),
                                color: color,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _IdentityChart extends StatelessWidget {
  const _IdentityChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{};
    for (final record in records) {
      counts[record.identity] = (counts[record.identity] ?? 0) + 1;
    }
    final colors = [
      const Color(0xFF14746F),
      const Color(0xFFD97706),
      const Color(0xFF2563EB),
      const Color(0xFF7C3AED),
      const Color(0xFFDB2777),
      const Color(0xFF475569),
      const Color(0xFF16A34A),
    ];
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    Widget legend() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < entries.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: colors[i % colors.length],
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text.option('identity', entries[i].key)),
                  ),
                  const SizedBox(width: 12),
                  Text(entries[i].value.toString()),
                ],
              ),
            ),
        ],
      );
    }

    Widget pie(double size) {
      final sectionRadius = max(48.0, size * 0.30);
      final centerRadius = max(30.0, size * 0.17);

      return SizedBox.square(
        dimension: size,
        child: PieChart(
          PieChartData(
            centerSpaceRadius: centerRadius,
            sectionsSpace: 2,
            sections: [
              for (var i = 0; i < entries.length; i++)
                PieChartSectionData(
                  value: entries[i].value.toDouble(),
                  title: entries[i].value.toString(),
                  color: colors[i % colors.length],
                  radius: sectionRadius,
                  titleStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byIdentity'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 620;
                final pieSize = compact
                    ? min(220.0, max(170.0, constraints.maxWidth * 0.56))
                    : min(240.0, max(190.0, constraints.maxWidth * 0.34));

                // Small screens give the legend a full row below the pie.
                // This avoids the old fixed-height row that clipped the chart.
                if (compact) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Align(alignment: Alignment.center, child: pie(pieSize)),
                      const SizedBox(height: 12),
                      legend(),
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SizedBox(width: pieSize, child: pie(pieSize)),
                    const SizedBox(width: 24),
                    Expanded(child: legend()),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _RelationshipChart extends StatelessWidget {
  const _RelationshipChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{for (final level in relationshipLevels) level: 0};
    for (final record in records) {
      counts[record.relationshipLevel] =
          (counts[record.relationshipLevel] ?? 0) + 1;
    }
    final maxCount = max(1, counts.values.reduce(max));
    final color = Theme.of(context).colorScheme.primary;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byRelationship'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxCount.toDouble() + 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        reservedSize: 36,
                        showTitles: true,
                        interval: _countAxisInterval(maxCount),
                        getTitlesWidget: (value, meta) =>
                            _countAxisTitle(context, value),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
                        getTitlesWidget: (value, meta) {
                          final level = value.toInt() + 1;
                          if (!_isWholeChartValue(value) ||
                              !relationshipLevels.contains(level)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              text.localeCode == 'zh' ? '$level级' : 'L$level',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final level in relationshipLevels)
                      BarChartGroupData(
                        x: level - 1,
                        barRods: [
                          BarChartRodData(
                            toY: (counts[level] ?? 0).toDouble(),
                            width: 32,
                            borderRadius: BorderRadius.circular(4),
                            color: color,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: [
                for (final level in relationshipLevels)
                  Text(
                    text.option('relationship', _relationshipKey(level)),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestChart extends StatelessWidget {
  const _InterestChart({required this.records, required this.text});

  final List<ConversationRecord> records;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final counts = <int, int>{for (final level in interestLevels) level: 0};
    for (final record in records) {
      counts[record.interestLevel] = (counts[record.interestLevel] ?? 0) + 1;
    }
    final maxCount = max(1, counts.values.reduce(max));
    final colors = {
      0: const Color(0xFFB91C1C),
      1: const Color(0xFFD97706),
      2: const Color(0xFF64748B),
      3: const Color(0xFF0D9488),
      4: const Color(0xFF15803D),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text.t('byInterest'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 240,
              child: BarChart(
                BarChartData(
                  minY: 0,
                  maxY: maxCount.toDouble() + 1,
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        reservedSize: 36,
                        showTitles: true,
                        interval: _countAxisInterval(maxCount),
                        getTitlesWidget: (value, meta) =>
                            _countAxisTitle(context, value),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        getTitlesWidget: (value, meta) {
                          final level = value.toInt();
                          if (!_isWholeChartValue(value) ||
                              !interestLevels.contains(level)) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              text.localeCode == 'zh' ? '$level级' : 'L$level',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  barGroups: [
                    for (final level in interestLevels)
                      BarChartGroupData(
                        x: level,
                        barRods: [
                          BarChartRodData(
                            toY: (counts[level] ?? 0).toDouble(),
                            width: 32,
                            borderRadius: BorderRadius.circular(4),
                            color: colors[level],
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _AccessScopeBanner extends StatelessWidget {
  const _AccessScopeBanner({required this.controller, required this.text});

  final AppController controller;
  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    final user = controller.currentUser;
    final cities = user?.cityNames.join(', ') ?? '-';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            Icons.policy_outlined,
            color: Theme.of(context).colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${text.t('accessScopeHint')} · ${text.t('allowedCities')}: $cities',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoStrip extends StatelessWidget {
  const _InfoStrip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 10),
          Text('$label: '),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeartRateTile extends StatelessWidget {
  const _HeartRateTile({
    required this.text,
    required this.value,
    required this.statusKey,
    required this.loading,
    required this.onTap,
  });

  final AppStrings text;
  final double? value;
  final String statusKey;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = value == null
        ? text.t(statusKey)
        : '${value!.toStringAsFixed(0)} bpm';
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: loading ? null : onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.monitor_heart_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(text.t('averageHeartRate')),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ),
            if (loading)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.lock_open_outlined),
          ],
        ),
      ),
    );
  }
}

class _OptionDropdown extends StatelessWidget {
  const _OptionDropdown({
    required this.label,
    required this.value,
    required this.values,
    required this.group,
    required this.text,
    required this.onChanged,
  });

  final String label;
  final String value;
  final List<String> values;
  final String group;
  final AppStrings text;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final item in values)
          DropdownMenuItem(value: item, child: Text(text.option(group, item))),
      ],
      onChanged: (selected) {
        if (selected != null) {
          onChanged(selected);
        }
      },
    );
  }
}

class _ContactDraftRow extends StatelessWidget {
  const _ContactDraftRow({
    required this.draft,
    required this.text,
    required this.canRemove,
    required this.onChanged,
    required this.onRemove,
  });

  final _ContactDraft draft;
  final AppStrings text;
  final bool canRemove;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final dropdown = DropdownButtonFormField<String>(
          initialValue: draft.channel,
          decoration: InputDecoration(labelText: text.t('contactChannel')),
          items: [
            for (final item in contactChannelOptions)
              DropdownMenuItem(
                value: item,
                child: Text(text.option('contact', item)),
              ),
          ],
          onChanged: (selected) {
            if (selected != null) {
              draft.channel = selected;
              onChanged();
            }
          },
        );
        final valueField = TextField(
          controller: draft.controller,
          decoration: InputDecoration(
            labelText: text.t('contactValue'),
            hintText: text.t('contactHint'),
            prefixIcon: const Icon(Icons.contact_phone_outlined),
          ),
        );
        final removeButton = IconButton(
          tooltip: text.t('removeContact'),
          onPressed: canRemove ? onRemove : null,
          icon: const Icon(Icons.remove_circle_outline),
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dropdown,
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: valueField),
                  const SizedBox(width: 8),
                  removeButton,
                ],
              ),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 180, child: dropdown),
            const SizedBox(width: 12),
            Expanded(child: valueField),
            const SizedBox(width: 4),
            removeButton,
          ],
        );
      },
    );
  }
}

class _ChartBuilderPreview extends StatelessWidget {
  const _ChartBuilderPreview({required this.text});

  final AppStrings text;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.auto_graph_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    text.t('chartBuilder'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(text.t('chartBuilderHint')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InterestSlider extends StatelessWidget {
  const _InterestSlider({
    required this.value,
    required this.text,
    required this.onChanged,
  });

  final int value;
  final AppStrings text;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = text.option('interest', _interestKey(value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            selectedLabel,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: 4,
          divisions: 4,
          label: selectedLabel,
          onChanged: (next) => onChanged(next.round()),
        ),
        Row(
          children: [
            for (final level in interestLevels)
              Expanded(
                child: Text(
                  text.localeCode == 'zh' ? '$level级' : 'L$level',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _RelationshipSlider extends StatelessWidget {
  const _RelationshipSlider({
    required this.value,
    required this.text,
    required this.onChanged,
  });

  final int value;
  final AppStrings text;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedLabel = text.option('relationship', _relationshipKey(value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(text.t('relationship')),
        const SizedBox(height: 6),
        Center(
          child: Text(
            selectedLabel,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
        ),
        Slider(
          value: value.toDouble(),
          min: 1,
          max: 4,
          divisions: 3,
          label: selectedLabel,
          onChanged: (next) => onChanged(next.round()),
        ),
        Row(
          children: [
            for (final level in relationshipLevels)
              Expanded(
                child: Text(
                  text.localeCode == 'zh' ? '$level级' : 'L$level',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          text.t('relationshipHelp'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(label),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(color: Theme.of(context).colorScheme.outline),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

Widget _horizontalChartViewport({
  required double width,
  required double height,
  required Widget child,
}) {
  // Keep the card itself fixed while only the plot scrolls. This is friendlier
  // on phones than shrinking every label until the chart becomes unreadable.
  return SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: SizedBox(width: width, height: height, child: child),
  );
}

Widget _categoryAxisTitle(
  BuildContext context, {
  required String label,
  required bool rotated,
}) {
  final style = Theme.of(context).textTheme.bodySmall;
  if (rotated) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RotatedBox(
        quarterTurns: 3,
        child: SizedBox(
          width: 80,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ),
    );
  }

  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: SizedBox(
      width: 96,
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: style,
      ),
    ),
  );
}

double _countAxisInterval(int maxCount) {
  return max(1, (maxCount / 3).ceil()).toDouble();
}

Widget _countAxisTitle(BuildContext context, double value) {
  if (!_isWholeChartValue(value)) {
    return const SizedBox.shrink();
  }
  return Text(
    value.toInt().toString(),
    style: Theme.of(context).textTheme.bodySmall,
  );
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _formatBirthday(DateTime? value) {
  if (value == null) {
    return '-';
  }
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String _coordinateText(double? value) {
  if (value == null) {
    return '';
  }
  return value.toStringAsFixed(6);
}

String _formatPercent(double? value) {
  if (value == null) {
    return '-';
  }
  return '${(value * 100).toStringAsFixed(0)}%';
}

bool _isWholeChartValue(double value) {
  return (value - value.roundToDouble()).abs() < 0.01;
}

String _interestKey(int value) {
  return switch (value) {
    0 => 'rejected',
    1 => 'low',
    3 => 'interested',
    4 => 'high',
    _ => 'neutral',
  };
}

String _relationshipKey(int value) {
  return switch (value) {
    2 => 'familiar_contact',
    3 => 'very_interested',
    4 => 'companion',
    _ => 'new_contact',
  };
}
