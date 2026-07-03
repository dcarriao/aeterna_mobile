import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../models/memorial.dart';
import '../models/contribuicao.dart';
import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../services/supabase_service.dart';
import '../services/legacy_curator_service.dart';
import '../theme/app_theme.dart';
import 'nova_memoria_screen.dart';

class MemorialDetalheScreen extends StatefulWidget {
  const MemorialDetalheScreen({required this.memorial, super.key});

  final Memorial memorial;

  @override
  State<MemorialDetalheScreen> createState() => _MemorialDetalheScreenState();
}

class _MemorialDetalheScreenState extends State<MemorialDetalheScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _service = SupabaseService.instance;

  List<Memoria> _memoriasOficiais = [];
  List<Contribuicao> _contribuicoes = [];
  bool _carregandoLembrancas = false;

  // IA Chat
  final List<Map<String, String>> _conversa = [];
  final _chatController = TextEditingController();
  final _chatScrollController = ScrollController();
  bool _enviandoChat = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _carregarDados();
    _inicializarMensagemCurador();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _chatController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  void _inicializarMensagemCurador() {
    _conversa.add({
      'role': 'assistant',
      'content': 'Olá, sou o Curador de Memórias de ${widget.memorial.nome}. Estou aqui para preservar seu legado, contar suas histórias e responder perguntas sobre sua vida e seus valores. Sobre o que você gostaria de lembrar hoje?',
    });
  }

  Future<void> _carregarDados() async {
    if (!_service.isConfigured) return;
    setState(() => _carregandoLembrancas = true);
    try {
      // 1. Listar todas as contribuições
      final contribs = await _service.listarContribuicoes(widget.memorial.id!);

      // 2. Listar memórias oficiais e cruzar os vínculos
      final todasMemorias = await _service.listarMemorias();
      final vinculos = await PessoaRepository.listarVinculos();
      
      // Buscar contatos com mesmo nome para cruzamento resiliente
      final contatos = await PessoaRepository.listar();
      final contatosComMesmoNome = contatos
          .where((c) => c.nome.trim().toLowerCase() == widget.memorial.nome.trim().toLowerCase())
          .map((c) => c.id)
          .toSet();

      final oficiais = todasMemorias.where((m) {
        if (m.id == null) return false;
        final contatosIds = vinculos[m.id];
        if (contatosIds == null) return false;
        
        final matchesContatoId = widget.memorial.contatoId != null && contatosIds.contains(widget.memorial.contatoId);
        final matchesName = contatosIds.any((id) => contatosComMesmoNome.contains(id));
        
        return matchesContatoId || matchesName;
      }).toList();

      if (mounted) {
        setState(() {
          _contribuicoes = contribs;
          _memoriasOficiais = oficiais;
          _carregandoLembrancas = false;
        });
      }
    } catch (e) {
      print('Erro ao carregar dados do memorial: $e');
      if (mounted) setState(() => _carregandoLembrancas = false);
    }
  }

  String _formatarData(DateTime data) {
    return '${data.day.toString().padLeft(2, '0')}/${data.month.toString().padLeft(2, '0')}/${data.year}';
  }

  int get _countPendentes => _contribuicoes.where((c) => !c.aprovado).length;

  Future<void> _moderar(Contribuicao c, bool aprovado) async {
    try {
      await _service.moderarContribuicao(c.id!, aprovado);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(aprovado ? 'Contribuição aprovada com sucesso.' : 'Contribuição rejeitada.')),
      );
      _carregarDados();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erro ao moderar: $e')),
      );
    }
  }

  Future<void> _excluirMemorial() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Excluir Memorial', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
        content: const Text('Tem certeza que deseja excluir permanentemente este memorial e todas as suas contribuições? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: Color(0xFF9B949D))),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmar == true && mounted) {
      try {
        await _service.excluirMemorial(widget.memorial.id!);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao excluir memorial: $e')),
        );
      }
    }
  }

  Future<void> _abrirCompartilharMemorial() async {
    final contatosVinculados = await PessoaRepository.obterContatosDoMemorial(widget.memorial.id!);
    
    if (!mounted) return;

    final resultado = await showModalBottomSheet<List<int>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return PessoaPickerSheet(
          selecionadas: contatosVinculados.toSet(),
          titulo: 'Convidar Familiares',
        );
      },
    );

    if (resultado != null && mounted) {
      setState(() {
        _carregandoLembrancas = true;
      });
      try {
        await PessoaRepository.atualizarContatosDoMemorial(widget.memorial.id!, resultado);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compartilhamento do memorial atualizado com sucesso! Seus convidados agora podem ver e enviar lembranças.')),
          );
        }
        _carregarDados();
      } catch (e) {
        if (mounted) {
          setState(() {
            _carregandoLembrancas = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao atualizar compartilhamento: $e')),
          );
        }
      }
    }
  }

  Future<void> _abrirNovaContribuicao() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => _NovaContribuicaoScreen(memorialId: widget.memorial.id!),
      ),
    );
    if (result == true) {
      _carregarDados();
    }
  }

  Future<void> _enviarMensagemChat() async {
    final texto = _chatController.text.trim();
    if (texto.isEmpty || _enviandoChat) return;

    setState(() {
      _conversa.add({'role': 'user', 'content': texto});
      _chatController.clear();
      _enviandoChat = true;
    });

    _rolarChatAoFim();

    try {
      // Compilar contexto dinâmico da história de vida do falecido
      final historias = <String>[];
      for (final m in _memoriasOficiais) {
        historias.add('Memória "${m.titulo}": ${m.contexto}');
      }
      for (final c in _contribuicoes.where((c) => c.aprovado)) {
        historias.add('Lembrança de ${c.autor} (${c.relacao}): ${c.conteudo}');
      }

      final resposta = await LegacyCuratorService.instance.responderComoCurador(
        nome: widget.memorial.nome,
        parentesco: widget.memorial.parentesco,
        biografia: widget.memorial.biografia,
        memoriasEContribuicoes: historias,
        historicoConversa: _conversa.sublist(1), // Exclui a mensagem de boas-vindas local
      );

      if (mounted) {
        setState(() {
          _conversa.add({
            'role': 'assistant',
            'content': resposta ?? 'Desculpe, tive um contratempo para acessar a memória do curador.',
          });
          _enviandoChat = false;
        });
        _rolarChatAoFim();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _conversa.add({
            'role': 'assistant',
            'content': 'Desculpe, ocorreu um erro de conexão com o curador.',
          });
          _enviandoChat = false;
        });
        _rolarChatAoFim();
      }
    }
  }

  void _rolarChatAoFim() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_chatScrollController.hasClients) {
        _chatScrollController.animateTo(
          _chatScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final aprovadas = _contribuicoes.where((c) => c.aprovado).toList();

    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Text(widget.memorial.nome,
            style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 20,
                fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
        actions: [
          IconButton(
            icon: const Icon(Icons.group_add_outlined, color: AppColors.roxo),
            onPressed: _abrirCompartilharMemorial,
            tooltip: 'Compartilhar / Convidar',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: _excluirMemorial,
            tooltip: 'Excluir Memorial',
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Column(
              children: [
                // Header do Memorial com Resumo Rápido
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  color: AppColors.fundo,
                  child: Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EAF5),
                          borderRadius: BorderRadius.circular(40),
                          border: Border.all(color: AppColors.borda, width: 2),
                          image: widget.memorial.fotoUrl != null && widget.memorial.fotoUrl!.isNotEmpty
                              ? DecorationImage(
                                  image: NetworkImage(widget.memorial.fotoUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: widget.memorial.fotoUrl == null || widget.memorial.fotoUrl!.isEmpty
                            ? const Icon(Icons.favorite_outline,
                                color: AppColors.roxo, size: 32)
                            : null,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.memorial.nome,
                              style: const TextStyle(
                                  color: AppColors.roxo,
                                  fontSize: 22,
                                  fontWeight: FontWeight.w900),
                            ),
                            Text(
                              widget.memorial.parentesco,
                              style: const TextStyle(
                                  color: AppColors.dourado,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.favorite, size: 14, color: AppColors.dourado),
                                const SizedBox(width: 6),
                                Text(
                                  '${_formatarData(widget.memorial.dataNascimento)} - ${_formatarData(widget.memorial.dataFalecimento)}',
                                  style: const TextStyle(
                                      color: Color(0xFF7A7280),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // TabBar Customizada
                TabBar(
                  controller: _tabController,
                  indicatorColor: AppColors.dourado,
                  labelColor: AppColors.roxo,
                  unselectedLabelColor: const Color(0xFF9B949D),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  tabs: [
                    const Tab(text: 'Biografia'),
                    const Tab(text: 'Lembranças'),
                    Tab(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('Moderar'),
                          if (_countPendentes > 0) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                              ),
                              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                              child: Text(
                                '$_countPendentes',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ]
                        ],
                      ),
                    ),
                    const Tab(text: 'Curador IA'),
                  ],
                ),

                // Conteúdo das Abas
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAbaBiografia(),
                      _buildAbaLembrancas(aprovadas),
                      _buildAbaModeracao(),
                      _buildAbaCuradorIA(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── ABA 1: BIOGRAFIA ──
  Widget _buildAbaBiografia() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_stories_outlined, color: AppColors.dourado, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sua História de Vida',
                    style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              const Divider(height: 24, color: AppColors.borda),
              Text(
                widget.memorial.biografia,
                style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    height: 1.6,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── ABA 2: LEMBRANÇAS (Timeline Unificada) ──
  Widget _buildAbaLembrancas(List<Contribuicao> aprovadas) {
    if (_carregandoLembrancas) {
      return const Center(child: CircularProgressIndicator(color: AppColors.roxo));
    }

    final totalItens = _memoriasOficiais.length + aprovadas.length;

    if (totalItens == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timeline_outlined, size: 48, color: AppColors.borda),
              const SizedBox(height: 16),
              const Text(
                'Nenhuma recordação ainda',
                style: TextStyle(color: AppColors.roxo, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Seja o primeiro a enviar uma lembrança ou vincule memórias oficiais a este ente querido.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _abrirNovaContribuicao,
                style: FilledButton.styleFrom(backgroundColor: AppColors.roxo),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Enviar Contribuição'),
              ),
            ],
          ),
        ),
      );
    }

    // Unificar e ordenar cronologicamente por data de criação descrescente
    final listaUnificada = <_ItemTimeline>[];
    for (final m in _memoriasOficiais) {
      listaUnificada.add(_ItemTimeline(
        titulo: m.titulo,
        autor: 'Proprietário',
        relacao: widget.memorial.parentesco,
        conteudo: m.contexto,
        fotoUrl: m.fotoUrl,
        criadoEm: m.criadaEm,
        isOficial: true,
      ));
    }
    for (final c in aprovadas) {
      listaUnificada.add(_ItemTimeline(
        titulo: 'Homenagem',
        autor: c.autor,
        relacao: c.relacao,
        conteudo: c.conteudo,
        fotoUrl: c.fotoUrl,
        videoUrl: c.videoUrl,
        criadoEm: c.createdAt,
        isOficial: false,
      ));
    }

    listaUnificada.sort((a, b) => b.criadoEm.compareTo(a.criadoEm));

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _abrirNovaContribuicao,
        backgroundColor: AppColors.roxo,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_outlined, size: 18),
        label: const Text('Contribuir', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 80),
        itemCount: listaUnificada.length,
        itemBuilder: (context, index) {
          final item = listaUnificada[index];
          return _buildCardTimeline(item);
        },
      ),
    );
  }

  Widget _buildCardTimeline(_ItemTimeline item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header com Autor
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: item.isOficial ? const Color(0xFFF0EAF5) : const Color(0xFFEAF5EF),
                  radius: 18,
                  child: Icon(
                    item.isOficial ? Icons.star_border : Icons.people_outline,
                    color: item.isOficial ? AppColors.roxo : AppColors.verdeApoio,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            item.autor,
                            style: const TextStyle(color: AppColors.roxo, fontSize: 14, fontWeight: FontWeight.w800),
                          ),
                          if (item.isOficial) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: const Color(0x1AD4A84F), borderRadius: BorderRadius.circular(4)),
                              child: const Text('Oficial', style: TextStyle(color: AppColors.dourado, fontSize: 9, fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ],
                      ),
                      Text(
                        item.relacao,
                        style: const TextStyle(color: Color(0xFF9B949D), fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatarData(item.criadoEm),
                  style: const TextStyle(color: Color(0xFF9B949D), fontSize: 11),
                ),
              ],
            ),
          ),

          // Foto anexada (se houver)
          if (item.fotoUrl != null && item.fotoUrl!.isNotEmpty) ...[
            Image.network(
              item.fotoUrl!,
              width: double.infinity,
              height: 200,
              fit: BoxFit.cover,
            ),
            const SizedBox(height: 12),
          ],

          // Conteúdo
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isOficial) ...[
                  Text(
                    item.titulo,
                    style: const TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                ],
                Text(
                  item.conteudo,
                  style: const TextStyle(color: AppColors.roxo, fontSize: 13, height: 1.5, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── ABA 3: MODERAÇÃO DE CONTRIBUIÇÕES ──
  Widget _buildAbaModeracao() {
    final pendentes = _contribuicoes.where((c) => !c.aprovado).toList();

    if (pendentes.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle_outline, size: 48, color: AppColors.verdeApoio),
              const SizedBox(height: 16),
              Text(
                'Tudo sob controle',
                style: TextStyle(color: AppColors.roxo, fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Não há nenhuma contribuição pendente de aprovação no momento.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF7A7280), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: pendentes.length,
      itemBuilder: (context, index) {
        final c = pendentes[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.autor,
                          style: const TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800),
                        ),
                        Text(
                          'Relação: ${c.relacao}',
                          style: const TextStyle(color: AppColors.dourado, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    _formatarData(c.createdAt),
                    style: const TextStyle(color: Color(0xFF9B949D), fontSize: 11),
                  ),
                ],
              ),
              const Divider(height: 20),
              if (c.fotoUrl != null && c.fotoUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    c.fotoUrl!,
                    width: double.infinity,
                    height: 150,
                    fit: BoxFit.cover,
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Text(
                c.conteudo,
                style: const TextStyle(color: AppColors.roxo, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _moderar(c, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rejeitar'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _moderar(c, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.verdeApoio,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprovar'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── ABA 4: CURADOR DE IA ──
  Widget _buildAbaCuradorIA() {
    return Column(
      children: [
        // Chat List
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            itemCount: _conversa.length,
            itemBuilder: (context, index) {
              final msg = _conversa[index];
              final isMe = msg['role'] == 'user';
              
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.roxo : Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(16),
                      topRight: const Radius.circular(16),
                      bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                      bottomRight: isMe ? Radius.zero : const Radius.circular(16),
                    ),
                    border: isMe ? null : Border.all(color: AppColors.borda),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.01),
                        blurRadius: 5,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  constraints: const BoxConstraints(maxWidth: 380),
                  child: Text(
                    msg['content']!,
                    style: TextStyle(
                      color: isMe ? Colors.white : AppColors.roxo,
                      fontSize: 13,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),

        if (_enviandoChat) ...[
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(color: AppColors.roxo, strokeWidth: 2),
            ),
          ),
        ],

        // Input Bar
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.borda)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.fundo,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: TextField(
                    controller: _chatController,
                    style: const TextStyle(fontSize: 14, color: AppColors.roxo),
                    onSubmitted: (_) => _enviarMensagemChat(),
                    decoration: const InputDecoration(
                      hintText: 'Pergunte algo sobre seu legado...',
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      border: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                backgroundColor: AppColors.roxo,
                child: IconButton(
                  icon: const Icon(Icons.send, color: Colors.white, size: 18),
                  onPressed: _enviarMensagemChat,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// Classe Auxiliar para Timeline unificada
class _ItemTimeline {
  const _ItemTimeline({
    required this.titulo,
    required this.autor,
    required this.relacao,
    required this.conteudo,
    this.fotoUrl,
    this.videoUrl,
    required this.criadoEm,
    required this.isOficial,
  });

  final String titulo;
  final String autor;
  final String relacao;
  final String conteudo;
  final String? fotoUrl;
  final String? videoUrl;
  final DateTime criadoEm;
  final bool isOficial;
}

// ── TELA PARA ENVIAR NOVA CONTRIBUIÇÃO ──
class _NovaContribuicaoScreen extends StatefulWidget {
  const _NovaContribuicaoScreen({required this.memorialId, super.key});

  final int memorialId;

  @override
  State<_NovaContribuicaoScreen> createState() => _NovaContribuicaoScreenState();
}

class _NovaContribuicaoScreenState extends State<_NovaContribuicaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _autorController = TextEditingController();
  final _relacaoController = TextEditingController();
  final _conteudoController = TextEditingController();
  final _picker = ImagePicker();

  Uint8List? _fotoBytes;
  bool _enviando = false;

  @override
  void dispose() {
    _autorController.dispose();
    _relacaoController.dispose();
    _conteudoController.dispose();
    super.dispose();
  }

  Future<void> _capturarFoto() async {
    try {
      final imagem = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (imagem == null) return;
      final bytes = await imagem.readAsBytes();
      setState(() {
        _fotoBytes = bytes;
      });
    } catch (_) {}
  }

  Future<void> _submeter() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _enviando = true);
    try {
      final contribuicao = Contribuicao(
        memorialId: widget.memorialId,
        autor: _autorController.text.trim(),
        relacao: _relacaoController.text.trim(),
        conteudo: _conteudoController.text.trim(),
        fotoBytes: _fotoBytes,
        aprovado: false, // Inicializa pendente
        createdAt: DateTime.now(),
      );

      await SupabaseService.instance.salvarContribuicao(contribuicao);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sua lembrança foi enviada para moderação e aparecerá após a aprovação do proprietário!'),
            duration: Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar contribuição: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Nova Homenagem', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _enviando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        const Text(
                          'Envie uma Recordação',
                          style: TextStyle(color: AppColors.roxo, fontSize: 24, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Compartilhe uma história, foto ou mensagem de carinho para fazer parte deste espaço de homenagem.',
                          style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
                        ),
                        const SizedBox(height: 24),

                        TextFormField(
                          controller: _autorController,
                          textCapitalization: TextCapitalization.words,
                          decoration: const InputDecoration(labelText: 'Seu Nome', hintText: 'Como deseja ser identificado'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe seu nome.' : null,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _relacaoController,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(labelText: 'Sua Relação', hintText: 'Ex: Amigo de infância, Primo'),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Informe sua relação.' : null,
                        ),
                        const SizedBox(height: 16),

                        TextFormField(
                          controller: _conteudoController,
                          maxLines: 5,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Sua História ou Mensagem',
                            hintText: 'Escreva com carinho aquela lembrança inesquecível...',
                            alignLabelWithHint: true,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Por favor, escreva sua história.' : null,
                        ),
                        const SizedBox(height: 20),

                        // Anexo de Foto
                        const Text('Anexar uma Imagem (Opcional):', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: _capturarFoto,
                          child: Container(
                            height: 150,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borda),
                            ),
                            child: _fotoBytes != null
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(12),
                                    child: Image.memory(_fotoBytes!, fit: BoxFit.cover, width: double.infinity),
                                  )
                                : const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.add_photo_alternate_outlined, color: AppColors.dourado, size: 40),
                                      SizedBox(height: 8),
                                      Text('Selecionar Foto da Galeria', style: TextStyle(color: AppColors.roxo, fontSize: 13, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        FilledButton(
                          onPressed: _submeter,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.roxo,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: const Text('Enviar para Moderação', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
