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
}
