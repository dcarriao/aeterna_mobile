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

      // TODO: autenticar com Supabase Auth e guardar tokens apenas em storage seguro.
      // Nunca persistir a senha em texto puro.
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
    // TODO: integrar local_auth no Android/iOS com flutter_secure_storage.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Biometria disponível no app mobile.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.borda),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x172B1747),
                      blurRadius: 28,
                      offset: Offset(0, 14),
                    ),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.all_inclusive,
                              color: AppColors.dourado,
                              size: 31,
                            ),
                            SizedBox(width: 9),
                            Text(
                              'aEterna',
                              style: TextStyle(
                                color: AppColors.roxo,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Bem-vindo à aEterna',
                        style: TextStyle(
                          color: AppColors.roxo,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 7),
                      const Text(
                        'Continue construindo sua história.',
                        style: TextStyle(
                          color: AppColors.textoSuave,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 26),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'E-mail',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: (valor) {
                          final email = valor?.trim() ?? '';
                          if (!email.contains('@') || !email.contains('.')) {
                            return 'Digite um e-mail válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _senhaController,
                        obscureText: _ocultarSenha,
                        autofillHints: const [AutofillHints.password],
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline),
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
                      Material(
                        color: Colors.transparent,
                        child: CheckboxListTile(
                          value: _lembrarDados,
                          onChanged: (valor) {
                            setState(() => _lembrarDados = valor ?? false);
                          },
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Lembrar meus dados'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _entrando ? null : _entrar,
                        child: _entrando
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Entrar'),
                      ),
                      const SizedBox(height: 10),
                      TextButton.icon(
                        onPressed: _mostrarBiometria,
                        icon: const Icon(Icons.fingerprint),
                        label: const Text('Entrar com biometria'),
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
                        child: const Text('Ainda não tenho conta'),
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
