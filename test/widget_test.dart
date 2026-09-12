import 'dart:async';

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

class FakeAuthRepository implements AuthRepository {
  LoginRequest? request;
  AuthSession? response;
  AuthException? error;
  Completer<AuthSession>? completer;
  bool sessionValid = true;

  @override
  Future<AuthSession> login(LoginRequest request) {
    this.request = request;
    if (error != null) return Future.error(error!);
    if (completer != null) return completer!.future;
    return Future.value(response ?? const AuthSession('token-de-teste'));
  }

  @override
  Future<bool> validateSession(String token) async => sessionValid;
}

class FakeProfileRepository implements ProfileRepository {
  UserProfile? response;
  ProfileException? error;
  ProfileUpdateRequest? updateRequest;
  UserProfile? updateResponse;
  ProfileException? updateError;
  int calls = 0;

  @override
  Future<UserProfile> fetchProfile(String token) async {
    calls++;
    if (error != null) throw error!;
    return response ??
        UserProfile(
          name: 'Ana Silva',
          email: 'ana@example.com',
          birthDate: DateTime(1990, 2, 15),
          active: true,
        );
  }

  @override
  Future<UserProfile> updateProfile(
    String token,
    ProfileUpdateRequest request,
  ) async {
    updateRequest = request;
    if (updateError != null) throw updateError!;
    return updateResponse ??
        UserProfile(
          name: request.name,
          email: 'ana@example.com',
          birthDate: request.birthDate,
          active: true,
        );
  }
}

class FakeSessionStorage implements SessionStorage {
  String? token;
  int deleteCount = 0;
  bool failOnRead = false;

  @override
  Future<String?> readToken() async {
    if (failOnRead) throw StateError('storage unavailable');
    return token;
  }

  @override
  Future<void> writeToken(String token) async => this.token = token;

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    token = null;
  }
}

void main() {
  testWidgets('valida campos obrigatórios antes do envio', (tester) async {
    final repository = FakeRegistrationRepository();
    await tester.pumpWidget(
      MaterialApp(home: RegistrationPage(repository: repository)),
    );

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

  test('normaliza o request de login no contrato', () {
    final request = LoginRequest(
      email: 'ana@example.com',
      password: 'senha-segura',
    );

    expect(request.toJson(), {
      'email': 'ana@example.com',
      'senha': 'senha-segura',
    });
  });

  test('converte o perfil do contrato sem incluir senha ou hash', () {
    final profile = UserProfile.fromJson({
      'nome': 'Ana Silva',
      'email': 'ana@example.com',
      'dataNascimento': '15/02/1990',
      'status': 'ATIVO',
      'senha': 'não deve ser lida',
      'hash': 'não deve ser lido',
    });

    expect(profile.name, 'Ana Silva');
    expect(profile.email, 'ana@example.com');
    expect(profile.birthDate, DateTime(1990, 2, 15));
    expect(profile.active, isTrue);
  });

  test('serializa somente os campos permitidos na edição do perfil', () {
    final request = ProfileUpdateRequest(
      name: 'Ana Souza',
      birthDate: DateTime(1991, 3, 16),
    );

    expect(request.toJson(), {
      'nome': 'Ana Souza',
      'dataNascimento': '16/03/1991',
    });
  });

  test('consulta o perfil com sucesso e mantém estado success', () async {
    final session = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage(),
    );
    await session.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    final profile = ProfileController(
      repository: FakeProfileRepository(),
      session: session,
    );

    await profile.load();

    expect(profile.status, ProfileStatus.success);
    expect(profile.profile?.email, 'ana@example.com');
    expect(profile.errorMessage, isNull);
  });

  test('permite tentar novamente após erro de consulta', () async {
    final repository = FakeProfileRepository()
      ..error = const ProfileException('Erro de rede.');
    final session = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage(),
    );
    await session.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    final profile = ProfileController(repository: repository, session: session);

    await profile.load();
    expect(profile.status, ProfileStatus.error);
    expect(profile.errorMessage, 'Erro de rede.');

    repository.error = null;
    await profile.load();

    expect(profile.status, ProfileStatus.success);
    expect(repository.calls, 2);
  });

  test('atualiza o perfil e reflete os dados retornados', () async {
    final repository = FakeProfileRepository();
    final session = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage(),
    );
    await session.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    final profile = ProfileController(repository: repository, session: session);
    await profile.load();

    final updated = await profile.updateProfile(
      ProfileUpdateRequest(name: 'Ana Souza', birthDate: DateTime(1991, 3, 16)),
    );

    expect(updated, isTrue);
    expect(profile.updateStatus, ProfileUpdateStatus.success);
    expect(profile.profile?.name, 'Ana Souza');
    expect(profile.profile?.birthDate, DateTime(1991, 3, 16));
    expect(repository.updateRequest?.toJson().containsKey('email'), isFalse);
  });

  test(
    'preserva o perfil quando a atualização falha e permite nova tentativa',
    () async {
      final repository = FakeProfileRepository()
        ..updateError = const ProfileException('Erro de rede.');
      final session = SessionController(
        repository: FakeAuthRepository(),
        storage: FakeSessionStorage(),
      );
      await session.login(
        const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
      );
      final profile = ProfileController(
        repository: repository,
        session: session,
      );
      await profile.load();

      final updated = await profile.updateProfile(
        ProfileUpdateRequest(
          name: 'Ana Souza',
          birthDate: DateTime(1991, 3, 16),
        ),
      );

      expect(updated, isFalse);
      expect(profile.updateStatus, ProfileUpdateStatus.error);
      expect(profile.updateErrorMessage, 'Erro de rede.');
      expect(profile.profile?.name, 'Ana Silva');

      repository.updateError = null;
      expect(
        await profile.updateProfile(
          ProfileUpdateRequest(
            name: 'Ana Souza',
            birthDate: DateTime(1991, 3, 16),
          ),
        ),
        isTrue,
      );
      expect(profile.profile?.name, 'Ana Souza');
    },
  );

  test('encerra a sessão quando a atualização rejeita o token', () async {
    final repository = FakeProfileRepository()
      ..updateError = const ProfileException(
        'Sua sessão não está mais válida.',
        unauthorized: true,
      );
    final session = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage(),
    );
    await session.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    final profile = ProfileController(repository: repository, session: session);
    await profile.load();

    await profile.updateProfile(
      ProfileUpdateRequest(name: 'Ana Souza', birthDate: DateTime(1991, 3, 16)),
    );

    expect(session.status, SessionStatus.signedOut);
  });

  test('encerra a sessão quando o perfil rejeita o token', () async {
    final repository = FakeProfileRepository()
      ..error = const ProfileException(
        'Sua sessão não está mais válida.',
        unauthorized: true,
      );
    final session = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage(),
    );
    await session.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    final profile = ProfileController(repository: repository, session: session);

    await profile.load();

    expect(session.status, SessionStatus.signedOut);
    expect(profile.status, ProfileStatus.loading);
  });

  test('restaura uma sessão persistida sem expor o token', () async {
    final storage = FakeSessionStorage()..token = 'token-persistido';
    final controller = SessionController(
      repository: FakeAuthRepository(),
      storage: storage,
    );

    await controller.restore();

    expect(controller.status, SessionStatus.signedIn);
    expect(controller.errorMessage, isNull);
  });

  test(
    'remove uma sessão persistida quando o backend rejeita o token',
    () async {
      final storage = FakeSessionStorage()..token = 'token-expirado';
      final controller = SessionController(
        repository: FakeAuthRepository()..sessionValid = false,
        storage: storage,
      );

      await controller.restore();

      expect(controller.status, SessionStatus.signedOut);
      expect(storage.token, isNull);
      expect(storage.deleteCount, 1);
    },
  );

  test('encerra a sessão quando o armazenamento falha ao restaurar', () async {
    final controller = SessionController(
      repository: FakeAuthRepository(),
      storage: FakeSessionStorage()..failOnRead = true,
    );

    await controller.restore();

    expect(controller.status, SessionStatus.signedOut);
    expect(controller.errorMessage, isNull);
  });

  test('login persiste a sessão e logout remove o token', () async {
    final storage = FakeSessionStorage();
    final controller = SessionController(
      repository: FakeAuthRepository(),
      storage: storage,
    )..status = SessionStatus.signedOut;

    final loggedIn = await controller.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );
    expect(loggedIn, isTrue);
    expect(controller.status, SessionStatus.signedIn);
    expect(storage.token, 'token-de-teste');

    await controller.logout();
    expect(controller.status, SessionStatus.signedOut);
    expect(storage.token, isNull);
    expect(storage.deleteCount, 1);
  });

  test('rejeita credenciais inválidas sem persistir sessão', () async {
    final storage = FakeSessionStorage();
    final repository = FakeAuthRepository()
      ..error = const AuthException('E-mail ou senha inválidos.');
    final controller = SessionController(
      repository: repository,
      storage: storage,
    )..status = SessionStatus.signedOut;

    final loggedIn = await controller.login(
      const LoginRequest(email: 'ana@example.com', password: 'senha-segura'),
    );

    expect(loggedIn, isFalse);
    expect(controller.status, SessionStatus.signedOut);
    expect(controller.errorMessage, 'E-mail ou senha inválidos.');
    expect(storage.token, isNull);
  });

  testWidgets('login valida campos antes de enviar', (tester) async {
    final repository = FakeAuthRepository();
    final controller = SessionController(
      repository: repository,
      storage: FakeSessionStorage(),
    )..status = SessionStatus.signedOut;

    await tester.pumpWidget(MaterialApp(home: LoginPage(session: controller)));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();

    expect(find.text('Informe seu e-mail.'), findsOneWidget);
    expect(repository.request, isNull);
  });

  testWidgets('login bloqueia nova submissão enquanto aguarda resposta', (
    tester,
  ) async {
    final repository = FakeAuthRepository()
      ..completer = Completer<AuthSession>();
    final controller = SessionController(
      repository: repository,
      storage: FakeSessionStorage(),
    )..status = SessionStatus.signedOut;

    await tester.pumpWidget(MaterialApp(home: LoginPage(session: controller)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), 'ANA@EXAMPLE.COM');
    await tester.enterText(fields.at(1), 'senha-segura');
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));

    expect(repository.request?.email, 'ana@example.com');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
