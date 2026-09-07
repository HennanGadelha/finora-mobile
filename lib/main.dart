import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

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
      : baseUri = baseUri ?? Uri.parse(const String.fromEnvironment(
          'API_BASE_URL',
          defaultValue: 'http://10.0.2.2:8080',
        ));

  final Uri baseUri;

  @override
  Future<void> register(RegistrationRequest request) async {
    final client = HttpClient();
    try {
      final httpRequest = await client.postUrl(baseUri.resolve('/api/auth/register'));
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
      await widget.repository.register(RegistrationRequest(
        name: _nameController.text.trim(),
        email: _emailController.text.trim().toLowerCase(),
        password: _passwordController.text,
        birthDate: _birthDate!,
      ));
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _isComplete = true;
      });
      widget.onRegistrationSuccess?.call();
    } on RegistrationException catch (error) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
        _formError = error.message;
      });
    }
  }

  Future<void> _selectBirthDate() async {
    final selected = await showDatePicker(
      context: context,
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
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(labelText: 'Senha'),
            validator: (value) => value == null || value.isEmpty
                ? 'Informe sua senha.'
                : null,
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
            validator: (_) => _birthDate == null
                ? 'Informe sua data de nascimento.'
                : null,
          ),
          if (_formError != null) ...[
            const SizedBox(height: 16),
            Text(_formError!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
        Icon(Icons.check_circle_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Conta criada', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        const Text('Seu cadastro foi concluído. Continue para autenticar sua conta.', textAlign: TextAlign.center),
      ],
    );
  }
}

void main() {
  runApp(const FinoraApp());
}

class FinoraApp extends StatelessWidget {
  const FinoraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finora',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB))),
      darkTheme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2563EB), brightness: Brightness.dark)),
      home: RegistrationPage(repository: RegistrationApiClient()),
    );
  }
}
