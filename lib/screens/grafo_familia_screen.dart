import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../models/memorial.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../theme/app_theme.dart';
import '../services/supabase_service.dart';
import '../widgets/pessoa_avatar.dart';
import 'memorial_detalhe_screen.dart';
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

  /// S.9.4d — pessoa_id → memorial_id (fita preta no mapa; toque abre
  /// o memorial).
  Map<int, int> _memorialPorPessoa = const {};

  /// S.9.4c — memoriais que têm parentesco mas cuja pessoa NÃO está na
  /// árvore de relacionamentos (ex.: Douglas, "Irmão"). Entram no mapa
  /// automaticamente, posicionados pela geração do parentesco.
  List<Memorial> _memoriaisOrfaos = const [];
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
        SupabaseService.instance.listarMemoriais(),
        SupabaseService.instance.listarMemorialIdsDePets(),
      ]);
      final pessoas = resultados[0] as List<Pessoa>;
      final grafo = resultados[1] as List<Map<String, dynamic>>;
      final memoriais = resultados[2] as List<Memorial>;
      final petMemorialIds = resultados[3] as Set<int>;
      // S.9.3.2 — Meus Pets: pets relacionados ao usuário logado
      // (tutoria; um pet com dois tutores aparece uma vez em cada mapa,
      // sem duplicar o registro em pessoas).
      final rels = await PessoaRelacionamentoService.instance
          .listarContatos(pessoaId: PessoaRepository.usuarioId);
      final idsRelacionados = {
        for (final r in rels) r['pessoa_b_id'] as int,
      };
      // S.9.4c — pet falecido com memorial vive no memorial (regra igual
      // à da lista Pets).
      final memorialPorPessoa = await PessoaRepository.mapaPessoaMemorial();
      final comMemorial = memorialPorPessoa.keys.toSet();
      final meusPets = pessoas
          .where((p) =>
              p.isPet &&
              idsRelacionados.contains(p.id) &&
              !(p.falecido && comMemorial.contains(p.id)))
          .toList()
        ..sort((a, b) => a.nome.compareTo(b.nome));

      // S.9.4c — memoriais órfãos: têm parentesco mas a pessoa não está
      // na árvore. Removemos os que já aparecem na árvore (por memorial_id
      // ou por nome) e os de pets, para não duplicar.
      final idsNaArvore = grafo
          .map<int>((r) => (r['pessoa_b_id'] as num).toInt())
          .toSet();
      final memoriaisNaArvore = <int>{
        for (final bId in idsNaArvore)
          if (memorialPorPessoa[bId] != null) memorialPorPessoa[bId]!,
      };
      final nomesNaArvore = grafo
          .map((r) => ((r['nome'] as String?) ?? '').toLowerCase().trim())
          .toSet();
      final orfaos = memoriais
          .where((m) =>
              m.id != null &&
              !petMemorialIds.contains(m.id) &&
              !memoriaisNaArvore.contains(m.id) &&
              !nomesNaArvore.contains(m.nome.toLowerCase().trim()))
          .toList();

      if (mounted) {
        setState(() {
          _pessoas = pessoas;
          _grafo = grafo;
          _meusPets = meusPets;
          _memorialPorPessoa = memorialPorPessoa;
          _memoriaisOrfaos = orfaos;
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
                    : (_grafo.isEmpty && _memoriaisOrfaos.isEmpty)
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
                      PessoaAvatar(
                        radius: 20,
                        fotoUrl: pet.fotoUrl,
                        fotoBytes: pet.fotoBytes,
                        falecido: pet.falecido,
                        isPet: true,
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

  /// S.9.4d — abre o memorial da pessoa (fita preta).
  Future<void> _abrirMemorialDe(Pessoa pessoa) async {
    final memorialId = _memorialPorPessoa[pessoa.id];
    if (memorialId == null) return;
    final memoriais = await SupabaseService.instance.listarMemoriais();
    final m = memoriais.where((x) => x.id == memorialId).firstOrNull;
    if (m == null || !mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MemorialDetalheScreen(memorial: m)),
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
    // Agrupa por nível hierárquico.
    // O grafo já vem filtrado: sem o próprio usuário, sem AMIGO/CONHECIDO/OUTRO.
    final porNivel = <int, List<Map<String, dynamic>>>{};
    for (final r in _grafo) {
      final nivel = (r['nivel'] as num?)?.toInt() ?? 99;
      porNivel.putIfAbsent(nivel, () => []).add(r);
    }

    // S.9.4c — memoriais órfãos agrupados pela geração do parentesco.
    final orfaosPorNivel = <int, List<Memorial>>{};
    for (final m in _memoriaisOrfaos) {
      final nivel = _nivelPorParentesco(m.parentesco);
      orfaosPorNivel.putIfAbsent(nivel, () => []).add(m);
    }

    final niveisOrdenados =
        <int>{...porNivel.keys, ...orfaosPorNivel.keys}.toList()..sort();
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
      for (final r in porNivel[nivel] ?? const []) {
        final bId = (r['pessoa_b_id'] as num).toInt();
        final nome = r['nome'] as String? ?? 'Pessoa #$bId';
        final rotulo = r['relacao_b_para_a'] as String? ?? '';
        final pessoa = pessoasPorId[bId];
        widgets.add(_buildCardPessoa(bId, nome, rotulo, pessoa));
      }
      for (final m in orfaosPorNivel[nivel] ?? const []) {
        widgets.add(_buildCardMemorialOrfao(m));
      }
    }

    return widgets;
  }

  /// S.9.4c — classifica o parentesco (texto livre) na geração do mapa.
  /// Casos não reconhecidos caem em "Outros vínculos" (99), garantindo
  /// que o memorial NUNCA some do mapa.
  int _nivelPorParentesco(String parentesco) {
    final p = parentesco.toLowerCase().trim();
    if (p.contains('bisav')) return 1;
    if (p.contains('bisneto') || p.contains('bisneta')) return 6;
    if (p.contains('av')) return 2; // avô / avó / avos
    if (p.contains('pai') ||
        p.contains('mãe') ||
        p.contains('mae') ||
        p.contains('padrast') ||
        p.contains('madrast') ||
        p.contains('sogr')) return 3;
    if (p.contains('irm') ||
        p.contains('espos') ||
        p.contains('marido') ||
        p.contains('mulher') ||
        p.contains('cônjuge') ||
        p.contains('conjuge') ||
        p.contains('compan') ||
        p.contains('prim') ||
        p.contains('cunhad')) return 4;
    if (p.contains('filh') ||
        p.contains('entead') ||
        p.contains('genro') ||
        p.contains('nora') ||
        p.contains('sobrinh')) return 5;
    if (p.contains('neto') || p.contains('neta')) return 6;
    return 99;
  }

  /// S.9.4c — card de um memorial órfão no mapa: fita preta, rótulo do
  /// parentesco e toque abre o memorial diretamente.
  Widget _buildCardMemorialOrfao(Memorial m) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MemorialDetalheScreen(memorial: m),
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
                PessoaAvatar(
                  radius: 16,
                  fotoUrl: m.fotoUrl,
                  falecido: true,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.nome,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (m.parentesco.trim().isNotEmpty)
                        Text(
                          m.parentesco,
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
              // S.9.4d — falecido com memorial: toque abre o MEMORIAL.
              : (_memorialPorPessoa.containsKey(pessoa.id) && pessoa.falecido)
                  ? () => _abrirMemorialDe(pessoa)
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
                PessoaAvatar(
                  radius: 16,
                  fotoUrl: pessoa?.fotoUrl,
                  fotoBytes: pessoa?.fotoBytes,
                  falecido: pessoa?.falecido ?? false,
                  isPet: pessoa?.isPet ?? false,
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
