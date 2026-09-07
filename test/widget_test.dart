import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:finora_mobile/main.dart';

class FakeRegistrationRepository implements RegistrationRepository {
  RegistrationRequest? request;

  @override
  Future<void> register(RegistrationRequest request) async {
    this.request = request;
  }
}

void main() {
  testWidgets('valida campos obrigatórios antes do envio', (tester) async {
    final repository = FakeRegistrationRepository();
    await tester.pumpWidget(MaterialApp(
      home: RegistrationPage(repository: repository),
    ));

    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Informe seu nome.'), findsOneWidget);
    expect(repository.request, isNull);
  });

  test('serializa o request no contrato de cadastro', () {
    final request = RegistrationRequest(
      name: 'Ana Silva',
      email: 'ana@example.com',
      password: 'senha-segura',
      birthDate: DateTime(1990, 2, 15),
    );

    expect(request.toJson(), {
      'nome': 'Ana Silva',
      'email': 'ana@example.com',
      'senha': 'senha-segura',
      'dataNascimento': '15/02/1990',
    });
  });
}
