import 'package:flutter_test/flutter_test.dart';
import 'package:tongxingzhe_app/l10n/app_strings.dart';

void main() {
  test('兴趣比例行按语言使用本地标点和结构', () {
    expect(
      const AppStrings('zh').format('interestRatioRow', const {
        'level': 3,
        'count': 2,
        'unit': '场',
        'numerator': 2,
        'denominator': 3,
        'percentage': '66.67%',
      }),
      '兴趣 3：2 场；2 / 3（66.67%）',
    );
    expect(
      const AppStrings('en').format('interestRatioRow', const {
        'level': 3,
        'count': 2,
        'unit': 'sessions',
        'numerator': 2,
        'denominator': 3,
        'percentage': '66.67%',
      }),
      'Interest 3: 2 sessions; 2 / 3 (66.67%)',
    );
  });

  test('兴趣比例覆盖文案使用传入的实际计数', () {
    final message = const AppStrings('en').format(
      'interestRatioCoverage',
      const {
        'unknown': 1,
        'refused': 2,
        'notApplicable': 3,
        'unanswered': 4,
        'excluded': 5,
      },
    );

    expect(message, contains('unknown 1'));
    expect(message, contains('refused 2'));
    expect(message, contains('not applicable 3'));
    expect(message, contains('unanswered 4'));
    expect(message, contains('candidate exclusions 5'));
  });

  test('兴趣子集比例行按语言使用本地标点且不伪造中间档', () {
    expect(
      const AppStrings('zh').format('interestSubsetRatioRow', const {
        'label': '兴趣 3–4',
        'numerator': 2,
        'denominator': 3,
        'percentage': '66.67%',
      }),
      '兴趣 3–4：2 / 3（66.67%）',
    );
    expect(
      const AppStrings('en').format('interestSubsetRatioRow', const {
        'label': 'Interest 0',
        'numerator': 1,
        'denominator': 3,
        'percentage': '33.33%',
      }),
      'Interest 0: 1 / 3 (33.33%)',
    );
  });

  test('对象反应分布文案保留关联单位与未填写边界', () {
    expect(
      const AppStrings('zh').format('targetResponseRow', const {
        'level': 2,
        'count': 2,
        'numerator': 2,
        'denominator': 9,
        'percentage': '22.22%',
      }),
      '反应 2：2 条已填关联；2 / 9（22.22%）',
    );
    expect(
      const AppStrings('en').format('targetResponseRow', const {
        'level': 2,
        'count': 0,
        'numerator': 0,
        'denominator': 0,
        'percentage': 'No calculable percentage',
      }),
      'Response 2: 0 answered links; 0 / 0 (No calculable percentage)',
    );
    expect(
      const AppStrings('en').format('targetResponseCoverage', const {
        'answered': 3,
        'unknown': 0,
        'refused': 0,
        'notApplicable': 0,
        'unanswered': 2,
        'excluded': 0,
      }),
      allOf(
        contains('3 answered'),
        contains('0 unknown'),
        contains('0 refused'),
        contains('0 not applicable'),
        contains('2 unanswered'),
        contains('0 candidate exclusions'),
      ),
    );
    expect(
      const AppStrings(
        'zh',
      ).format('targetResponseMedianLevel', const {'level': 0, 'answered': 2}),
      '对象当次反应中位等级：0（2 条已填关联）',
    );
    expect(
      const AppStrings('en').t('targetResponseMedianHelp'),
      contains('lower observed level'),
    );
  });
}
