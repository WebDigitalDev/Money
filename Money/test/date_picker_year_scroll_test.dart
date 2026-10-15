import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:money/presentation/widgets/shared/modal_bottom_sheet.dart';

void main() {
  testWidgets('seleção de ano abre rolável e posicionada no ano atual', (
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showAppDatePickerDialog(
                  context: context,
                  initialDate: DateTime(2026, 8, 25),
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2027, 8, 25),
                  title: 'Data inicial',
                ),
                child: const Text('ABRIR'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('ABRIR'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('agosto de 2026'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Scrollbar), findsOneWidget);
    expect(find.text('2026'), findsOneWidget);

    final Finder yearScrollable = find.descendant(
      of: find.byType(Scrollbar),
      matching: find.byType(Scrollable),
    );
    final ScrollableState scrollable = tester.state<ScrollableState>(
      yearScrollable,
    );
    expect(scrollable.position.pixels, greaterThan(0));

    final Rect selectedYear = tester.getRect(find.text('2026'));
    final Rect calendar = tester.getRect(find.byType(Scrollbar));
    expect(calendar.overlaps(selectedYear), isTrue);
  });
}
