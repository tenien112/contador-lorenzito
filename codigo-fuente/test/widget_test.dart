import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:contador_series_lorenzito/firebase_options.dart';
import 'package:contador_series_lorenzito/main.dart';

void main() {
  testWidgets('shows exercise type selector and updates selection', (
    WidgetTester tester,
  ) async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    await initializeDateFormatting('es_ES', null);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Ejercicio: General'), findsOneWidget);

    await tester.tap(find.text('Ejercicio: General'));
    await tester.pumpAndSettle();

    expect(find.text('Selecciona el tipo de ejercicio'), findsOneWidget);

    await tester.tap(find.text('Press de banca'));
    await tester.pumpAndSettle();

    expect(find.text('Ejercicio: Press de banca'), findsOneWidget);
  });
}
