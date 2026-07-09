import 'package:flutter/material.dart';

import '../models/pessoa.dart';
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
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final pessoas = await PessoaRepository.listar();
      final grafo =
          await PessoaRelacionamentoService.instance.carregarGrafo();
      if (mounted) {
        setState(() {
          _pessoas = pessoas;
          _grafo = grafo;
          _carregando = false;
        });
      }
    } catch (e) {
      print('[GrafoFamilia] _carregar ERRO: $e');
      if (mounted) {
        setState(() {
          _carregando = false;
          _erro = 'Não foi possível carregar o Mapa da Família.';
        });
      }
    }
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
                : _erro != null
                    ? _buildErro()
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

  Widget _buildErro() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.cloud_off, size: 56, color: AppColors.dourado),
          const SizedBox(height: 16),
          Text(
            _erro!,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _carregar,
            icon: const Icon(Icons.refresh, size: 18),
            label: const Text('Tentar novamente'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
            ),
          ),
        ],
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
    // Agrupa por nível hierárquico
    final porNivel = <int, List<Map<String, dynamic>>>{};
    for (final r in _grafo) {
      final nivel = (r['nivel'] as num?)?.toInt() ?? 99;
      porNivel.putIfAbsent(nivel, () => []).add(r);
    }
    final niveisOrdenados = porNivel.keys.toList()..sort();
    final widgets = <Widget>[];

    final pessoasNoGrafo = _grafo
        .map<int>((r) => (r['pessoa_b_id'] as num).toInt())
        .toSet();
    final pessoasPorId = {for (final p in _pessoas) p.id: p};

    for (final nivel in niveisOrdenados) {
      final titulo = _rotuloNivel(nivel);
      widgets.add(Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8, top: 16),
        child: Text(
          titulo,
          style: const TextStyle(
            color: AppColors.dourado,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ));
      for (final r in porNivel[nivel]!) {
        final bId = (r['pessoa_b_id'] as num).toInt();
        final nome = r['nome'] as String? ?? 'Pessoa #$bId';
        final rotulo = r['relacao_b_para_a'] as String? ?? '';
        final pessoa = pessoasPorId[bId];
        widgets.add(_buildCardPessoa(bId, nome, rotulo, pessoa));
      }
    }

    // Pessoas sem relação
    final semRelacao = _pessoas
        .where((p) => p.id != null && !pessoasNoGrafo.contains(p.id))
        .toList();
    if (semRelacao.isNotEmpty) {
      widgets.add(const SizedBox(height: 16));
      widgets.add(const Padding(
        padding: EdgeInsets.only(left: 4, bottom: 8),
        child: Text(
          'Sem relação definida',
          style: TextStyle(
            color: AppColors.dourado,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
      ));
      for (final p in semRelacao) {
        widgets.add(_buildCardSemRelacao(p));
      }
    }

    return widgets;
  }

  String _rotuloNivel(int nivel) {
    switch (nivel) {
      case 1: return 'Geração +3';
      case 2: return 'Geração +2';
      case 3: return 'Geração +1 (Pais)';
      case 4: return 'Minha Geração';
      case 5: return 'Geração -1 (Filhos)';
      case 6: return 'Geração -2';
      default: return 'Nível $nivel';
    }
  }

  Widget _buildCardPessoa(int id, String nome, String rotulo, Pessoa? pessoa) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
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
            padding: const EdgeInsets.all(12),
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
                        nome,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (rotulo.isNotEmpty)
                        Text(
                          rotulo,
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: Color(0xFF9B949D), size: 18),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardSemRelacao(Pessoa p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
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
            padding: const EdgeInsets.all(12),
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
                  child: Text(
                    p.nome,
                    style: const TextStyle(
                      color: AppColors.roxo,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

}
