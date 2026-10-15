import 'package:flutter_test/flutter_test.dart';
import 'package:money/money.dart';

void main() {
  test('tutorial reconhece o nome atual da região', () {
    expect(
      TutorialGuideController.isTutorialRegionName(' TUTORIAL '),
      isTrue,
    );
  });

  test('tutorial não usa mais o nome legado da região', () {
    expect(
      TutorialGuideController.isTutorialRegionName('  tutorial - webdigital  '),
      isFalse,
    );
  });

  test('tutorial não aceita outra região', () {
    expect(
      TutorialGuideController.isTutorialRegionName('OUTRA REGIÃO'),
      isFalse,
    );
  });
}
