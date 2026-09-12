import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LoginRequest {
  const LoginRequest({required this.email, required this.password});

  final String email;
  final String password;

  Map<String, dynamic> toJson() => {'email': email, 'senha': password};
}

class AuthSession {
  const AuthSession(this.token);

  final String token;
}

class UserProfile {
  const UserProfile({
    required this.name,
    required this.email,
    required this.birthDate,
    required this.active,
  });

  final String name;
  final String email;
  final DateTime birthDate;
  final bool active;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final birthDateValue = json['dataNascimento'];
    if (birthDateValue is! String) {
      throw const FormatException('Data de nascimento ausente.');
    }

    return UserProfile(
      name: json['nome'] as String? ?? '',
      email: json['email'] as String? ?? '',
      birthDate: _parseDate(birthDateValue),
      active: json['ativo'] as bool? ?? json['status'] == 'ATIVO',
    );
  }
}

class ProfileUpdateRequest {
  const ProfileUpdateRequest({required this.name, required this.birthDate});

  final String name;
  final DateTime birthDate;

  Map<String, dynamic> toJson() => {
    'nome': name,
    'dataNascimento': _formatDate(birthDate),
  };
}

DateTime _parseDate(String value) {
  final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value);
  if (match == null) {
    throw const FormatException('Data de nascimento inválida.');
  }
  final date = DateTime(
    int.parse(match.group(3)!),
    int.parse(match.group(2)!),
    int.parse(match.group(1)!),
  );
  if (_formatDate(date) != value) {
    throw const FormatException('Data de nascimento inválida.');
  }
  return date;
}

abstract interface class AuthRepository {
  Future<AuthSession> login(LoginRequest request);

  Future<bool> validateSession(String token);
}

abstract interface class ProfileRepository {
  Future<UserProfile> fetchProfile(String token);

  Future<UserProfile> updateProfile(String token, ProfileUpdateRequest request);
}

abstract interface class SessionStorage {
  Future<String?> readToken();

  Future<void> writeToken(String token);

  Future<void> deleteToken();
}

class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage({this._storage = const FlutterSecureStorage()});

  static const _tokenKey = 'finora.auth.token';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) =>
      _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}

class FinoraApp extends StatelessWidget {
  const FinoraApp({super.key, required this.session});

  final SessionController session;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finora',
      locale: const Locale('pt', 'BR'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('pt', 'BR')],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB)),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2563EB),
          brightness: Brightness.dark,
        ),
      ),
      home: SessionGate(session: session),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key, required this.session});

  final SessionController session;

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    widget.session.addListener(_onSessionChanged);
    widget.session.restore();
  }

  @override
  void dispose() {
    widget.session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.session.status) {
      case SessionStatus.loading:
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      case SessionStatus.signedOut:
        return LoginPage(session: widget.session);
      case SessionStatus.signedIn:
        final profileRepository = widget.session.profileRepository;
        if (profileRepository == null) {
          return const Scaffold(
            body: Center(child: Text('Perfil indisponível.')),
          );
        }
        return ProtectedHomePage(
          session: widget.session,
          repository: profileRepository,
        );
    }
  }
}

class AuthException implements Exception {
  const AuthException(this.message);

  final String message;
}

class AuthApiClient implements AuthRepository, ProfileRepository {
  AuthApiClient({Uri? baseUri})
    : baseUri =
          baseUri ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8080',
            ),
          );

  final Uri baseUri;

  @override
  Future<AuthSession> login(LoginRequest request) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(
        baseUri.resolve('/api/auth/login'),
      );
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(jsonEncode(request.toJson()));
      final response = await httpRequest.close().timeout(
        const Duration(seconds: 10),
      );
      final responseBody = await utf8.decoder.bind(response).join();

      if (response.statusCode == 200) {
        final payload = jsonDecode(responseBody) as Map<String, dynamic>;
        final token = payload['token'] ?? payload['accessToken'];
        if (token is String && token.isNotEmpty) return AuthSession(token);
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const AuthException('E-mail ou senha inválidos.');
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw const AuthException('Revise os dados informados.');
      }
      throw const AuthException('Não foi possível entrar. Tente novamente.');
    } on AuthException {
      rethrow;
    } on FormatException {
      throw const AuthException('Não foi possível entrar. Tente novamente.');
    } on SocketException {
      throw const AuthException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    } on HttpException {
      throw const AuthException('Não foi possível entrar. Tente novamente.');
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<bool> validateSession(String token) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.getUrl(baseUri.resolve('/api/users/me'));
      httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await httpRequest.close();
      if (response.statusCode == 401 || response.statusCode == 403) {
        return false;
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return true;
      }
      throw const AuthException(
        'Não foi possível validar a sessão. Tente novamente.',
      );
    } on AuthException {
      rethrow;
    } on SocketException {
      throw const AuthException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    } on HttpException {
      throw const AuthException(
        'Não foi possível validar a sessão. Tente novamente.',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<UserProfile> fetchProfile(String token) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.getUrl(baseUri.resolve('/api/users/me'));
      httpRequest.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final response = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ProfileException(
          'Sua sessão não está mais válida.',
          unauthorized: true,
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(responseBody) as Map<String, dynamic>;
        return UserProfile.fromJson(payload);
      }
      throw const ProfileException(
        'Não foi possível carregar seu perfil. Tente novamente.',
      );
    } on ProfileException {
      rethrow;
    } on FormatException {
      throw const ProfileException(
        'Não foi possível carregar seu perfil. Tente novamente.',
      );
    } on SocketException {
      throw const ProfileException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    } on HttpException {
      throw const ProfileException(
        'Não foi possível carregar seu perfil. Tente novamente.',
      );
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<UserProfile> updateProfile(
    String token,
    ProfileUpdateRequest request,
  ) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.putUrl(baseUri.resolve('/api/users/me'));
      httpRequest.headers
        ..contentType = ContentType.json
        ..set(HttpHeaders.authorizationHeader, 'Bearer $token');
      httpRequest.write(jsonEncode(request.toJson()));
      final response = await httpRequest.close();
      final responseBody = await utf8.decoder.bind(response).join();
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ProfileException(
          'Sua sessão não está mais válida.',
          unauthorized: true,
        );
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final payload = jsonDecode(responseBody) as Map<String, dynamic>;
        return UserProfile.fromJson(payload);
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw const ProfileException('Revise os dados informados.');
      }
      throw const ProfileException(
        'Não foi possível salvar seu perfil. Tente novamente.',
      );
    } on ProfileException {
      rethrow;
    } on FormatException {
      throw const ProfileException(
        'Não foi possível salvar seu perfil. Tente novamente.',
      );
    } on SocketException {
      throw const ProfileException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    } on HttpException {
      throw const ProfileException(
        'Não foi possível salvar seu perfil. Tente novamente.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

enum SessionStatus { loading, signedOut, signedIn }

class SessionController extends ChangeNotifier {
  SessionController({required this.repository, required this.storage});

  final AuthRepository repository;
  final SessionStorage storage;
  SessionStatus status = SessionStatus.loading;
  String? errorMessage;
  bool isSubmitting = false;
  String? _token;

  ProfileRepository? get profileRepository =>
      repository is ProfileRepository ? repository as ProfileRepository : null;

  String? get accessToken => _token;

  Future<void> restore() async {
    try {
      final token = await storage.readToken();
      if (token == null || token.isEmpty) {
        status = SessionStatus.signedOut;
      } else if (await repository.validateSession(token)) {
        _token = token;
        status = SessionStatus.signedIn;
      } else {
        await storage.deleteToken();
        _token = null;
        status = SessionStatus.signedOut;
      }
    } catch (_) {
      status = SessionStatus.signedOut;
    }
    notifyListeners();
  }

  Future<bool> login(LoginRequest request) async {
    if (isSubmitting) return false;
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final session = await repository.login(request);
      await storage.writeToken(session.token);
      _token = session.token;
      status = SessionStatus.signedIn;
      return true;
    } on AuthException catch (error) {
      errorMessage = error.message;
      status = SessionStatus.signedOut;
      return false;
    } catch (_) {
      errorMessage = 'Não foi possível entrar. Tente novamente.';
      status = SessionStatus.signedOut;
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await storage.deleteToken();
    _token = null;
    errorMessage = null;
    status = SessionStatus.signedOut;
    notifyListeners();
  }
}

class ProfileException implements Exception {
  const ProfileException(this.message, {this.unauthorized = false});

  final String message;
  final bool unauthorized;
}

enum ProfileStatus { loading, success, error }

enum ProfileUpdateStatus { initial, submitting, success, error }

class ProfileController extends ChangeNotifier {
  ProfileController({required this.repository, required this.session});

  final ProfileRepository repository;
  final SessionController session;
  ProfileStatus status = ProfileStatus.loading;
  UserProfile? profile;
  String? errorMessage;
  ProfileUpdateStatus updateStatus = ProfileUpdateStatus.initial;
  String? updateErrorMessage;

  Future<void> load() async {
    status = ProfileStatus.loading;
    errorMessage = null;
    notifyListeners();
    final token = session.accessToken;
    if (token == null || token.isEmpty) {
      await session.logout();
      return;
    }
    try {
      profile = await repository.fetchProfile(token);
      status = ProfileStatus.success;
    } on ProfileException catch (error) {
      if (error.unauthorized) {
        await session.logout();
        return;
      }
      status = ProfileStatus.error;
      errorMessage = error.message;
    } catch (_) {
      status = ProfileStatus.error;
      errorMessage = 'Não foi possível carregar seu perfil. Tente novamente.';
    }
    notifyListeners();
  }

  Future<bool> updateProfile(ProfileUpdateRequest request) async {
    if (updateStatus == ProfileUpdateStatus.submitting) return false;
    final token = session.accessToken;
    if (token == null || token.isEmpty) {
      await session.logout();
      return false;
    }
    updateStatus = ProfileUpdateStatus.submitting;
    updateErrorMessage = null;
    notifyListeners();
    try {
      profile = await repository.updateProfile(token, request);
      updateStatus = ProfileUpdateStatus.success;
      return true;
    } on ProfileException catch (error) {
      if (error.unauthorized) {
        await session.logout();
        return false;
      }
      updateStatus = ProfileUpdateStatus.error;
      updateErrorMessage = error.message;
      return false;
    } catch (_) {
      updateStatus = ProfileUpdateStatus.error;
      updateErrorMessage =
          'Não foi possível salvar seu perfil. Tente novamente.';
      return false;
    } finally {
      if (updateStatus != ProfileUpdateStatus.success) {
        notifyListeners();
      } else {
        notifyListeners();
      }
    }
  }

  void resetUpdateState() {
    updateStatus = ProfileUpdateStatus.initial;
    updateErrorMessage = null;
    notifyListeners();
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({
    super.key,
    required this.session,
    this.registrationRepository,
  });

  final SessionController session;
  final RegistrationRepository? registrationRepository;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    await widget.session.login(
      LoginRequest(
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSubmitting = widget.session.isSubmitting;
    return Scaffold(
      appBar: AppBar(title: const Text('Entrar')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Acesse sua conta',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('Entre para continuar no Finora.'),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _emailController,
                      enabled: !isSubmitting,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'E-mail'),
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Informe seu e-mail.';
                        if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                            .hasMatch(email)) {
                          return 'Informe um e-mail válido.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      enabled: !isSubmitting,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Senha',
                        suffixIcon: IconButton(
                          onPressed: isSubmitting
                              ? null
                              : () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                          tooltip: _obscurePassword
                              ? 'Mostrar senha'
                              : 'Ocultar senha',
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Informe sua senha.'
                          : null,
                    ),
                    if (widget.session.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        widget.session.errorMessage!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: isSubmitting ? null : _submit,
                      child: isSubmitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Entrar'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: isSubmitting
                          ? null
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => RegistrationPage(
                                    repository:
                                        widget.registrationRepository ??
                                        RegistrationApiClient(),
                                  ),
                                ),
                              );
                            },
                      child: const Text('Criar conta'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProtectedHomePage extends StatefulWidget {
  const ProtectedHomePage({
    super.key,
    required this.session,
    required this.repository,
  });

  final SessionController session;
  final ProfileRepository repository;

  @override
  State<ProtectedHomePage> createState() => _ProtectedHomePageState();
}

class _ProtectedHomePageState extends State<ProtectedHomePage> {
  late final ProfileController _profile;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _birthDateController = TextEditingController();
  DateTime? _editBirthDate;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _profile = ProfileController(
      repository: widget.repository,
      session: widget.session,
    )..addListener(_onProfileChanged);
    _profile.load();
  }

  @override
  void dispose() {
    _profile
      ..removeListener(_onProfileChanged)
      ..dispose();
    _nameController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  void _onProfileChanged() {
    if (mounted) setState(() {});
  }

  void _startEditing(UserProfile profile) {
    _nameController.text = profile.name;
    _editBirthDate = profile.birthDate;
    _birthDateController.text = _formatDate(profile.birthDate);
    _profile.resetUpdateState();
    setState(() => _isEditing = true);
  }

  void _cancelEditing() {
    _profile.resetUpdateState();
    setState(() => _isEditing = false);
  }

  Future<void> _selectEditBirthDate() async {
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _editBirthDate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Selecione sua data de nascimento',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _editBirthDate = selected;
      _birthDateController.text = _formatDate(selected);
    });
  }

  Future<void> _saveProfile() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    final birthDate = _editBirthDate;
    if (birthDate == null) return;
    final saved = await _profile.updateProfile(
      ProfileUpdateRequest(
        name: _nameController.text.trim(),
        birthDate: birthDate,
      ),
    );
    if (!mounted || !saved) return;
    setState(() => _isEditing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Perfil atualizado com sucesso.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Finora'),
        actions: [
          IconButton(
            onPressed: widget.session.logout,
            tooltip: 'Sair',
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildContent(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (_profile.status) {
      case ProfileStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case ProfileStatus.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Não foi possível carregar seu perfil',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_profile.errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _profile.load,
              icon: const Icon(Icons.refresh),
              label: const Text('Tentar novamente'),
            ),
          ],
        );
      case ProfileStatus.success:
        final profile = _profile.profile!;
        return _isEditing ? _buildEditForm() : _buildProfile(profile);
    }
  }

  Widget _buildProfile(UserProfile profile) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Meu perfil', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        const Text('Confira os dados da sua conta.'),
        const SizedBox(height: 24),
        _ProfileField(label: 'Nome', value: profile.name),
        _ProfileField(label: 'E-mail', value: profile.email),
        _ProfileField(
          label: 'Data de nascimento',
          value: _formatDate(profile.birthDate),
        ),
        _ProfileField(
          label: 'Estado da conta',
          value: profile.active ? 'Ativa' : 'Inativa',
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: () => _startEditing(profile),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('Editar perfil'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.person_off_outlined),
          label: const Text('Inativar conta'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
        ),
      ],
    );
  }

  Widget _buildEditForm() {
    final isSubmitting =
        _profile.updateStatus == ProfileUpdateStatus.submitting;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Editar perfil',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const Text('Atualize apenas os dados permitidos da sua conta.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            enabled: !isSubmitting,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nome completo'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Informe seu nome.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birthDateController,
            enabled: !isSubmitting,
            readOnly: true,
            onTap: isSubmitting ? null : _selectEditBirthDate,
            decoration: const InputDecoration(
              labelText: 'Data de nascimento',
              hintText: 'dd/MM/yyyy',
              suffixIcon: Icon(Icons.calendar_today_outlined),
            ),
            validator: (_) => _editBirthDate == null
                ? 'Informe sua data de nascimento.'
                : null,
          ),
          if (_profile.updateErrorMessage != null) ...[
            const SizedBox(height: 16),
            Text(
              _profile.updateErrorMessage!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : _cancelEditing,
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: isSubmitting ? null : _saveProfile,
                  child: isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Salvar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileField extends StatelessWidget {
  const _ProfileField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value),
      ),
    );
  }
}

class RegistrationRequest {
  const RegistrationRequest({
    required this.name,
    required this.email,
    required this.password,
    required this.birthDate,
  });

  final String name;
  final String email;
  final String password;
  final DateTime birthDate;

  Map<String, dynamic> toJson() => {
    'nome': name,
    'email': email,
    'senha': password,
    'dataNascimento': _formatDate(birthDate),
  };
}

String _formatDate(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

abstract interface class RegistrationRepository {
  Future<void> register(RegistrationRequest request);
}

class RegistrationException implements Exception {
  const RegistrationException(this.message);

  final String message;
}

class RegistrationApiClient implements RegistrationRepository {
  RegistrationApiClient({Uri? baseUri})
    : baseUri =
          baseUri ??
          Uri.parse(
            const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8080',
            ),
          );

  final Uri baseUri;

  @override
  Future<void> register(RegistrationRequest request) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(
        baseUri.resolve('/api/auth/register'),
      );
      httpRequest.headers.contentType = ContentType.json;
      httpRequest.write(jsonEncode(request.toJson()));
      final response = await httpRequest.close();
      if (response.statusCode == 201) return;
      if (response.statusCode == 409) {
        throw const RegistrationException('Este e-mail já está cadastrado.');
      }
      if (response.statusCode >= 400 && response.statusCode < 500) {
        throw const RegistrationException('Revise os dados informados.');
      }
      throw const RegistrationException(
        'Não foi possível concluir o cadastro. Tente novamente.',
      );
    } on RegistrationException {
      rethrow;
    } on SocketException {
      throw const RegistrationException(
        'Não foi possível conectar ao servidor. Tente novamente.',
      );
    } on TimeoutException {
      throw const RegistrationException(
        'O servidor demorou para responder. Tente novamente.',
      );
    } on HttpException {
      throw const RegistrationException(
        'Não foi possível concluir o cadastro. Tente novamente.',
      );
    } finally {
      client.close(force: true);
    }
  }
}

class RegistrationPage extends StatefulWidget {
  const RegistrationPage({
    super.key,
    required this.repository,
    this.onRegistrationSuccess,
  });

  final RegistrationRepository repository;
  final VoidCallback? onRegistrationSuccess;

  @override
  State<RegistrationPage> createState() => _RegistrationPageState();
}

class _RegistrationPageState extends State<RegistrationPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _birthDateController = TextEditingController();
  DateTime? _birthDate;
  String? _formError;
  bool _isSubmitting = false;
  bool _isComplete = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _birthDateController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() => _formError = null);
    if (!_formKey.currentState!.validate()) return;
    if (_birthDate == null) {
      setState(() => _formError = 'Informe uma data de nascimento válida.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.repository.register(
        RegistrationRequest(
          name: _nameController.text.trim(),
          email: _emailController.text.trim().toLowerCase(),
          password: _passwordController.text,
          birthDate: _birthDate!,
        ),
      );
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isComplete = true;
      });
      widget.onRegistrationSuccess?.call();
    } on RegistrationException catch (error) {
      if (!mounted) return;
      _setSubmissionError(error.message);
    } catch (_) {
      if (!mounted) return;
      _setSubmissionError(
        'Não foi possível concluir o cadastro. Tente novamente.',
      );
    } finally {
      if (mounted && !_isComplete) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  void _setSubmissionError(String message) {
    setState(() {
      _isSubmitting = false;
      _formError = message;
    });
  }

  Future<void> _selectBirthDate() async {
    final selected = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: _birthDate ?? DateTime(1990),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Selecione sua data de nascimento',
    );
    if (selected == null) return;
    setState(() {
      _birthDate = selected;
      _birthDateController.text = _formatDate(selected);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Criar conta')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: _isComplete ? _buildSuccess() : _buildForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Seus dados', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text('Preencha os dados para começar a usar o Finora.'),
          const SizedBox(height: 24),
          TextFormField(
            controller: _nameController,
            enabled: !_isSubmitting,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Nome completo'),
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Informe seu nome.'
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _emailController,
            enabled: !_isSubmitting,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'E-mail'),
            validator: (value) {
              final email = value?.trim() ?? '';
              if (email.isEmpty) return 'Informe seu e-mail.';
              if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(email)) {
                return 'Informe um e-mail válido.';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            enabled: !_isSubmitting,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: 'Senha',
              suffixIcon: IconButton(
                onPressed: _isSubmitting
                    ? null
                    : () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                tooltip: _obscurePassword ? 'Mostrar senha' : 'Ocultar senha',
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
              ),
            ),
            validator: (value) =>
                value == null || value.isEmpty ? 'Informe sua senha.' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _birthDateController,
            enabled: !_isSubmitting,
            readOnly: true,
            onTap: _selectBirthDate,
            decoration: const InputDecoration(
              labelText: 'Data de nascimento',
              hintText: 'dd/MM/yyyy',
              suffixIcon: Icon(Icons.calendar_today_outlined),
            ),
            validator: (_) =>
                _birthDate == null ? 'Informe sua data de nascimento.' : null,
          ),
          if (_formError != null) ...[
            const SizedBox(height: 16),
            Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _isSubmitting ? null : _submit,
            child: _isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Criar conta'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccess() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 56,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Conta criada',
          style: Theme.of(context).textTheme.headlineSmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Seu cadastro foi concluído. Continue para autenticar sua conta.',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

void main() {
  final session = SessionController(
    repository: AuthApiClient(),
    storage: const SecureSessionStorage(),
  );
  runApp(FinoraApp(session: session));
}
