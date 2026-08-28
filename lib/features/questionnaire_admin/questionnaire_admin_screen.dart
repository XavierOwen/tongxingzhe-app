import 'dart:async';

import 'package:flutter/material.dart';

import '../../foundation/runtime_values.dart';
import '../../l10n/app_strings.dart';
import '../../questionnaires/questionnaire_administration.dart';
import '../../questionnaires/questionnaire_contract.dart';
import '../../questionnaires/questionnaire_metric_compatibility.dart';
import '../contact_entry/questionnaire_form.dart';
import 'questionnaire_admin_view_model.dart';
import 'questionnaire_metric_compatibility_panel.dart';

final class QuestionnaireAdminScreen extends StatefulWidget {
  const QuestionnaireAdminScreen({
    super.key,
    required this.localeCode,
    required this.gateway,
    required this.idGenerator,
  });

  final String localeCode;
  final QuestionnaireAdministrationGateway gateway;
  final IdGenerator idGenerator;

  @override
  State<QuestionnaireAdminScreen> createState() =>
      _QuestionnaireAdminScreenState();
}

final class _QuestionnaireAdminScreenState
    extends State<QuestionnaireAdminScreen> {
  late final QuestionnaireAdminViewModel _viewModel;
  final TextEditingController _publicationNoteController =
      TextEditingController();
  QuestionnaireAdministrationFailureCode? _shownFailure;

  @override
  void initState() {
    super.initState();
    _viewModel = QuestionnaireAdminViewModel(
      gateway: widget.gateway,
      idGenerator: widget.idGenerator,
    )..addListener(_stateChanged);
    unawaited(_viewModel.initialize());
  }

  @override
  void dispose() {
    _viewModel
      ..removeListener(_stateChanged)
      ..dispose();
    _publicationNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = AppStrings(widget.localeCode);
    final state = _viewModel.state;
    if (state.stage == QuestionnaireAdminStage.loading) {
      return Scaffold(
        appBar: AppBar(title: Text(text.t('questionnaireManage'))),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (state.snapshot == null || state.currentVersion == null) {
      return Scaffold(
        appBar: AppBar(title: Text(text.t('questionnaireManage'))),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text.t('questionnaireAdminLoadFailed')),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: state.isBusy
                    ? null
                    : () => unawaited(_viewModel.initialize()),
                icon: const Icon(Icons.refresh_outlined),
                label: Text(text.t('retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (state.draft == null || state.definition == null) {
      return _chooser(text, state);
    }
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(text.t('questionnaireDraftEditor')),
          leading: IconButton(
            key: const ValueKey('close-questionnaire-draft'),
            onPressed: state.isBusy ? null : _viewModel.closeDraft,
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            TextButton.icon(
              key: const ValueKey('save-questionnaire-draft'),
              onPressed: !state.isDirty || state.isBusy
                  ? null
                  : () => unawaited(_viewModel.save()),
              icon: const Icon(Icons.save_outlined),
              label: Text(text.t('saveDraft')),
            ),
          ],
          bottom: TabBar(
            tabs: [
              Tab(text: text.t('questionnaireDesign')),
              Tab(text: text.t('questionnairePreview')),
              Tab(text: text.t('questionnairePublish')),
            ],
          ),
        ),
        body: Stack(
          children: [
            TabBarView(
              children: [
                _designTab(text, state),
                _previewTab(text, state),
                _publishTab(text, state),
              ],
            ),
            if (state.isBusy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x22000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _chooser(AppStrings text, QuestionnaireAdminViewState state) {
    final snapshot = state.snapshot!;
    return Scaffold(
      appBar: AppBar(title: Text(text.t('questionnaireManage'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            text.t('questionnaireDrafts'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (snapshot.drafts.isEmpty) Text(text.t('questionnaireNoDrafts')),
          for (final draft in snapshot.drafts)
            Card(
              child: ListTile(
                key: ValueKey('questionnaire-draft-${draft.id}'),
                leading: const Icon(Icons.edit_note_outlined),
                title: Text(
                  '${text.t('questionnaireDraftRevision')} ${draft.revision}',
                ),
                subtitle: Text(
                  draft.sourceVersionId == null
                      ? text.t('questionnaireBlankDraft')
                      : text.t('questionnaireCopiedDraft'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: state.isBusy ? null : () => _viewModel.openDraft(draft),
              ),
            ),
          const SizedBox(height: 20),
          FilledButton.icon(
            key: const ValueKey('create-blank-questionnaire-draft'),
            onPressed: state.isBusy
                ? null
                : () => unawaited(_viewModel.createDraft()),
            icon: const Icon(Icons.note_add_outlined),
            label: Text(text.t('questionnaireCreateBlank')),
          ),
          const SizedBox(height: 20),
          Text(
            text.t('questionnairePublishedVersions'),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          for (final version in snapshot.versions)
            Card(
              child: ListTile(
                key: ValueKey('questionnaire-version-${version.id}'),
                leading: Icon(
                  version.isCurrent
                      ? Icons.check_circle_outline
                      : Icons.history_outlined,
                ),
                title: Text(
                  '${text.t('questionnaireVersion')} ${version.versionNumber}',
                ),
                subtitle: Text(
                  version.isCurrent
                      ? text.t('questionnaireCurrentVersion')
                      : version.publicationNote ??
                            text.t('questionnaireNoPublicationNote'),
                ),
                trailing: TextButton(
                  onPressed: state.isBusy
                      ? null
                      : () => unawaited(
                          _viewModel.createDraft(sourceVersionId: version.id),
                        ),
                  child: Text(text.t('questionnaireCopyAsDraft')),
                ),
              ),
            ),
          if (widget.gateway is QuestionnaireMetricCompatibilityGateway)
            QuestionnaireMetricCompatibilityPanel(
              text: text,
              gateway:
                  widget.gateway as QuestionnaireMetricCompatibilityGateway,
              idGenerator: widget.idGenerator,
            ),
        ],
      ),
    );
  }

  Widget _designTab(AppStrings text, QuestionnaireAdminViewState state) {
    final questions = state.definition!.questions;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(text.t('questionnaireDesignHelp')),
        const SizedBox(height: 12),
        if (questions.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(text.t('questionnaireEmptyDraft')),
            ),
          ),
        for (var index = 0; index < questions.length; index += 1)
          Card(
            key: ValueKey('design-question-${questions[index].id}'),
            child: ListTile(
              leading: CircleAvatar(child: Text('${index + 1}')),
              title: Text(questions[index].prompt),
              subtitle: Text(_questionSummary(text, questions[index])),
              isThreeLine: questions[index].displayRule != null,
              trailing: PopupMenuButton<String>(
                onSelected: (action) =>
                    _questionAction(action, questions[index], questions),
                itemBuilder: (context) => [
                  PopupMenuItem(value: 'edit', child: Text(text.t('edit'))),
                  PopupMenuItem(
                    value: 'up',
                    enabled: index > 0,
                    child: Text(text.t('moveUp')),
                  ),
                  PopupMenuItem(
                    value: 'down',
                    enabled: index + 1 < questions.length,
                    child: Text(text.t('moveDown')),
                  ),
                  PopupMenuItem(value: 'delete', child: Text(text.t('delete'))),
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const ValueKey('add-questionnaire-question'),
          onPressed: state.isBusy ? null : () => _editQuestion(null, questions),
          icon: const Icon(Icons.add),
          label: Text(text.t('questionnaireAddQuestion')),
        ),
      ],
    );
  }

  Widget _previewTab(AppStrings text, QuestionnaireAdminViewState state) {
    final evaluation = state.previewEvaluation!;
    final definition = state.definition!;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(text.t('questionnairePreviewHelp')),
        const SizedBox(height: 12),
        if (definition.questions.isEmpty)
          Text(text.t('questionnaireEmptyDraft'))
        else
          QuestionnaireForm(
            key: ValueKey(
              'questionnaire-preview-${state.draft!.revision}-'
              '${definition.questions.length}',
            ),
            text: text,
            version: definition,
            answers: state.previewAnswers,
            errors: evaluation.errors,
            visibleQuestionIds: evaluation.visibleQuestionIds,
            onValueChanged: _viewModel.setPreviewValue,
            onStateChanged: _viewModel.setPreviewState,
          ),
      ],
    );
  }

  Widget _publishTab(AppStrings text, QuestionnaireAdminViewState state) {
    final differences = state.differences;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          text.t('questionnaireChanges'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        if (differences.isEmpty)
          Text(text.t('questionnaireNoChanges'))
        else
          for (final difference in differences)
            ListTile(
              dense: true,
              leading: Icon(_differenceIcon(difference.kind)),
              title: Text(difference.questionId),
              subtitle: Text(
                difference.fields
                    .map((field) => _differenceLabel(text, field))
                    .join(' · '),
              ),
            ),
        const Divider(height: 32),
        TextField(
          key: const ValueKey('questionnaire-publication-note'),
          controller: _publicationNoteController,
          maxLength: 500,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: text.t('questionnairePublicationNote'),
            helperText: text.t('questionnairePublicationNoteHelp'),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 12),
        Text(text.t('questionnairePublishTransactionHelp')),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('publish-questionnaire-draft'),
          onPressed:
              state.isBusy ||
                  state.definition!.questions.isEmpty ||
                  _publicationNoteController.text.trim().isEmpty
              ? null
              : () => unawaited(
                  _viewModel.publish(_publicationNoteController.text),
                ),
          icon: const Icon(Icons.publish_outlined),
          label: Text(text.t('questionnairePublishNewVersion')),
        ),
      ],
    );
  }

  Future<void> _questionAction(
    String action,
    QuestionnaireQuestion question,
    List<QuestionnaireQuestion> questions,
  ) async {
    switch (action) {
      case 'edit':
        await _editQuestion(question, questions);
      case 'up':
        _viewModel.moveQuestion(question.id, -1);
      case 'down':
        _viewModel.moveQuestion(question.id, 1);
      case 'delete':
        _viewModel.removeQuestion(question.id);
    }
  }

  Future<void> _editQuestion(
    QuestionnaireQuestion? question,
    List<QuestionnaireQuestion> questions,
  ) async {
    final edited = await showDialog<QuestionnaireQuestion>(
      context: context,
      builder: (context) => _QuestionEditorDialog(
        text: AppStrings(widget.localeCode),
        idGenerator: widget.idGenerator,
        existing: question,
        earlierQuestions: [
          for (final candidate in questions)
            if (question == null || candidate.position < question.position)
              candidate,
        ],
      ),
    );
    if (edited == null) return;
    question == null
        ? _viewModel.addQuestion(edited)
        : _viewModel.updateQuestion(edited);
  }

  void _stateChanged() {
    if (!mounted) return;
    setState(() {});
    final state = _viewModel.state;
    if (state.stage == QuestionnaireAdminStage.published) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop(true);
      });
      return;
    }
    final failure = state.failureCode;
    if (failure != null && failure != _shownFailure) {
      _shownFailure = failure;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final text = AppStrings(widget.localeCode);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_failureLabel(text, failure))));
      });
    }
    if (failure == null) _shownFailure = null;
  }
}

final class _QuestionEditorDialog extends StatefulWidget {
  const _QuestionEditorDialog({
    required this.text,
    required this.idGenerator,
    required this.existing,
    required this.earlierQuestions,
  });

  final AppStrings text;
  final IdGenerator idGenerator;
  final QuestionnaireQuestion? existing;
  final List<QuestionnaireQuestion> earlierQuestions;

  @override
  State<_QuestionEditorDialog> createState() => _QuestionEditorDialogState();
}

final class _QuestionEditorDialogState extends State<_QuestionEditorDialog> {
  late QuestionnaireQuestionType _type;
  late bool _required;
  late bool _allowUnknown;
  late bool _allowRefused;
  late bool _allowNotApplicable;
  late QuestionnaireNumberKind _numberKind;
  late final TextEditingController _prompt;
  late final TextEditingController _options;
  late final TextEditingController _minimum;
  late final TextEditingController _maximum;
  late final TextEditingController _unit;
  late final TextEditingController _maximumLength;
  bool _hasRule = false;
  late QuestionnaireVisibilityMatch _ruleMatch;
  final List<_RuleConditionDraft> _ruleConditions = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _type = existing?.type ?? QuestionnaireQuestionType.boolean;
    _required = existing?.required ?? false;
    _allowUnknown = existing?.allowUnknown ?? false;
    _allowRefused = existing?.allowRefused ?? true;
    _allowNotApplicable = existing?.allowNotApplicable ?? true;
    _numberKind = existing?.numberKind ?? QuestionnaireNumberKind.integer;
    _prompt = TextEditingController(text: existing?.prompt ?? '');
    _options = TextEditingController(
      text: existing?.options.map((option) => option.label).join('\n') ?? '',
    );
    _minimum = TextEditingController(text: existing?.minimum?.toString() ?? '');
    _maximum = TextEditingController(text: existing?.maximum?.toString() ?? '');
    _unit = TextEditingController(text: existing?.unit ?? '');
    _maximumLength = TextEditingController(
      text: existing?.maximumLength?.toString() ?? '120',
    );
    final displayRule = existing?.displayRule;
    _hasRule = displayRule != null;
    _ruleMatch = displayRule?.match ?? QuestionnaireVisibilityMatch.all;
    for (final condition
        in displayRule?.conditions ??
            const <QuestionnaireVisibilityCondition>[]) {
      _ruleConditions.add(
        _RuleConditionDraft.fromCondition(condition, widget.earlierQuestions),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _prompt,
      _options,
      _minimum,
      _maximum,
      _unit,
      _maximumLength,
    ]) {
      controller.dispose();
    }
    for (final condition in _ruleConditions) {
      condition.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final choice = _isChoice(_type);
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? widget.text.t('questionnaireAddQuestion')
            : widget.text.t('questionnaireEditQuestion'),
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<QuestionnaireQuestionType>(
                key: const ValueKey('question-editor-type'),
                initialValue: _type,
                decoration: InputDecoration(
                  labelText: widget.text.t('questionnaireQuestionType'),
                ),
                items: [
                  for (final type in QuestionnaireQuestionType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(_typeLabel(widget.text, type)),
                    ),
                ],
                onChanged: widget.existing == null
                    ? (value) => setState(() => _type = value!)
                    : null,
              ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('question-editor-prompt'),
                controller: _prompt,
                decoration: InputDecoration(
                  labelText: widget.text.t('questionnaireQuestionPrompt'),
                ),
              ),
              CheckboxListTile(
                value: _required,
                onChanged: (value) => setState(() => _required = value!),
                title: Text(widget.text.t('questionnaireRequired')),
                contentPadding: EdgeInsets.zero,
              ),
              _stateSwitch(
                widget.text.t('questionnaireAllowUnknown'),
                _allowUnknown,
                (value) => _allowUnknown = value,
              ),
              _stateSwitch(
                widget.text.t('questionnaireAllowRefused'),
                _allowRefused,
                (value) => _allowRefused = value,
              ),
              _stateSwitch(
                widget.text.t('questionnaireAllowNotApplicable'),
                _allowNotApplicable,
                (value) => _allowNotApplicable = value,
              ),
              if (choice) ...[
                const SizedBox(height: 8),
                TextField(
                  key: const ValueKey('question-editor-options'),
                  controller: _options,
                  minLines: 2,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: widget.text.t('questionnaireOptions'),
                    helperText: widget.text.t('questionnaireOptionsHelp'),
                  ),
                ),
              ],
              if (_type == QuestionnaireQuestionType.number) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<QuestionnaireNumberKind>(
                  initialValue: _numberKind,
                  decoration: InputDecoration(
                    labelText: widget.text.t('questionnaireNumberKind'),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: QuestionnaireNumberKind.integer,
                      child: Text(widget.text.t('questionnaireInteger')),
                    ),
                    DropdownMenuItem(
                      value: QuestionnaireNumberKind.decimal,
                      child: Text(widget.text.t('questionnaireDecimal')),
                    ),
                  ],
                  onChanged: (value) => setState(() => _numberKind = value!),
                ),
                Row(
                  children: [
                    Expanded(child: _numberField(_minimum, 'minimum')),
                    const SizedBox(width: 8),
                    Expanded(child: _numberField(_maximum, 'maximum')),
                  ],
                ),
                TextField(
                  controller: _unit,
                  decoration: InputDecoration(
                    labelText: widget.text.t('questionnaireUnit'),
                  ),
                ),
              ],
              if (_type == QuestionnaireQuestionType.shortText ||
                  _type == QuestionnaireQuestionType.longText)
                TextField(
                  controller: _maximumLength,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: widget.text.t('questionnaireMaximumLength'),
                  ),
                ),
              if (widget.earlierQuestions.isNotEmpty) ...[
                const Divider(height: 28),
                SwitchListTile(
                  value: _hasRule,
                  onChanged: (value) => setState(() {
                    _hasRule = value;
                    if (value && _ruleConditions.isEmpty) {
                      _ruleConditions.add(_RuleConditionDraft());
                    } else if (!value) {
                      for (final condition in _ruleConditions) {
                        condition.dispose();
                      }
                      _ruleConditions.clear();
                    }
                  }),
                  title: Text(widget.text.t('questionnaireDisplayRule')),
                  contentPadding: EdgeInsets.zero,
                ),
                if (_hasRule) ...[
                  DropdownButtonFormField<QuestionnaireVisibilityMatch>(
                    key: const ValueKey('question-rule-match'),
                    initialValue: _ruleMatch,
                    decoration: InputDecoration(
                      labelText: widget.text.t('questionnaireRuleMatch'),
                    ),
                    items: [
                      for (final match in QuestionnaireVisibilityMatch.values)
                        DropdownMenuItem(
                          value: match,
                          child: Text(
                            widget.text.t(
                              match == QuestionnaireVisibilityMatch.all
                                  ? 'questionnaireRuleMatchAll'
                                  : 'questionnaireRuleMatchAny',
                            ),
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() => _ruleMatch = value!),
                  ),
                  const SizedBox(height: 8),
                  for (
                    var index = 0;
                    index < _ruleConditions.length;
                    index += 1
                  )
                    _conditionEditor(index),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const ValueKey('question-rule-add-condition'),
                      onPressed: _ruleConditions.length >= 20
                          ? null
                          : () => setState(
                              () => _ruleConditions.add(_RuleConditionDraft()),
                            ),
                      icon: const Icon(Icons.add),
                      label: Text(
                        widget.text.t('questionnaireRuleAddCondition'),
                      ),
                    ),
                  ),
                ],
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(widget.text.t('cancel')),
        ),
        FilledButton(
          key: const ValueKey('save-questionnaire-question'),
          onPressed: _submit,
          child: Text(widget.text.t('save')),
        ),
      ],
    );
  }

  Widget _stateSwitch(String label, bool value, ValueChanged<bool> update) =>
      SwitchListTile(
        value: value,
        onChanged: (next) => setState(() => update(next)),
        title: Text(label),
        contentPadding: EdgeInsets.zero,
      );

  Widget _numberField(TextEditingController controller, String keyName) =>
      TextField(
        key: ValueKey('question-editor-$keyName'),
        controller: controller,
        keyboardType: const TextInputType.numberWithOptions(
          decimal: true,
          signed: true,
        ),
        decoration: InputDecoration(labelText: widget.text.t(keyName)),
      );

  Widget _conditionEditor(int index) {
    final condition = _ruleConditions[index];
    final source = condition.source;
    return Container(
      key: ValueKey('question-rule-condition-$index'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${widget.text.t('questionnaireRuleCondition')} ${index + 1}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: ValueKey('question-rule-remove-condition-$index'),
                tooltip: widget.text.t('questionnaireRuleRemoveCondition'),
                onPressed: _ruleConditions.length == 1
                    ? null
                    : () => setState(() {
                        _ruleConditions.removeAt(index).dispose();
                      }),
                icon: const Icon(Icons.remove_circle_outline),
              ),
            ],
          ),
          DropdownButtonFormField<QuestionnaireQuestion>(
            key: ValueKey('question-rule-source-$index'),
            initialValue: source,
            decoration: InputDecoration(
              labelText: widget.text.t('questionnaireRuleSource'),
            ),
            items: [
              for (final question in widget.earlierQuestions)
                DropdownMenuItem(value: question, child: Text(question.prompt)),
            ],
            onChanged: (value) => setState(() {
              condition.source = value;
              condition.operator = value == null
                  ? null
                  : _operators(value.type).first;
              condition.clearOperand();
            }),
          ),
          if (source != null) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<QuestionnaireVisibilityOperator>(
              key: ValueKey('question-rule-operator-$index'),
              initialValue: condition.operator,
              decoration: InputDecoration(
                labelText: widget.text.t('questionnaireRuleOperator'),
              ),
              items: [
                for (final operator in _operators(source.type))
                  DropdownMenuItem(
                    value: operator,
                    child: Text(operator.storageValue),
                  ),
              ],
              onChanged: (value) => setState(() {
                condition.operator = value;
                condition.clearOperand();
              }),
            ),
            if (condition.operator !=
                    QuestionnaireVisibilityOperator.isAnswered &&
                condition.operator !=
                    QuestionnaireVisibilityOperator.isUnanswered)
              _operandControl(condition, index),
          ],
          if (index + 1 < _ruleConditions.length) const Divider(height: 24),
        ],
      ),
    );
  }

  Widget _operandControl(_RuleConditionDraft condition, int index) {
    final source = condition.source!;
    if (source.type == QuestionnaireQuestionType.boolean) {
      if (condition.operator == QuestionnaireVisibilityOperator.inSet) {
        return InputDecorator(
          key: ValueKey('question-rule-operand-$index'),
          decoration: InputDecoration(
            labelText: widget.text.t('questionnaireRuleOperand'),
          ),
          child: Wrap(
            spacing: 8,
            children: [
              for (final value in const [true, false])
                FilterChip(
                  label: Text(value.toString()),
                  selected: condition.booleanOperands.contains(value),
                  onSelected: (selected) => setState(() {
                    selected
                        ? condition.booleanOperands.add(value)
                        : condition.booleanOperands.remove(value);
                  }),
                ),
            ],
          ),
        );
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('question-rule-operand-$index'),
        initialValue: condition.operand.text.isEmpty
            ? null
            : condition.operand.text,
        decoration: InputDecoration(
          labelText: widget.text.t('questionnaireRuleOperand'),
        ),
        items: const [
          DropdownMenuItem(value: 'true', child: Text('true')),
          DropdownMenuItem(value: 'false', child: Text('false')),
        ],
        onChanged: (value) => condition.operand.text = value ?? '',
      );
    }
    if (_isChoice(source.type)) {
      if (condition.operator == QuestionnaireVisibilityOperator.inSet) {
        return InputDecorator(
          key: ValueKey('question-rule-operand-$index'),
          decoration: InputDecoration(
            labelText: widget.text.t('questionnaireRuleOperand'),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in source.options)
                FilterChip(
                  label: Text(option.label),
                  selected: condition.choiceOperands.contains(option.id),
                  onSelected: (selected) => setState(() {
                    selected
                        ? condition.choiceOperands.add(option.id)
                        : condition.choiceOperands.remove(option.id);
                  }),
                ),
            ],
          ),
        );
      }
      return DropdownButtonFormField<String>(
        key: ValueKey('question-rule-operand-$index'),
        initialValue:
            source.options.any((option) => option.id == condition.choiceOperand)
            ? condition.choiceOperand
            : null,
        decoration: InputDecoration(
          labelText: widget.text.t('questionnaireRuleOperand'),
        ),
        items: [
          for (final option in source.options)
            DropdownMenuItem(value: option.id, child: Text(option.label)),
        ],
        onChanged: (value) => setState(() => condition.choiceOperand = value),
      );
    }
    return TextField(
      key: ValueKey('question-rule-operand-$index'),
      controller: condition.operand,
      decoration: InputDecoration(
        labelText: widget.text.t('questionnaireRuleOperand'),
        helperText:
            condition.operator == QuestionnaireVisibilityOperator.between
            ? widget.text.t('questionnaireBetweenHelp')
            : null,
      ),
    );
  }

  void _submit() {
    try {
      final prompt = _prompt.text.trim();
      if (prompt.isEmpty) throw const FormatException('prompt');
      final existing = widget.existing;
      final options = _isChoice(_type)
          ? _buildOptions(existing?.options ?? const [])
          : const <QuestionnaireOption>[];
      if (_isChoice(_type) && options.isEmpty) {
        throw const FormatException('options');
      }
      final minimum = _type == QuestionnaireQuestionType.number
          ? _nullableNumber(_minimum.text)
          : null;
      final maximum = _type == QuestionnaireQuestionType.number
          ? _nullableNumber(_maximum.text)
          : null;
      if (minimum != null && maximum != null && minimum > maximum) {
        throw const FormatException('range');
      }
      final maximumLength =
          _type == QuestionnaireQuestionType.shortText ||
              _type == QuestionnaireQuestionType.longText
          ? int.tryParse(_maximumLength.text.trim())
          : null;
      if ((_type == QuestionnaireQuestionType.shortText ||
              _type == QuestionnaireQuestionType.longText) &&
          (maximumLength == null || maximumLength < 1)) {
        throw const FormatException('length');
      }
      final displayRule = _buildDisplayRule();
      final question = QuestionnaireQuestion(
        id: existing?.id ?? widget.idGenerator.next(),
        position: existing?.position ?? widget.earlierQuestions.length + 1,
        prompt: prompt,
        type: _type,
        required: _required,
        allowUnknown: _allowUnknown,
        allowRefused: _allowRefused,
        allowNotApplicable: _allowNotApplicable,
        options: options,
        minimumSelections: _type == QuestionnaireQuestionType.multiChoice
            ? 1
            : null,
        maximumSelections: _type == QuestionnaireQuestionType.multiChoice
            ? options.length
            : null,
        numberKind: _type == QuestionnaireQuestionType.number
            ? _numberKind
            : null,
        unit:
            _type == QuestionnaireQuestionType.number &&
                _unit.text.trim().isNotEmpty
            ? _unit.text.trim()
            : null,
        minimum: minimum,
        maximum: maximum,
        maximumLength: maximumLength,
        displayRule: displayRule,
      );
      final validationVersion = QuestionnaireVersion(
        id: 'editor-preview',
        projectId: 'editor-preview',
        versionNumber: 1,
        questions: [...widget.earlierQuestions, question],
      );
      QuestionnaireContract.parseVersion(
        QuestionnaireContract.versionToJson(validationVersion),
      );
      Navigator.of(context).pop(question);
    } on Object {
      setState(() => _error = widget.text.t('questionnaireQuestionInvalid'));
    }
  }

  List<QuestionnaireOption> _buildOptions(List<QuestionnaireOption> existing) {
    final labels = _options.text
        .split('\n')
        .map((label) => label.trim())
        .where((label) => label.isNotEmpty)
        .toList();
    return [
      for (var index = 0; index < labels.length; index += 1)
        QuestionnaireOption(
          id: index < existing.length
              ? existing[index].id
              : widget.idGenerator.next(),
          position: index + 1,
          label: labels[index],
        ),
    ];
  }

  QuestionnaireVisibilityRule? _buildDisplayRule() {
    if (!_hasRule) return null;
    if (_ruleConditions.isEmpty) {
      throw const FormatException('rule');
    }
    return QuestionnaireVisibilityRule(
      match: _ruleMatch,
      conditions: [
        for (final condition in _ruleConditions)
          _buildVisibilityCondition(condition),
      ],
    );
  }

  QuestionnaireVisibilityCondition _buildVisibilityCondition(
    _RuleConditionDraft condition,
  ) {
    final source = condition.source;
    final operator = condition.operator;
    if (source == null || operator == null) {
      throw const FormatException('rule');
    }
    Object? operand;
    if (operator == QuestionnaireVisibilityOperator.isAnswered ||
        operator == QuestionnaireVisibilityOperator.isUnanswered) {
      operand = null;
    } else if (source.type == QuestionnaireQuestionType.boolean) {
      if (operator == QuestionnaireVisibilityOperator.inSet) {
        if (condition.booleanOperands.isEmpty) {
          throw const FormatException('operand');
        }
        operand = [
          if (condition.booleanOperands.contains(true)) true,
          if (condition.booleanOperands.contains(false)) false,
        ];
      } else {
        if (condition.operand.text != 'true' &&
            condition.operand.text != 'false') {
          throw const FormatException('operand');
        }
        operand = condition.operand.text == 'true';
      }
    } else if (_isChoice(source.type)) {
      if (operator == QuestionnaireVisibilityOperator.inSet) {
        final selected = [
          for (final option in source.options)
            if (condition.choiceOperands.contains(option.id)) option.id,
        ];
        if (selected.isEmpty) throw const FormatException('operand');
        operand = selected;
      } else {
        if (condition.choiceOperand == null) {
          throw const FormatException('operand');
        }
        operand = condition.choiceOperand;
      }
    } else if (source.type == QuestionnaireQuestionType.number) {
      operand = operator == QuestionnaireVisibilityOperator.between
          ? condition.operand.text.split(',').map((value) {
              final parsed = num.tryParse(value.trim());
              if (parsed == null) throw const FormatException('operand');
              return parsed;
            }).toList()
          : num.tryParse(condition.operand.text.trim());
      if (operand == null || operand is List && operand.length != 2) {
        throw const FormatException('operand');
      }
    } else {
      operand = operator == QuestionnaireVisibilityOperator.between
          ? condition.operand.text
                .split(',')
                .map((value) => value.trim())
                .toList()
          : condition.operand.text.trim();
      if (operand == '' || operand is List && operand.length != 2) {
        throw const FormatException('operand');
      }
    }
    return QuestionnaireVisibilityCondition(
      sourceQuestionId: source.id,
      operator: operator,
      operand: operand,
    );
  }
}

final class _RuleConditionDraft {
  _RuleConditionDraft({
    this.source,
    this.operator,
    String operandText = '',
    this.choiceOperand,
    Iterable<String> choiceOperands = const [],
    Iterable<bool> booleanOperands = const [],
  }) : operand = TextEditingController(text: operandText),
       choiceOperands = {...choiceOperands},
       booleanOperands = {...booleanOperands};

  factory _RuleConditionDraft.fromCondition(
    QuestionnaireVisibilityCondition condition,
    List<QuestionnaireQuestion> earlierQuestions,
  ) {
    final source = earlierQuestions
        .where((question) => question.id == condition.sourceQuestionId)
        .firstOrNull;
    final rawOperand = condition.operand;
    final isChoiceSource = source != null && _isChoice(source.type);
    return _RuleConditionDraft(
      source: source,
      operator: condition.operator,
      operandText: switch (rawOperand) {
        List<Object?> values => values.join(','),
        null => '',
        _ => rawOperand.toString(),
      },
      choiceOperand: isChoiceSource && rawOperand is String ? rawOperand : null,
      choiceOperands: isChoiceSource && rawOperand is List
          ? rawOperand.whereType<String>()
          : const [],
      booleanOperands:
          source?.type == QuestionnaireQuestionType.boolean &&
              rawOperand is List
          ? rawOperand.whereType<bool>()
          : const [],
    );
  }

  QuestionnaireQuestion? source;
  QuestionnaireVisibilityOperator? operator;
  final TextEditingController operand;
  String? choiceOperand;
  final Set<String> choiceOperands;
  final Set<bool> booleanOperands;

  void clearOperand() {
    operand.clear();
    choiceOperand = null;
    choiceOperands.clear();
    booleanOperands.clear();
  }

  void dispose() => operand.dispose();
}

List<QuestionnaireVisibilityOperator> _operators(
  QuestionnaireQuestionType type,
) => switch (type) {
  QuestionnaireQuestionType.boolean ||
  QuestionnaireQuestionType.singleChoice ||
  QuestionnaireQuestionType.ordinalChoice => const [
    QuestionnaireVisibilityOperator.equals,
    QuestionnaireVisibilityOperator.notEquals,
    QuestionnaireVisibilityOperator.inSet,
  ],
  QuestionnaireQuestionType.multiChoice => const [
    QuestionnaireVisibilityOperator.contains,
    QuestionnaireVisibilityOperator.notContains,
  ],
  QuestionnaireQuestionType.number || QuestionnaireQuestionType.date => const [
    QuestionnaireVisibilityOperator.equals,
    QuestionnaireVisibilityOperator.notEquals,
    QuestionnaireVisibilityOperator.greaterThan,
    QuestionnaireVisibilityOperator.greaterThanOrEqual,
    QuestionnaireVisibilityOperator.lessThan,
    QuestionnaireVisibilityOperator.lessThanOrEqual,
    QuestionnaireVisibilityOperator.between,
  ],
  QuestionnaireQuestionType.shortText ||
  QuestionnaireQuestionType.longText => const [
    QuestionnaireVisibilityOperator.isAnswered,
    QuestionnaireVisibilityOperator.isUnanswered,
  ],
};

bool _isChoice(QuestionnaireQuestionType type) =>
    type == QuestionnaireQuestionType.singleChoice ||
    type == QuestionnaireQuestionType.ordinalChoice ||
    type == QuestionnaireQuestionType.multiChoice;

num? _nullableNumber(String value) {
  final normalized = value.trim();
  return normalized.isEmpty ? null : num.tryParse(normalized);
}

String _questionSummary(AppStrings text, QuestionnaireQuestion question) {
  final parts = [
    _typeLabel(text, question.type),
    if (question.required) text.t('questionnaireRequired'),
    if (question.displayRule != null) text.t('questionnaireConditional'),
  ];
  return parts.join(' · ');
}

String _typeLabel(AppStrings text, QuestionnaireQuestionType type) => text.t(
  'questionnaireType${switch (type) {
    QuestionnaireQuestionType.boolean => 'Boolean',
    QuestionnaireQuestionType.singleChoice => 'SingleChoice',
    QuestionnaireQuestionType.ordinalChoice => 'OrdinalChoice',
    QuestionnaireQuestionType.multiChoice => 'MultiChoice',
    QuestionnaireQuestionType.number => 'Number',
    QuestionnaireQuestionType.date => 'Date',
    QuestionnaireQuestionType.shortText => 'ShortText',
    QuestionnaireQuestionType.longText => 'LongText',
  }}',
);

IconData _differenceIcon(QuestionnaireDifferenceKind kind) => switch (kind) {
  QuestionnaireDifferenceKind.added => Icons.add_circle_outline,
  QuestionnaireDifferenceKind.removed => Icons.remove_circle_outline,
  QuestionnaireDifferenceKind.changed => Icons.change_circle_outlined,
};

String _differenceLabel(AppStrings text, QuestionnaireDifferenceField field) =>
    text.t(
      'questionnaireDifference${switch (field) {
        QuestionnaireDifferenceField.definition => 'Definition',
        QuestionnaireDifferenceField.options => 'Options',
        QuestionnaireDifferenceField.valueBounds => 'ValueBounds',
        QuestionnaireDifferenceField.answerMode => 'AnswerMode',
        QuestionnaireDifferenceField.displayRule => 'DisplayRule',
      }}',
    );

String _failureLabel(
  AppStrings text,
  QuestionnaireAdministrationFailureCode code,
) => switch (code) {
  QuestionnaireAdministrationFailureCode.forbidden ||
  QuestionnaireAdministrationFailureCode.unauthorized => text.t(
    'questionnaireAdminForbidden',
  ),
  QuestionnaireAdministrationFailureCode.revisionConflict => text.t(
    'questionnaireDraftConflict',
  ),
  QuestionnaireAdministrationFailureCode.invalidDefinition => text.t(
    'questionnaireQuestionInvalid',
  ),
  QuestionnaireAdministrationFailureCode.notFound => text.t(
    'questionnaireDraftNotFound',
  ),
  QuestionnaireAdministrationFailureCode.networkUnavailable ||
  QuestionnaireAdministrationFailureCode.serverRejected => text.t(
    'questionnaireAdminLoadFailed',
  ),
};
