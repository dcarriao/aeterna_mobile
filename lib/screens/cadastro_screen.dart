import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pessoa.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

class CadastroScreen extends StatefulWidget {
  const CadastroScreen({required this.onCadastrado, super.key});

  final VoidCallback onCadastrado;

  @override
  State<CadastroScreen> createState() => _CadastroScreenState();
}

class _CadastroScreenState extends State<CadastroScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nomeCtrl = TextEditingController();
  final _sobrenomeCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _senhaCtrl = TextEditingController();
  final _confirmaCtrl = TextEditingController();

  bool _ocultarSenha = true;
  bool _salvando = false;

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _sobrenomeCtrl.dispose();
    _emailCtrl.dispose();
    _senhaCtrl.dispose();
    _confirmaCtrl.dispose();
    super.dispose();
  }

  Future<void> _cadastrar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      final uid = await PessoaRepository.criarUsuario(
        nome: _nomeCtrl.text.trim(),
        sobrenome: _sobrenomeCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
        senha: _senhaCtrl.text,
      );
      if (uid == null) {
        if (mounted) _mostrarErro('Erro ao criar conta. Tente novamente.');
        return;
      }
      // FLUXO TRANSPARENTE: o usuário nunca é mandado para outra tela nem
      // descobre se já tinha conta. Novo/pendente/senha-certa => entra aqui.
      if (uid == -2) {
        // E-mail já existe e a senha digitada não confere. Mensagem mínima,
        // sem revelar a existência da conta nem empurrar para o login.
        if (mounted) {
          _mostrarErro('Senha incorreta. Se você já criou uma senha antes, use a mesma.');
        }
        return;
      }
      if (uid == -1 || uid <= 0) {
        if (mounted) _mostrarErro('Não foi possível entrar. Tente novamente.');
        return;
      }
      PessoaRepository.usuarioId = uid;
      PessoaRepository.usuarioEmail = _emailCtrl.text.trim().toLowerCase();
      SupabaseService.usuarioId = uid;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_logged_in', true);
      await prefs.setString('session_user_email', _emailCtrl.text.trim().toLowerCase());
      await prefs.setInt('session_pessoa_id', uid);

      if (mounted) widget.onCadastrado();
    } catch (_) {
      if (mounted) _mostrarErro('Erro ao criar conta. Tente novamente.');
    }
  }

  void _mostrarErro(String msg) {
    setState(() => _salvando = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
                    BoxShadow(color: Color(0x062B1747), blurRadius: 16, offset: Offset(0, 8)),
                  ],
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: Image.asset('assets/logo.png', height: 72)),
                      const SizedBox(height: 24),
                      const Text(
                        'Criar conta',
                        style: TextStyle(color: AppColors.roxo, fontSize: 22, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Comece a construir o legado da sua família.',
                        style: TextStyle(color: AppColors.textoSuave, fontSize: 14),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nomeCtrl,
                              decoration: const InputDecoration(labelText: 'Nome', prefixIcon: Icon(Icons.person_outline, color: AppColors.dourado, size: 20)),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe seu nome' : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _sobrenomeCtrl,
                              decoration: const InputDecoration(labelText: 'Sobrenome', prefixIcon: Icon(Icons.person_outline, color: AppColors.dourado, size: 20)),
                              validator: (v) => (v ?? '').trim().isEmpty ? 'Informe seu sobrenome' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'E-mail', prefixIcon: Icon(Icons.mail_outline, color: AppColors.dourado, size: 20)),
                        validator: (v) {
                          final e = (v ?? '').trim();
                          if (!e.contains('@') || !e.contains('.')) return 'E-mail inválido';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _senhaCtrl,
                        obscureText: _ocultarSenha,
                        decoration: InputDecoration(
                          labelText: 'Senha',
                          prefixIcon: const Icon(Icons.lock_outline, color: AppColors.dourado, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(_ocultarSenha ? Icons.visibility_outlined : Icons.visibility_off_outlined, color: Colors.grey.shade400),
                            onPressed: () => setState(() => _ocultarSenha = !_ocultarSenha),
                          ),
                        ),
                        validator: (v) {
                          if ((v ?? '').length < 6) return 'Mínimo 6 caracteres';
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _confirmaCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: 'Confirmar senha', prefixIcon: Icon(Icons.lock_outline, color: AppColors.dourado, size: 20)),
                        validator: (v) {
                          if (v != _senhaCtrl.text) return 'Senhas não conferem';
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _salvando ? null : _cadastrar,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.roxo,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: _salvando
                            ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('Criar conta'),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: AppColors.roxo),
                        child: const Text('Já tenho conta', style: TextStyle(fontWeight: FontWeight.w600)),
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
