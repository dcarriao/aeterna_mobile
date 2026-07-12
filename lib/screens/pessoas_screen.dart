import 'package:flutter/material.dart';

import '../models/pessoa.dart';
import '../models/pessoa_linha_tempo.dart';
import '../models/pessoa_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../services/pessoa_timeline_service.dart';
import '../theme/app_theme.dart';
import 'convites_screen.dart';
import 'grafo_familia_screen.dart';
import 'nova_pessoa_screen.dart';
import 'pessoa_detalhe_screen.dart';
import 'pets_screen.dart'; // S.9.3

class PessoasScreen extends StatefulWidget {
  const PessoasScreen({
    required this.onAbrirMemoria,
    this.titulosMemorias = const {},
    super.key,
  });

  final void Function(int memoriaId) onAbrirMemoria;
  final Map<int, String> titulosMemorias;

  @override
  State<PessoasScreen> createState() => _PessoasScreenState();
}

class _PessoasScreenState extends State<PessoasScreen> {
  List<Pessoa> _pessoas = [];
  Map<int, List<int>> _vinculos = {};
  bool _carregando = true;
  List<PessoaSugerida> _sugestoes = const [];
  Map<int, String> _parentescoMap = {};
  List<PessoaVivaResumo> _pessoasVivas = const [];
  bool _carregandoSugestoes = true;

  @override
  void initState() {
    super.initState();
    print('[PessoasScreen] initState -> carregando');
    _carregar();
    _carregarSugestoes();
  }

  Future<void> _carregarSugestoes() async {
    final sug = await PessoaTimelineService.instance.obterSugestoes();
    final vivas = await PessoaTimelineService.instance.obterPessoasRecentes(limite: 10);
    if (mounted) {
      setState(() {
        _sugestoes = sug;
        _pessoasVivas = vivas;
        _carregandoSugestoes = false;
      });
    }
  }

  Future<void> _cadastrarSugestao(PessoaSugerida s) async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => NovaPessoaScreen(
          pessoa: Pessoa(
            id: DateTime.now().millisecondsSinceEpoch,
            nome: s.nome,
            parentesco: 'Outro',
          ),
        ),
      ),
    );
    if (mounted) _carregarSugestoes();
  }

  Future<void> _carregar() async {
    final sw = Stopwatch()..start();
    print('[PERF] tela=Pessoas inicio=${DateTime.now().toIso8601String()}');
    try {
      // S.9.3.1 (Item 9) — as três queries são independentes entre si;
      // antes rodavam em sequência (soma das latências). Future.wait
      // paraleliza sem alterar nenhuma regra funcional.
      final resultados = await Future.wait([
        PessoaRepository.listar(),
        PessoaRepository.listarVinculos(),
        PessoaRelacionamentoService.instance
            .listarRelacionamentos(PessoaRepository.usuarioId),
        PessoaRepository.listarPessoasComMemorial(),
      ]);
      final pessoas = resultados[0] as List<Pessoa>;
      final vinculos = resultados[1] as Map<int, List<int>>;
      final rels = resultados[2] as List<OutraPessoaNaFamilia>;
      final comMemorial = resultados[3] as Set<int>;
      final parentescoMap = <int, String>{};
      for (final r in rels) {
        parentescoMap[r.outraPessoaId] = r.rotuloDaOutraParaMim;
      }
      print(
          '[PessoasScreen] _carregar() recebeu ${pessoas.length} pessoas. mounted=$mounted');
      if (mounted) {
        setState(() {
          // S.9.3: exclui o próprio usuário E pets (pets têm seção própria)
          // S.9.3.2 — FALECIDO com memorial vive no memorial, não na
          // lista. (Correção: memorial_pessoas também tem colaboradores
          // vivos — o filtro anterior escondia gente viva da lista.)
          _pessoas = pessoas
              .where((p) =>
                  p.id != PessoaRepository.usuarioId &&
                  !p.isPet &&
                  !(p.falecido && comMemorial.contains(p.id)))
              .toList();
          _vinculos = vinculos;
          _parentescoMap = parentescoMap;
          _carregando = false;
        });
      }
      print('[PERF] tela=Pessoas pronta_em_ms=${sw.elapsedMilliseconds}');
    } catch (_) {
      if (mounted) setState(() => _carregando = false);
    }
  }

  Future<void> _adicionarPessoa() async {
    print('[PessoasScreen] _adicionarPessoa -> abrindo NovaPessoaScreen');
    final criada = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const NovaPessoaScreen()),
    );
    print(
        '[PessoasScreen] _adicionarPessoa -> retornou criada=$criada mounted=$mounted');
    if (criada == true && mounted) _carregar();
  }

  void _abrirDetalhe(Pessoa pessoa) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PessoaDetalheScreen(
          pessoa: pessoa,
          onAbrirMemoria: widget.onAbrirMemoria,
          titulosMemorias: widget.titulosMemorias,
        ),
      ),
    ).then((_) => _carregar());
  }

  int _contarMemorias(int id) {
    return _vinculos.entries.where((e) => e.value.contains(id)).length;
  }

  void _abrirConvites() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => const ConvitesScreen()),
    ).then((_) => _carregar());
  }

  void _abrirGrafoFamilia() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const GrafoFamiliaScreen()),
    );
  }

  // S.9.3
  void _abrirPets() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PetsScreen(
          onAbrirMemoria: widget.onAbrirMemoria,
          titulosMemorias: widget.titulosMemorias,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: Image.asset('assets/logo.png', height: 44),
        centerTitle: false,
        backgroundColor: AppColors.fundo,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Mapa da Família',
            onPressed: _abrirGrafoFamilia,
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.diversity_3,
                  color: AppColors.dourado, size: 20),
            ),
          ),
          // S.9.3 — Acesso à seção de Pets
          IconButton(
            tooltip: 'Meus Pets',
            onPressed: _abrirPets,
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.pets,
                  color: AppColors.dourado, size: 20),
            ),
          ),
          IconButton(
            tooltip: 'Convites Familiares',
            onPressed: _abrirConvites,
            icon: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFFF0EAF5),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.mail_outline,
                  color: AppColors.roxo, size: 20),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      bottomNavigationBar: _pessoas.isEmpty || _carregando
          ? null
          : Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.borda)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: FilledButton.icon(
                    onPressed: _adicionarPessoa,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.roxo,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: const Icon(Icons.person_add_outlined, size: 18),
                    label: const Text('Adicionar pessoa'),
                  ),
                ),
              ),
            ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _pessoas.isEmpty && _sugestoes.isEmpty
                    ? _EstadoVazio(onAdicionar: _adicionarPessoa)
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        children: [
                          // ── HEADER ──
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12, left: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Pessoas importantes',
                                  style: TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 26,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: 6),
                                Text(
                                  'As pessoas que fazem parte da sua história.',
                                  style: TextStyle(
                                    color: AppColors.textoSuave,
                                    fontSize: 15,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // ── SPRINT H — DESCOBERTA AUTOMÁTICA ──
                          if (_sugestoes.isNotEmpty)
                            ..._sugestoes.map((s) => _buildCardSugestao(s)),
                          if (_sugestoes.isNotEmpty) const SizedBox(height: 16),

                          // ── LISTA DE PESSOAS CADASTRADAS ──
                          if (_pessoas.isNotEmpty) ...[
                            for (var i = 0; i < _pessoas.length; i++) ...[
                              if (i > 0) const SizedBox(height: 12),
                              Builder(
                                builder: (_) {
                                  final pessoa = _pessoas[i];
                                  return _PessoaCard(
                                    pessoa: pessoa,
                                    relacaoLabel: _parentescoMap[pessoa.id] ?? pessoa.parentesco,
                                    totalMemorias: _contarMemorias(pessoa.id),
                                    onTap: () => _abrirDetalhe(pessoa),
                                  );
                                },
                              ),
                            ],
                          ],
                        ],
                      ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardSugestao(PessoaSugerida s) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: AppColors.dourado, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Talvez você queira cadastrar ${s.nome}',
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.ocorrencias == 1
                      ? 'Aparece em 1 história sua.'
                      : 'Aparece em ${s.ocorrencias} histórias suas.',
                  style: const TextStyle(
                    color: Color(0xFF7A7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => _cadastrarSugestao(s),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.dourado,
              side: const BorderSide(color: AppColors.dourado, width: 1.2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.person_add_alt_1, size: 14),
            label: const Text('Cadastrar', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _PessoaCard extends StatelessWidget {
  const _PessoaCard({
    required this.pessoa,
    required this.relacaoLabel,
    required this.totalMemorias,
    required this.onTap,
  });

  final Pessoa pessoa;
  final String relacaoLabel;
  final int totalMemorias;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEDE8DC)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x062B1747),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFFF0EAF5),
                  backgroundImage: pessoa.fotoBytes != null
                      ? MemoryImage(pessoa.fotoBytes!)
                      : null,
                  child: pessoa.fotoBytes == null
                      ? const Icon(Icons.person, color: AppColors.roxo, size: 26)
                      : null,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pessoa.nome,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _ParentescoChip(parentesco: relacaoLabel),
                          const SizedBox(width: 10),
                          Icon(Icons.auto_stories_outlined,
                              size: 13, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          Text(
                            '$totalMemorias ${totalMemorias == 1 ? 'memória' : 'memórias'}',
                            style: const TextStyle(
                              color: Color(0xFF817987),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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
    );
  }
}

class _ParentescoChip extends StatelessWidget {
  const _ParentescoChip({required this.parentesco});
  final String parentesco;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x26D4A84F),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        parentesco,
        style: const TextStyle(
          color: AppColors.dourado,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onAdicionar});

  final VoidCallback onAdicionar;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0x26D4A84F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.people_outline,
                size: 32, color: AppColors.dourado),
          ),
          const SizedBox(height: 20),
          const Text(
            'As histórias ficam mais ricas quando sabemos quem fez parte delas.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.roxo,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Cadastre familiares e pessoas importantes para conectar '
            'memórias e preservar relações.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF746D78), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdicionar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.person_add_outlined, size: 18),
            label: const Text('Adicionar primeira pessoa'),
          ),
        ],
      ),
    );
  }
}
