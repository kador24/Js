import 'package:flutter_test/flutter_test.dart';
import 'package:jamal_phone_manager/main.dart';

void main() {
  testWidgets('application entry point builds', (tester) async {
    await tester.pumpWidget(const JamalPhoneApp());
    await tester.pump();
    expect(find.text('Jamal Phone'), findsWidgets);
  });
}
