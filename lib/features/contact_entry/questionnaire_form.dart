import 'package:flutter/material.dart';

import '../../l10n/app_strings.dart';
import '../../questionnaires/questionnaire_contract.dart';

/// 已发布问卷的受控录入面板。
///
/// 这里只把八种合同类型翻译为 Material 控件。回答状态和值的分离、必填和
/// 范围判断仍由 [QuestionnaireCatalog.evaluate] 统一决定。
final class QuestionnaireForm extends StatefulWidget {
  const QuestionnaireForm({
    super.key,
    required this.text,
    required this.version,
    required this.answers,
    required this.errors,
    required this.onValueChanged,
    required this.onStateChanged,
  });

  final AppStrings text;
  final QuestionnaireVersion version;
  final List<QuestionnaireAnswer> answers;
  final List<QuestionnaireValidationError> errors;
  final void Function(QuestionnaireQuestion question, Object value)
  onValueChanged;
  final void Function(
    QuestionnaireQuestion question,
    QuestionnaireAnswerState state,
  )
  onStateChanged;

  @override
  State<QuestionnaireForm> createState() => _QuestionnaireFormState();
}

final class _QuestionnaireFormState extends State<QuestionnaireForm> {
  final Map<String, TextEditingController> _textControllers = {};

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final answers = {
      for (final answer in widget.answers) answer.questionId: answer,
    };
    final errors = <String, List<QuestionnaireValidationError>>{};
    for (final error in widget.errors) {
      errors.putIfAbsent(error.questionId, () => []).add(error);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text.t('questionnaireAnswers'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 6),
        Text(widget.text.t('questionnairePrivacyHelp')),
        const SizedBox(height: 8),
        for (final question in widget.version.questions) ...[
          _questionCard(
            context,
            question,
            answers[question.id],
            errors[question.id] ?? const [],
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _questionCard(
    BuildContext context,
    QuestionnaireQuestion question,
    QuestionnaireAnswer? answer,
    List<QuestionnaireValidationError> errors,
  ) {
    final state = answer?.state ?? QuestionnaireAnswerState.unanswered;
    return Card(
      key: ValueKey('question-${question.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${question.position}. ${question.prompt}'
              '${question.required ? ' *' : ''}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<QuestionnaireAnswerState>(
              key: ValueKey(
                'question-state-${question.id}-${state.storageValue}',
              ),
              initialValue: state,
              decoration: InputDecoration(
                labelText: widget.text.t('questionnaireAnswerState'),
              ),
              items: [
                for (final item in _availableStates(question, state))
                  DropdownMenuItem(value: item, child: Text(_stateLabel(item))),
              ],
              onChanged: (next) {
                if (next == null || next == QuestionnaireAnswerState.answered) {
                  return;
                }
                _textControllers[question.id]?.clear();
                widget.onStateChanged(question, next);
              },
            ),
            if (state == QuestionnaireAnswerState.answered ||
                answer == null) ...[
              const SizedBox(height: 12),
              _valueControl(question, answer),
            ],
            if (errors.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _errorLabel(errors.first),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<QuestionnaireAnswerState> _availableStates(
    QuestionnaireQuestion question,
    QuestionnaireAnswerState current,
  ) => [
    if (current == QuestionnaireAnswerState.answered)
      QuestionnaireAnswerState.answered,
    QuestionnaireAnswerState.unanswered,
    if (question.allowUnknown) QuestionnaireAnswerState.unknown,
    if (question.allowRefused) QuestionnaireAnswerState.refused,
    if (question.allowNotApplicable) QuestionnaireAnswerState.notApplicable,
  ];

  Widget _valueControl(
    QuestionnaireQuestion question,
    QuestionnaireAnswer? answer,
  ) {
    final value = answer?.state == QuestionnaireAnswerState.answered
        ? answer?.value
        : null;
    return switch (question.type) {
      QuestionnaireQuestionType.boolean => Wrap(
        spacing: 8,
        children: [
          for (final option in [true, false])
            ChoiceChip(
              key: ValueKey('question-${question.id}-$option'),
              label: Text(
                widget.text.t(
                  option ? 'questionnaireAnswerYes' : 'questionnaireAnswerNo',
                ),
              ),
              selected: value == option,
              onSelected: (_) => widget.onValueChanged(question, option),
            ),
        ],
      ),
      QuestionnaireQuestionType.singleChoice ||
      QuestionnaireQuestionType.ordinalChoice => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in question.options)
            ChoiceChip(
              key: ValueKey('question-${question.id}-${option.id}'),
              label: Text(option.label),
              selected: value == option.id,
              onSelected: (_) => widget.onValueChanged(question, option.id),
            ),
        ],
      ),
      QuestionnaireQuestionType.multiChoice => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final option in question.options)
            FilterChip(
              key: ValueKey('question-${question.id}-${option.id}'),
              label: Text(option.label),
              selected: (value as List<String>? ?? const []).contains(
                option.id,
              ),
              onSelected: (selected) {
                final next = [...(value ?? const <String>[])];
                selected ? next.add(option.id) : next.remove(option.id);
                widget.onValueChanged(question, next);
              },
            ),
        ],
      ),
      QuestionnaireQuestionType.number => TextField(
        key: ValueKey('question-value-${question.id}'),
        controller: _controller(question.id, value?.toString() ?? ''),
        keyboardType: TextInputType.numberWithOptions(
          decimal: question.numberKind == QuestionnaireNumberKind.decimal,
          signed: (question.minimum ?? 0) < 0,
        ),
        decoration: InputDecoration(
          labelText: widget.text.t('questionnaireNumberValue'),
          suffixText: question.unit,
          helperText: _numberRange(question),
        ),
        onChanged: (raw) {
          final parsed = question.numberKind == QuestionnaireNumberKind.integer
              ? int.tryParse(raw.trim())
              : double.tryParse(raw.trim());
          if (parsed == null) {
            widget.onStateChanged(
              question,
              QuestionnaireAnswerState.unanswered,
            );
          } else {
            widget.onValueChanged(question, parsed);
          }
        },
      ),
      QuestionnaireQuestionType.date => OutlinedButton.icon(
        key: ValueKey('question-value-${question.id}'),
        onPressed: () => _pickDate(question, value),
        icon: const Icon(Icons.calendar_month_outlined),
        label: Text(
          value as String? ?? widget.text.t('questionnaireChooseDate'),
        ),
      ),
      QuestionnaireQuestionType.shortText ||
      QuestionnaireQuestionType.longText => TextField(
        key: ValueKey('question-value-${question.id}'),
        controller: _controller(question.id, value as String? ?? ''),
        maxLength: question.maximumLength,
        minLines: question.type == QuestionnaireQuestionType.longText ? 3 : 1,
        maxLines: question.type == QuestionnaireQuestionType.longText ? 6 : 1,
        decoration: InputDecoration(
          labelText: widget.text.t('questionnaireTextValue'),
        ),
        onChanged: (raw) {
          if (raw.trim().isEmpty) {
            widget.onStateChanged(
              question,
              QuestionnaireAnswerState.unanswered,
            );
          } else {
            widget.onValueChanged(question, raw);
          }
        },
      ),
    };
  }

  TextEditingController _controller(String questionId, String initialValue) {
    return _textControllers.putIfAbsent(
      questionId,
      () => TextEditingController(text: initialValue),
    );
  }

  Future<void> _pickDate(
    QuestionnaireQuestion question,
    String? current,
  ) async {
    final parsed = current == null ? null : DateTime.tryParse(current);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
    );
    if (picked == null) {
      return;
    }
    widget.onValueChanged(
      question,
      '${picked.year.toString().padLeft(4, '0')}-'
      '${picked.month.toString().padLeft(2, '0')}-'
      '${picked.day.toString().padLeft(2, '0')}',
    );
  }

  String _stateLabel(QuestionnaireAnswerState state) => switch (state) {
    QuestionnaireAnswerState.answered => widget.text.t(
      'questionnaireAnswerAnswered',
    ),
    QuestionnaireAnswerState.unknown => widget.text.t(
      'questionnaireAnswerUnknown',
    ),
    QuestionnaireAnswerState.refused => widget.text.t(
      'questionnaireAnswerRefused',
    ),
    QuestionnaireAnswerState.notApplicable => widget.text.t(
      'questionnaireAnswerNotApplicable',
    ),
    QuestionnaireAnswerState.unanswered => widget.text.t(
      'questionnaireAnswerUnanswered',
    ),
  };

  String _errorLabel(
    QuestionnaireValidationError error,
  ) => switch (error.code) {
    'required_answer_missing' => widget.text.t('questionnaireRequiredMissing'),
    'answer_state_not_allowed' => widget.text.t('questionnaireStateNotAllowed'),
    _ => widget.text.t('questionnaireValueInvalid'),
  };

  String? _numberRange(QuestionnaireQuestion question) {
    if (question.minimum == null && question.maximum == null) {
      return null;
    }
    return '${widget.text.t('questionnaireAllowedRange')} '
        '${question.minimum ?? '−∞'} – ${question.maximum ?? '+∞'}';
  }
}
