import 'package:flutter_test/flutter_test.dart';

import 'package:filebridge/main.dart';

void main() {
  testWidgets('App starts on the connections list screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FileBridgeApp());
    expect(find.text('FileBridge'), findsOneWidget);
  });
}
