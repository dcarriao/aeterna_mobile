import 'package:aeterna_mobile/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> entrarNoApp(WidgetTester tester) async {
    await tester.pumpWidget(const AeternaApp());
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'E-mail'),
      'teste@aeterna.com',
    );
    await tester.enterText(find.widgetWithText(TextFormField, 'Senha'), '1234');
    await tester.tap(find.widgetWithText(FilledButton, 'Entrar'));
    await tester.pumpAndSettle();
  }

  testWidgets('faz login e abre o formulário completo', (tester) async {
    await entrarNoApp(tester);

    expect(find.text('O que aconteceu hoje?'), findsOneWidget);
    await tester.tap(find.text('Registrar momento'));
    await tester.pumpAndSettle();

    expect(find.text('Guarde este instante'), findsOneWidget);
    expect(find.text('Tirar foto'), findsOneWidget);
    expect(find.text('Galeria'), findsOneWidget);
    expect(find.text('Categoria'), findsOneWidget);
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Salvar memória'), findsOneWidget);
  });

  testWidgets('salva localmente e abre Minha História', (tester) async {
    await entrarNoApp(tester);
    await tester.tap(find.text('Registrar momento'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Título'),
      'Café em família',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'O que aconteceu?'),
      'Conversamos juntos durante toda a tarde.',
    );
    await tester.drag(find.byType(ListView).last, const Offset(0, -350));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar memória'));
    await tester.pumpAndSettle();

    expect(find.text('Minha História'), findsOneWidget);
    expect(find.text('Café em família'), findsOneWidget);
    expect(find.text('Memória salva na sua história'), findsOneWidget);
    expect(find.textContaining('Modo local'), findsOneWidget);
  });
}
