import 'package:flutter/material.dart';

import '../models/tipo_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';

/// Sprint L — Tela para adicionar uma relação pessoa-pessoa.
///
/// Fluxo (redesenhado para eliminar ambiguidade de perspectiva):
///   Etapa 1 — "Conectando {origem}": escolher a outra pessoa (com busca).
///   Etapa 2 — "Quem {destino} é para {origem}?": escolher o tipo de relação.
///   O sistema calcula automaticamente a direção e os rótulos inversos.
class AdicionarRelacionamentoScreen extends StatefulWidget {
  const AdicionarRelacionamentoScreen({
    required this.pessoaOrigemId,
    required this.pessoaOrigemNome,
    super.key,
  });

  final int pessoaOrigemId;
  final String pessoaOrigemNome;

  @override
  State<AdicionarRelacionamentoScreen> createState() =>
      _AdicionarRelacionamentoScreenState();
}

class _AdicionarRelacionamentoScreenState
    extends State<AdicionarRelacionamentoScreen> {
  List<TipoRelacionamento> _tipos = TIPOS_RELACIONAMENTO_INICIAIS;
  List<Map<String, dynamic>> _pessoas = [];
  List<Map<String, dynamic>> _pessoasFiltradas = [];
  bool _carregando = true;
  bool _salvando = false;

  /// true = etapa de escolher pessoa, false = etapa de escolher tipo
  bool _escolhendoPessoa = true;
  String _filtroBusca = '';

  String? _tipoId;
  int? _outraPessoaId;
  String? _outraPessoaNome;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final tipos = await PessoaRelacionamentoService.instance.listarTipos();

    // CORREÇÃO S.8.14 Item 9:
    // O pool de candidatos são os contatos do USUÁRIO LOGADO — não da
    // pessoa-alvo. Em seguida, excluímos quem já tem relação com a
    // pessoa-alvo em qualquer direção (A→B ou B→A, ambas existem porque
    // PessoaRelacionamentoService.criar() insere as duas linhas).
    final pessoasLogado = await PessoaRelacionamentoService.instance
        .listarContatos(pessoaId: PessoaRelacionamentoService.instance.usuarioId);

    final jaRelacionados = await PessoaRelacionamentoService.instance
        .listarContatos(pessoaId: widget.pessoaOrigemId);

    final idsJaRelacionados = <int>{
      widget.pessoaOrigemId, // nunca mostrar a própria pessoa-alvo
      for (final r in jaRelacionados) r['pessoa_b_id'] as int,
    };

    if (mounted) {
      setState(() {
        _tipos = tipos;
        _pessoas = pessoasLogado
            .where((m) =>
                !idsJaRelacionados.contains(m['pessoa_b_id'] as int))
            .toList();
        _aplicarFiltro();
        _carregando = false;
      });
    }
  }

  void _aplicarFiltro() {
    if (_filtroBusca.isEmpty) {
      _pessoasFiltradas = List.from(_pessoas);
    } else {
      final q = _filtroBusca.toLowerCase();
      _pessoasFiltradas = _pessoas
          .where((m) =>
              (m['nome'] as String? ?? '').toLowerCase().contains(q))
          .toList();
    }
    _pessoasFiltradas.sort((a, b) =>
        ((a['nome'] as String? ?? '').compareTo(b['nome'] as String? ?? '')));
  }

  void _selecionarPessoa(Map<String, dynamic> m) {
    setState(() {
      _outraPessoaId = m['pessoa_b_id'] as int;
      _outraPessoaNome = m['nome'] as String? ?? '';
      _escolhendoPessoa = false;
      _tipoId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Text(
          _escolhendoPessoa ? 'Conectando ${widget.pessoaOrigemNome}' : 'Qual a relação?',
          style: const TextStyle(
              color: AppColors.roxo, fontWeight: FontWeight.w800, fontSize: 16),
        ),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (!_escolhendoPessoa) {
              setState(() {
                _escolhendoPessoa = true;
                _outraPessoaId = null;
                _outraPessoaNome = null;
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(
                    child: CircularProgressIndicator(color: AppColors.roxo))
                : Padding(
                    padding: const EdgeInsets.all(20),
                    child: _escolhendoPessoa
                        ? _buildEtapaPessoa()
                        : _buildEtapaTipo(),
                  ),
          ),
        ),
      ),
    );
  }

  // ── ETAPA 1: ESCOLHER A PESSOA ──

  Widget _buildEtapaPessoa() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(),
        const SizedBox(height: 20),
        const Text(
          'Escolha uma pessoa',
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          decoration: InputDecoration(
            hintText: 'Buscar por nome...',
            prefixIcon:
                const Icon(Icons.search, color: Color(0xFF9B949D), size: 20),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
          ),
          onChanged: (v) => setState(() {
            _filtroBusca = v;
            _aplicarFiltro();
          }),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _pessoasFiltradas.isEmpty
              ? Center(
                  child: Text(
                    _filtroBusca.isEmpty
                        ? 'Você precisa cadastrar outra pessoa antes de criar uma relação.'
                        : 'Nenhuma pessoa encontrada.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 13,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _pessoasFiltradas.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (_, i) {
                    final m = _pessoasFiltradas[i];
                    final nome = m['nome'] as String? ?? '';
                    final label = m['relacao_b_para_a'] as String? ?? '';
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _selecionarPessoa(m),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.borda),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: const Color(0xFFE8E2D8),
                                child: Text(
                                  nome.isNotEmpty
                                      ? nome[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    color: AppColors.roxo,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      nome,
                                      style: const TextStyle(
                                        color: AppColors.roxo,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (label.isNotEmpty)
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          color: Color(0xFF7A7280),
                                          fontSize: 12,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right,
                                  color: Color(0xFF9B949D), size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── ETAPA 2: ESCOLHER O TIPO DE RELAÇÃO ──

  Widget _buildEtapaTipo() {
    // Agrupa tipos por categoria
    final agrupados = <String, List<TipoRelacionamento>>{};
    for (final t in _tipos) {
      agrupados.putIfAbsent(t.categoria, () => []).add(t);
    }
    // Ordem das categorias
    final ordem = ['familia', 'afinidade', 'conjugue', 'amizade', 'outro'];
    final rotulos = {
      'familia': 'Família',
      'afinidade': 'Afinidade',
      'conjugue': 'Conjugal',
      'amizade': 'Amizade',
      'outro': 'Outro',
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF9F6F0),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.dourado.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.swap_horiz,
                  color: AppColors.dourado, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: RichText(
                  text: TextSpan(
                    style: const TextStyle(fontSize: 14),
                    children: [
                      TextSpan(
                        text: 'Quem ',
                        style: TextStyle(
                          color: AppColors.roxo.withValues(alpha: 0.7),
                        ),
                      ),
                      TextSpan(
                        text: _outraPessoaNome ?? '...',
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      TextSpan(
                        text: ' é para ',
                        style: TextStyle(
                          color: AppColors.roxo.withValues(alpha: 0.7),
                        ),
                      ),
                      TextSpan(
                        text: widget.pessoaOrigemNome,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: '?'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              for (final cat in ordem)
                if (agrupados.containsKey(cat) && agrupados[cat]!.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6, top: 4),
                    child: Text(
                      rotulos[cat] ?? cat,
                      style: const TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (final t in agrupados[cat]!) ...[
                    _buildTipoTile(t),
                    const SizedBox(height: 6),
                  ],
                ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _salvando || _tipoId == null
                ? null
                : _salvar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: _salvando
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check, size: 18),
            label: const Text('Conectar',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
          ),
        ),
      ],
    );
  }

  Widget _buildTipoTile(TipoRelacionamento t) {
    final selecionado = _tipoId == t.id;
    return Material(
      color: selecionado ? const Color(0xFFF9F6F0) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => setState(() => _tipoId = t.id),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selecionado ? AppColors.dourado : AppColors.borda,
              width: selecionado ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selecionado
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selecionado
                    ? AppColors.dourado
                    : const Color(0xFF9B949D),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t.rotuloA,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (selecionado && !t.simetrico)
                Text(
                  '→ ${t.rotuloB}',
                  style: const TextStyle(
                    color: Color(0xFF7A7280),
                    fontSize: 12,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.dourado.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.diversity_3,
              color: AppColors.dourado, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Conectando ${widget.pessoaOrigemNome} à família',
              style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _salvar() async {
    if (_tipoId == null || _outraPessoaId == null) return;
    setState(() => _salvando = true);

    try {
      final t = _tipos.firstWhere((t) => t.id == _tipoId);

      // A relação é definida do ponto de vista da ORIGEM.
      // O tipo escolhido (ex: 'AVO' com rotuloA='Avô(ó)') significa
      // que a ORIGEM (pessoaA) tem esse papel em relação ao DESTINO.
      // Os rótulos são passados sem troca: relacaoA = o que A é para B,
      // relacaoB = o que B é para A. O método criar() já insere as
      // duas linhas (direta + inversa) automaticamente.
      final id = await PessoaRelacionamentoService.instance.criar(
        pessoaAId: widget.pessoaOrigemId,
        pessoaBId: _outraPessoaId!,
        tipo: _tipoId!,
        relacaoA: t.rotuloA,
        relacaoB: t.rotuloB,
      );

      if (id != null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      throw Exception('A relação não pôde ser criada (retorno nulo).');
    } catch (e) {
      print('[AdicionarRelacionamento] _salvar ERRO: $e');
      if (mounted) {
        setState(() => _salvando = false);
        String mensagem = 'Não foi possível criar a relação.';
        final msg = e.toString();
        if (msg.contains('unique') || msg.contains('duplicate')) {
          mensagem = 'Esta relação já existe entre as duas pessoas.';
        } else if (msg.contains('violates foreign key')) {
          mensagem = 'Pessoa não encontrada no banco de dados.';
        } else if (msg.contains('permission denied') ||
            msg.contains('policy')) {
          mensagem = 'Permissão negada. Contate o suporte.';
        } else if (msg.contains('retorno nulo')) {
          mensagem = 'Não foi possível criar a relação.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagem)),
        );
      }
    }
  }
}
