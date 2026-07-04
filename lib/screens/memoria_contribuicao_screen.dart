import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/contribuicao.dart';
import '../models/pessoa.dart';
import '../services/memory_relationship_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';

/// Sprint G — Tela para enriquecer uma memória existente com texto, foto,
/// vídeo ou áudio (áudio preparado pela arquitetura, sem UI de gravação
/// ainda). O texto ORIGINAL da memória nunca é alterado — toda contribuição
/// vira um registro separado em `contribuicoes` (FK polimórfica via
/// `tipo_conteudo='memoria'` + `conteudo_id`).
class MemoriaContribuicaoScreen extends StatefulWidget {
  const MemoriaContribuicaoScreen({
    required this.memoriaId,
    required this.memoriaTitulo,
    required this.usuarioDonoId,
    this.aprovacaoObrigatoria = true,
    super.key,
  });

  final int memoriaId;
  final String memoriaTitulo;
  final int usuarioDonoId;

  /// Se true, a contribuição entra com `status='pendente'` até o dono
  /// aprovar. Se false, entra direto como `status='aprovado'`.
  final bool aprovacaoObrigatoria;

  @override
  State<MemoriaContribuicaoScreen> createState() =>
      _MemoriaContribuicaoScreenState();
}

class _MemoriaContribuicaoScreenState
    extends State<MemoriaContribuicaoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _conteudoController = TextEditingController();
  final _picker = ImagePicker();

  // Foto, vídeo ou áudio — apenas um é enviado por contribuição.
  Uint8List? _fotoBytes;
  Uint8List? _videoBytes;
  // (Sem _audioBytes por enquanto — a UI ainda não oferece gravação, mas o
  // model e a query já suportam.)
  String? _meuNome = '';
  String _tipoSelecionado = 'texto'; // 'texto' | 'foto' | 'video' | 'audio'
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    _carregarIdentidade();
  }

  Future<void> _carregarIdentidade() async {
    final dados = await PessoaRepository.obterUsuario();
    if (mounted && dados != null) {
      setState(() {
        _meuNome = '${dados['nome'] ?? ''} ${dados['sobrenome'] ?? ''}'.trim();
      });
    }
  }

  @override
  void dispose() {
    _conteudoController.dispose();
    super.dispose();
  }

  Future<void> _selecionarFoto() async {
    try {
      final imagem = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 1024,
      );
      if (imagem == null) return;
      final bytes = await imagem.readAsBytes();
      setState(() {
        _fotoBytes = bytes;
        _videoBytes = null;
        _tipoSelecionado = 'foto';
      });
    } catch (_) {}
  }

  Future<void> _selecionarVideo() async {
    try {
      final video = await _picker.pickVideo(source: ImageSource.gallery);
      if (video == null) return;
      final bytes = await video.readAsBytes();
      setState(() {
        _videoBytes = bytes;
        _fotoBytes = null;
        _tipoSelecionado = 'video';
      });
    } catch (_) {}
  }

  void _limparMidia() {
    setState(() {
      _fotoBytes = null;
      _videoBytes = null;
      _tipoSelecionado = _conteudoController.text.trim().isNotEmpty ? 'texto' : 'texto';
    });
  }

  Future<void> _submeter() async {
    if (!_formKey.currentState!.validate()) return;

    // Pelo menos texto OU mídia é obrigatório.
    final temTexto = _conteudoController.text.trim().isNotEmpty;
    final temMidia = _fotoBytes != null || _videoBytes != null;
    if (!temTexto && !temMidia) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Adicione um texto, uma foto ou um vídeo à sua contribuição.'),
        ),
      );
      return;
    }

    setState(() => _enviando = true);
    try {
      final String tipoContribuicao = temMidia
          ? _tipoSelecionado // 'foto' ou 'video'
          : 'texto';

      final contribuicao = Contribuicao(
        // memorialId permanece null: estamos contribuindo a uma MEMÓRIA,
        // não a um memorial — a FK polimórfica é `tipo_conteudo='memoria'`
        // + `conteudo_id=memoriaId`.
        memorialId: null,
        tipoConteudo: 'memoria',
        conteudoId: widget.memoriaId,
        usuarioDonoId: widget.usuarioDonoId,
        usuarioContribuidorEmail: PessoaRepository.usuarioEmail ?? '',
        usuarioContribuidorNome: _meuNome?.isNotEmpty == true ? _meuNome! : 'Familiar',
        tipoContribuicao: tipoContribuicao,
        texto: temTexto ? _conteudoController.text.trim() : null,
        fotoBytes: _fotoBytes,
        videoBytes: _videoBytes,
        status: widget.aprovacaoObrigatoria ? 'pendente' : 'aprovado',
        createdAt: DateTime.now(),
      );

      await SupabaseService.instance.salvarContribuicao(contribuicao);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.aprovacaoObrigatoria
              ? 'Sua contribuição foi enviada para aprovação do dono da memória.'
              : 'Sua contribuição foi publicada e já aparece na história.'),
          duration: const Duration(seconds: 4),
        ),
      );

      // Sprint K — hook incremental: contribuição nova pode gerar
      // novas relações (ex: pessoas em comum entre memórias). Fire-
      // and-forget.
      // ignore: unawaited_futures
      MemoryRelationshipService.instance
          .aoReceberContribuicao(widget.memoriaId);

      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao enviar contribuição: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tipoTexto = _conteudoController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: AppColors.fundo,
      appBar: AppBar(
        title: const Text('Contribuir com a memória',
            style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
        backgroundColor: AppColors.fundo,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.roxo),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: _enviando
                ? const Center(child: CircularProgressIndicator(color: AppColors.roxo))
                : Form(
                    key: _formKey,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Contexto da memória que está sendo enriquecida.
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0EAF5),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.borda),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.auto_stories_outlined,
                                  color: AppColors.roxo, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Enriquecendo: "${widget.memoriaTitulo}"',
                                  style: const TextStyle(
                                    color: AppColors.roxo,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'A história original permanece intacta — sua contribuição será exibida na seção "Evolução da memória" como um complemento identificado por você.',
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _meuNome?.isNotEmpty == true
                              ? 'Enviando como $_meuNome (${PessoaRepository.usuarioEmail ?? ''})'
                              : 'Carregando sua identidade...',
                          style: const TextStyle(
                            color: AppColors.dourado,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Tipo de contribuição ──
                        const Text('O que você quer adicionar?',
                            style: TextStyle(
                                color: AppColors.roxo,
                                fontSize: 14,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _TipoChip(
                              label: 'Texto',
                              icon: Icons.notes_outlined,
                              selecionado: _tipoSelecionado == 'texto',
                              onTap: () => setState(() {
                                _tipoSelecionado = 'texto';
                                _limparMidia();
                              }),
                            ),
                            _TipoChip(
                              label: 'Foto',
                              icon: Icons.photo_outlined,
                              selecionado: _tipoSelecionado == 'foto',
                              onTap: () async {
                                setState(() => _tipoSelecionado = 'foto');
                                await _selecionarFoto();
                              },
                            ),
                            _TipoChip(
                              label: 'Vídeo',
                              icon: Icons.videocam_outlined,
                              selecionado: _tipoSelecionado == 'video',
                              onTap: () async {
                                setState(() => _tipoSelecionado = 'video');
                                await _selecionarVideo();
                              },
                            ),
                            _TipoChip(
                              label: 'Áudio',
                              icon: Icons.mic_outlined,
                              selecionado: _tipoSelecionado == 'audio',
                              onTap: () {
                                setState(() => _tipoSelecionado = 'audio');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Gravação de áudio em breve. Por enquanto, selecione texto, foto ou vídeo.',
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        // ── Campo de texto ──
                        TextFormField(
                          controller: _conteudoController,
                          maxLines: 6,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: const InputDecoration(
                            labelText: 'Sua lembrança ou comentário',
                            hintText: 'Adicione um detalhe, uma história, um sentimento...',
                            alignLabelWithHint: true,
                          ),
                          onChanged: (_) {
                            // Apenas força rebuild para o chip de texto destacar
                            // quando o usuário está digitando.
                            if (mounted) setState(() {});
                          },
                        ),
                        const SizedBox(height: 20),

                        // ── Pré-visualização da mídia selecionada ──
                        if (_fotoBytes != null) ...[
                          Stack(
                            alignment: Alignment.topRight,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(_fotoBytes!,
                                    width: double.infinity, height: 220, fit: BoxFit.cover),
                              ),
                              IconButton.filled(
                                tooltip: 'Remover foto',
                                onPressed: _limparMidia,
                                icon: const Icon(Icons.close, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (_videoBytes != null) ...[
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0EAF5),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.borda),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.movie_outlined, color: AppColors.roxo),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Vídeo selecionado (${(_videoBytes!.lengthInBytes / 1024 / 1024).toStringAsFixed(1)} MB)',
                                    style: const TextStyle(
                                      color: AppColors.roxo,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Remover',
                                  onPressed: _limparMidia,
                                  icon: const Icon(Icons.close, size: 18),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],

                        // ── Banner explicativo: status da contribuição ──
                        if (widget.aprovacaoObrigatoria)
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0x1AD4A84F),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              children: [
                                Icon(Icons.fact_check_outlined,
                                    size: 18, color: AppColors.dourado),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Esta memória exige aprovação: sua contribuição ficará pendente até que o dono da história aprove.',
                                    style: TextStyle(
                                      color: AppColors.dourado,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        const SizedBox(height: 32),
                        FilledButton(
                          onPressed: _enviando ? null : _submeter,
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.roxo,
                            foregroundColor: Colors.white,
                            minimumSize: const Size.fromHeight(54),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text(
                            _enviando
                                ? 'Enviando...'
                                : 'Adicionar à história',
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                        // O TextEditingController é só estado local.
                        // ignore: unused_local_variable
                        if (tipoTexto) const SizedBox.shrink(),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TipoChip extends StatelessWidget {
  const _TipoChip({
    required this.label,
    required this.icon,
    required this.selecionado,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selecionado;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selecionado ? AppColors.roxo : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selecionado ? AppColors.roxo : AppColors.borda, width: 1.4),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon,
                size: 16,
                color: selecionado ? Colors.white : AppColors.roxo),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selecionado ? Colors.white : AppColors.roxo,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
