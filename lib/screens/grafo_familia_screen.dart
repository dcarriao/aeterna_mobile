import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../models/pessoa_relacionamento.dart';
import '../models/tipo_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';
import 'pessoa_detalhe_screen.dart';

/// Sprint L — Mapa da Família (esqueleto).
///
/// Mostra a estrutura familiar do usuário como uma árvore simples
/// (Darlan → [Alice (esposa), Bia (filha), Douglas (irmão), José (pai)]
/// → netos, primos, etc.).
///
/// É a base para futuras evoluções (grafo interativo, navegação
/// por fase da vida, etc.).
class GrafoFamiliaScreen extends StatefulWidget {
  const GrafoFamiliaScreen({super.key});

  @override
  State<GrafoFamiliaScreen> createState() => _GrafoFamiliaScreenState();
}

class _GrafoFamiliaScreenState extends State<GrafoFamiliaScreen> {
  List<Pessoa> _pessoas = const [];
  List<Map<String, dynamic>> _grafo = const [];
  Map<int, String> _nomePorId = const {};
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final pessoas = await PessoaRepository.listar();
    final grafo = await PessoaRelacionamentoService.instance.carregarGrafo();
    if (mounted) {
      setState(() {
        _pessoas = pessoas;
        _grafo = grafo;
        _nomePorId = {for (final p in pessoas) p.id: p.nome};
        _carregando = false;
      });
    }
  }

  /// Agrupa as relações POR PESSOA central, e retorna a árvore.
  /// Critério: cada pessoa é "raiz" se não tem pai/mãe (heurística:
  /// aparece como `filho(a)` em alguma relação). Pessoas sem
  /// relações ficam no nível "Outros".
  Map<int, List<Map<String, dynamic>>> _agruparPorPessoa() {
    final porPessoa = <int, List<Map<String, dynamic>>>{};
    for (final r in _grafo) {
      // `pessoa_mais_antiga_id` é sempre < `pessoa_mais_nova_id` (SQL).
      final a = (r['pessoa_mais_antiga_id'] as num).toInt();
      final b = (r['pessoa_mais_nova_id'] as num).toInt();
      porPessoa.putIfAbsent(a, () => []).add({
        'relacionamento_id': r['relacionamento_id'],
        'outra_id': b,
        'rotulo_a': r['rotulo_a'],
        'rotulo_b': r['rotulo_b'],
        'nome_b': r['nome_b'],
        'tipo': r['tipo'],
      });
      porPessoa.putIfAbsent(b, () => []).add({
        'relacionamento_id': r['relacionamento_id'],
        'outra_id': a,
        'rotulo_a': r['rotulo_b'],
        'rotulo_b': r['rotulo_a'],
        'nome_b': r['nome_a'],
        'tipo': r['tipo'],
      });
    }
    return porPessoa;
  }

  /// Retorna a lista de pessoas que são "filho(a)" em alguma
  /// relação (não devem ser raízes).
  Set<int> _idsQueSaoFilhos() {
    final filhos = <int>{};
    for (final r in _grafo) {
      final tipo = r['tipo'] as String? ?? '';
      if (tipo == 'FILHO' || tipo == 'FILHA' || tipo == 'NETO' ||
          tipo == 'SOBRINHO' || tipo == 'BISNETO' || tipo == 'AFILHADO') {
        // pessoa_mais_nova é o filho
        final filho = (r['pessoa_mais_nova_id'] as num).toInt();
        filhos.add(filho);
      }
    }
    return filhos;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Mapa da Família',
            style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : _grafo.isEmpty
                    ? _vazio()
                    : RefreshIndicator(
                        onRefresh: _carregar,
                        child: ListView(
                          padding:
                              const EdgeInsets.fromLTRB(20, 16, 20, 40),
                          children: _buildTree(),
                        ),
                      ),
          ),
        ),
      ),
    );
  }

  Widget _vazio() {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.diversity_3, size: 56, color: AppColors.dourado),
          SizedBox(height: 16),
          Text(
            'O Mapa da Família começa com a primeira relação.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Abra qualquer pessoa e conecte-a a quem vive junto com ela. '
            'O grafo familiar vai crescer organicamente a partir daí.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTree() {
    final grupos = _agruparPorPessoa();
    final filhos = _idsQueSaoFilhos();
    final todasIds = grupos.keys.toList();
    final pessoasPorId = {for (final p in _pessoas) p.id: p};

    // Raízes = todas as pessoas que NÃO são filhos.
    final raizes = todasIds.where((id) => !filhos.contains(id)).toList();

    final widgets = <Widget>[];

    if (raizes.length == 1) {
      // Caso comum: 1 raiz (o próprio usuário ou a pessoa mais
      // antiga do grafo).
      widgets.add(_buildNo(raizes.first, grupos, pessoasPorId, 0));
    } else {
      for (final id in raizes) {
        widgets.add(_buildNo(id, grupos, pessoasPorId, 0));
      }
    }

    // Pessoas sem nenhuma relação (não aparecem nos grupos).
    final nosGrupos = todasIds.toSet();
    final semRelacao = _pessoas
        .where((p) => p.id != null && !nosGrupos.contains(p.id))
        .toList();
    if (semRelacao.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'Outros',
          style: TextStyle(
            color: AppColors.dourado,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ));
      for (final p in semRelacao) {
        widgets.add(_buildNoSemRelacao(p));
      }
    }

    return widgets;
  }

  Widget _buildNo(
    int pessoaId,
    Map<int, List<Map<String, dynamic>>> grupos,
    Map<int, Pessoa> pessoasPorId,
    int profundidade,
  ) {
    final pessoa = pessoasPorId[pessoaId];
    final nome = pessoa?.nome ??
        (_nomePorId[pessoaId] ?? 'Pessoa #$pessoaId');
    final parentesco = pessoa?.parentesco ?? '';
    final relacionados = grupos[pessoaId] ?? const <Map<String, dynamic>>[];

    return Padding(
      padding: EdgeInsets.only(left: profundidade * 16.0, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: pessoa == null
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PessoaDetalheScreen(
                            pessoa: pessoa,
                            onAbrirMemoria: (_) {},
                            titulosMemorias: const {},
                          ),
                        ),
                      ),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borda),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 16,
                      backgroundColor: Color(0xFFF0EAF5),
                      child: Icon(Icons.person,
                          size: 16, color: AppColors.roxo),
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
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (parentesco.isNotEmpty)
                            Text(
                              parentesco,
                              style: const TextStyle(
                                color: Color(0xFF7A7280),
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          for (final r in relacionados)
            _buildRelacionamento(r, pessoaId, grupos, pessoasPorId, profundidade + 1),
        ],
      ),
    );
  }

  Widget _buildRelacionamento(
    Map<String, dynamic> rel,
    int pessoaOrigemId,
    Map<int, List<Map<String, dynamic>>> grupos,
    Map<int, Pessoa> pessoasPorId,
    int profundidade,
  ) {
    final rotulo = rel['rotulo_a'] as String? ?? 'Conhecido(a)';
    final outraId = (rel['outra_id'] as num).toInt();
    final tipo = rel['tipo'] as String? ?? 'OUTRO';
    final tipoObj = _tipos.firstWhere(
      (t) => t.id == tipo,
      orElse: () => const TipoRelacionamento(
        id: 'OUTRO',
        rotuloA: 'Conhecido(a)',
        rotuloB: 'Conhecido(a)',
        categoria: 'outro',
      ),
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 20.0,
        top: 2,
        bottom: 2,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.subdirectory_arrow_right,
                  size: 16, color: AppColors.dourado),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x1AD4A84F),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  rotulo,
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          _buildNo(outraId, grupos, pessoasPorId, profundidade),
        ],
      ),
    );
  }

  Widget _buildNoSemRelacao(Pessoa p) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => PessoaDetalheScreen(
              pessoa: p,
              onAbrirMemoria: (_) {},
              titulosMemorias: const {},
            ),
          ),
        ),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borda),
          ),
          child: Row(
            children: [
              const CircleAvatar(
                radius: 16,
                backgroundColor: Color(0xFFF0EAF5),
                child: Icon(Icons.person, size: 16, color: AppColors.roxo),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.nome,
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (p.parentesco.isNotEmpty)
                      Text(
                        p.parentesco,
                        style: const TextStyle(
                          color: Color(0xFF7A7280),
                          fontSize: 11,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Lista de tipos client-side para mapear tipo -> categoria.
  static final _tipos = TIPOS_RELACIONAMENTO_INICIAIS;
}
