import 'package:feldexa_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Feldexa application shell', (tester) async {
    await tester.pumpWidget(const FeldexaApp());

    expect(find.byType(FeldexaApp), findsOneWidget);
    expect(find.text('Feldexa'), findsOneWidget);
  });
}
