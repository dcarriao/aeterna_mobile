import 'dart:typed_data';
import 'package:flutter/material.dart';

import '../curador/perguntas.dart';
import '../services/legacy_curator_service.dart';
import '../theme/app_theme.dart';

class CuradorResultado {
  const CuradorResultado({required this.contextoEnriquecido});

  final String contextoEnriquecido;
}

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

  @override
  State<CuradorScreen> createState() => _CuradorScreenState();
}

class _CuradorScreenState extends State<CuradorScreen> {
  late final List<PerguntaCurador> _perguntas;
  final _respostas = <String, String>{};
  final _controller = TextEditingController();
  int _indice = 0;
  bool _mostrandoPreview = false;
  bool _carregandoPerguntas = true;
  AnaliseLegado? _analiseLegado;
  String? _narrativa;

  @override
  void initState() {
    super.initState();
    _carregarPerguntas();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _carregarPerguntas() async {
    if (widget.isProativo) {
      if (mounted) {
        setState(() {
          _perguntas = [
            const PerguntaCurador(texto: 'O que estava acontecendo?', categoria: CategoriaPergunta.factual),
            const PerguntaCurador(texto: 'O que tornou esse momento especial?', categoria: CategoriaPergunta.emocional),
            const PerguntaCurador(texto: 'Existe algum detalhe que uma foto não mostraria?', categoria: CategoriaPergunta.emocional),
            const PerguntaCurador(texto: 'Qual lembrança ou valor você gostaria de preservar?', categoria: CategoriaPergunta.legado),
          ];
          _carregandoPerguntas = false;
        });
      }
      return;
    }

    if (LegacyCuratorService.instance.isConfigured) {
      final perguntasIA =
          await LegacyCuratorService.instance.gerarPerguntas(
        widget.contextoOriginal,
        widget.titulo,
        widget.pessoas ?? [],
        dataMemoria: widget.dataMemoria,
        categoria: widget.categoria,
      );
      if (perguntasIA != null && perguntasIA.isNotEmpty) {
        if (mounted) {
          setState(() {
            _perguntas = perguntasIA
                .map((p) => PerguntaCurador(
                      texto: p,
                      categoria: CategoriaPergunta.legado,
                    ))
                .toList();
            _carregandoPerguntas = false;
          });
        }
        return;
      }
    }

    if (mounted) {
      setState(() {
        _perguntas = const MotorPerguntas().selecionar(
          widget.contextoOriginal,
          temPessoas: widget.pessoas != null && widget.pessoas!.isNotEmpty,
          temData: widget.dataMemoria != null,
        );
        _carregandoPerguntas = false;
      });
    }
  }

  PerguntaCurador? get _perguntaAtual {
    if (_indice >= _perguntas.length) return null;
    return _perguntas[_indice];
  }

  void _responder() {
    final pergunta = _perguntaAtual;
    if (pergunta == null) return;

    final resposta = _controller.text.trim();
    if (resposta.isNotEmpty) {
      _respostas[pergunta.texto] = resposta;
    }
  }

  void _avancar() {
    _responder();

    if (_indice + 1 < _perguntas.length) {
      _controller.clear();
      setState(() => _indice++);
    } else {
      _controller.dispose();
      setState(() => _mostrandoPreview = true);
      _carregarAnalise();
      _carregarNarrativa();
    }
  }

  void _pular() {
    if (_indice + 1 < _perguntas.length) {
      _controller.clear();
      setState(() => _indice++);
    } else {
      setState(() => _mostrandoPreview = true);
      _carregarAnalise();
      _carregarNarrativa();
    }
  }

  Future<void> _carregarNarrativa() async {
    if (LegacyCuratorService.instance.isConfigured && _respostas.isNotEmpty) {
      final resultado = await LegacyCuratorService.instance.gerarNarrativa(
        widget.contextoOriginal,
        widget.titulo,
        _respostas,
      );
      if (resultado != null && mounted) {
        setState(() => _narrativa = resultado);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _narrativa = const MotorPerguntas().montarNarrativa(
          widget.contextoOriginal,
          _respostas,
        );
      });
    }
  }

  Future<void> _carregarAnalise() async {
    if (LegacyCuratorService.instance.isConfigured) {
      final resultado = await LegacyCuratorService.instance.analisarLegado(
        widget.contextoOriginal,
        _respostas,
      );
      if (resultado != null && mounted) {
        setState(() => _analiseLegado = resultado);
        return;
      }
    }

    if (mounted) {
      setState(() {
        _analiseLegado = const MotorPerguntas().analisarLegado(
          widget.contextoOriginal,
          _respostas,
        );
      });
    }
  }

  AnaliseLegado get _analise => _analiseLegado ??
      const MotorPerguntas().analisarLegado(
        widget.contextoOriginal,
        _respostas,
      );

  String _montarContextoEnriquecido() {
    if (_narrativa != null && _narrativa!.isNotEmpty) return _narrativa!;
    if (_respostas.isEmpty) return widget.contextoOriginal;

    final buffer = StringBuffer();
    buffer.writeln(widget.contextoOriginal);
    buffer.writeln();

    for (final pergunta in _perguntas) {
      final resposta = _respostas[pergunta.texto];
      if (resposta != null) {
        buffer.writeln(resposta);
      }
    }

    return buffer.toString().trim();
  }

  void _salvar() {
    Navigator.of(context).pop(
      CuradorResultado(
        contextoEnriquecido: _montarContextoEnriquecido(),
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
          Container(
            margin: const EdgeInsets.only(right: 20),
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EAF5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(Icons.auto_awesome_outlined,
                color: AppColors.roxo, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _carregandoPerguntas
                ? const _CarregandoCurador()
                : _mostrandoPreview
                    ? _buildPreview()
                    : _buildPergunta(),
          ),
        ),
      ),
    );
  }

  Widget _buildPergunta() {
    final pergunta = _perguntaAtual;
    if (pergunta == null) return const SizedBox.shrink();

    final progresso = (_indice + 1) / _perguntas.length;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      children: [
        // ── TITULO DO CURADOR ──
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
          'Vamos transformar lembranças em histórias que permanecerão vivas.',
          style: TextStyle(
            color: AppColors.textoSuave,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 20),

        if (widget.isProativo && widget.proativoMediaBytes != null) ...[
          Container(
            height: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borda),
              image: !widget.proativoMediaIsVideo
                  ? DecorationImage(
                      image: MemoryImage(widget.proativoMediaBytes!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: widget.proativoMediaIsVideo
                ? const Center(
                    child: Icon(Icons.play_circle_fill, size: 48, color: AppColors.roxo),
                  )
                : null,
          ),
          const SizedBox(height: 20),
        ],

        const SizedBox(height: 8),

        // ── PROGRESSO E BARRA ──
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Pergunta ${_indice + 1} de ${_perguntas.length}',
              style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '${(progresso * 100).toInt()}%',
              style: const TextStyle(
                color: AppColors.dourado,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progresso,
            backgroundColor: const Color(0xFFEDE8DC),
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.dourado),
            minHeight: 6,
          ),
        ),
        const SizedBox(height: 24),

        // ── CARD DA PERGUNTA PRINCIPAL ──
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
                pergunta.texto,
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

        // ── CAMPO DE RESPOSTA ──
        TextFormField(
          controller: _controller,
          textCapitalization: TextCapitalization.sentences,
          minLines: 4,
          maxLines: 8,
          decoration: InputDecoration(
            hintText: 'Escreva sua resposta para preservar este detalhe...',
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
        const SizedBox(height: 28),

        // ── BOTÕES DE NAVEGAÇÃO ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pular,
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
                onPressed: _avancar,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.roxo,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  _indice + 1 < _perguntas.length ? 'Próxima pergunta' : 'Finalizar',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview() {
    final respondeu = _respostas.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
      children: [
        // ── CABEÇALHO FINALE ──
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

        // ── CARD PRINCIPAL: SUA HISTÓRIA (NARRATIVA) ──
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

        // ── CARD REVELADO (Valores / Características / Aprendizados) ──
        if (_analise.temConteudo) ...[
          const SizedBox(height: 16),
          _PreviewCard(
            icon: Icons.emoji_objects_outlined,
            titulo: 'O que esta história revela',
            color: AppColors.dourado,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_analise.valores.isNotEmpty) ...[
                  const Text(
                    'Valores',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._analise.valores.map(
                    (v) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 14, color: AppColors.verdeApoio),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              v,
                              style: const TextStyle(
                                color: Color(0xFF625B67),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_analise.caracteristicas.isNotEmpty) ...[
                  const Text(
                    'Características',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._analise.caracteristicas.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          const Icon(Icons.person_outline,
                              size: 14, color: AppColors.dourado),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              c,
                              style: const TextStyle(
                                color: Color(0xFF625B67),
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_analise.aprendizados.isNotEmpty) ...[
                  const Text(
                    'Aprendizados',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  ..._analise.aprendizados.map(
                    (a) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.format_quote_outlined,
                                size: 14, color: AppColors.verdeApoio),
                          ),
                          const SizedBox(width: 6),
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
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],

        // ── CARD AUXILIAR: ORIGINAL E RESPOSTAS ──
        if (respondeu) ...[
          const SizedBox(height: 16),
          _PreviewCard(
            icon: Icons.forum_outlined,
            titulo: 'Respostas coletadas',
            color: AppColors.verdeApoio,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._perguntas
                    .where((p) => _respostas.containsKey(p.texto))
                    .map(
                      (p) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.texto,
                              style: const TextStyle(
                                color: AppColors.roxo,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _respostas[p.texto]!,
                              style: const TextStyle(
                                color: Color(0xFF625B67),
                                fontSize: 14,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 28),

        // ── BOTÕES DE SALVAMENTO ──
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
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
            'Organizando sua história...',
            style: TextStyle(color: Color(0xFF7A7280), fontSize: 15),
          ),
        ],
      ),
    );
  }
}
