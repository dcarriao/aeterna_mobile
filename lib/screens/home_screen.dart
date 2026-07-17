import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/contribuicao.dart';
import '../models/curador_sessao.dart';
import '../models/memoria.dart';
import '../models/detected_moment.dart';
import '../models/memoria_do_dia.dart';
import '../models/memoria_relacionamento.dart';
import '../models/pessoa.dart';
import '../models/pessoa_linha_tempo.dart';
import '../models/pessoa_relacionamento.dart';
import '../models/proactive_opportunity.dart';
import '../services/curator_decision_log_service.dart';
import '../services/curator_invitation_scoring_service.dart';
import '../services/curador_proativo_service.dart';
import '../services/curador_sessao_service.dart';
import '../services/memory_growth_invitation_service.dart';
import '../services/memory_growth_scoring_service.dart';
import '../services/memory_relationship_service.dart';
import '../services/pessoa_relacionamento_service.dart';
import '../services/memorias_do_dia_service.dart';
import '../services/moment_detection_service.dart';
import '../services/pessoa_timeline_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';
import '../widgets/pessoa_avatar.dart';
import '../widgets/home/curador_continuar_card.dart';
import '../widgets/home/detected_moment_card.dart';
import '../widgets/home/memoria_do_dia_card.dart';
import '../widgets/home/memoria_pode_crescer_card.dart';
import '../widgets/home/proactive_opportunity_card.dart';
import 'conexoes_descobertas_screen.dart';
import 'curador_screen.dart';
import 'mapa_vida_screen.dart';
import 'nova_memoria_screen.dart';
import 'pessoa_detalhe_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onRegistrar,
    required this.onMinhaHistoria,
    required this.onAbrirMemoria,
    required this.onPessoas,
    required this.onPets,
    required this.onTimeline,
    required this.onCompartilhadas,
    required this.onPerfil,
    required this.onMemoriais,
    this.fotoUrl,
    this.memorias = const [],
    super.key,
  });

  final VoidCallback onRegistrar;
  final VoidCallback onMinhaHistoria;
  final void Function(Memoria memoria) onAbrirMemoria;
  final VoidCallback onPessoas;
  final VoidCallback onPets;
  final VoidCallback onTimeline;
  final VoidCallback onCompartilhadas;
  final VoidCallback onPerfil;
  final VoidCallback onMemoriais;
  final String? fotoUrl;
  final List<Memoria> memorias;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<DetectedMoment> _sugestoes = [];
  bool _carregandoSugestoes = false;
  bool _esconderBanner = false;

  // Sprint H â€” Pessoas Vivas Recentemente
  List<PessoaVivaResumo> _pessoasVivas = const [];
  Map<int, String> _parentescoMap = {};

  // Sprint I â€” Memórias que podem crescer
  List<MemoriaComScore> _memoriasQuePodemCrescer = const [];
  bool _carregandoCrescer = true;

  // Sprint J — Sessão ativa do Curador Contextual
  CuradorSessao? _sessaoCuradorAtiva;
  bool _carregandoSessaoCurador = true;

  // Sprint M — Memórias do Dia
  List<MemoriaDoDia> _memoriasDoDia = const [];
  bool _carregandoMemDia = true;

  // Sprint K — Conexões pendentes (Home: "Conexões descobertas")
  List<MemoriaRelacionamento> _conexoesPendentes = const [];

  // Sprint N — Curador Proativo Inteligente
  ProactiveOpportunity? _proactiveOpportunity;
  bool _carregandoProativo = true;

  @override
  void initState() {
    super.initState();
    // S.9.3.1 (Item 9) — instrumentação de performance da Home.
    final sw = Stopwatch()..start();
    print('[PERF] tela=Home inicio=${DateTime.now().toIso8601String()}');
    Future.wait([
      _carregarSugestoes().catchError((e) => print('[PERF] Home sugestoes ERRO: $e')),
      _carregarPessoasVivas().catchError((e) => print('[PERF] Home pessoasVivas ERRO: $e')),
      _carregarMemoriasQuePodemCrescer().catchError((e) => print('[PERF] Home memCrescer ERRO: $e')),
      _carregarSessaoCurador().catchError((e) => print('[PERF] Home sessaoCurador ERRO: $e')),
      _carregarConexoesPendentes().catchError((e) => print('[PERF] Home conexoes ERRO: $e')),
      _carregarMemoriasDoDia().catchError((e) => print('[PERF] Home memDoDia ERRO: $e')),
      _carregarOportunidadeProativa().catchError((e) => print('[PERF] Home proativo ERRO: $e')),
    ]).whenComplete(() =>
        print('[PERF] tela=Home pronta_em_ms=${sw.elapsedMilliseconds}'));
  }

  Future<void> _carregarSessaoCurador() async {
    final s = await CuradorSessaoService.instance.obterSessaoAtiva();
    if (mounted) {
      setState(() {
        _sessaoCuradorAtiva = s;
        _carregandoSessaoCurador = false;
      });
    }
  }

  Future<void> _carregarConexoesPendentes() async {
    final lista = await MemoryRelationshipService.instance
        .listarPendentesDoUsuario(limite: 6);
    if (mounted) {
      setState(() => _conexoesPendentes = lista);
    }
  }

  Future<void> _abrirTelaConexoes() async {
    final processou = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ConexoesDescobertasScreen(
        memorias: widget.memorias,
        onAbrirMemoria: (m) => widget.onAbrirMemoria(m),
      ),
    ));
    if (processou == true) _carregarConexoesPendentes();
  }

  Future<void> _carregarMemoriasDoDia() async {
    setState(() => _carregandoMemDia = true);
    final lista = await MemoriasDoDiaService.instance.listarParaHome(limite: 5);
    if (mounted) {
      setState(() {
        _memoriasDoDia = lista;
        _carregandoMemDia = false;
      });
    }
  }

  Future<void> _carregarOportunidadeProativa() async {
    setState(() => _carregandoProativo = true);
    final op = await CuradorProativoService.instance.obterMelhorOportunidade();
    if (mounted) {
      setState(() {
        _proactiveOpportunity = op;
        _carregandoProativo = false;
      });
    }
  }

  Future<void> _transformarOportunidadeProativa(ProactiveOpportunity op) async {
    await CuradorProativoService.instance.registrarExibicao();
    if (op.memoriaDoDia != null) {
      await _continuarMemoriaDoDia(op.memoriaDoDia!);
      return;
    }
    if (op.detectedMoment != null) {
      await _navegarParaCuradorProativo(op);
      return;
    }
    await _navegarParaCuradorProativo(op);
  }

  Future<void> _navegarParaCuradorProativo(ProactiveOpportunity op) async {
    Uint8List? mediaBytes;
    final momento = op.detectedMoment;
    if (momento != null) {
      try {
        final file = await MomentDetectionService.instance.obterMidiaMaisRecente(momento);
        if (file != null) {
          mediaBytes = await file.readAsBytes();
        }
      } catch (_) {}
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: op.titulo,
          contextoOriginal: '',
          isProativo: true,
          proativoMediaBytes: mediaBytes,
          proativoMediaIsVideo: op.temVideo,
          proativoFotosCount: op.quantidadeFotos,
          proativoVideosCount: op.quantidadeVideos,
        ),
      ),
    );
    if (mounted) _carregarOportunidadeProativa();
  }

  Future<void> _dispensarOportunidadeProativa(ProactiveOpportunity op) async {
    await CuradorProativoService.instance.registrarDispensa(op.oportunidadeId);
    if (mounted) {
      setState(() => _proactiveOpportunity = null);
    }
  }

  Future<void> _abrirMemoriaDoDia(MemoriaDoDia m) async {
    final mems = widget.memorias;
    if (mems.isEmpty) return;
    final encontrada =
        mems.cast<Memoria?>().firstWhere((x) => x?.id == m.id, orElse: () => null);
    if (encontrada != null) {
      widget.onAbrirMemoria(encontrada);
      return;
    }
    widget.onAbrirMemoria(mems.first);
  }

  Future<void> _continuarMemoriaDoDia(MemoriaDoDia m) async {
    final mems = widget.memorias;
    if (mems.isEmpty) return;
    final encontrada =
        mems.cast<Memoria?>().firstWhere((x) => x?.id == m.id, orElse: () => null);
    if (encontrada == null || encontrada.id == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: encontrada.titulo,
          contextoOriginal: encontrada.contexto,
          isProativo: false,
          complementoMemoriaId: encontrada.id,
        ),
      ),
    );
    if (mounted) _carregarMemoriasDoDia();
  }

  Future<void> _abrirMapaVida() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => MapaVidaScreen(
          memorias: widget.memorias,
          onAbrirMemoria: (m) {
            Navigator.of(context).pop();
            widget.onAbrirMemoria(m);
          },
        ),
      ),
    );
  }

  /// Prioridade de exibição em "Pessoas importantes":
  /// 1 companheiro/esposo · 2 filhos/enteados · 3 pai/mãe ·
  /// 4 irmãos/avós · 5 amigos · 6 demais.
  int _prioridadePessoaImportante(String tipo, String rotulo) {
    final t = tipo.toUpperCase();
    final r = rotulo.toLowerCase();
    if (t == 'CONJUGE' ||
        t == 'COMPANHEIRO' ||
        r.contains('companheir') ||
        r.contains('espos') ||
        r.contains('marido') ||
        r.contains('cônjuge') ||
        r.contains('conjuge')) {
      return 1;
    }
    if (t == 'FILHO' ||
        t == 'FILHA' ||
        t == 'ENTEADO' ||
        t == 'ENTEADA' ||
        r.contains('filh') ||
        r.contains('entead')) {
      return 2;
    }
    if (t == 'PAI' ||
        t == 'MAE' ||
        t == 'PADRASTO' ||
        t == 'MADRASTA' ||
        r == 'pai' ||
        r == 'mãe' ||
        r == 'mae' ||
        r.contains('padrast') ||
        r.contains('madrast')) {
      return 3;
    }
    if (t == 'IRMAO' ||
        t == 'AVO' ||
        t == 'NETO' ||
        t == 'BISAVO' ||
        t == 'BISNETO' ||
        r.contains('irm') ||
        r.contains('avô') ||
        r.contains('avó') ||
        r.contains('avo') ||
        r.contains('neto') ||
        r.contains('neta')) {
      return 4;
    }
    if (t == 'AMIGO' || r.contains('amig')) return 5;
    return 6;
  }

  Future<void> _carregarPessoasVivas() async {
    // Ativos humanos (nunca pet/falecido), ordenados por proximidade
    // familiar. Contagem = memórias que ELES publicaram (ownership).
    final resultadosPV = await Future.wait([
      PessoaRepository.listar(),
      PessoaRelacionamentoService.instance
          .listarRelacionamentos(PessoaRepository.usuarioId),
    ]);
    final todas = resultadosPV[0] as List<Pessoa>;
    final rels = resultadosPV[1] as List<OutraPessoaNaFamilia>;
    final parentescoMap = <int, String>{};
    final tipoPorId = <int, String>{};
    for (final r in rels) {
      if (r.rotuloDaOutraParaMim.isNotEmpty) {
        parentescoMap[r.outraPessoaId] = r.rotuloDaOutraParaMim;
      }
      if (r.tipo.isNotEmpty) tipoPorId[r.outraPessoaId] = r.tipo;
    }

    final elegiveis = todas
        .where((p) =>
            p.id != PessoaRepository.usuarioId &&
            p.isHumano &&
            !p.falecido &&
            p.situacao == 'ativo')
        .toList();
    elegiveis.sort((a, b) {
      // Só rótulos do grafo da sessão — nunca pessoas.parentesco (criador).
      final pa = _prioridadePessoaImportante(
          tipoPorId[a.id] ?? '', parentescoMap[a.id] ?? '');
      final pb = _prioridadePessoaImportante(
          tipoPorId[b.id] ?? '', parentescoMap[b.id] ?? '');
      if (pa != pb) return pa.compareTo(pb);
      return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
    });

    final top = elegiveis.take(6).toList();
    final counts =
        await PessoaRepository.contarMemoriasPublicadas(top.map((p) => p.id));
    final pessoas = top
        .map((p) => PessoaVivaResumo(
              id: p.id,
              nome: p.nome,
              parentesco: parentescoMap[p.id] ?? '',
              fotoUrl: p.fotoUrl,
              ultimaInteracao: null,
              totalEventos: counts[p.id] ?? 0,
            ))
        .toList();

    if (mounted) {
      setState(() {
        _pessoasVivas = pessoas;
        _parentescoMap = parentescoMap;
      });
    }
    // Sprint L — heurística temporal: para cada pessoa viva, calcula
    // se HOJE é aniversário de uma memória (tempo juntos).
    final resultado = <int, int>{};
    for (final p in pessoas) {
      final r =
          await PessoaTimelineService.instance.calcularAniversario(p.id);
      if (r.anos != null) {
        resultado[p.id] = r.anos!;
      }
    }
    if (mounted) {
      setState(() => _aniversarioHoje = resultado);
    }
  }

  // Sprint L — Mapa da pessoaId -> quantos anos fazendo parte
  // da história (calculado a partir da 1ª memória).
  Map<int, int> _aniversarioHoje = {};

  Future<void> _carregarMemoriasQuePodemCrescer() async {
    setState(() => _carregandoCrescer = true);
    final memorias =
        await MemoryGrowthInvitationService.instance.listarParaHome(limite: 3);
    if (mounted) {
      setState(() {
        _memoriasQuePodemCrescer = memorias;
        _carregandoCrescer = false;
      });
    }
  }

  Future<void> _dispensarMemoriaCrescer(int memoriaId) async {
    await MemoryGrowthScoringService.instance.dispensarConvite(memoriaId);
    if (mounted) _carregarMemoriasQuePodemCrescer();
  }

  // SPRINT F â€” Sensibilidade dos Convites do Curador: só momentos com score
  // >= CuratorScoringWeights.minimumInvitationScore aparecem como convite
  // principal (banner/card). Momentos com score baixo são descartados nesta
  // sprint (não há área secundária ainda).
  Future<void> _carregarSugestoes() async {
    if (mounted) setState(() => _carregandoSugestoes = true);
    final todos = await MomentDetectionService.instance.obterMomentosDetectados();

    final qualificados = <DetectedMoment>[];
    for (final momento in todos) {
      final score = await CuratorInvitationScoringService.instance.calcularScore(momento);
      await CuratorDecisionLogService.instance.registrarDecisao(
        momento: momento,
        score: score,
        conviteCriado: score.atingiuLimite,
      );
      if (score.atingiuLimite) {
        qualificados.add(momento);
      }
    }

    if (mounted) {
      setState(() {
        _sugestoes = qualificados;
        _carregandoSugestoes = false;
      });
    }
  }

  void _iniciarCriacaoMemoriaComGrupo(DetectedMoment momento) {
    CuratorDecisionLogService.instance.atualizarAcaoUsuario(momento.id, 'abriu');
    Navigator.of(context).push<Memoria>(
      MaterialPageRoute(
        builder: (_) => NovaMemoriaScreen(
          onSalvar: SupabaseService.instance.salvarMemoriaComFoto,
          sugestaoMomento: momento,
        ),
      ),
    ).then((resultado) {
      if (resultado is Memoria) {
        CuratorDecisionLogService.instance.atualizarAcaoUsuario(momento.id, 'criou_memoria');
      }
      _carregarSugestoes();
    });
  }

  @override
  Widget build(BuildContext context) {
    final recentes = widget.memorias.take(3).toList();

    return Scaffold(
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.borda)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                _NavItem(
                    icon: Icons.people_outline,
                    label: 'Pessoas',
                    onTap: widget.onPessoas),
                // S.9.3.2 — Pets com a mesma visibilidade de Pessoas
                _NavItem(
                    icon: Icons.pets_outlined,
                    label: 'Pets',
                    onTap: widget.onPets),
                _NavItem(
                    icon: Icons.timeline_outlined,
                    label: 'Timeline',
                    onTap: widget.onTimeline),
                _NavItem(
                    icon: Icons.favorite_outline,
                    label: 'Memoriais',
                    onTap: widget.onMemoriais),
                _NavItem(
                    icon: Icons.share_outlined,
                    label: 'Compartilhadas',
                    onTap: widget.onCompartilhadas),
              ],
            ),
          ),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Image.asset('assets/logo.png', height: 72),
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Mapa da Vida',
                          onPressed: _abrirMapaVida,
                          icon: const Icon(Icons.timeline,
                              color: AppColors.dourado, size: 22),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: widget.onPerfil,
                        child: Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EAF5),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.borda),
                            image: widget.fotoUrl != null && widget.fotoUrl!.isNotEmpty
                                ? DecorationImage(
                                    image: NetworkImage(widget.fotoUrl!),
                                    fit: BoxFit.cover,
                                  )
                                : null,
                          ),
                          child: widget.fotoUrl == null || widget.fotoUrl!.isEmpty
                              ? const Icon(Icons.person_outline,
                                  color: AppColors.roxo, size: 20)
                              : null,
                        ),
                      ),
                    ),
                  ],
                ),

                // Sprint J â€” Sessão ativa do Curador Contextual
                if (_sessaoCuradorAtiva != null) ...[
                  const SizedBox(height: 16),
                  CuradorContinuarCard(
                    sessao: _sessaoCuradorAtiva!,
                    onContinuar: () => _retomarSessaoCurador(),
                    onDescartar: () => _descartarSessaoCurador(),
                  ),
                ],

                // Sprint N — Curador Proativo Inteligente
                if (!_carregandoProativo &&
                    _proactiveOpportunity != null) ...[
                  const SizedBox(height: 16),
                  ProactiveOpportunityCard(
                    opportunity: _proactiveOpportunity!,
                    onTransformar: () =>
                        _transformarOportunidadeProativa(
                            _proactiveOpportunity!),
                    onDispensar: () =>
                        _dispensarOportunidadeProativa(
                            _proactiveOpportunity!),
                  ),
                ],

                // Banner de Convite do Curador (Sprint D)
                // Só mostra quando não há oportunidade proativa com mídia (evita
                // duplicação do mesmo conteúdo na Home).
                if (!_carregandoSugestoes &&
                    !_esconderBanner &&
                    _sugestoes.isNotEmpty &&
                    _proactiveOpportunity?.detectedMoment == null) ...[
                  const SizedBox(height: 16),
                  _buildBannerConvite(_sugestoes.first),
                ],
                
                // Card de Sugestões de Mídia Proativas
                // Só mostra quando não há oportunidade proativa com mídia (evita
                // duplicação do mesmo conteúdo na Home).
                if (!_carregandoSugestoes &&
                    _sugestoes.isNotEmpty &&
                    _proactiveOpportunity?.detectedMoment == null) ...[
                  const SizedBox(height: 16),
                  DetectedMomentCard(
                    sugestoes: _sugestoes,
                    onCriarHistoria: _iniciarCriacaoMemoriaComGrupo,
                  ),
                ],

                // SPRINT H â€” Pessoas Vivas Recentemente
                if (_pessoasVivas.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Pessoas importantes',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Familiares ativos, ordenados por proximidade. O número é de memórias que cada um publicou.',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  ..._pessoasVivas.take(4).map((p) => _buildCardPessoaViva(p)),
                ],

                // SPRINT L — Aniversário de memórias
                if (_aniversarioHoje.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Hoje faz aniversário',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Marcos do tempo que você compartilha com quem está perto.',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  ..._pessoasVivas
                      .where((p) => _aniversarioHoje.containsKey(p.id))
                      .map((p) => _buildCardAniversario(p)),
                ],

                // SPRINT I â€" Memórias que podem crescer
                if (_memoriasQuePodemCrescer.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Memórias que podem crescer',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'O Curador percebeu que estas histórias podem ficar ainda mais ricas com novas contribuições.',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  ..._memoriasQuePodemCrescer.map(
                    (item) => MemoriaPodeCrescerCard(
                      item: item,
                      onAbrirMemoria: (id) =>
                          widget.onAbrirMemoria(_resolveMemoria(id)),
                      onAbrirCurador: () =>
                          _abrirCuradorComplemento(item),
                      onDispensar: () =>
                          _dispensarMemoriaCrescer(item.memoria.memoriaId),
                    ),
                  ),
                ],

                // SPRINT M — Memórias do Dia
                if (_memoriasDoDia.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Hoje na sua história',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Memórias que aconteceram neste mesmo dia em outros anos da sua vida.',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  ..._memoriasDoDia.take(3).map((m) => MemoriaDoDiaCard(
                        item: m,
                        onRelembrar: () => _abrirMemoriaDoDia(m),
                        onContinuar: () => _continuarMemoriaDoDia(m),
                      )),
                ],

                // SPRINT K — Conexões descobertas
                if (_conexoesPendentes.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Conexões descobertas',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 12),
                    child: Text(
                      'Encontramos histórias que parecem fazer parte do mesmo momento da sua vida. Deseja conectá-las?',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  _buildCardConexoes(_conexoesPendentes.first),
                  if (_conexoesPendentes.length > 1)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextButton(
                        onPressed: _abrirTelaConexoes,
                        child: Text(
                          'Ver mais ${_conexoesPendentes.length - 1} conexões',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                ],

                const SizedBox(height: 28),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Suas memórias',
                              style: TextStyle(
                                  color: AppColors.roxo,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text(
                            widget.memorias.isEmpty
                                ? 'Nenhuma ainda'
                                : '${widget.memorias.length} ${widget.memorias.length == 1 ? 'registro' : 'registros'}',
                            style: const TextStyle(
                                color: Color(0xFF9B949D), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: widget.onRegistrar,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.roxo,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 46),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Nova memória'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                if (widget.memorias.isEmpty)
                  _EstadoVazio(onRegistrar: widget.onRegistrar)
                else ...[
                  ...recentes.map(
                    (memoria) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: MemoryCard(
                        memoria: memoria,
                        onLer: () => widget.onAbrirMemoria(memoria),
                      ),
                    ),
                  ),
                  if (widget.memorias.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: widget.onMinhaHistoria,
                          icon: const Text('Ver todas as memórias',
                              style: TextStyle(
                                  color: AppColors.roxo,
                                  fontWeight: FontWeight.w600)),
                          label: const Icon(Icons.arrow_forward,
                              size: 18, color: AppColors.roxo),
                        ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBannerConvite(DetectedMoment pending) {
    final hasVideos = pending.quantidadeVideos > 0;
    
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    String diaStr;
    if (pending.inicio.year == hoje.year && pending.inicio.month == hoje.month && pending.inicio.day == hoje.day) {
      diaStr = 'hoje';
    } else if (pending.inicio.year == ontem.year && pending.inicio.month == ontem.month && pending.inicio.day == ontem.day) {
      diaStr = 'ontem';
    } else {
      diaStr = '${pending.inicio.day.toString().padLeft(2, '0')}/${pending.inicio.month.toString().padLeft(2, '0')}';
    }
    final horaStr = '${pending.inicio.hour.toString().padLeft(2, '0')}:${pending.inicio.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dourado.withOpacity(0.3), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome, color: AppColors.dourado, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O Curador encontrou um momento que merece ser preservado.',
                  style: TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                hasVideos ? Icons.videocam_outlined : Icons.photo_library_outlined,
                size: 16,
                color: AppColors.roxo,
              ),
              const SizedBox(width: 8),
              Text(
                '${hasVideos ? 'Vídeo' : 'Foto'} registrado $diaStr às $horaStr',
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  CuratorInvitationScoringService.instance.registrarMomentoIgnorado(pending.id);
                  CuratorDecisionLogService.instance.atualizarAcaoUsuario(pending.id, 'ignorou');
                  setState(() {
                    _esconderBanner = true;
                  });
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A7280),
                ),
                child: const Text('Agora não', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: () => _iniciarCriacaoMemoriaComGrupo(pending),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text('Criar memória', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Sprint H â€” Card de "Pessoa Viva" na Home
  Widget _buildCardPessoaViva(PessoaVivaResumo p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => _abrirPessoa(p),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.borda),
            ),
            child: Row(
              children: [
                PessoaAvatar(
                  radius: 24,
                  fotoUrl: p.fotoUrl,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.nome,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if ((_parentescoMap[p.id] ?? '').isNotEmpty)
                        Text(
                          _parentescoMap[p.id]!,
                          style: const TextStyle(
                            color: AppColors.dourado,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        p.totalEventos == 0
                            ? 'Nenhuma memória publicada'
                            : '${p.totalEventos} ${p.totalEventos == 1 ? "memória" : "memórias"} publicadas',
                        style: const TextStyle(
                          color: Color(0xFF7A7280),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF9B949D)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPessoa(PessoaVivaResumo resumo) async {
    // Carrega o Pessoa completo do banco (precisa do `p.id` real, não
    // do `id` local do construtor).
    final todas = await PessoaRepository.listar();
    if (!mounted) return;
    final pessoa = todas.firstWhere(
      (p) => p.id == resumo.id,
      orElse: () => Pessoa(
        nome: resumo.nome,
        parentesco: resumo.parentesco,
      ),
    );
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => PessoaDetalheScreen(
          pessoa: pessoa,
          onAbrirMemoria: (id) {
            // A Home não tem callback direto para abrir uma memória;
            // apenas volta para que a navegação existente (main.dart)
            // seja usada. Solução prática: usar widget.onAbrirMemoria.
            // Como esse callback não está no HomeScreen, delegamos
            // para a main via Navigator.
            Navigator.of(context).pop();
          },
        ),
      ),
    );
    if (mounted) _carregarPessoasVivas();
  }

  // Sprint I â€” Abre a CuradorScreen em modo "complemento" para a
  // memória selecionada. Ao voltar com um `CuradorResultado`, o texto
  // enriquecido vira uma contribuição (NÃƒO sobrescreve a memória).
  Future<void> _abrirCuradorComplemento(MemoriaComScore item) async {
    // Carrega a memória completa (precisa do `id` real + contexto)
    // a partir de widget.memorias (passado pela main.dart).
    final m = widget.memorias.firstWhere(
      (mm) => mm.id == item.memoria.memoriaId,
      orElse: () => widget.memorias.first,
    );
    if (m.id == null) return;
    final result = await Navigator.of(context).push<CuradorResultado>(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: m.titulo,
          contextoOriginal: m.contexto,
          isProativo: false,
          // Sprint I: modo "complemento" â€” a CuradorScreen sabe que deve
          // carregar a memória do banco (contribuições, pessoas) e
          // oferecer a primeira pergunta "você gostaria de complementar
          // esta história ou registrar um novo capítulo?". O retorno
          // é tratado como CONTRIBUIÃ‡ÃƒO, não como reescrita.
          complementoMemoriaId: m.id,
        ),
      ),
    );
    if (result == null) return;
    final texto = result.contextoEnriquecido.trim();
    if (texto.isEmpty) return;
    try {
      final contrib = Contribuicao(
        tipoConteudo: 'memoria',
        conteudoId: m.id!,
        usuarioDonoId: m.donoUsuarioId ?? SupabaseService.usuarioId,
        usuarioContribuidorEmail: PessoaRepository.usuarioEmail ?? '',
        usuarioContribuidorNome: _meuNomeCurador,
        tipoContribuicao: 'texto',
        texto: texto,
        status: 'aprovado', // dono é quem está criando
        createdAt: DateTime.now(),
      );
      await SupabaseService.instance.salvarContribuicao(contrib);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Complemento adicionado à história.'),
          ),
        );
        _carregarMemoriasQuePodemCrescer();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar complemento: $e')),
        );
      }
    }
  }

  String get _meuNomeCurador {
    final user = SupabaseService.instance;
    // O nome é resolvido na contribuição via PessoaRepository.obterUsuario();
    // aqui devolvemos um placeholder caso ainda não tenha sido carregado.
    return 'Eu';
  }

  /// Helper para o callback de abrir memória a partir de cards da
  /// Home (que recebem apenas o id).
  Memoria _resolveMemoria(int id) {
    return widget.memorias.firstWhere(
      (m) => m.id == id,
      orElse: () => widget.memorias.isNotEmpty
          ? widget.memorias.first
          : Memoria(
              titulo: '',
              contexto: '',
              categoria: 'momentos',
              criadaEm: DateTime.now(),
            ),
    );
  }

  // Sprint L — Card de aniversário de memórias
  Widget _buildCardAniversario(PessoaVivaResumo p) {
    final anos = _aniversarioHoje[p.id] ?? 0;
    final plural = anos == 1 ? 'ano' : 'anos';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.dourado.withValues(alpha: 0.4),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.celebration, color: AppColors.dourado, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hoje faz $anos $plural que você compartilha memórias com ${p.nome.split(' ').first}.',
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${p.totalEventos} ${p.totalEventos == 1 ? "memória" : "memórias"} publicadas'
                  '${(_parentescoMap[p.id] ?? '').isNotEmpty ? ' · ${_parentescoMap[p.id]}' : ''}',
                  style: const TextStyle(
                    color: Color(0xFF7A7280),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Sprint J — Continuar / descartar sessão ativa do Curador
  Future<void> _retomarSessaoCurador() async {
    final s = _sessaoCuradorAtiva;
    if (s == null) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: s.titulo ?? '',
          contextoOriginal: s.contextoInicial,
          isProativo: false,
          complementoMemoriaId: s.memoriaId,
          sessaoParaRetomar: s,
        ),
      ),
    );
    _carregarSessaoCurador();
  }

  Future<void> _descartarSessaoCurador() async {
    final s = _sessaoCuradorAtiva;
    if (s == null) return;
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Text('Descartar conversa?',
            style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.bold)),
        content: const Text(
          'A conversa atual do Curador será apagada. Você pode começar uma nova quando quiser.',
          style: TextStyle(color: Color(0xFF625B67), fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar',
                style: TextStyle(color: Color(0xFF7A7280))),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Descartar'),
          ),
        ],
      ),
    );
    if (confirmou == true) {
      await CuradorSessaoService.instance.cancelarSessao(s.id!);
      _carregarSessaoCurador();
    }
  }

  // Sprint K — Card de "Conexão Descoberta" na Home.
  Widget _buildCardConexoes(MemoriaRelacionamento rel) {
    final legendas = rel.motivos.legendasHumanas;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.timeline_outlined, color: AppColors.dourado, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'O Curador encontrou uma conexão',
                  style: TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '"${rel.tituloOrigem ?? 'Memória'}" parece fazer parte da mesma fase de "${rel.tituloDestino ?? 'outra história'}".',
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 14,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          if (legendas.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...legendas.take(3).map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 12, color: AppColors.verdeApoio),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () async {
                  await MemoryRelationshipService.instance.ignorar(rel.id!);
                  _carregarConexoesPendentes();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A7280),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Nunca sugerir'),
              ),
              const SizedBox(width: 4),
              TextButton(
                onPressed: () async {
                  await MemoryRelationshipService.instance.ignorar(rel.id!);
                  _carregarConexoesPendentes();
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF7A7280),
                  visualDensity: VisualDensity.compact,
                ),
                child: const Text('Agora não'),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () async {
                  await MemoryRelationshipService.instance.confirmar(rel.id!);
                  _carregarConexoesPendentes();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                icon: const Icon(Icons.check, size: 14),
                label: const Text('Conectar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // S.9.4c (Item 9) — 5 itens: cada um ocupa 1/5 da largura, texto
    // encolhe em vez de cortar, espaçamento uniforme.
    return Expanded(
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.roxo, size: 22),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(label,
                  style: const TextStyle(
                      color: AppColors.roxo,
                      fontSize: 11,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _EstadoVazio extends StatelessWidget {
  const _EstadoVazio({required this.onRegistrar});
  final VoidCallback onRegistrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.borda),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0x26D4A84F),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_stories_outlined,
                size: 32, color: AppColors.dourado),
          ),
          const SizedBox(height: 20),
          const Text('Sua história começa aqui',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.roxo,
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text(
            'Registre sua primeira memória e comece a preservar\nmomentos importantes para sua família.',
            textAlign: TextAlign.center,
            style:
                TextStyle(color: Color(0xFF7A7280), fontSize: 14, height: 1.5),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRegistrar,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.roxo,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 46),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Criar primeira memória'),
          ),
        ],
      ),
    );
  }
}
