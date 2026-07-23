import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../models/memorial.dart';
import '../models/pessoa.dart';
import '../models/pessoa_linha_tempo.dart';
import '../models/pessoa_relacionamento.dart';
import '../models/tipo_relacionamento.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../services/pessoa_timeline_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';
import '../widgets/pessoa_avatar.dart';
import 'adicionar_relacionamento_screen.dart';
import 'memorial_detalhe_screen.dart';
import 'nova_memoria_screen.dart';
import 'nova_pessoa_screen.dart';
import 'nova_pet_screen.dart';
import 'novo_memorial_screen.dart';

/// Sprint H — Pessoa VIVA.
/// Cada pessoa cadastrada ganha uma "Linha do Tempo" construída
/// automaticamente a partir de memórias/fotos/vídeos/contribuições em
/// que aparece. As estatísticas são computadas em uma única RPC
/// (`pessoa_estatisticas(pessoa_id)`), e a timeline também é uma única
/// query (`pessoa_linha_tempo`).
class PessoaDetalheScreen extends StatefulWidget {
  const PessoaDetalheScreen({
    required this.pessoa,
    required this.onAbrirMemoria,
    this.titulosMemorias = const {},
    super.key,
  });

  final Pessoa pessoa;
  final void Function(int memoriaId) onAbrirMemoria;
  final Map<int, String> titulosMemorias;

  @override
  State<PessoaDetalheScreen> createState() => _PessoaDetalheScreenState();
}

class _PessoaDetalheScreenState extends State<PessoaDetalheScreen> {
  Pessoa? _pessoa;
  List<int> _memoriasVinculadas = [];
  bool _carregando = true;

  // Sprint H — agregações
  PessoaEstatisticas _stats = const PessoaEstatisticas(
    totalMemorias: 0, totalFotos: 0, totalVideos: 0, totalContribuicoes: 0);
  List<PessoaTimelineEvento> _eventos = const [];
  MemorialResumo? _memorialVinculado;

  // Sprint L — Família (grafo pessoa-pessoa)
  List<OutraPessoaNaFamilia> _familia = const [];

  /// S.9.3.2 — rótulo da relação do usuário logado com esta pessoa.
  String? _minhaRelacao;
  bool _carregandoFamilia = true;
  bool _carregandoEventos = true;

  @override
  void initState() {
    super.initState();
    _pessoa = widget.pessoa;
    _carregar();
    _carregarAgregacoes();
  }

  Future<void> _carregar() async {
    try {
      // Duas queries diretas e filtradas em paralelo (antes: listar() todas
      // as pessoas + listarVinculos() toda a tabela de permissões, em série).
      final results = await Future.wait([
        PessoaRepository.obterPorId(widget.pessoa.id),
        PessoaRepository.listarMemoriasVinculadas(widget.pessoa.id),
      ]);
      final atualizada = (results[0] as Pessoa?) ?? widget.pessoa;
      final ids = results[1] as List<int>;
      if (mounted) {
        setState(() {
          _pessoa = atualizada;
          _memoriasVinculadas = ids;
          _carregando = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _carregando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erro ao carregar dados.')),
        );
      }
    }
  }

  Future<void> _carregarAgregacoes() async {
    final sw = Stopwatch()..start();
    print('[PERF] tela=PerfilPessoa inicio=${DateTime.now().toIso8601String()} pessoa_id=${widget.pessoa.id}');
    // S.9.3.1 (Item 9) — 4 queries independentes que rodavam em sequência;
    // paralelizadas sem alterar regra funcional.
    // S.9.4b — humano: patrimônio/linha do tempo = o que ELE publicou;
    // pet: aparições (não publica). Pendente => vazio naturalmente.
    final ehPetCarga = widget.pessoa.isPet;
    final resultados = await Future.wait([
      ehPetCarga
          ? PessoaTimelineService.instance.obterEstatisticas(widget.pessoa.id)
          : PessoaTimelineService.instance
              .obterEstatisticasPublicadas(widget.pessoa.id),
      ehPetCarga
          ? PessoaTimelineService.instance.obterLinhaDoTempo(widget.pessoa.id)
          : PessoaTimelineService.instance
              .obterLinhaDoTempoPublicada(widget.pessoa.id),
      PessoaTimelineService.instance.obterMemorialDaPessoa(widget.pessoa.id),
      PessoaRelacionamentoService.instance
          .listarRelacionamentos(widget.pessoa.id),
      // S.9.3.2 — minha relação com esta pessoa (badge sob o nome)
      PessoaRepository.listarRelacionados(PessoaRepository.usuarioId),
    ]);
    final stats = resultados[0] as PessoaEstatisticas;
    final eventos = resultados[1] as List<PessoaTimelineEvento>;
    final memorial = resultados[2] as MemorialResumo?;
    final familia = resultados[3] as List<OutraPessoaNaFamilia>;
    final minhasRelacoes = resultados[4] as Map<int, String>;
    _minhaRelacao = minhasRelacoes[widget.pessoa.id];
    print('[PERF] tela=PerfilPessoa pronta_em_ms=${sw.elapsedMilliseconds}');
    if (mounted) {
      setState(() {
        _stats = stats;
        _eventos = eventos;
        _memorialVinculado = memorial;
        _familia = familia;
        _carregandoEventos = false;
        _carregandoFamilia = false;
      });
    }
  }

  Future<void> _editar() async {
    // S.9.3.1 — Pet edita em NovaPetScreen (campos de pet); humano em
    // NovaPessoaScreen. Antes, o pet era editado no formulário humano
    // (sobrenome/e-mail/telefone) e o UPDATE regravava tipo='humano'.
    final pessoa = _pessoa ?? widget.pessoa;
    final alterou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => pessoa.isPet
            ? NovaPetScreen(pet: pessoa)
            : NovaPessoaScreen(pessoa: _pessoa),
      ),
    );
    if (alterou == true && mounted) _carregar();
  }

  Future<void> _excluir() async {
    final pessoa = _pessoa ?? widget.pessoa;
    final motivo = _motivoExclusaoBloqueada(pessoa);
    if (motivo != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(motivo)),
      );
      return;
    }

    final rotulo = pessoa.isPet ? 'pet' : 'contato';
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(pessoa.isPet ? 'Excluir pet' : 'Excluir contato'),
        content: Text(
          'Tem certeza que deseja excluir ${pessoa.nome}? '
          'O $rotulo deixará de aparecer nas suas listas.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmou == true && mounted) {
      final erro = await PessoaRepository.remover(pessoa.id);
      if (!mounted) return;
      if (erro == null) {
        Navigator.of(context).pop(true);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_mensagemErroRemover(erro, pessoa.nome))),
      );
    }
  }

  /// null = pode excluir; senão mensagem clara.
  String? _motivoExclusaoBloqueada(Pessoa pessoa) {
    if (pessoa.id == PessoaRepository.usuarioId) {
      return 'Você não pode excluir a própria conta por aqui.';
    }
    if (pessoa.criadoPorId != PessoaRepository.usuarioId) {
      return 'Só quem cadastrou este contato pode excluí-lo.';
    }
    if (pessoa.situacao == 'ativo') {
      return 'Não é possível excluir: esta pessoa já tem conta ativa.';
    }
    return null;
  }

  bool _podeExcluir(Pessoa pessoa) => _motivoExclusaoBloqueada(pessoa) == null;

  String _mensagemErroRemover(String codigo, String nome) {
    switch (codigo) {
      case 'nao_criador':
        return 'Só quem cadastrou este contato pode excluí-lo.';
      case 'conta_ativa':
        return 'Não é possível excluir: $nome já tem conta ativa.';
      case 'nao_encontrada':
        return 'Contato não encontrado.';
      default:
        return 'Não foi possível excluir $nome.';
    }
  }

  Future<void> _abrirMemorial(int memorialId) async {
    final memoriais = await SupabaseService.instance.listarMemoriais();
    if (!mounted) return;
    final m = memoriais.where((mm) => mm.id == memorialId).firstOrNull;
    if (m == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Memorial não encontrado.')),
      );
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MemorialDetalheScreen(memorial: m),
      ),
    );
  }

  Future<void> _criarMemorialParaPessoa() async {
    final pessoa = _pessoa ?? widget.pessoa;
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NovoMemorialScreen(pessoaParaVincular: pessoa),
      ),
    );
    if (mounted) _carregarAgregacoes();
  }

  String _formatarDataCurta(DateTime? data) {
    if (data == null) return '—';
    return DateFormat('MM/yyyy').format(data);
  }

  @override
  Widget build(BuildContext context) {
    final pessoa = _pessoa ?? widget.pessoa;

    return Scaffold(
      appBar: AppBar(
        title: Text(pessoa.nome),
        actions: [
          IconButton(
            tooltip: 'Editar',
            onPressed: _editar,
            icon: const Icon(Icons.edit_outlined),
          ),
          if (_podeExcluir(pessoa))
            IconButton(
              tooltip: 'Excluir',
              onPressed: _excluir,
              icon: const Icon(Icons.delete_outline),
            )
          else if (pessoa.id != PessoaRepository.usuarioId)
            IconButton(
              tooltip: _motivoExclusaoBloqueada(pessoa) ?? 'Excluir',
              onPressed: _excluir,
              icon: Icon(
                Icons.delete_outline,
                color: Colors.grey.shade400,
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _carregarAgregacoes,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // ── HEADER ──
                        Center(
                          child: PessoaAvatar(
                            radius: 52,
                            fotoUrl: pessoa.fotoUrl,
                            fotoBytes: pessoa.fotoBytes,
                            falecido: pessoa.falecido,
                            isPet: pessoa.isPet,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          pessoa.nome,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: AppColors.roxo,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (pessoa.apelido != null &&
                            pessoa.apelido!.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            pessoa.apelido!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Color(0xFF7A7280),
                              fontSize: 16,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0x26D4A84F),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              // S.9.3.1 — pet: espécie/raça.
                              // Humano: só a relação da SESSÃO com esta
                              // pessoa — nunca pessoas.parentesco (rótulo
                              // do criador, ex. "irmão" do dono da conta).
                              pessoa.isPet
                                  ? (pessoa.especieRacaLabel ?? 'Pet')
                                  : (_minhaRelacao?.isNotEmpty == true
                                      ? _minhaRelacao!
                                      : 'Familiar'),
                              style: const TextStyle(
                                color: AppColors.dourado,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        if (pessoa.dataNascimento != null) ...[
                          const SizedBox(height: 18),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.cake_outlined,
                                  size: 16, color: AppColors.verdeApoio),
                              const SizedBox(width: 6),
                              Text(
                                DateFormat('dd/MM/yyyy')
                                    .format(pessoa.dataNascimento!),
                                style: const TextStyle(
                                  color: Color(0xFF817987),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (pessoa.email != null && pessoa.email!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.email_outlined,
                                  size: 16, color: AppColors.dourado),
                              const SizedBox(width: 6),
                              Text(
                                pessoa.email!,
                                style: const TextStyle(
                                  color: Color(0xFF817987),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (pessoa.telefone != null && pessoa.telefone!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.phone_outlined,
                                  size: 16, color: AppColors.dourado),
                              const SizedBox(width: 6),
                              Text(
                                pessoa.telefone!,
                                style: const TextStyle(
                                  color: Color(0xFF817987),
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ],

                        // ── ESTATÍSTICAS ──
                        const SizedBox(height: 24),
                        _buildEstatisticas(),

                        // ── MEMORIAL VINCULADO ──
                        // S.9.3.1 — pets também podem ter memorial (Item 5).
                        const SizedBox(height: 20),
                        _buildSecaoMemorial(),

                        // ── SPRINT L — FAMÍLIA (grafo pessoa-pessoa) ──
                        const SizedBox(height: 28),
                        _buildSecaoFamilia(),

                        // ── LINHA DO TEMPO DA PESSOA ──
                        const SizedBox(height: 28),
                        _buildSecaoLinhaDoTempo(),

                        // ── MEMÓRIAS VINCULADAS (lista auxiliar) ──
                        // S.9.4c — só para PETS. Para humanos, o perfil já
                        // mostra o que a pessoa PUBLICOU (patrimônio + linha
                        // do tempo); "aparições" em memórias de terceiros não
                        // pertencem ao humano e confundiam o "N memórias".
                        if ((_pessoa ?? widget.pessoa).isPet) ...[
                          const SizedBox(height: 28),
                          _buildSecaoMemorias(),
                        ],

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildEstatisticas() {
    final stats = _stats;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.3), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.insights_outlined, color: AppColors.dourado, size: 20),
              SizedBox(width: 8),
              Text(
                'Patrimônio afetivo',
                style: TextStyle(
                  color: AppColors.roxo,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _EstatisticaBloco(
                icone: Icons.auto_stories_outlined,
                valor: stats.totalMemorias,
                rotulo: 'memórias',
                cor: AppColors.roxo,
              ),
              _EstatisticaBloco(
                icone: Icons.photo_outlined,
                valor: stats.totalFotos,
                rotulo: 'fotos',
                cor: AppColors.dourado,
              ),
              _EstatisticaBloco(
                icone: Icons.videocam_outlined,
                valor: stats.totalVideos,
                rotulo: 'vídeos',
                cor: AppColors.verdeApoio,
              ),
              _EstatisticaBloco(
                icone: Icons.add_comment_outlined,
                valor: stats.totalContribuicoes,
                rotulo: 'contribuições',
                cor: AppColors.roxo,
              ),
            ],
          ),
          if (stats.primeiraData != null || stats.ultimaData != null) ...[
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (stats.primeiraData != null)
                  Text(
                    'Primeira memória: ${_formatarDataCurta(stats.primeiraData)}',
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                if (stats.ultimaData != null)
                  Text(
                    'Última: ${_formatarDataCurta(stats.ultimaData)}',
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSecaoMemorial() {
    if (_memorialVinculado != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.borda),
        ),
        child: Row(
          children: [
            const Icon(Icons.favorite_outline, color: AppColors.dourado, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Memorial',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _memorialVinculado!.nome,
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: () => _abrirMemorial(_memorialVinculado!.id),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.dourado,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.open_in_new, size: 14),
              label: const Text('Abrir'),
            ),
          ],
        ),
      );
    }
    // S.9.3.1 (Item 5) — memorial liberado para pets, reutilizando o mesmo
    // fluxo estável (NovoMemorialScreen + vínculo via pessoas.id).
    // S.9.3.2 — memorial é para FALECIDOS: vivo não vê o botão.
    final pessoa = _pessoa ?? widget.pessoa;
    if (!pessoa.falecido) return const SizedBox.shrink();

    return OutlinedButton.icon(
      onPressed: _criarMemorialParaPessoa,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.dourado,
        side: const BorderSide(color: AppColors.dourado, width: 1.4),
        padding: const EdgeInsets.symmetric(vertical: 14),
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      icon: const Icon(Icons.add, size: 18),
      label: Text(
        pessoa.isPet
            ? 'Criar memorial para este pet'
            : 'Criar memorial para esta pessoa',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // SPRINT L — FAMÍLIA (grafo pessoa-pessoa)
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildSecaoFamilia() {
    if (_carregandoFamilia) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.roxo),
          ),
        ),
      );
    }
    if (_familia.isEmpty) {
      return _vazioFamilia();
    }
    // S.9.3.2 — perfil humano: vínculos de pet ficam fora da FAMÍLIA;
    // eles aparecem na seção própria "Pets" (S.9.4b, abaixo).
    final ehPetPerfil = (_pessoa ?? widget.pessoa).isPet;
    final vinculosPet = _familia
        .where((f) => f.tipo == 'TUTOR' || f.tipo == 'PET_DE')
        .toList();
    final familiaVisivel =
        ehPetPerfil ? vinculosPet : _familia.where((f) {
      return !(f.tipo == 'TUTOR' || f.tipo == 'PET_DE');
    }).toList();
    if (familiaVisivel.isEmpty && (ehPetPerfil || vinculosPet.isEmpty)) {
      return _vazioFamilia();
    }
    if (familiaVisivel.isEmpty) {
      // humano sem família mas com pets: só a seção Pets
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _buildSecaoPetsDoHumano(vinculosPet),
      );
    }
    // Agrupa por tipo (família / afinidade / conjugue / amizade / outro).
    final grupos = <String, List<OutraPessoaNaFamilia>>{};
    for (final f in familiaVisivel) {
      final cat = _categoriaParaTipo(f.tipo);
      grupos.putIfAbsent(cat, () => []).add(f);
    }
    const ordem = ['Família', 'Cônjuges', 'Afinidade', 'Amizades', 'Outros'];
    final categorias = ordem
        .where(grupos.containsKey)
        .toList();
    // S.9.3.1 — no perfil do pet a seção mostra o(s) tutor(es).
    final ehPet = (_pessoa ?? widget.pessoa).isPet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(ehPet ? Icons.pets : Icons.diversity_3,
                color: AppColors.dourado, size: 20),
            const SizedBox(width: 8),
            Text(
              ehPet ? 'Tutores' : 'Família',
              style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          ehPet
              ? 'Quem cuida deste pet na sua história.'
              : 'O lugar desta pessoa na sua história.',
          style: const TextStyle(
              color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        ...categorias.expand((cat) {
          return [
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 8),
              child: Text(
                cat,
                style: const TextStyle(
                  color: AppColors.dourado,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
            ...grupos[cat]!.map((f) => _buildCardRelacionamento(f)),
            const SizedBox(height: 8),
          ];
        }),
        // S.9.4b (Item 8) — pets dos quais este humano é tutor, visíveis
        // a qualquer pessoa (fora da árvore de família).
        if (!ehPetPerfil) ..._buildSecaoPetsDoHumano(vinculosPet),
        const SizedBox(height: 4),
        // S.9.3.2 — pet: só "Adicionar tutor" (vários tutores permitidos,
        // tipo fixo Tutor→Pet). Humano: "Adicionar relação" normal.
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _abrirAdicionarRelacionamento,
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              ehPet ? 'Adicionar tutor' : 'Adicionar relação',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
      ],
    );
  }

  /// S.9.4b — seção "Pets" no perfil de um humano (tutoria).
  List<Widget> _buildSecaoPetsDoHumano(List<OutraPessoaNaFamilia> vinculos) {
    if (vinculos.isEmpty) return const [];
    return [
      const SizedBox(height: 20),
      Row(children: const [
        Icon(Icons.pets, color: AppColors.dourado, size: 18),
        SizedBox(width: 8),
        Text('Pets',
            style: TextStyle(
                color: AppColors.roxo,
                fontSize: 16,
                fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 8),
      ...vinculos.map((f) => ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFF0EAF5),
              child: Icon(Icons.pets, color: AppColors.dourado, size: 18),
            ),
            title: Text(f.outraPessoaNome,
                style: const TextStyle(
                    color: AppColors.roxo, fontWeight: FontWeight.w700)),
            subtitle: const Text('Pet', style: TextStyle(fontSize: 12)),
            trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PessoaDetalheScreen(
                  pessoa: Pessoa(
                      id: f.outraPessoaId,
                      nome: f.outraPessoaNome,
                      tipo: 'pet'),
                  onAbrirMemoria: widget.onAbrirMemoria,
                  titulosMemorias: widget.titulosMemorias,
                ),
              ),
            ),
          )),
    ];
  }

  Widget _vazioFamilia() {
    // S.9.3.1 — texto/título de pet quando o perfil é de um pet.
    final ehPet = (_pessoa ?? widget.pessoa).isPet;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(ehPet ? Icons.pets : Icons.diversity_3,
                  color: AppColors.dourado, size: 20),
              const SizedBox(width: 8),
              Text(
                ehPet ? 'Tutores' : 'Família',
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            ehPet
                ? 'Este pet ainda não tem tutor definido. '
                    'Conecte-o a quem cuida dele.'
                : 'Esta pessoa ainda não tem relações na sua família. '
                    'Conecte-a a quem vive junto com ela para começar a construir o grafo familiar.',
            style: const TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _abrirAdicionarRelacionamento,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.roxo,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.add, size: 16),
              label: Text(
                ehPet ? 'Adicionar tutor' : 'Adicionar primeira relação',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _femininos = {
    'Mãe', 'Avó', 'Avozinha', 'Bisavó', 'Tia', 'Madrinha',
    'Irmã', 'Prima', 'Sobrinha', 'Neta', 'Bisneta', 'Nora',
    'Filha', 'Esposa', 'Companheira', 'Cunhada', 'Sogra',
  };

  String _relacaoTexto(OutraPessoaNaFamilia f) {
    final rot = f.rotuloDaOutraParaMim;
    final base = rot.replaceAll(RegExp(r'\(.*\)$'), '').trim();
    final feminino = _femininos.contains(base);
    final artigo = feminino ? 'sua' : 'seu';
    return 'É $artigo $rot';
  }

  Future<void> _alterarRelacao(OutraPessoaNaFamilia f) async {
    // S.9.3.2 — relação de pet (tutor) é fixa: não há o que alterar.
    if ((_pessoa ?? widget.pessoa).isPet ||
        f.tipo == 'TUTOR' || f.tipo == 'PET_DE') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O vínculo tutor–pet é fixo.')),
      );
      return;
    }
    // S.9.3.1 — alterar relação nunca oferece tipos de pet (o vínculo
    // tutor/pet é fixo, criado pela área Pets).
    final tipos = (await PessoaRelacionamentoService.instance.listarTipos())
        .where((t) => t.id != 'TUTOR' && t.id != 'PET_DE' && t.categoria != 'pet')
        .toList();
    if (!mounted || tipos.isEmpty) return;

    final selecionado = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final agrupados = <String, List<TipoRelacionamento>>{};
        for (final t in tipos) {
          agrupados.putIfAbsent(t.categoria, () => []).add(t);
        }
        final ordem = ['familia', 'afinidade', 'conjugue', 'amizade', 'outro'];
        final rotulos = {
          'familia': 'Família',
          'afinidade': 'Afinidade',
          'conjugue': 'Conjugal',
          'amizade': 'Amizade',
          'outro': 'Outro',
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borda,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Alterar relação',
                style: TextStyle(
                  color: AppColors.roxo, fontSize: 18, fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final cat in ordem)
                      if (agrupados.containsKey(cat) && agrupados[cat]!.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4, top: 8),
                          child: Text(
                            rotulos[cat] ?? cat,
                            style: const TextStyle(
                              color: Color(0xFF7A7280), fontSize: 12,
                              fontWeight: FontWeight.w700, letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        for (final t in agrupados[cat]!)
                          ListTile(
                            title: Text(t.rotuloA,
                              style: const TextStyle(
                                color: AppColors.roxo, fontWeight: FontWeight.w600, fontSize: 14,
                              ),
                            ),
                            onTap: () => Navigator.of(ctx).pop(t.id),
                          ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );

    if (selecionado == null || !mounted) return;
    final t = tipos.firstWhere((t) => t.id == selecionado);
    // S.9.3.1 (Item 6) — o tipo escolhido descreve o papel da OUTRA pessoa
    // (o card diz "É seu X"). Convenção oficial: `tipo` = papel de B
    // (a outra pessoa) — portanto tipo = escolhido, sem inversão.
    // Rótulos: relacao_a_para_b = papel do perfil (rotuloB do escolhido);
    // relacao_b_para_a = papel da outra (rotuloA).
    // atualizarRotulos() replica na linha inversa com _inverseTipo.
    await PessoaRelacionamentoService.instance.atualizarRotulos(
      relacionamentoId: f.relacionamentoId,
      tipo: t.id,
      relacaoA: t.rotuloB,
      relacaoB: t.rotuloA,
    );
    if (mounted) {
      setState(() {
        _familia = _familia.map((x) {
          if (x.relacionamentoId == f.relacionamentoId) {
            return OutraPessoaNaFamilia(
              relacionamentoId: x.relacionamentoId,
              outraPessoaId: x.outraPessoaId,
              outraPessoaNome: x.outraPessoaNome,
              tipo: t.id,
              rotuloDaOutraParaMim: t.rotuloA,
              rotuloDeMimParaAOutra: t.rotuloB,
              observacoes: x.observacoes,
              dataInicio: x.dataInicio,
              dataFim: x.dataFim,
            );
          }
          return x;
        }).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Relação alterada com sucesso!')),
      );
    }
  }

  Widget _buildCardRelacionamento(OutraPessoaNaFamilia f) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borda),
      ),
      child: Row(
        children: [
          PessoaAvatar(
            radius: 16,
            fotoUrl: f.fotoUrl,
            isPet: f.tipo == 'TUTOR' || f.tipo == 'PET_DE',
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.outraPessoaNome.isEmpty
                      ? 'Outra pessoa'
                      : f.outraPessoaNome,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _relacaoTexto(f),
                  style: const TextStyle(
                    color: Color(0xFF7A7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Color(0xFF9B949D), size: 18),
            onSelected: (acao) async {
              if (acao == 'remover') {
                await PessoaRelacionamentoService.instance.deletar(f.relacionamentoId);
                if (mounted) {
                  setState(() {
                    _familia = _familia.where((x) => x.relacionamentoId != f.relacionamentoId).toList();
                  });
                }
              } else if (acao == 'inativar') {
                await PessoaRelacionamentoService.instance.inativar(f.relacionamentoId);
                if (mounted) {
                  setState(() {
                    _familia = _familia.where((x) => x.relacionamentoId != f.relacionamentoId).toList();
                  });
                }
              } else if (acao == 'alterar') {
                await _alterarRelacao(f);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'inativar',
                child: Text('Marcar como inativo'),
              ),
              const PopupMenuItem(
                value: 'alterar',
                child: Text('Alterar relação'),
              ),
              const PopupMenuItem(
                value: 'remover',
                child: Text('Remover', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _categoriaParaTipo(String tipo) {
    switch (tipo) {
      case 'CONJUGE':
      case 'COMPANHEIRO':
        return 'Cônjuges';
      case 'PADRINHO':
      case 'MADRINHA':
      case 'AFILHADO':
        return 'Afinidade';
      case 'AMIGO':
        return 'Amizades';
      case 'OUTRO':
        return 'Outros';
      default:
        return 'Família';
    }
  }

  Future<void> _abrirAdicionarRelacionamento() async {
    final pessoa = _pessoa ?? widget.pessoa;
    if (pessoa.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdicionarRelacionamentoScreen(
          pessoaOrigemId: pessoa.id!,
          pessoaOrigemNome: pessoa.nome,
          // S.9.3.2 — do perfil do pet, só se adiciona TUTOR.
          tutorDePet: pessoa.isPet,
        ),
      ),
    );
    if (mounted) {
      setState(() => _carregandoFamilia = true);
      final f = await PessoaRelacionamentoService.instance
          .listarRelacionamentos(pessoa.id!);
      if (mounted) {
        setState(() {
          _familia = f;
          _carregandoFamilia = false;
        });
      }
    }
  }

  Widget _buildSecaoLinhaDoTempo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.history_edu_outlined, color: AppColors.dourado, size: 20),
            SizedBox(width: 8),
            Text(
              'Linha do tempo',
              style: TextStyle(
                color: AppColors.roxo,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Como esta pessoa foi aparecendo nas suas histórias, em ordem cronológica.',
          style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        if (_carregandoEventos)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.roxo),
              ),
            ),
          )
        else if (_eventos.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borda),
            ),
            child: Text(
              (_pessoa ?? widget.pessoa).isPet
                  ? 'Este pet ainda não apareceu em nenhuma memória ou contribuição. '
                      'Adicione o nome dele em uma memória para ele ganhar vida aqui.'
                  : 'Esta pessoa ainda não apareceu em nenhuma memória ou contribuição. '
                      'Adicione o nome dela em uma memória para ela ganhar vida aqui.',
              style: const TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
            ),
          )
        else
          ..._eventos.map((e) => _buildItemTimelinePessoa(e)),
      ],
    );
  }

  Widget _buildItemTimelinePessoa(PessoaTimelineEvento e) {
    final data = e.data;
    final dataStr = DateFormat('MMM/yyyy').format(data);
    final ehMemoria = e.tipo == PessoaTimelineTipo.memoria;
    final ehContribuicao = e.tipo == PessoaTimelineTipo.contribuicao;
    final ehFoto = e.tipo == PessoaTimelineTipo.foto;

    final icone = ehMemoria
        ? Icons.auto_stories_outlined
        : ehContribuicao
            ? Icons.add_comment_outlined
            : ehFoto
                ? Icons.photo_outlined
                : Icons.videocam_outlined;
    final cor = ehMemoria
        ? AppColors.roxo
        : ehContribuicao
            ? AppColors.verdeApoio
            : AppColors.dourado;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            if (ehMemoria) {
              widget.onAbrirMemoria(e.conteudoId);
            } else if (e.memoriaOrigemId != null) {
              widget.onAbrirMemoria(e.memoriaOrigemId!);
            }
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borda),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: cor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icone, size: 18, color: cor),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            e.tipo.rotulo,
                            style: TextStyle(
                              color: cor,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '· $dataStr',
                            style: const TextStyle(
                              color: Color(0xFF9B949D),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        e.titulo,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if (e.fotoUrl != null && e.fotoUrl!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            e.fotoUrl!,
                            height: 120,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                        ),
                      ] else if (e.videoUrl != null &&
                          e.videoUrl!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: VideoFramePreview(
                            url: e.videoUrl!,
                            height: 120,
                          ),
                        ),
                      ],
                      if (ehContribuicao && e.autorContribuicao != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'por ${e.autorContribuicao}',
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
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

  Widget _buildSecaoMemorias() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.auto_stories_outlined,
                size: 18, color: AppColors.dourado),
            const SizedBox(width: 8),
            Text(
              _memoriasVinculadas.isEmpty
                  ? 'Nenhuma memória vinculada'
                  : '${_memoriasVinculadas.length} ${_memoriasVinculadas.length == 1 ? 'memória' : 'memórias'}',
              style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_memoriasVinculadas.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borda),
            ),
            child: const Text(
              'As memórias em que você adicionar esta pessoa aparecerão aqui.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF7A7280), fontSize: 14, height: 1.4),
            ),
          )
        else
          ..._memoriasVinculadas.map(
            (id) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => widget.onAbrirMemoria(id),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.borda),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_stories_outlined,
                            size: 20, color: AppColors.roxo),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.titulosMemorias[id] ?? 'Memória',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.roxo,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right,
                            color: Color(0xFF9B949D)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _EstatisticaBloco extends StatelessWidget {
  const _EstatisticaBloco({
    required this.icone,
    required this.valor,
    required this.rotulo,
    required this.cor,
  });

  final IconData icone;
  final int valor;
  final String rotulo;
  final Color cor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icone, color: cor, size: 24),
        const SizedBox(height: 6),
        Text(
          '$valor',
          style: const TextStyle(
            color: AppColors.roxo,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          rotulo,
          style: const TextStyle(
            color: Color(0xFF7A7280),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
