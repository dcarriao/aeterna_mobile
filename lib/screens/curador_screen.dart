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
    super.key,
  });

  final String titulo;
  final String contextoOriginal;
  final List<Map<String, String>>? pessoas;

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

  @override
  void initState() {
    super.initState();
    _carregarPerguntas();
  }

  Future<void> _carregarPerguntas() async {
    if (LegacyCuratorService.instance.isConfigured) {
      final perguntasIA =
          await LegacyCuratorService.instance.gerarPerguntas(
        widget.contextoOriginal,
        widget.titulo,
        widget.pessoas ?? [],
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
        _perguntas = const MotorPerguntas().selecionar(widget.contextoOriginal);
        _carregandoPerguntas = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
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
    }
  }

  void _pular() {
    if (_indice + 1 < _perguntas.length) {
      _controller.clear();
      setState(() => _indice++);
    } else {
      setState(() => _mostrandoPreview = true);
      _carregarAnalise();
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
      appBar: AppBar(
        title: const Text('Curador de Histórias'),
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Color(0x26D4A84F),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  '${_indice + 1}',
                  style: const TextStyle(
                    color: AppColors.dourado,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${_indice + 1} de ${_perguntas.length}',
              style: const TextStyle(
                color: Color(0xFF7A7280),
                fontSize: 14,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borda),
          ),
          child: Text(
            pergunta.texto,
            style: const TextStyle(
              color: AppColors.roxo,
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
            ),
          ),
        ),
        const SizedBox(height: 20),
        TextFormField(
          controller: _controller,
          textCapitalization: TextCapitalization.sentences,
          minLines: 3,
          maxLines: 6,
          decoration: InputDecoration(
            hintText: 'Escreva sua resposta...',
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
              borderSide:
                  const BorderSide(color: AppColors.roxo, width: 2),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pular,
                child: const Text('Pular'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _avancar,
                child: Text(
                  _indice + 1 < _perguntas.length ? 'Continuar' : 'Finalizar',
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        const Text(
          'Antes de salvar',
          style: TextStyle(
            color: AppColors.roxo,
            fontSize: 26,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Revise como sua memória ficou.',
          style: TextStyle(color: Color(0xFF7A7280), fontSize: 15),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.borda),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.auto_stories_outlined,
                      size: 18, color: AppColors.roxo),
                  SizedBox(width: 8),
                  Text(
                    'Sua memória',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                widget.contextoOriginal,
                style: const TextStyle(
                  color: Color(0xFF625B67),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (respondeu) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.borda),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.forum_outlined,
                        size: 18, color: AppColors.verdeApoio),
                    SizedBox(width: 8),
                    Text(
                      'Perguntas respondidas',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
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
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF0EAF5),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.merge_type,
                      size: 18, color: AppColors.dourado),
                  SizedBox(width: 8),
                  Text(
                    'Versão completa',
                    style: TextStyle(
                      color: AppColors.roxo,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _montarContextoEnriquecido(),
                style: const TextStyle(
                  color: Color(0xFF625B67),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
            ],
          ),
        ),
        if (_analise.temConteudo) ...[
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x26D4A84F),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppColors.dourado.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.emoji_objects_outlined,
                        size: 18, color: AppColors.dourado),
                    SizedBox(width: 8),
                    Text(
                      'O que esta história revela',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
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
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton.icon(
                onPressed: _salvar,
                icon: const Icon(Icons.favorite_outline),
                label: const Text('Salvar memória'),
              ),
            ),
          ],
        ),
      ],
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
            'Preparando perguntas...',
            style: TextStyle(color: Color(0xFF7A7280), fontSize: 15),
          ),
        ],
      ),
    );
  }
}
