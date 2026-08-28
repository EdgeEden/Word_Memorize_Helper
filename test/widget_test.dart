import 'package:flutter_test/flutter_test.dart';
import 'package:wordn/main.dart';

void main() {
  testWidgets('WordNApp loads and mounts successfully', (WidgetTester tester) async {
    await tester.pumpWidget(const WordNApp());
    expect(find.textContaining('WordN'), findsOneWidget);
  });
}
