# Finora Mobile

Aplicativo Flutter do Finora. Este documento descreve como preparar, executar e validar o frontend da Historia 001.

## Pre-requisitos

- Flutter SDK compativel com Dart `3.13.2` ou superior dentro da faixa definida em `pubspec.yaml`.
- Android Studio com um emulador Android, Xcode com um simulador iOS, Chrome ou um dispositivo desktop suportado pelo Flutter.
- Backend local do Finora executando e acessivel pelo dispositivo escolhido.
- `flutter doctor` sem problemas bloqueantes para a plataforma usada.

Valide o ambiente a partir deste diretorio:

```text
finora-mobile/
```

```bash
flutter doctor -v
flutter devices
```

## Dependencias

Ainda no diretorio `finora-mobile/`, instale ou atualize as dependencias:

```bash
flutter pub get
```

O projeto utiliza, entre outras dependencias, `flutter_secure_storage` para manter a sessao local. Nao versione arquivos de configuracao com credenciais, tokens ou chaves.

## Backend local

O aplicativo precisa de um backend local disponivel para cadastro, autenticacao e operacoes protegidas. Inicie o backend conforme as instrucoes proprias do projeto antes de validar os fluxos integrados.

Informe somente a URL base local por `--dart-define`. O valor nao e persistido no repositorio:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

Para o emulador Android, o valor padrao do aplicativo usa `http://10.0.2.2:8080`, que aponta para o host da maquina. Em simuladores iOS e dispositivos desktop, use a URL acessivel pela plataforma, normalmente `http://localhost:8080` durante o desenvolvimento local.

Nao informe senha, token JWT ou qualquer segredo em `--dart-define`, argumentos compartilhados, logs ou arquivos versionados.

## Executar em desenvolvimento

Liste os dispositivos disponiveis e substitua `<device-id>` pelo identificador escolhido:

```bash
flutter devices
flutter run -d <device-id> --dart-define=API_BASE_URL=http://localhost:8080
```

Exemplos de plataformas suportadas pelo projeto:

```bash
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
flutter run -d windows --dart-define=API_BASE_URL=http://localhost:8080
```

O aplicativo inicia verificando a sessao persistida. Uma sessao ausente, invalida ou rejeitada deve levar ao fluxo publico de entrada.

## Testes e quality gates

Execute os comandos a partir de `finora-mobile/`:

```bash
flutter test
flutter analyze
flutter build web --release
```

Os testes automatizados cobrem cadastro, autenticacao, restauracao e encerramento de sessao, consulta e edicao do perfil, confirmacao/cancelamento da inativacao e tratamento de erros. O build web valida que o aplicativo pode ser empacotado para uma plataforma suportada.

## Roteiro manual da Historia 001

Use uma conta descartavel do ambiente local. Nao use dados pessoais reais e nao compartilhe a senha criada para o teste.

1. Inicie o backend local e o aplicativo com `API_BASE_URL` apontando para ele.
2. Crie uma conta informando nome, e-mail, senha e data de nascimento. Confirme que o cadastro termina sem expor a senha.
3. Entre com a conta criada. Confirme que a sessao abre a area protegida e permanece apos reiniciar o aplicativo quando o token local ainda for valido.
4. Abra o perfil. Confirme nome, e-mail, data de nascimento e estado da conta. Senha, hash e token nao devem aparecer.
5. Abra a edicao. Confirme que nome e data iniciam preenchidos, que e-mail nao e campo editavel, que cancelar descarta alteracoes e que salvar atualiza os dados exibidos.
6. Provoque um erro de rede ou backend durante a consulta/edicao. Confirme que o erro e seguro, que os dados anteriores permanecem e que uma nova tentativa e possivel.
7. Use logout. Confirme que a sessao local e removida e que o fluxo protegido nao permanece acessivel.
8. Abra novamente o perfil e selecione `Inativar conta`. Cancele o dialogo e confirme que nenhuma requisicao e feita e a sessao permanece ativa.
9. Repita a acao, confirme a inativacao e aguarde o retorno ao fluxo publico. A requisicao deve ocorrer uma vez, mostrar processamento e nao pedir a senha atual.
10. Tente entrar novamente com a conta inativada. Confirme que o backend rejeita o acesso e que a conta nao permanece utilizavel na sessao atual.

## Limitacoes conhecidas

- A validacao integrada depende do backend local, do banco e das configuracoes de ambiente correspondentes.
- O frontend nao fornece renovacao silenciosa de token nem recuperacao de senha.
- O endereco `10.0.2.2` e especifico do emulador Android; outros dispositivos podem exigir uma URL diferente.
- O armazenamento seguro e especifico da plataforma. Testes automatizados usam implementacoes falsas e nao substituem a validacao manual em um dispositivo.