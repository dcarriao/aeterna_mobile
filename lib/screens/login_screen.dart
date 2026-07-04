import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pessoa.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({required this.onEntrar, super.key});

  final VoidCallback onEntrar;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  static const _emailKey = 'login_email';
  static const _lembrarKey = 'login_lembrar_email';
  static const _biometriaHabilitadaKey = 'biometria_habilitada';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();
  final LocalAuthentication _auth = LocalAuthentication();

  bool _lembrarDados = false;
  bool _ocultarSenha = true;
  bool _entrando = false;
  bool _podeUsarBiometria = false;

  @override
  void initState() {
    super.initState();
    _carregarPreferencias();
    _verificarConfiguracaoBiometria();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
  }

  Future<void> _verificarConfiguracaoBiometria() async {
    try {
      final canAuthenticateWithBiometrics = await _auth.canCheckBiometrics;
      final canAuthenticate = canAuthenticateWithBiometrics || await _auth.isDeviceSupported();
      if (!canAuthenticate) return;

      final prefs = await SharedPreferences.getInstance();
      final habilitada = prefs.getBool(_biometriaHabilitadaKey) ?? false;

      if (mounted) {
        setState(() {
          _podeUsarBiometria = habilitada;
        });
      }
    } catch (_) {}
  }

  Future<void> _carregarPreferencias() async {
    final preferencias = await SharedPreferences.getInstance();
    final lembrar = preferencias.getBool(_lembrarKey) ?? false;
    if (!mounted) return;

    setState(() {
      _lembrarDados = lembrar;
      if (lembrar) {
        _emailController.text = preferencias.getString(_emailKey) ?? '';
      }
    });
  }

  Future<void> _entrar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _entrando = true);
    try {
      final email = _emailController.text.trim();
      final senha = _senhaController.text;
      final uid = await PessoaRepository.autenticarUsuario(email, senha);
      if (uid == null) {
        if (mounted) {
          setState(() => _entrando = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('E-mail ou senha incorretos.')),
          );
        }
        return;
      }

      // Define a sessão dinâmica
      PessoaRepository.usuarioId = uid;
      PessoaRepository.usuarioEmail = email;
      SupabaseService.usuarioId = uid;

      final preferencias = await SharedPreferences.getInstance();
      await preferencias.setBool('is_logged_in', true);
      await preferencias.setString('session_user_email', email);
      await preferencias.setBool(_lembrarKey, _lembrarDados);

      if (_lembrarDados) {
        await preferencias.setString(_emailKey, email);
      } else {
        await preferencias.remove(_emailKey);
      }

      if (!mounted) return;
      widget.onEntrar();
    } catch (_) {
      if (mounted) {
        setState(() => _entrando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao acessar. Tente novamente.')),
        );
      }
    }
  }

  Future<void> _autenticarComBiometria() async {
    try {
      final autenticado = await _auth.authenticate(
        localizedReason: 'Acesse seu legado familiar na aEterna',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );

      if (autenticado && mounted) {
        final email = _emailController.text.trim();
        final uid = await PessoaRepository.obterUsuarioIdPorEmail(email);
        if (uid != null) {
          PessoaRepository.usuarioId = uid;
          PessoaRepository.usuarioEmail = email;
          SupabaseService.usuarioId = uid;
          final preferencias = await SharedPreferences.getInstance();
          await preferencias.setBool('is_logged_in', true);
          await preferencias.setString('session_user_email', email);
        }
        widget.onEntrar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Falha na biometria: $e')),
        );
      }
    }
  }

  void _recuperarSenhaDialog() {
    final controller = TextEditingController(text: _emailController.text);
    showDialog<void>(
      context: context,
      builder: (ctx) {
        bool enviando = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: const Text('Recuperar senha', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Digite seu e-mail cadastrado para receber um link de redefinição de senha.', style: TextStyle(color: Color(0xFF625B67), fontSize: 14)),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: controller,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'E-mail',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancelar', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w700)),
                ),
                FilledButton(
                  onPressed: enviando ? null : () async {
                    final email = controller.text.trim();
                    if (email.isEmpty || !email.contains('@')) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Por favor, insira um e-mail válido.')),
                      );
                      return;
                    }
                    setDialogState(() => enviando = true);
                    try {
                      await PessoaRepository.recuperarSenha(email);
                      if (ctx.mounted) Navigator.of(ctx).pop();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Link de recuperação enviado com sucesso! Verifique seu e-mail.')),
                        );
                      }
                    } catch (e) {
                      setDialogState(() => enviando = false);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erro ao enviar: $e')),
                        );
                      }
                    }
                  },
                  style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
                  child: enviando
                      ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Enviar'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFEDE8DC)),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x062B1747),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Image.asset('assets/logo.png', height: 80),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Bem-vindo de volta',
                        style: TextStyle(
                          color: AppColors.roxo,
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Continue construindo o legado da sua família.',
                        style: TextStyle(
                          color: AppColors.textoSuave,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 28),

                      // ── EMAIL ──
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          'E-mail',
                          style: TextStyle(
                              color: AppColors.roxo,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          hintText: 'Digite seu e-mail',
                          prefixIcon: Icon(Icons.mail_outline,
                              color: AppColors.dourado, size: 20),
                        ),
                        validator: (valor) {
                          final email = valor?.trim() ?? '';
                          if (!email.contains('@') || !email.contains('.')) {
                            return 'Digite um e-mail válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),

                      // ── SENHA ──
                      const Padding(
                        padding: EdgeInsets.only(bottom: 6, left: 4),
                        child: Text(
                          'Senha',
                          style: TextStyle(
                              color: AppColors.roxo,
                              fontSize: 13,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      TextFormField(
                        controller: _senhaController,
                        obscureText: _ocultarSenha,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          hintText: 'Digite sua senha',
                          prefixIcon: const Icon(Icons.lock_outline,
                              color: AppColors.dourado, size: 20),
                          suffixIcon: IconButton(
                            tooltip: _ocultarSenha
                                ? 'Mostrar senha'
                                : 'Ocultar senha',
                            onPressed: () {
                              setState(() => _ocultarSenha = !_ocultarSenha);
                            },
                            icon: Icon(
                              _ocultarSenha
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              color: Colors.grey.shade400,
                            ),
                          ),
                        ),
                        validator: (valor) {
                          if ((valor ?? '').length < 4) {
                            return 'Digite sua senha.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 6),

                      // ── LEMBRAR ME & RECUPERAR SENHA ──
                      SizedBox(
                        width: double.infinity,
                        child: Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    checkboxTheme: CheckboxThemeData(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                  ),
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Checkbox(
                                      value: _lembrarDados,
                                      activeColor: AppColors.roxo,
                                      onChanged: (valor) {
                                        setState(() => _lembrarDados = valor ?? false);
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Text(
                                  'Lembrar meus dados',
                                  style: TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _recuperarSenhaDialog,
                                child: const Text(
                                  'Esqueceu a senha?',
                                  style: TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),

                      // ── BOTÃO ENTRAR ──
                      FilledButton(
                        onPressed: _entrando ? null : _entrar,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: _entrando
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Entrar'),
                      ),
                      if (_podeUsarBiometria) ...[
                        const SizedBox(height: 12),
                        TextButton.icon(
                          onPressed: _autenticarComBiometria,
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.roxo,
                          ),
                          icon: const Icon(Icons.fingerprint, size: 20),
                          label: const Text('Entrar com biometria',
                              style: TextStyle(fontWeight: FontWeight.w600)),
                        ),
                      ],
                      const Divider(height: 28),
                      TextButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Criação de conta em breve.'),
                            ),
                          );
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.roxo,
                        ),
                        child: const Text('Ainda não tenho conta',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
