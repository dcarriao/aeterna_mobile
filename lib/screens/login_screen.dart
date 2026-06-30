import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _senhaController = TextEditingController();

  bool _lembrarDados = false;
  bool _ocultarSenha = true;
  bool _entrando = false;

  @override
  void initState() {
    super.initState();
    _carregarPreferencias();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _senhaController.dispose();
    super.dispose();
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
      final preferencias = await SharedPreferences.getInstance();
      await preferencias.setBool(_lembrarKey, _lembrarDados);

      if (_lembrarDados) {
        await preferencias.setString(_emailKey, _emailController.text.trim());
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

  void _mostrarBiometria() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Biometria disponível no app mobile.')),
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
                        style: TextStyle(
                            color: AppColors.roxo,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
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
                        style: TextStyle(
                            color: AppColors.roxo,
                            fontSize: 13,
                            fontWeight: FontWeight.w700),
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

                      // ── LEMBRAR ME ──
                      Theme(
                        data: Theme.of(context).copyWith(
                          checkboxTheme: CheckboxThemeData(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ),
                        child: CheckboxListTile(
                          value: _lembrarDados,
                          onChanged: (valor) {
                            setState(() => _lembrarDados = valor ?? false);
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: AppColors.roxo,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text(
                            'Lembrar meus dados',
                            style: TextStyle(
                                color: AppColors.roxo,
                                fontWeight: FontWeight.w600),
                          ),
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
                      const SizedBox(height: 12),

                      TextButton.icon(
                        onPressed: _mostrarBiometria,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.roxo,
                        ),
                        icon: const Icon(Icons.fingerprint, size: 20),
                        label: const Text('Entrar com biometria',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
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
