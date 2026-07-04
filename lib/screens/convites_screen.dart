import 'package:flutter/material.dart';

import '../models/convite_familiar.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';

/// Tela de convites familiares (Sprint — Vínculos Familiares e Permissões
/// Colaborativas). Substitui o modelo frágil "contato por e-mail": aqui o
/// convite tem ciclo de vida real (pendente -> aceito/recusado) e, ao ser
/// aceito, cria um vínculo bilateral de verdade entre as duas contas.
class ConvitesScreen extends StatefulWidget {
  const ConvitesScreen({super.key});

  @override
  State<ConvitesScreen> createState() => _ConvitesScreenState();
}

class _ConvitesScreenState extends State<ConvitesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<ConviteFamiliar> _recebidos = [];
  List<ConviteFamiliar> _enviados = [];
  bool _carregando = true;
  final _emailController = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _carregar();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    setState(() => _carregando = true);
    final recebidos = await PessoaRepository.listarConvitesRecebidos();
    final enviados = await PessoaRepository.listarConvitesEnviados();
    if (mounted) {
      setState(() {
        _recebidos = recebidos;
        _enviados = enviados;
        _carregando = false;
      });
    }
  }

  Future<void> _aceitar(ConviteFamiliar convite) async {
    try {
      await PessoaRepository.aceitarConviteFamiliar(convite);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Vínculo com ${convite.nomeOrigem ?? 'familiar'} confirmado!')),
        );
        _carregar();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao aceitar convite: $e')),
        );
      }
    }
  }

  Future<void> _recusar(ConviteFamiliar convite) async {
    if (convite.id == null) return;
    try {
      await PessoaRepository.recusarConviteFamiliar(convite.id!);
      if (mounted) _carregar();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao recusar convite: $e')),
        );
      }
    }
  }

  Future<void> _enviarConvite() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe um e-mail válido.')),
      );
      return;
    }
    setState(() => _enviando = true);
    try {
      await PessoaRepository.enviarConviteFamiliar(email: email);
      _emailController.clear();
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Convite enviado com sucesso!')),
        );
        _carregar();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar convite: $e')),
        );
      }
    }
  }

  String _rotuloStatus(String status) {
    switch (status) {
      case 'aceito':
        return 'Aceito';
      case 'recusado':
        return 'Recusado';
      case 'expirado':
        return 'Expirado';
      default:
        return 'Pendente';
    }
  }

  Color _corStatus(String status) {
    switch (status) {
      case 'aceito':
        return AppColors.verdeApoio;
      case 'recusado':
        return Colors.redAccent;
      default:
        return AppColors.dourado;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Convites Familiares',
            style: TextStyle(color: AppColors.roxo, fontSize: 20, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.roxo,
          unselectedLabelColor: AppColors.textoSuave,
          indicatorColor: AppColors.dourado,
          tabs: [
            Tab(text: 'Recebidos${_recebidos.isNotEmpty ? ' (${_recebidos.length})' : ''}'),
            const Tab(text: 'Enviados'),
          ],
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAbaRecebidos(),
                      _buildAbaEnviados(),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildAbaRecebidos() {
    if (_recebidos.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mail_outline, size: 48, color: AppColors.borda),
              SizedBox(height: 16),
              Text(
                'Nenhum convite pendente.',
                style: TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text(
                'Quando um familiar te convidar, o convite aparecerá aqui para você aceitar ou recusar.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _recebidos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final c = _recebidos[index];
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${c.nomeOrigem ?? 'Alguém'} quer se conectar com você',
                style: const TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800),
              ),
              if (c.tipoConteudoAlvo != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Convite para colaborar em um ${c.tipoConteudoAlvo == 'memorial' ? 'memorial' : 'conteúdo'}'
                  '${c.papelSugerido != null ? ' como ${PapelColaborador.fromValor(c.papelSugerido)?.rotulo ?? c.papelSugerido}' : ''}.',
                  style: const TextStyle(color: AppColors.dourado, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _recusar(c),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                    ),
                    child: const Text('Recusar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => _aceitar(c),
                    style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
                    child: const Text('Aceitar'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAbaEnviados() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Convidar um familiar',
          style: TextStyle(color: AppColors.roxo, fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Envie um convite por e-mail. Quando a pessoa aceitar, ela passa a '
          'ver você e você passa a vê-la — sem depender de e-mail digitado errado.',
          style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'email@exemplo.com',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _enviando ? null : _enviarConvite,
              style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
              child: _enviando
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Convidar'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (_enviados.isEmpty)
          const Text(
            'Você ainda não enviou nenhum convite.',
            style: TextStyle(color: Color(0xFF7A7280), fontSize: 13),
          )
        else ...[
          const Text(
            'Convites enviados',
            style: TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          ..._enviados.map((c) {
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borda),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      c.emailDestino,
                      style: const TextStyle(color: AppColors.roxo, fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _corStatus(c.status).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      _rotuloStatus(c.status),
                      style: TextStyle(color: _corStatus(c.status), fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ],
    );
  }
}
