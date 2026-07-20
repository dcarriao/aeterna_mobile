import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../models/contribuicao.dart';
import '../models/curador_resposta_ia.dart';
import '../models/curador_sessao.dart';
import '../models/detected_moment.dart';
import '../models/memoria_relacionamento.dart';
import '../models/pending_memory.dart';
import '../models/pessoa.dart';
import '../curador/perguntas.dart';
import '../services/curador_sessao_service.dart';
import '../services/legacy_curator_service.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Sprint J — Resultado do Curador devolvido à `NovaMemoriaScreen`.
/// Inclui o contexto consolidado e a sessão persistida (para que
/// a Home possa oferecer "continuar conversa" se o usuário
/// descartar sem salvar).
class CuradorResultado {
  const CuradorResultado({
    required this.contextoEnriquecido,
    this.sessaoId,
  });

  final String contextoEnriquecido;
  final int? sessaoId;
}

/// Curador Contextual — Sprint J. Conversa com memória de contexto
/// (histórico completo enviado à OpenAI), persistida entre
/// fechamentos de app, e que termina naturalmente quando a IA sinaliza
/// "já temos material suficiente".
class CuradorScreen extends StatefulWidget {
  const CuradorScreen({
    required this.titulo,
    required this.contextoOriginal,
    this.pessoas,
    this.dataMemoria,
    this.categoria,
    this.isProativo = false,
    this.proativoMediaBytes,
    this.proativoMediaIsVideo = false,
    this.proativoFotosCount = 0,
    this.proativoVideosCount = 0,
    this.pendingMemory,
    this.detectedMoment,
    this.complementoMemoriaId,
    this.sessaoParaRetomar, // Sprint J: se já existe sessão, retoma
    super.key,
  });

  final String titulo;
  final String contextoOriginal;
  final List<Map<String, String>>? pessoas;
  final DateTime? dataMemoria;
  final String? categoria;
  final bool isProativo;
  final Uint8List? proativoMediaBytes;
  final bool proativoMediaIsVideo;
  final int proativoFotosCount;
  final int proativoVideosCount;
  final PendingMemory? pendingMemory;
  final DetectedMoment? detectedMoment;

  /// Sprint I — Modo Complemento. Quando fornecido, a CuradorScreen
  /// entra em um modo especial: carrega a memória existente
  /// (contribuições, pessoas vinculadas).
  final int? complementoMemoriaId;

  /// Sprint J — Se fornecido, a CuradorScreen retoma a conversa
  /// exatamente de onde parou (carrega todas as mensagens do
  /// histórico e continua a partir da próxima pergunta da IA).
  final CuradorSessao? sessaoParaRetomar;

  @override
  State<CuradorScreen> createState() => _CuradorScreenState();
}

class _CuradorScreenState extends State<CuradorScreen> {
  final _sessaoService = CuradorSessaoService.instance;
  final _legacyService = LegacyCuratorService.instance;
  final _supabaseService = SupabaseService.instance;
  final _controller = TextEditingController();

  // Estado da conversa (Sprint J)
  int? _sessaoId;
  final List<CuradorMensagem> _historico = []; // mensagens já trocadas
  String _perguntaAtual = '';
  bool _carregandoPergunta = false;
  bool _iniciouConversa = true;
  bool _deveEncerrar = false; // sinalizado pela IA
  bool _solicitandoFinalizacao = false; // aguardando user aceitar
  bool _concluiu = false; // user disse "não, pode encerrar"
  String? _narrativa;
  AnaliseLegado? _analiseLegado;

  // Pessoas carregadas no modo complemento (Sprint I)
  int _contribuicoesAprovadasCount = 0;
  List<Map<String, String>>? _pessoasCarregadas;
  DateTime? _dataMemoriaCarregada;
  String? _categoriaCarregada;

  // Sprint K — Histórias relacionadas (modo complemento)
  List<MemoriaRelacionamento> _relacionadosComplemento = const [];

  @override
  void initState() {
    super.initState();
    // S.9.3.2 — CAUSA RAIZ do botão Responder desabilitado: o onPressed
    // depende de _controller.text, mas nada reconstruía o widget ao
    // digitar. Listener força rebuild e o botão habilita.
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
    _iniciouConversa = widget.pendingMemory == null && widget.detectedMoment == null;

    if (widget.sessaoParaRetomar != null) {
      _retomarSessao();
    } else if (widget.complementoMemoriaId != null) {
      _carregarContextoComplemento();
    } else {
      _iniciarNovaSessao();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // ════════════════════════════════════════════════════════════════════════
  // Sprint J — Iniciar / retomar sessão
  // ════════════════════════════════════════════════════════════════════════

  Future<void> _retomarSessao() async {
    final sessao = widget.sessaoParaRetomar!;
    if (sessao.id == null) {
      _iniciarNovaSessao();
      return;
    }
    setState(() {
      _sessaoId = sessao.id;
      _carregandoPergunta = true;
    });
    final mensagens = await _sessaoService.listarMensagens(sessao.id!);

    // Pega a última pergunta do assistente (a próxima a exibir).
    String? ultimaPergunta;
    for (var i = mensagens.length - 1; i >= 0; i--) {
      if (mensagens[i].role == CuradorMensagemRole.assistant) {
        ultimaPergunta = mensagens[i].conteudo;
        break;
      }
    }

    if (!mounted) return;
    setState(() {
      _historico.addAll(mensagens);
      _perguntaAtual = ultimaPergunta ?? '';
      _carregandoPergunta = false;
    });
  }

  Future<void> _iniciarNovaSessao() async {
    setState(() {
      _carregandoPergunta = true;
      _iniciouConversa = false; // mostra tela de proposta primeiro
    });
  }

  Future<void> _comecarConversa() async {
    setState(() {
      _iniciouConversa = true;
      _carregandoPergunta = true;
    });
    await _criarSessaoEGerarPrimeiraPergunta();
  }

  Future<void> _criarSessaoEGerarPrimeiraPergunta() async {
    // Modo Complemento (Sprint I): contexto carregado primeiro
    if (widget.complementoMemoriaId != null) {
      await _carregarContextoComplemento();
    }

    final sessaoId = await _sessaoService.criarSessao(
      titulo: widget.titulo,
      contextoInicial: widget.contextoOriginal,
      dataEvento: widget.dataMemoria ?? _dataMemoriaCarregada,
      pessoas: widget.pessoas ?? _pessoasCarregadas ?? const [],
      memoriaId: widget.complementoMemoriaId,
    );
    if (sessaoId == null) {
      if (mounted) {
        setState(() => _carregandoPergunta = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não foi possível iniciar a sessão do Curador.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      _sessaoId = sessaoId;
      _carregandoPergunta = true;
    });

    // Adiciona a primeira mensagem do usuário (a memória inicial).
    if (widget.contextoOriginal.trim().isNotEmpty) {
      await _sessaoService.adicionarMensagem(
        sessaoId: sessaoId,
        role: CuradorMensagemRole.user,
        conteudo: widget.contextoOriginal,
        tipo: CuradorMensagemTipo.inicial,
      );
      _historico.add(CuradorMensagem(
        sessaoId: sessaoId,
        role: CuradorMensagemRole.user,
        conteudo: widget.contextoOriginal,
        ordem: 1,
        tipo: CuradorMensagemTipo.inicial,
      ));
    }

    await _gerarProximaPergunta();
  }

  Future<void> _carregarContextoComplemento() async {
    if (widget.complementoMemoriaId == null) return;
    try {
      final id = widget.complementoMemoriaId!;
      final todasMemorias = await _supabaseService.listarMemorias();
      final m = todasMemorias.firstWhere(
        (mm) => mm.id == id,
        orElse: () => todasMemorias.first,
      );

      final contribs = await _supabaseService
          .listarContribuicoesDaMemoria(id, apenasAprovadas: true);
      _contribuicoesAprovadasCount = contribs.length;

      final ids = await PessoaRepository.obterPessoasDaMemoria(id);
      final todasPessoas = await PessoaRepository.listar();
      _pessoasCarregadas = todasPessoas
          .where((p) => ids.contains(p.id))
          .map((p) => {'nome': p.nome, 'parentesco': p.parentesco})
          .toList();
      _dataMemoriaCarregada = m.dataMemoria;
      _categoriaCarregada = m.categoria;

      // Sprint K — carrega relações confirmadas para mencionar
      // memórias parecidas no Curador (sem IA, só heurística
      // já persistida).
      _relacionadosComplemento = await MemoryRelationshipService.instance
          .listarRelacionamentosConfirmados(id);
    } catch (e) {
      print('[CuradorScreen] _carregarContextoComplemento ERRO: $e');
    }
  }

  Future<void> _gerarProximaPergunta() async {
    if (_sessaoId == null) return;
    setState(() => _carregandoPergunta = true);

    final resposta = await _legacyService.proximaPerguntaAdaptativa(
      contextoInicial: widget.contextoOriginal,
      titulo: widget.complementoMemoriaId != null
          ? 'Complemento de história'
          : widget.titulo,
      dataMemoria: widget.dataMemoria ?? _dataMemoriaCarregada,
      categoria: widget.categoria ?? _categoriaCarregada,
      pessoas: widget.pessoas ?? _pessoasCarregadas ?? const [],
      historico: _historico
          .map((m) => CuradorMensagemDTO(
                role: m.role.valor,
                conteudo: m.conteudo,
                tipo: m.tipo?.name,
              ))
          .toList(),
    );

    if (resposta == null) {
      // Fallback: usar o motor local. Mantém a conversa fluindo
      // mesmo se a OpenAI falhar.
      final perguntas = const MotorPerguntas().selecionar(
        widget.contextoOriginal,
        temPessoas: (widget.pessoas ?? _pessoasCarregadas ?? const [])
            .isNotEmpty,
        temData: widget.dataMemoria != null,
      );
      final fallback = widget.complementoMemoriaId != null
          ? 'Como esse novo momento se conecta com o que você já guardou?'
          : 'Conte um pouco mais sobre o que você viveu.';
      final proxima = perguntas.isNotEmpty ? perguntas.first.texto : fallback;
      _persistirPerguntaIA(proxima, false);
      return;
    }

    _persistirPerguntaIA(resposta.pergunta, resposta.deveEncerrar);
  }

  Future<void> _persistirPerguntaIA(String pergunta, bool deveEncerrar) async {
    final sessaoId = _sessaoId!;
    // IA respondeu com despedida mas sem ENCERRAR:sim — trata como fim.
    final encerrar = deveEncerrar || _ehDespedidaDaIa(pergunta);
    await _sessaoService.adicionarMensagem(
      sessaoId: sessaoId,
      role: CuradorMensagemRole.assistant,
      conteudo: pergunta,
      tipo: encerrar
          ? CuradorMensagemTipo.finalizacao
          : CuradorMensagemTipo.pergunta,
    );
    if (!mounted) return;
    final ordem = _historico.length + 1;
    setState(() {
      _historico.add(CuradorMensagem(
        sessaoId: sessaoId,
        role: CuradorMensagemRole.assistant,
        conteudo: pergunta,
        ordem: ordem,
        tipo: encerrar
            ? CuradorMensagemTipo.finalizacao
            : CuradorMensagemTipo.pergunta,
      ));
      _perguntaAtual = pergunta;
      _deveEncerrar = encerrar;
      _carregandoPergunta = false;
    });
    // Despedida da IA → abre preview imediatamente (sem esperar outro "tchau").
    if (encerrar && _ehDespedidaDaIa(pergunta)) {
      await _confirmarEncerramento();
    }
  }

  /// Usuário quer terminar (Tchau / Termina / Ok / …) — encerra de verdade
  /// em vez de mandar outra despedida da IA (loop infinito).
  bool _ehIntencaoEncerrar(String texto) {
    final t = texto
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[!.?,;:]+$'), '')
        .trim();
    if (t.isEmpty) return false;
    const exatos = {
      'tchau',
      'adeus',
      'ate logo',
      'até logo',
      'ate mais',
      'até mais',
      'encerrar',
      'terminar',
      'termina',
      'fim',
      'ok',
      'okay',
      'certo',
      'nao',
      'não',
      'nao obrigado',
      'não obrigado',
      'pode encerrar',
      'pode terminar',
      'chega',
      'ja deu',
      'já deu',
      'pronto',
      'feito',
      'sair',
    };
    if (exatos.contains(t)) return true;
    if (RegExp(r'^(tchau|adeus|até logo|ate logo)\b').hasMatch(t)) {
      return true;
    }
    if (RegExp(r'\b(pode encerrar|pode terminar|encerrar|terminar)\b')
        .hasMatch(t)) {
      return true;
    }
    return false;
  }

  bool _ehDespedidaDaIa(String texto) {
    final t = texto.trim().toLowerCase();
    if (t.isEmpty) return false;
    return RegExp(
      r'\b(tchau|adeus|até logo|ate logo|até a próxima|ate a proxima|'
      r'cuide-se|cuidese|foi um prazer|obrigad[oa] por compartilhar|'
      r'até breve|ate breve)\b',
    ).hasMatch(t);
  }

  Future<void> _responder(String texto) async {
    final sessaoId = _sessaoId!;
    final ordem = _historico.length + 1;
    final intencaoEncerrar = _ehIntencaoEncerrar(texto);
    final msg = CuradorMensagem(
      sessaoId: sessaoId,
      role: CuradorMensagemRole.user,
      conteudo: texto,
      ordem: ordem,
      tipo: intencaoEncerrar
          ? CuradorMensagemTipo.fechamento
          : CuradorMensagemTipo.resposta,
    );
    setState(() {
      _historico.add(msg);
      _controller.clear();
      _solicitandoFinalizacao = false;
    });
    await _sessaoService.adicionarMensagem(
      sessaoId: sessaoId,
      role: CuradorMensagemRole.user,
      conteudo: texto,
      tipo: intencaoEncerrar
          ? CuradorMensagemTipo.fechamento
          : CuradorMensagemTipo.resposta,
    );

    // Farewell do usuário OU IA já pediu encerrar → vai para preview,
    // NÃO gera mais uma pergunta/despedida (evita loop "Tchau!").
    if (intencaoEncerrar || _deveEncerrar) {
      await _confirmarEncerramento();
      return;
    }
    await _gerarProximaPergunta();
  }

  Future<void> _confirmarEncerramento() async {
    setState(() => _concluiu = true);
    await _carregarAnalise();
    await _carregarNarrativa();
  }

  Future<void> _carregarAnalise() async {
    final contextoCompleto = widget.contextoOriginal;
    final respostas = <String, String>{};
    for (final m in _historico.where((m) => m.role == CuradorMensagemRole.user)) {
      respostas[m.ordem.toString()] = m.conteudo;
    }
    if (_legacyService.isConfigured) {
      final resultado =
          await _legacyService.analisarLegado(contextoCompleto, respostas);
      if (resultado != null && mounted) {
        setState(() => _analiseLegado = resultado);
        return;
      }
    }
    if (mounted) {
      setState(() {
        _analiseLegado = const MotorPerguntas()
            .analisarLegado(contextoCompleto, respostas);
      });
    }
  }

  Future<void> _carregarNarrativa() async {
    final respostas = <String, String>{};
    for (final m in _historico.where((m) => m.role == CuradorMensagemRole.user)) {
      respostas[m.ordem.toString()] = m.conteudo;
    }
    if (_legacyService.isConfigured && respostas.isNotEmpty) {
      final resultado = await _legacyService.gerarNarrativa(
        widget.contextoOriginal,
        widget.titulo,
        respostas,
      );
      if (resultado != null && mounted) {
        setState(() => _narrativa = resultado);
        return;
      }
    }
    if (mounted) {
      setState(() {
        _narrativa = const MotorPerguntas()
            .montarNarrativa(widget.contextoOriginal, respostas);
      });
    }
  }

  String _montarContextoEnriquecido() {
    if (_narrativa != null && _narrativa!.isNotEmpty) return _narrativa!;
    final buffer = StringBuffer();
    buffer.writeln(widget.contextoOriginal);
    buffer.writeln();
    for (final m in _historico.where((m) => m.role == CuradorMensagemRole.user)) {
      buffer.writeln(m.conteudo);
      buffer.writeln();
    }
    return buffer.toString().trim();
  }

  Future<void> _salvar() async {
    if (_sessaoId != null) {
      await _sessaoService.finalizarSessao(
        sessaoId: _sessaoId!,
        contextoAtual: _montarContextoEnriquecido(),
      );
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      CuradorResultado(
        contextoEnriquecido: _montarContextoEnriquecido(),
        sessaoId: _sessaoId,
      ),
    );
  }

  Future<void> _cancelarESair() async {
    if (_sessaoId != null) {
      await _sessaoService.cancelarSessao(_sessaoId!);
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  // ════════════════════════════════════════════════════════════════════════
  // UI
  // ════════════════════════════════════════════════════════════════════════

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
            tooltip: 'Sair sem salvar',
            onPressed: _cancelarESair,
            icon: const Icon(Icons.close, color: AppColors.roxo),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: !_iniciouConversa
                ? _buildTelaProposta()
                : _carregandoPergunta && _perguntaAtual.isEmpty
                    ? const _CarregandoCurador()
                    : _concluiu
                        ? _buildPreview()
                        : _solicitandoFinalizacao
                            ? _buildTelaFinalizacao()
                            : _buildPergunta(),
          ),
        ),
      ),
    );
  }

  Widget _buildTelaProposta() {
    final pending = widget.pendingMemory;
    final momento = widget.detectedMoment;

    final capaBytes = pending?.capa ?? momento?.capa;
    final qntFotos = pending?.quantidadeFotos ?? momento?.quantidadeFotos ?? 0;
    final qntVideos = pending?.quantidadeVideos ?? momento?.quantidadeVideos ?? 0;
    final dataRef = pending?.data ?? momento?.inicio;

    final desc = '${qntVideos > 0 ? 'Vídeo' : 'Foto'} registrado em ${_formatarDataHora(dataRef)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        if (capaBytes != null) ...[
          Container(
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borda, width: 2),
              image: DecorationImage(
                image: MemoryImage(capaBytes),
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        Center(
          child: Text(
            desc,
            style: const TextStyle(
              color: Color(0xFF7A7280),
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text(
            '$qntFotos ${qntFotos == 1 ? 'foto' : 'fotos'} • $qntVideos ${qntVideos == 1 ? 'vídeo' : 'vídeos'}',
            style: const TextStyle(
              color: Color(0xFF9B949D),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 32),
        const Text(
          'Gostaria de preservar a história por trás deste momento?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Vamos conversar sobre isso. Posso te fazer algumas perguntas?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF7A7280),
            fontSize: 14,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 48),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelarESair,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roxo,
                  side: const BorderSide(color: AppColors.borda),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Agora não',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: FilledButton(
                onPressed: _comecarConversa,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Começar',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPergunta() {
    if (_carregandoPergunta) {
      return const _CarregandoCurador();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        const Text(
          'Curador de Memórias',
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Vamos conversar sobre o que você viveu. Responda como preferir — eu me adapto ao que você disser.',
          style: TextStyle(
            color: AppColors.textoSuave,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 20),
        _buildHistoricoResumido(),
        // Sprint K — Card "Lembro que você tem uma história parecida"
        // no modo complemento (só aparece se houver relações
        // confirmadas e a memória sendo complementada não for a
        // própria relacionada).
        if (widget.complementoMemoriaId != null &&
            _relacionadosComplemento.isNotEmpty)
          _buildCardRelacionadosComplemento(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(24),
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
              const Icon(Icons.format_quote_outlined,
                  size: 24, color: AppColors.dourado),
              const SizedBox(height: 12),
              Text(
                _perguntaAtual,
                style: const TextStyle(
                  color: AppColors.roxo,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _controller,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: 'Sua resposta...',
            alignLabelWithHint: true,
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.all(16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.borda),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.roxo, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  if (_controller.text.trim().isEmpty) {
                    _responder('(sem resposta)');
                  } else {
                    _responder(_controller.text.trim());
                  }
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roxo,
                  side: const BorderSide(color: AppColors.borda),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Pular'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _controller.text.trim().isEmpty
                    ? null
                    : () => _responder(_controller.text.trim()),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text('Responder'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Sprint K — Card de "Lembro que você tem uma história parecida" no
  // modo complemento do Curador.
  Widget _buildCardRelacionadosComplemento() {
    final rels = _relacionadosComplemento.take(2).toList();
    if (rels.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.history_toggle_off, size: 14, color: AppColors.dourado),
              SizedBox(width: 6),
              Text(
                'Lembro que você tem uma história parecida',
                style: TextStyle(
                  color: AppColors.roxo,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...rels.map((r) {
            final idOrigem = widget.complementoMemoriaId;
            final outroId = (r.memoriaOrigemId == idOrigem)
                ? r.memoriaDestinoId
                : r.memoriaOrigemId;
            final titulo = (r.memoriaOrigemId == idOrigem)
                ? (r.tituloDestino ?? 'Outra história')
                : (r.tituloOrigem ?? 'Outra história');
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  const Icon(Icons.timeline_outlined,
                      size: 12, color: AppColors.dourado),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    '(${r.score}%)',
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildHistoricoResumido() {
    if (_historico.isEmpty) return const SizedBox.shrink();
    final respostas = _historico
        .where((m) => m.role == CuradorMensagemRole.user)
        .toList();
    if (respostas.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.history, size: 14, color: AppColors.dourado),
              SizedBox(width: 6),
              Text(
                'O que você já me contou',
                style: TextStyle(
                  color: AppColors.roxo,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...respostas.reversed.take(3).toList().reversed.map(
                (m) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '• ${m.conteudo}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF625B67),
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _buildTelaFinalizacao() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        const Icon(Icons.check_circle_outline, size: 56, color: AppColors.verdeApoio),
        const SizedBox(height: 16),
        const Text(
          'Acho que já conseguimos preservar muito bem essa lembrança.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 22,
            fontWeight: FontWeight.w800,
            height: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Gostaria de acrescentar mais algum detalhe?',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF7A7280),
            fontSize: 15,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 32),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () async {
                  if (_sessaoId != null) {
                    await _sessaoService.adicionarMensagem(
                      sessaoId: _sessaoId!,
                      role: CuradorMensagemRole.user,
                      conteudo: 'Sim, mais um detalhe.',
                      tipo: CuradorMensagemTipo.resposta,
                    );
                  }
                  setState(() {
                    _solicitandoFinalizacao = false;
                    _deveEncerrar = false;
                  });
                  await _gerarProximaPergunta();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roxo,
                  side: const BorderSide(color: AppColors.borda),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Sim, mais um detalhe'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () async {
                  if (_sessaoId != null) {
                    await _sessaoService.adicionarMensagem(
                      sessaoId: _sessaoId!,
                      role: CuradorMensagemRole.user,
                      conteudo: 'Não, pode encerrar.',
                      tipo: CuradorMensagemTipo.fechamento,
                    );
                  }
                  await _confirmarEncerramento();
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Não, pode encerrar'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final respostas = _historico
        .where((m) => m.role == CuradorMensagemRole.user)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        const Text(
          'Antes de salvar',
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Revise como sua história enriquecida ficou.',
          style: TextStyle(color: Color(0xFF7A7280), fontSize: 15),
        ),
        const SizedBox(height: 24),
        _PreviewCard(
          icon: Icons.menu_book_outlined,
          titulo: 'Sua história',
          color: AppColors.roxo,
          child: Text(
            _montarContextoEnriquecido(),
            style: const TextStyle(
              color: Color(0xFF625B67),
              fontSize: 15,
              height: 1.6,
            ),
          ),
        ),
        if (_analiseLegado?.temConteudo ?? false) ...[
          const SizedBox(height: 16),
          _PreviewCard(
            icon: Icons.emoji_objects_outlined,
            titulo: 'O que esta história revela',
            color: AppColors.dourado,
            child: _buildAnaliseLegado(_analiseLegado!),
          ),
        ],
        if (respostas.isNotEmpty) ...[
          const SizedBox(height: 16),
          _PreviewCard(
            icon: Icons.forum_outlined,
            titulo: 'Respostas coletadas',
            color: AppColors.verdeApoio,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: respostas
                  .asMap()
                  .entries
                  .map((entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Resposta ${entry.key + 1}',
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry.value.conteudo,
                              style: const TextStyle(
                                color: Color(0xFF625B67),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _cancelarESair,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.roxo,
                  side: const BorderSide(color: AppColors.borda),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _salvar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: const Icon(Icons.favorite_outline, size: 18),
                label: const Text('Salvar memória'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAnaliseLegado(AnaliseLegado analise) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analise.valores.isNotEmpty) ...[
          const Text('Valores',
              style: TextStyle(
                  color: AppColors.roxo, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...analise.valores.map((v) => _buildLinhaAnalise(Icons.check_circle_outline, v, AppColors.verdeApoio)),
          const SizedBox(height: 12),
        ],
        if (analise.caracteristicas.isNotEmpty) ...[
          const Text('Características',
              style: TextStyle(
                  color: AppColors.roxo, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...analise.caracteristicas.map((c) => _buildLinhaAnalise(Icons.person_outline, c, AppColors.dourado)),
          const SizedBox(height: 12),
        ],
        if (analise.aprendizados.isNotEmpty) ...[
          const Text('Aprendizados',
              style: TextStyle(
                  color: AppColors.roxo, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ...analise.aprendizados.map((a) => _buildLinhaAnalise(Icons.format_quote_outlined, a, AppColors.verdeApoio)),
        ],
      ],
    );
  }

  Widget _buildLinhaAnalise(IconData icon, String texto, Color cor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 14, color: cor),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              texto,
              style: const TextStyle(color: Color(0xFF625B67), fontSize: 14, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  String _formatarDataHora(DateTime? date) {
    if (date == null) return 'agora';
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    String diaStr;
    if (date.year == hoje.year && date.month == hoje.month && date.day == hoje.day) {
      diaStr = 'hoje';
    } else if (date.year == ontem.year &&
        date.month == ontem.month &&
        date.day == ontem.day) {
      diaStr = 'ontem';
    } else {
      diaStr = '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }
    final horaStr = '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return '$diaStr às $horaStr';
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
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
            color: Color(0x042B1747),
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

class _CarregandoCurador extends StatelessWidget {
  const _CarregandoCurador();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox.square(
            dimension: 32,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(height: 16),
          Text(
            'Conversando com você...',
            style: TextStyle(color: Color(0xFF7A7280), fontSize: 15),
          ),
        ],
      ),
    );
  }
}
