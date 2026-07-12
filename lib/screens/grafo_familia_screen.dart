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

  /// S.9.3.2 — pets dos quais o usuário logado é tutor (seção separada,
  /// nunca nas gerações humanas).
  List<Pessoa> _meusPets = const [];
  bool _carregando = true;
  String? _erro;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    final sw = Stopwatch()..start();
    print('[PERF] tela=MapaFamilia inicio=${DateTime.now().toIso8601String()}');
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      // S.9.3.1 (Item 9) — queries independentes paralelizadas.
      final resultados = await Future.wait<dynamic>([
        PessoaRepository.listar(),
        PessoaRelacionamentoService.instance.carregarGrafo(),
      ]);
      final pessoas = resultados[0] as List<Pessoa>;
      final grafo = resultados[1] as List<Map<String, dynamic>>;
      // S.9.3.2 — Meus Pets: pets relacionados ao usuário logado
      // (tutoria; um pet com dois tutores aparece uma vez em cada mapa,
      // sem duplicar o registro em pessoas).
      final rels = await PessoaRelacionamentoService.instance
          .listarContatos(pessoaId: PessoaRepository.usuarioId);
      final idsRelacionados = {
        for (final r in rels) r['pessoa_b_id'] as int,
      };
      final meusPets = pessoas
          .where((p) => p.isPet && idsRelacionados.contains(p.id))
          .toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));
      if (mounted) {
        setState(() {
          _pessoas = pessoas;
          _grafo = grafo;
          _meusPets = meusPets;
          _carregando = false;
        });
      }
      print('[PERF] tela=MapaFamilia pronta_em_ms=${sw.elapsedMilliseconds}');
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
                              children: [
                                ..._buildTree(),
                                ..._buildMeusPets(),
                              ],
                            ),
                          ),
          ),
        ),
      ),
    );
  }

  /// S.9.3.2 — "Meu Pet"/"Meus Pets": abaixo da árvore, fora das gerações.
  List<Widget> _buildMeusPets() {
    if (_meusPets.isEmpty) return const [];
    return [
      const SizedBox(height: 28),
      Row(
        children: [
          const Icon(Icons.pets, color: AppColors.dourado, size: 20),
          const SizedBox(width: 8),
          Text(
            _meusPets.length == 1 ? 'Meu Pet' : 'Meus Pets',
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      ..._meusPets.map((pet) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => PessoaDetalheScreen(
                      pessoa: pet,
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
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: const Color(0xFFF0EAF5),
                        backgroundImage: pet.fotoBytes != null
                            ? MemoryImage(pet.fotoBytes!)
                            : (pet.fotoUrl != null
                                ? NetworkImage(pet.fotoUrl!) as ImageProvider
                                : null),
                        child: (pet.fotoBytes == null && pet.fotoUrl == null)
                            ? const Icon(Icons.pets,
                                size: 20, color: AppColors.dourado)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              pet.nome,
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (pet.especieRacaLabel != null)
                              Text(
                                pet.especieRacaLabel!,
                                style: const TextStyle(
                                  color: Color(0xFF7A7280),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),
          )),
    ];
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
    // Agrupa por nível hierárquico.
    // O grafo já vem filtrado: sem o próprio usuário, sem AMIGO/CONHECIDO/OUTRO.
    final porNivel = <int, List<Map<String, dynamic>>>{};
    for (final r in _grafo) {
      final nivel = (r['nivel'] as num?)?.toInt() ?? 99;
      porNivel.putIfAbsent(nivel, () => []).add(r);
    }
    final niveisOrdenados = porNivel.keys.toList()..sort();
    final widgets = <Widget>[];

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

    return widgets;
  }

  String _rotuloNivel(int nivel) {
    switch (nivel) {
      case 1: return 'Geração +3';
      case 2: return 'Geração +2';
      case 3: return 'Geração +1 (Pais / Padrastos)';
      case 4: return 'Minha Geração';
      case 5: return 'Geração -1 (Filhos / Enteados)';
      case 6: return 'Geração -2';
      default: return 'Outros vínculos';
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

}
