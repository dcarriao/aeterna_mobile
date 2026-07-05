import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'cofre_screen.dart';
import 'mensagens_futuro_screen.dart';
import 'quem_sou_eu_screen.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({
    required this.totalMemorias,
    required this.totalPessoas,
    required this.onLogout,
    super.key,
  });

  final int totalMemorias;
  final int totalPessoas;
  final VoidCallback onLogout;

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _picker = ImagePicker();
  final LocalAuthentication _auth = LocalAuthentication();
  static const _biometriaHabilitadaKey = 'biometria_habilitada';

  Map<String, dynamic> _usuario = {};
  bool _carregando = true;
  bool _salvandoFoto = false;

  // Preferências e Segurança
  bool _notificacoes = true;
  bool _biometria = false;

  @override
  void initState() {
    super.initState();
    _carregarUsuario();
    _carregarConfiguracaoBiometria();
  }

  Future<void> _carregarConfiguracaoBiometria() async {
    final prefs = await SharedPreferences.getInstance();
    final habilitada = prefs.getBool(_biometriaHabilitadaKey) ?? false;
    if (mounted) {
      setState(() {
        _biometria = habilitada;
      });
    }
  }

  Future<void> _carregarUsuario() async {
    setState(() => _carregando = true);
    final dados = await PessoaRepository.obterUsuario();
    if (mounted) {
      setState(() {
        _usuario = dados ??
            {
              'nome': 'Darlan',
              'sobrenome': 'Carrião',
              'email': 'darlan.p.carriao@gmail.com',
              'telefone': '(51) 99999-9999',
              'data_nascimento': '1990-01-24',
              'foto_perfil': null,
            };
        _carregando = false;
      });
    }
  }

  Future<void> _salvarCampo(String chave, String valor) async {
    final novosDados = Map<String, dynamic>.from(_usuario);
    novosDados[chave] = valor;

    setState(() {
      _usuario = novosDados;
    });

    await PessoaRepository.salvarUsuario({chave: valor});
  }

  Future<void> _capturarFoto(ImageSource origem) async {
    try {
      final imagem = await _picker.pickImage(
        source: origem,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (imagem == null) return;

      setState(() => _salvandoFoto = true);
      final bytes = await imagem.readAsBytes();
      final url = await PessoaRepository.uploadFotoPerfil(bytes, imagem.name);

      if (mounted) {
        setState(() {
          if (url != null) {
            _usuario['foto_perfil'] = url;
          }
          _salvandoFoto = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _salvandoFoto = false);
    }
  }

  void _abrirOpcoesFoto() {
    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.roxo),
              title: const Text('Tirar foto', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _capturarFoto(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.roxo),
              title: const Text('Escolher da Galeria', style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.of(ctx).pop();
                _capturarFoto(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _editarCampoDialog(String label, String chave, String valorAtual) {
    final controller = TextEditingController(text: valorAtual);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Editar $label', style: const TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        content: TextFormField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: label,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () {
              final novoValor = controller.text.trim();
              if (novoValor.isNotEmpty) {
                _salvarCampo(chave, novoValor);
              }
              Navigator.of(ctx).pop();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _confirmarLogout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Encerrar sessão', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        content: const Text('Tem certeza de que deseja sair da sua conta?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w700)),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              widget.onLogout();
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        appBar: AppBar(title: const Text('Minha Conta')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    final fotoUrl = _usuario['foto_perfil'] as String?;

    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 44),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 20),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.person_outline,
                color: AppColors.roxo, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
              children: [
                const Text(
                  'Minha Conta',
                  style: TextStyle(
                    color: AppColors.roxo,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 24),

                // ── CARD SUPERIOR: FOTO ──
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEDE8DC)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x042B1747),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Center(
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 52,
                              backgroundColor: const Color(0xFFF0EAF5),
                              backgroundImage: fotoUrl != null ? NetworkImage(fotoUrl) : null,
                              child: fotoUrl == null
                                  ? const Icon(Icons.person, size: 52, color: AppColors.roxo)
                                  : null,
                            ),
                            if (_salvandoFoto)
                              const Positioned.fill(
                                child: CircularProgressIndicator(strokeWidth: 3),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: _salvandoFoto ? null : _abrirOpcoesFoto,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.roxo,
                          side: const BorderSide(color: AppColors.borda),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.camera_alt_outlined, size: 16),
                        label: const Text('Alterar foto'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // ── INFORMAÇÕES PESSOAIS ──
                _PerfilSectionCard(
                  titulo: 'Informações pessoais',
                  icon: Icons.assignment_ind_outlined,
                  children: [
                    _PerfilInfoRow(
                      label: 'Nome',
                      value: _usuario['nome'] ?? 'Darlan',
                      onEdit: () => _editarCampoDialog('Nome', 'nome', _usuario['nome'] ?? 'Darlan'),
                    ),
                    _PerfilInfoRow(
                      label: 'Sobrenome',
                      value: _usuario['sobrenome'] ?? 'Carrião',
                      onEdit: () => _editarCampoDialog('Sobrenome', 'sobrenome', _usuario['sobrenome'] ?? 'Carrião'),
                    ),
                    _PerfilInfoRow(
                      label: 'E-mail',
                      value: _usuario['email'] ?? 'darlan.p.carriao@gmail.com',
                      onEdit: () => _editarCampoDialog('E-mail', 'email', _usuario['email'] ?? ''),
                    ),
                    _PerfilInfoRow(
                      label: 'Telefone',
                      value: _usuario['telefone'] ?? 'Não informado',
                      onEdit: () => _editarCampoDialog('Telefone', 'telefone', _usuario['telefone'] ?? ''),
                    ),
                    _PerfilInfoRow(
                      label: 'Data de nascimento',
                      value: _usuario['data_nascimento'] ?? 'Não informada',
                      onEdit: () => _editarCampoDialog('Data de nascimento', 'data_nascimento', _usuario['data_nascimento'] ?? ''),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── RECURSOS ──
                _PerfilSectionCard(
                  titulo: 'Recursos',
                  icon: Icons.widgets_outlined,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.schedule_send_outlined, color: AppColors.dourado, size: 20),
                      title: const Text('Mensagens para o Futuro', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8B8)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MensagensFuturoScreen())),
                    ),
                    const Divider(height: 1, color: Color(0xFFEDE8DC)),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.lock_outline, color: AppColors.dourado, size: 20),
                      title: const Text('Cofre', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8B8)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CofreScreen())),
                    ),
                    const Divider(height: 1, color: Color(0xFFEDE8DC)),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.face_outlined, color: AppColors.dourado, size: 20),
                      title: const Text('Quem Sou Eu', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      trailing: const Icon(Icons.chevron_right, color: Color(0xFFB0A8B8)),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const QuemSouEuScreen())),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── MEU PLANO CARD ──
                _PerfilSectionCard(
                  titulo: 'Meu Plano',
                  icon: Icons.star_outline,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Estrutura base — integração de pagamentos futura.',
                        style: TextStyle(color: Color(0xFF7A7280), fontSize: 12),
                      ),
                    ),
                    const Divider(height: 1, color: Color(0xFFEDE8DC)),
                    const SizedBox(height: 12),
                    _LimiteProgressRow(label: 'Histórias registradas', atual: widget.totalMemorias, max: 100),
                    const SizedBox(height: 8),
                    _LimiteProgressRow(label: 'Contatos da família', atual: widget.totalPessoas, max: 15),
                  ],
                ),
                const SizedBox(height: 16),

                // ── SEGURANÇA ──
                _PerfilSectionCard(
                  titulo: 'Segurança',
                  icon: Icons.shield_outlined,
                  children: [
                    _PerfilInfoRow(
                      label: 'Senha',
                      value: '••••••••••••',
                      onEdit: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Fluxo de redefinição de senha enviado ao e-mail.')),
                        );
                      },
                    ),
                    SwitchListTile(
                      value: _biometria,
                      onChanged: (val) async {
                        setState(() => _biometria = val);
                        final prefs = await SharedPreferences.getInstance();
                        await prefs.setBool(_biometriaHabilitadaKey, val);
                      },
                      activeThumbColor: AppColors.roxo,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Entrar com Biometria', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      secondary: const Icon(Icons.fingerprint, color: AppColors.dourado, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── PREFERÊNCIAS ──
                _PerfilSectionCard(
                  titulo: 'Preferências',
                  icon: Icons.tune_outlined,
                  children: [
                    SwitchListTile(
                      value: _notificacoes,
                      onChanged: (val) => setState(() => _notificacoes = val),
                      activeThumbColor: AppColors.roxo,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Notificações no celular', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      secondary: const Icon(Icons.notifications_none_outlined, color: AppColors.dourado, size: 20),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Idioma', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Português (Brasil)', style: TextStyle(fontSize: 12)),
                      leading: Icon(Icons.language_outlined, color: AppColors.dourado, size: 20),
                      enabled: false,
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Tema visual', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('Claro (Creme)', style: TextStyle(fontSize: 12)),
                      leading: Icon(Icons.dark_mode_outlined, color: AppColors.dourado, size: 20),
                      enabled: false,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── SOBRE ──
                _PerfilSectionCard(
                  titulo: 'Sobre',
                  icon: Icons.info_outline,
                  children: [
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('Versão do aplicativo', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      subtitle: Text('1.0.0 (Build 5)', style: TextStyle(fontSize: 12)),
                      leading: Icon(Icons.phone_android_outlined, color: AppColors.dourado, size: 20),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Política de Privacidade', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      leading: const Icon(Icons.policy_outlined, color: AppColors.dourado, size: 20),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Política de Privacidade', style: TextStyle(fontWeight: FontWeight.w800)),
                            content: const Text('Os seus dados de memórias e fotos familiares são mantidos de forma estritamente privada, criptografada e segura, não sendo compartilhados com terceiros em nenhuma hipótese.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar')),
                            ],
                          ),
                        );
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Termos de Uso', style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
                      leading: const Icon(Icons.gavel_outlined, color: AppColors.dourado, size: 20),
                      onTap: () {
                        showDialog<void>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Termos de Uso', style: TextStyle(fontWeight: FontWeight.w800)),
                            content: const Text('Ao utilizar a plataforma aEterna, você se compromete a registrar apenas conteúdos verídicos e de sua autoria ou com autorização da sua família.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fechar')),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // ── BOTÃO SAIR ──
                FilledButton.icon(
                  onPressed: _confirmarLogout,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.logout_outlined, size: 18),
                  label: const Text('Encerrar sessão'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PerfilSectionCard extends StatelessWidget {
  const _PerfilSectionCard({
    required this.titulo,
    required this.icon,
    required this.children,
  });

  final String titulo;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE8DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x042B1747),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: AppColors.dourado),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _PerfilInfoRow extends StatelessWidget {
  const _PerfilInfoRow({
    required this.label,
    required this.value,
    required this.onEdit,
  });

  final String label;
  final String value;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF7A7280), fontSize: 12)),
                const SizedBox(height: 2),
                Text(value, style: const TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.roxo),
            onPressed: onEdit,
          ),
        ],
      ),
    );
  }
}

class _LimiteProgressRow extends StatelessWidget {
  const _LimiteProgressRow({
    required this.label,
    required this.atual,
    required this.max,
  });

  final String label;
  final int atual;
  final int max;

  @override
  Widget build(BuildContext context) {
    final progresso = (atual / max).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF7A7280), fontSize: 12)),
              Text('$atual de $max', style: const TextStyle(color: AppColors.roxo, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progresso,
              backgroundColor: const Color(0xFFEDE8DC),
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dourado),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}


