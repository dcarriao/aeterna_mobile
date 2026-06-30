import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../curador/perguntas.dart';
import '../models/memoria.dart';
import '../models/pessoa.dart';
import '../theme/app_theme.dart';
import 'nova_memoria_screen.dart';

class MemoriaDetalheScreen extends StatefulWidget {
  const MemoriaDetalheScreen({
    required this.memoria,
    this.onEditar,
    super.key,
  });

  final Memoria memoria;
  final VoidCallback? onEditar; // Mantido para compatibilidade, mas faremos a navegação reativa interna

  @override
  State<MemoriaDetalheScreen> createState() => _MemoriaDetalheScreenState();
}

class _MemoriaDetalheScreenState extends State<MemoriaDetalheScreen> {
  late Memoria _memoria;
  List<Pessoa> _familiares = [];
  List<Pessoa> _participantes = [];
  String? _videoUrl;
  bool _carregandoDados = true;
  late AnaliseLegado _analise;

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

      if (mounted) {
        setState(() {
          _familiares = todasAsPessoas.where((p) => famIds.contains(p.id)).toList();
          _participantes = todasAsPessoas.where((p) => partIds.contains(p.id)).toList();
          _videoUrl = videoUrl;
          _carregandoDados = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _carregandoDados = false);
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
                      // ── HERO IMAGE ──
                      if (_memoria.foto != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Image.memory(_memoria.foto!, fit: BoxFit.cover),
                          ),
                        )
                      else if (_memoria.fotoUrl != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: AspectRatio(
                            aspectRatio: 16 / 10,
                            child: Image.network(
                              _memoria.fotoUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
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
                          child: InkWell(
                            onTap: () {
                              showDialog<void>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Vídeo da memória', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w800)),
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Este vídeo está salvo com segurança no Supabase Storage do seu legado.', style: TextStyle(color: Color(0xFF625B67))),
                                      const SizedBox(height: 12),
                                      SelectableText(_videoUrl!, style: const TextStyle(color: AppColors.roxo, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.of(ctx).pop(),
                                      child: const Text('Fechar', style: TextStyle(color: AppColors.roxo, fontWeight: FontWeight.w700)),
                                    ),
                                  ],
                                ),
                              );
                            },
                            child: Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFBF4E8),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: const Color(0xFFEDE8DC)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.play_circle_outline, size: 36, color: AppColors.dourado),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Assistir vídeo', style: TextStyle(color: AppColors.roxo, fontSize: 15, fontWeight: FontWeight.w800)),
                                        const SizedBox(height: 2),
                                        Text('Toque para ver a referência do vídeo salvo.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right, color: Colors.grey),
                                ],
                              ),
                            ),
                          ),
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

                      // ── BOTÃO EDITAR HISTÓRIA ──
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
