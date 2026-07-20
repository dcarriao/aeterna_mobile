import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:intl/intl.dart';

import '../curador/perguntas.dart';
import '../models/contribuicao.dart';
import '../models/memoria.dart';
import '../models/memoria_pode_crescer.dart';
import '../models/memoria_relacionamento.dart';
import '../models/pessoa.dart';
import '../services/memory_growth_invitation_service.dart';
import '../services/memory_growth_scoring_service.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import 'curador_screen.dart';
import 'memoria_contribuicao_screen.dart';
import 'nova_memoria_screen.dart';

class MemoriaDetalheScreen extends StatefulWidget {
  MemoriaDetalheScreen({
    required this.memoria,
    this.onEditar,
    this.somenteLeitura = false,
    this.memoriasConhecidas,
    this.onAbrirMemoria,
    super.key,
  });

  /// Quando true, oculta os controles de editar/excluir (usado para
  /// memórias recebidas de outra conta na tela Compartilhadas — Bug 1).
  final bool somenteLeitura;

  final Memoria memoria;
  final VoidCallback? onEditar; // Mantido para compatibilidade, mas faremos a navegação reativa interna

  /// Sprint K — Lista de memórias conhecidas (passada pela main)
  /// para que "Histórias relacionadas" possa navegar para a memória
  /// de destino ao tocar em "Ver história". Se não for passada,
  /// o card de relacionado aparece mas o botão "Ver" é omitido.
  final List<Memoria>? memoriasConhecidas;

  /// Callback de navegação para abrir uma memória relacionada. Default:
  /// usa o callback padrão do projeto.
  final void Function(Memoria)? onAbrirMemoria;

  @override
  State<MemoriaDetalheScreen> createState() => _MemoriaDetalheScreenState();
}

class _EventoTimeline {
  const _EventoTimeline({
    required this.ano,
    required this.titulo,
    required this.descricao,
    required this.autor,
    this.arquivoUrl,
    this.videoUrl,
    this.isOriginal = false,
  });

  final DateTime ano;
  final String titulo;
  final String descricao;
  final String autor;
  final String? arquivoUrl;
  final String? videoUrl;
  final bool isOriginal;
}

class _MemoriaDetalheScreenState extends State<MemoriaDetalheScreen> {
  late Memoria _memoria;
  List<Pessoa> _familiares = [];
  List<Pessoa> _participantes = [];
  String? _videoUrl;
  bool _carregandoDados = true;
  late AnaliseLegado _analise;

  // Sprint G — Enriquecimento Colaborativo
  final _supabase = SupabaseService.instance;
  List<Contribuicao> _contribuicoesAprovadas = [];
  List<Contribuicao> _contribuicoesPendentes = [];
  bool _aprovacaoObrigatoria = true;
  int _countPendentes = 0;

  // Sprint K — Histórias Relacionadas e Mapa da Vida
  List<MemoriaRelacionamento> _relacionados = const [];
  bool _carregandoRelacionados = true;

  bool get _souDono {
    final dono = _memoria.donoUsuarioId;
    final uid = SupabaseService.usuarioId;
    if (dono != null) return dono == uid;
    // Memória própria da lista sem dono preenchido: não é somente-leitura.
    return !widget.somenteLeitura && !_memoria.isRecebidaDeOutraConta;
  }

  /// Quem pode ENRIQUECER (criar contribuições). Dono sempre pode.
  /// Outros usuários só podem se forem colaboradores/editor (papel já
  /// garantido via `conteudo_colaboradores`) OU se a memória estiver
  /// compartilhada com eles (lista de 'memórias recebidas' da home).
  bool get _possoContribuir =>
      _souDono || !widget.somenteLeitura || _contribuicoesAprovadas.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _memoria = widget.memoria;
    _carregarDados();
    _analizarLegado();
  }

  void _analizarLegado() {
    _analise = const MotorPerguntas().analisarLegado(_memoria.contexto, {});
  }

  Future<void> _carregarDados() async {
    if (!mounted) return;
    setState(() => _carregandoDados = true);

    try {
      final todasAsPessoas = await PessoaRepository.listar();

      final famIds = _memoria.familiaresIds ??
          await PessoaRepository.obterFamiliaresDaMemoria(_memoria.id);

      final partIds = _memoria.pessoasIds ??
          await PessoaRepository.obterPessoasDaMemoria(_memoria.id);

      final videoUrl = _memoria.videoUrl ??
          await PessoaRepository.obterVideoDaMemoria(_memoria.id);

      // Sprint G — Enriquecimento: carregar contribuições + flag de aprovação
      // em paralelo com o restante.
      final futuros = <Future<dynamic>>[
        _supabase.listarContribuicoesDaMemoria(_memoria.id!),
        _supabase.memoriaExigeAprovacao(_memoria.id!),
      ];
      final results = await Future.wait(futuros);
      final todasContribuicoes = results[0] as List<Contribuicao>;
      final exigeAprovacao = results[1] as bool;
      final aprovadas =
          todasContribuicoes.where((c) => c.aprovado).toList(growable: false);
      final pendentes =
          todasContribuicoes.where((c) => c.pendente).toList(growable: false);

      if (mounted) {
        setState(() {
          _memoria = Memoria(
            id: _memoria.id,
            titulo: _memoria.titulo,
            contexto: _memoria.contexto,
            categoria: _memoria.categoria,
            criadaEm: _memoria.criadaEm,
            foto: _memoria.foto,
            fotoUrl: _memoria.fotoUrl,
            video: _memoria.video,
            videoUrl: videoUrl,
            // Preservar temVideo: rebuild sem ele (default false) apagava
            // o vídeo na Home/Timeline ao voltar do detalhe (pop(_memoria)).
            temVideo: _memoria.temVideo ||
                (videoUrl != null && videoUrl.isNotEmpty),
            pessoasIds: partIds,
            isCompartilhada: famIds.isNotEmpty,
            familiaresIds: famIds,
            dataMemoria: _memoria.dataMemoria,
            donoUsuarioId: _memoria.donoUsuarioId,
            compartilhadaPorNome: _memoria.compartilhadaPorNome,
          );
          _familiares = todasAsPessoas.where((p) => famIds.contains(p.id)).toList();
          _participantes = todasAsPessoas.where((p) => partIds.contains(p.id)).toList();
          _videoUrl = videoUrl;
          _contribuicoesAprovadas = aprovadas;
          _contribuicoesPendentes = pendentes;
          _countPendentes = pendentes.length;
          _aprovacaoObrigatoria = exigeAprovacao;
          _carregandoDados = false;
        });
      }
      // Sprint K — Carrega as relações já persistidas (sem O(n²)).
      if (!mounted) return;
      if (_memoria.id != null) {
        final rels = await MemoryRelationshipService.instance
            .listarRelacionamentosConfirmados(_memoria.id!);
        if (mounted) {
          setState(() {
            _relacionados = rels;
            _carregandoRelacionados = false;
          });
        }
      } else {
        if (mounted) {
          setState(() => _carregandoRelacionados = false);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _carregandoDados = false;
          _carregandoRelacionados = false;
        });
      }
    }
  }

  Future<void> _editarHistoria() async {
    final atualizada = await Navigator.of(context).push<Memoria>(
      MaterialPageRoute(
        builder: (_) => NovaMemoriaScreen(
          onSalvar: (r) async => _memoria, // não usado no edit
          memoria: _memoria,
          onEditar: (_) async => null,
        ),
      ),
    );

    if (atualizada != null && mounted) {
      setState(() {
        _memoria = atualizada;
      });
      _analizarLegado();
      _carregarDados();
    }
  }

  Future<void> _excluirHistoria() async {
    final m = _memoria;
    if (m.id == null) return;

    final confirmou = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir história', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        content: const Text('Tem certeza de que deseja excluir esta história do seu legado para sempre? Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancelar', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w700)),
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
      setState(() => _carregandoDados = true);
      try {
        await PessoaRepository.excluirMemoriaCompleta(m.id!);
        if (mounted) Navigator.of(context).pop('deletada');
      } catch (_) {
        if (mounted) {
          setState(() => _carregandoDados = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não foi possível excluir a história.')),
          );
        }
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SPRINT G — Ações de enriquecimento colaborativo da memória
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _abrirTelaContribuicao() async {
    if (_memoria.id == null) return;
    final enviou = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => MemoriaContribuicaoScreen(
          memoriaId: _memoria.id!,
          memoriaTitulo: _memoria.titulo,
          usuarioDonoId: _souDono ? SupabaseService.usuarioId : (_memoria.donoUsuarioId ?? SupabaseService.usuarioId),
          aprovacaoObrigatoria: _aprovacaoObrigatoria,
        ),
      ),
    );
    if (enviou == true) {
      _carregarDados();
    }
  }

  Future<void> _moderarContribuicaoMemoria(Contribuicao c, bool aprovado) async {
    if (!_souDono) return;
    try {
      await _supabase.moderarContribuicao(
        c.id!,
        aprovado,
        avaliadoPor: SupabaseService.usuarioId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(aprovado
              ? 'Contribuição aprovada — agora aparece na história.'
              : 'Contribuição rejeitada.')),
        );
      }
      _carregarDados();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao moderar: $e')),
        );
      }
    }
  }

  // ════════════════════════════════════════════════════════════════════════
  // SPRINT I — BANNER "ESSA MEMÓRIA PODE CRESCER" NA DETALHE
  // ════════════════════════════════════════════════════════════════════════
  MemoriaComScore? _conviteCuradorComplemento;
  bool _carregandoConviteComplemento = false;

  Future<void> _carregarConviteComplemento() async {
    if (_memoria.id == null) return;
    if (_conviteCuradorComplemento != null) return; // já carregado
    setState(() => _carregandoConviteComplemento = true);
    final convite = await MemoryGrowthInvitationService.instance
        .obterParaMemoria(_memoria.id!);
    if (mounted) {
      setState(() {
        _conviteCuradorComplemento = convite;
        _carregandoConviteComplemento = false;
      });
    }
  }

  Future<void> _dispensarConviteComplemento() async {
    if (_conviteCuradorComplemento == null) return;
    await MemoryGrowthScoringService.instance
        .dispensarConvite(_conviteCuradorComplemento!.memoria.memoriaId);
    if (mounted) {
      setState(() => _conviteCuradorComplemento = null);
    }
  }

  Future<void> _abrirCuradorComplemento() async {
    if (_conviteCuradorComplemento == null || _memoria.id == null) return;
    final result = await Navigator.of(context).push<CuradorResultado>(
      MaterialPageRoute(
        builder: (_) => CuradorScreen(
          titulo: _memoria.titulo,
          contextoOriginal: _memoria.contexto,
          isProativo: false,
          complementoMemoriaId: _memoria.id,
        ),
      ),
    );
    if (result == null) return;
    final texto = result.contextoEnriquecido.trim();
    if (texto.isEmpty) return;
    try {
      final dados = await PessoaRepository.obterUsuario();
      final nome = dados != null
          ? '${dados['nome'] ?? ''} ${dados['sobrenome'] ?? ''}'.trim()
          : 'Eu';
      final contrib = Contribuicao(
        tipoConteudo: 'memoria',
        conteudoId: _memoria.id!,
        usuarioDonoId: _memoria.donoUsuarioId ?? SupabaseService.usuarioId,
        usuarioContribuidorEmail: PessoaRepository.usuarioEmail ?? '',
        usuarioContribuidorNome: nome.isEmpty ? 'Eu' : nome,
        tipoContribuicao: 'texto',
        texto: texto,
        status: 'aprovado',
        createdAt: DateTime.now(),
      );
      await SupabaseService.instance.salvarContribuicao(contrib);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complemento adicionado à história.')),
        );
        setState(() => _conviteCuradorComplemento = null);
        _carregarDados();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar complemento: $e')),
        );
      }
    }
  }

  Widget _buildBannerCuradorComplemento() {
    // Carregamento preguiçoso
    if (_conviteCuradorComplemento == null && !_carregandoConviteComplemento) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _carregarConviteComplemento();
      });
    }

    if (_carregandoConviteComplemento) return const SizedBox.shrink();
    if (_conviteCuradorComplemento == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFF9F6F0),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.dourado.withValues(alpha: 0.4),
            width: 1.5,
          ),
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
                    'O Curador sugere complementar esta história',
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
              _motivoConviteComplemento(),
              style: const TextStyle(
                color: Color(0xFF625B67),
                fontSize: 13,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _dispensarConviteComplemento,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7A7280),
                  ),
                  child: const Text(
                    'Agora não',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _abrirCuradorComplemento,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roxo,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.edit_note, size: 16),
                  label: const Text(
                    'Complementar',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _motivoConviteComplemento() {
    final positivos = _conviteCuradorComplemento!.score.criterios
        .where((c) => c.pontos > 0)
        .map((c) => c.nome.toLowerCase())
        .toList();
    if (positivos.isEmpty) return 'O Curador percebeu que esta história pode crescer.';
    if (positivos.any((p) => p.contains('colaborador'))) {
      return 'Existem familiares cadastrados para essa história que ainda não contribuíram.';
    }
    if (positivos.any((p) => p.contains('autor único'))) {
      return 'Esta história foi escrita só por você. Convidar outra pessoa pode enriquecê-la.';
    }
    if (positivos.any((p) => p.contains('muitas mídias'))) {
      return 'Vimos mídias na galeria que ainda não foram associadas a essa história.';
    }
    if (positivos.any((p) => p.contains('última atualização'))) {
      return 'Esta história não é atualizada há mais de 90 dias. Talvez valha a pena revisitá-la.';
    }
    return 'O Curador percebeu que esta história pode crescer.';
  }

  Widget _buildSecaoEvolucao() {
    if (_carregandoDados) return const SizedBox.shrink();

    // Cabeçalho sempre visível.
    final children = <Widget>[
      Row(
        children: [
          const Icon(Icons.history_edu_outlined, color: AppColors.dourado, size: 20),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Evolução da memória',
              style: TextStyle(
                color: AppColors.roxo,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (_souDono && _countPendentes > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.redAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_countPendentes pendente${_countPendentes == 1 ? '' : 's'}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
        ],
      ),
      const SizedBox(height: 6),
      const Text(
        'Como a história foi crescendo ao longo do tempo com a contribuição de quem viveu esse momento.',
        style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
      ),
      const SizedBox(height: 16),
    ];

    // Linha do tempo: criação original + contribuições aprovadas (ordem
    // cronológica). Pendentes ficam em bloco separado abaixo, visível só
    // para o dono.
    final eventos = <_EventoTimeline>[
      _EventoTimeline(
        ano: _memoria.criadaEm,
        titulo: 'Memória criada',
        descricao: 'História original escrita.',
        autor: _memoria.compartilhadaPorNome ?? 'Dono da história',
        isOriginal: true,
      ),
      for (final c in _contribuicoesAprovadas)
        _EventoTimeline(
          ano: c.createdAt,
          titulo: _tituloParaContribuicao(c),
          descricao: c.texto ?? '',
          autor: c.usuarioContribuidorNome,
          arquivoUrl: c.tipoContribuicao == 'foto' ? c.arquivoUrl : null,
          videoUrl: c.tipoContribuicao == 'video' ? c.arquivoUrl : null,
        ),
    ];

    eventos.sort((a, b) => a.ano.compareTo(b.ano));

    for (final e in eventos) {
      children.add(_buildItemTimeline(e));
    }

    // Bloco de moderação para o dono: contribuições pendentes.
    // Autor também vê as próprias pendentes (antes "sumiam" para todos
    // porque _souDono era false sem donoUsuarioId nas memórias próprias).
    final emailSessao = PessoaRepository.usuarioEmail?.toLowerCase() ?? '';
    final pendentesVisiveis = _souDono
        ? _contribuicoesPendentes
        : _contribuicoesPendentes
            .where((c) =>
                emailSessao.isNotEmpty &&
                c.usuarioContribuidorEmail.toLowerCase() == emailSessao)
            .toList();
    if (pendentesVisiveis.isNotEmpty) {
      children.add(const SizedBox(height: 24));
      children.add(const Divider());
      children.add(const SizedBox(height: 16));
      children.add(
        Text(
          _souDono
              ? 'Contribuições aguardando aprovação'
              : 'Suas contribuições aguardando aprovação',
          style: const TextStyle(
            color: AppColors.roxo,
            fontSize: 15,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      children.add(const SizedBox(height: 4));
      children.add(
        Text(
          _souDono
              ? 'Aprove ou rejeite contribuições dos seus familiares para que passem a fazer parte da história.'
              : 'O dono da memória ainda precisa aprovar. Elas continuam salvas.',
          style: const TextStyle(color: Color(0xFF7A7280), fontSize: 12, height: 1.4),
        ),
      );
      children.add(const SizedBox(height: 12));
      for (final c in pendentesVisiveis) {
        children.add(_buildCardContribuicaoPendente(c));
      }
    }

    if (_contribuicoesAprovadas.isEmpty &&
        _contribuicoesPendentes.isEmpty &&
        eventos.length <= 1) {
      children.add(
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.borda),
          ),
          child: const Row(
            children: [
              Icon(Icons.family_restroom_outlined, color: AppColors.dourado),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Esta história ainda não foi enriquecida por outras pessoas. Convide familiares para começar.',
                  style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  String _tituloParaContribuicao(Contribuicao c) {
    switch (c.tipoContribuicao) {
      case 'foto':
        return 'Foto adicionada';
      case 'video':
        return 'Vídeo adicionado';
      case 'audio':
        return 'Áudio adicionado';
      default:
        return 'Lembrança escrita';
    }
  }

  String _formatarMes(DateTime data) {
    const meses = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    return '${meses[data.month - 1]} ${data.year}';
  }

  Widget _buildItemTimeline(_EventoTimeline e) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: e.isOriginal ? AppColors.roxo : AppColors.dourado,
                  shape: BoxShape.circle,
                ),
              ),
              Container(
                width: 2,
                height: e.isOriginal && e.descricao.isEmpty ? 0 : 80,
                color: AppColors.borda,
                margin: const EdgeInsets.symmetric(vertical: 4),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatarMes(e.ano),
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  e.titulo,
                  style: TextStyle(
                    color: e.isOriginal ? AppColors.roxo : AppColors.roxo,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (e.descricao.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    e.descricao,
                    style: const TextStyle(
                      color: Color(0xFF625B67),
                      fontSize: 13,
                      height: 1.4,
                    ),
                  ),
                ],
                if (e.arquivoUrl != null) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      e.arquivoUrl!,
                      width: double.infinity,
                      height: 160,
                      fit: BoxFit.cover,
                      alignment: Alignment.topCenter,
                      errorBuilder: (_, _, _) => Container(
                        height: 100,
                        color: const Color(0xFFF0EAF5),
                        child: const Center(
                          child: Icon(Icons.image_not_supported_outlined,
                              color: AppColors.roxo),
                        ),
                      ),
                    ),
                  ),
                ],
                if (e.videoUrl != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EAF5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.borda),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.movie_outlined, color: AppColors.roxo),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Vídeo da contribuição de ${e.autor}',
                            style: const TextStyle(
                              color: AppColors.roxo,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  'por ${e.autor}',
                  style: const TextStyle(
                    color: Color(0xFF9B949D),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════
  // SPRINT K — HISTÓRIAS RELACIONADAS
  // ════════════════════════════════════════════════════════════════════════
  Widget _buildSecaoRelacionados() {
    if (_carregandoRelacionados) {
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
    if (_relacionados.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: const [
            Icon(Icons.timeline_outlined, color: AppColors.dourado, size: 20),
            SizedBox(width: 8),
            Text(
              'Histórias relacionadas',
              style: TextStyle(
                color: AppColors.roxo,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Outras memórias que fazem parte desta fase da sua vida.',
          style: TextStyle(color: Color(0xFF7A7280), fontSize: 13, height: 1.4),
        ),
        const SizedBox(height: 16),
        ..._relacionados.map((r) => _buildCardRelacionado(r)),
      ],
    );
  }

  Widget _buildCardRelacionado(MemoriaRelacionamento r) {
    final outroId = r.memoriaOrigemId == _memoria.id
        ? r.memoriaDestinoId
        : r.memoriaOrigemId;
    final outroTitulo = r.memoriaOrigemId == _memoria.id
        ? (r.tituloDestino ?? '')
        : (r.tituloOrigem ?? '');
    final legendas = r.motivos.legendasHumanas;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
            children: [
              Expanded(
                child: Text(
                  outroTitulo.isEmpty ? 'Outra história' : outroTitulo,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0x1AD4A84F),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Conexão ${r.score}%',
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          if (legendas.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...legendas.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          size: 14, color: AppColors.verdeApoio),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s,
                          style: const TextStyle(
                            color: Color(0xFF625B67),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: () => _abrirMemoriaRelacionada(outroId),
              icon: const Icon(Icons.arrow_forward, size: 14),
              label: const Text(
                'Ver história',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _abrirMemoriaRelacionada(int outroId) {
    final mems = widget.memoriasConhecidas;
    final callback = widget.onAbrirMemoria;
    if (mems == null || callback == null) return;
    final m = mems.cast<Memoria?>().firstWhere(
          (x) => x?.id == outroId,
          orElse: () => null,
        );
    if (m == null) return;
    callback(m);
  }

  Widget _buildCardContribuicaoPendente(Contribuicao c) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4A84F).withValues(alpha: 0.5), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.hourglass_top_outlined, color: AppColors.dourado, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.usuarioContribuidorNome,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _tituloParaContribuicao(c),
                style: const TextStyle(
                  color: AppColors.dourado,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (c.texto != null && c.texto!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              c.texto!,
              style: const TextStyle(color: Color(0xFF625B67), fontSize: 13, height: 1.4),
            ),
          ],
          if (c.tipoContribuicao == 'foto' && c.arquivoUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                c.arquivoUrl!,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_souDono)
            // Theme global usa minimumSize: Size.fromHeight(54) (largura
            // infinita) — FilledButton.icon num Row overflowa e o Aprovar
            // some; override finite + Wrap garante os dois botões.
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _moderarContribuicaoMemoria(c, false),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                      side: const BorderSide(color: Colors.redAccent),
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Rejeitar'),
                  ),
                  FilledButton.icon(
                    onPressed: () => _moderarContribuicaoMemoria(c, true),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.verdeApoio,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Aprovar'),
                  ),
                ],
              ),
            )
          else
            const Text(
              'Aguardando aprovação do dono da memória.',
              style: TextStyle(
                color: AppColors.dourado,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(_memoria),
        ),
        actions: [
          if (!widget.somenteLeitura)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.roxo),
              tooltip: 'Excluir história',
              onPressed: _carregandoDados ? null : _excluirHistoria,
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregandoDados
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                    children: [
                      // ── HERO IMAGE (contain: foto inteira, sem cortar cabeça) ──
                      if (_memoria.foto != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: const Color(0xFFF0EAF5),
                            child: Image.memory(
                              _memoria.foto!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                            ),
                          ),
                        )
                      else if (_memoria.fotoUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: ColoredBox(
                            color: const Color(0xFFF0EAF5),
                            child: Image.network(
                              _memoria.fotoUrl!,
                              fit: BoxFit.contain,
                              width: double.infinity,
                              errorBuilder: (_, _, _) => Container(
                                height: 180,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF0EAF5),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Center(
                                  child: Icon(
                                    Icons.image_not_supported_outlined,
                                    color: AppColors.roxo,
                                    size: 48,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (_memoria.foto != null || _memoria.fotoUrl != null)
                        const SizedBox(height: 24),

                      // ── RECEBIDA DE OUTRA CONTA (Bug 1) ──
                      if (_memoria.isRecebidaDeOutraConta) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0x262B1747),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.people_alt_outlined,
                                      size: 14, color: AppColors.roxo),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Compartilhada por '
                                    '${_memoria.compartilhadaPorNome ?? 'Familiar'}',
                                    style: const TextStyle(
                                      color: AppColors.roxo,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── COMPARTILHADA BADGE ──
                      if (_memoria.isCompartilhada) ...[
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0x26D4A84F),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.share_outlined,
                                      size: 14, color: AppColors.dourado),
                                  SizedBox(width: 6),
                                  Text(
                                    'Compartilhada',
                                    style: TextStyle(
                                      color: AppColors.dourado,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],

                      // ── TITULO ──
                      Text(
                        _memoria.titulo,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          height: 1.2,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── DATA / LOCAL / CATEGORIA ──
                      Row(
                        children: [
                          const Icon(
                            Icons.calendar_today_outlined,
                            size: 14,
                            color: AppColors.dourado,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            DateFormat('dd/MM/yyyy').format(_memoria.criadaEm),
                            style: const TextStyle(
                              color: Color(0xFF817987),
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 14),
                          _CategoriaBadge(categoria: _memoria.categoria),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // ── CARD 1: HISTÓRIA / NARRATIVA ──
                      _DetalheCard(
                        icon: Icons.menu_book_outlined,
                        titulo: 'A história',
                        color: AppColors.roxo,
                        child: Text(
                          _limparEFormatarTexto(_memoria.contexto),
                          style: const TextStyle(
                            color: Color(0xFF625B67),
                            fontSize: 15,
                            height: 1.6,
                          ),
                        ),
                      ),

                      // ── CARD VÍDEO (Se existir) ──
                      if (_videoUrl != null) ...[
                        const SizedBox(height: 16),
                        _DetalheCard(
                          icon: Icons.video_library_outlined,
                          titulo: 'Vídeo da memória',
                          color: AppColors.roxo,
                          child: _VideoInline(url: _videoUrl!),
                        ),
                      ],

                      // ── CARD 2: PARTICIPANTES ──
                      if (_participantes.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DetalheCard(
                          icon: Icons.people_outline,
                          titulo: 'Quem participou',
                          color: AppColors.dourado,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _participantes.map((p) {
                              return Chip(
                                avatar: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: const Color(0xFFF0EAF5),
                                  backgroundImage: p.fotoBytes != null
                                      ? MemoryImage(p.fotoBytes!)
                                      : null,
                                  child: p.fotoBytes == null
                                      ? const Icon(Icons.person,
                                          size: 14, color: AppColors.roxo)
                                      : null,
                                ),
                                label: Text(p.nome,
                                    style: const TextStyle(fontSize: 12)),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // ── CARD 3: VALORES ──
                      if (_analise.valores.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DetalheCard(
                          icon: Icons.favorite_outline,
                          titulo: 'Valores revelados',
                          color: Colors.red.shade400,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _analise.valores.map((v) {
                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF5E6E8),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  v,
                                  style: const TextStyle(
                                    color: Color(0xFF8B5E6B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // ── CARD 4: APRENDIZADOS ──
                      if (_analise.aprendizados.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DetalheCard(
                          icon: Icons.lightbulb_outline,
                          titulo: 'Aprendizados',
                          color: AppColors.verdeApoio,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _analise.aprendizados.map((a) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Padding(
                                      padding: EdgeInsets.only(top: 2),
                                      child: Icon(Icons.check,
                                          size: 14,
                                          color: AppColors.verdeApoio),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        a,
                                        style: const TextStyle(
                                          color: Color(0xFF625B67),
                                          fontSize: 14,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      // ── CARD COMPARTILHADO COM ──
                      if (_familiares.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _DetalheCard(
                          icon: Icons.share_outlined,
                          titulo: 'Compartilhada com',
                          color: AppColors.dourado,
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _familiares.map((f) {
                              return Chip(
                                avatar: CircleAvatar(
                                  radius: 12,
                                  backgroundColor: const Color(0xFFF0EAF5),
                                  backgroundImage: f.fotoBytes != null
                                      ? MemoryImage(f.fotoBytes!)
                                      : null,
                                  child: f.fotoBytes == null
                                      ? const Icon(Icons.person,
                                          size: 14, color: AppColors.roxo)
                                      : null,
                                ),
                                label: Text(f.nome, style: const TextStyle(fontSize: 13)),
                                visualDensity: VisualDensity.compact,
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 28),

                      // ═════════════════════════════════════════════════════════
                      // SPRINT I — CONVITE DO CURADOR PARA COMPLEMENTO
                      // ═════════════════════════════════════════════════════════
                      if (!_carregandoDados && widget.somenteLeitura == false)
                        _buildBannerCuradorComplemento(),

                      // ═════════════════════════════════════════════════════════
                      // SPRINT G — ENRIQUECIMENTO COLABORATIVO DA MEMÓRIA
                      // ═════════════════════════════════════════════════════════

                      // ── 1. Botão principal do DONO: Editar história original ──
                      if (!widget.somenteLeitura)
                        FilledButton.icon(
                          onPressed: _editarHistoria,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.roxo,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: const Text('Editar história'),
                        ),

                      // ── 2. SEÇÃO EVOLUÇÃO DA MEMÓRIA ──
                      const SizedBox(height: 32),
                      _buildSecaoEvolucao(),

                      // ── 2.5 SPRINT K — HISTÓRIAS RELACIONADAS ──
                      const SizedBox(height: 24),
                      _buildSecaoRelacionados(),

                      // ── 3. Botão "Contribuir" (discreto, abaixo da evolução) ──
                      if (!_carregandoDados && _memoria.id != null) ...[
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _abrirTelaContribuicao,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.roxo,
                            side: const BorderSide(color: AppColors.roxo, width: 1.4),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            minimumSize: const Size.fromHeight(50),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          icon: const Icon(Icons.add_circle_outline, size: 18),
                          label: const Text(
                            'Contribuir com esta história',
                            style: TextStyle(fontWeight: FontWeight.w700),
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

  String _limparEFormatarTexto(String texto) {
    final linhas = texto.split('\n');
    final unicas = <String>[];
    for (var linha in linhas) {
      final l = linha.trim();
      if (l == '---' || l == '***' || l == '...' || l.isEmpty) continue;
      if (!unicas.contains(l)) {
        unicas.add(l);
      }
    }
    return unicas.join('\n\n');
  }
}

class _DetalheCard extends StatelessWidget {
  const _DetalheCard({
    required this.icon,
    required this.titulo,
    required this.color,
    required this.child,
  });

  final IconData icon;
  final String titulo;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Text(
                titulo,
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _CategoriaBadge extends StatelessWidget {
  const _CategoriaBadge({required this.categoria});
  final String categoria;

  String get _label => switch (categoria) {
        'familia' => 'Família',
        'aprendizados' => 'Aprendizados',
        'viagens' => 'Viagens',
        'tradicoes' => 'Tradições',
        _ => 'Momentos',
      };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6E8),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(_label,
          style: const TextStyle(
              color: Color(0xFF8B5E6B),
              fontSize: 12,
              fontWeight: FontWeight.w600)),
    );
  }
}

/// S.9.3.2 (Item 7) — player inline: o vídeo APARECE na memória
/// (antes, só um diálogo com a URL). Toque para reproduzir/pausar.
class _VideoInline extends StatefulWidget {
  const _VideoInline({required this.url});
  final String url;

  @override
  State<_VideoInline> createState() => _VideoInlineState();
}

class _VideoInlineState extends State<_VideoInline> {
  VideoPlayerController? _ctrl;
  bool _erro = false;

  @override
  void initState() {
    super.initState();
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    _ctrl = c;
    c.initialize().then((_) {
      if (mounted) setState(() {});
    }).catchError((e) {
      print('[VIDEO] erro ao inicializar: $e');
      if (mounted) setState(() => _erro = true);
    });
    c.setLooping(false);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _ctrl;
    if (_erro) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('Não foi possível carregar o vídeo.',
            style: TextStyle(color: Color(0xFF7A7280))),
      );
    }
    if (c == null || !c.value.isInitialized) {
      return const SizedBox(
        height: 180,
        child: Center(
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.roxo),
        ),
      );
    }
    return Column(
      children: [
        GestureDetector(
          onTap: () => setState(
              () => c.value.isPlaying ? c.pause() : c.play()),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                AspectRatio(
                  aspectRatio:
                      c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
                  child: VideoPlayer(c),
                ),
                if (!c.value.isPlaying)
                  Container(
                    decoration: const BoxDecoration(
                      color: Colors.black45,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(14),
                    child: const Icon(Icons.play_arrow,
                        color: Colors.white, size: 36),
                  ),
              ],
            ),
          ),
        ),
        VideoProgressIndicator(c, allowScrubbing: true,
            padding: const EdgeInsets.only(top: 8)),
      ],
    );
  }
}
