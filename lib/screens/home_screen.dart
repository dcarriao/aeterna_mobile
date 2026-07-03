import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../models/pending_memory.dart';
import '../services/pending_memory_service.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';
import '../widgets/home/pending_memory_card.dart';
import 'nova_memoria_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.onRegistrar,
    required this.onMinhaHistoria,
    required this.onAbrirMemoria,
    required this.onPessoas,
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
  List<PendingMemory> _sugestoes = [];
  bool _carregandoSugestoes = false;
  bool _esconderBanner = false;

  @override
  void initState() {
    super.initState();
    _carregarSugestoes();
  }

  Future<void> _carregarSugestoes() async {
    if (mounted) setState(() => _carregandoSugestoes = true);
    final lista = await PendingMemoryService.instance.obterMemoriasPendentes();
    if (mounted) {
      setState(() {
        _sugestoes = lista;
        _carregandoSugestoes = false;
      });
    }
  }

  void _iniciarCriacaoMemoriaComGrupo(PendingMemory pending) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovaMemoriaScreen(
          onSalvar: SupabaseService.instance.salvarMemoriaComFoto,
          sugestaoPending: pending,
        ),
      ),
    ).then((_) {
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
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                    icon: Icons.people_outline,
                    label: 'Pessoas',
                    onTap: widget.onPessoas),
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

                // Banner de Convite do Curador (Sprint D)
                if (!_carregandoSugestoes && !_esconderBanner && _sugestoes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildBannerConvite(_sugestoes.first),
                ],
                
                // Card de Sugestões de Mídia Proativas
                if (!_carregandoSugestoes && _sugestoes.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  PendingMemoryCard(
                    sugestoes: _sugestoes,
                    onCriarHistoria: _iniciarCriacaoMemoriaComGrupo,
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

  Widget _buildBannerConvite(PendingMemory pending) {
    final hasVideos = pending.quantidadeVideos > 0;
    
    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    String diaStr;
    if (pending.data.year == hoje.year && pending.data.month == hoje.month && pending.data.day == hoje.day) {
      diaStr = 'hoje';
    } else if (pending.data.year == ontem.year && pending.data.month == ontem.month && pending.data.day == ontem.day) {
      diaStr = 'ontem';
    } else {
      diaStr = '${pending.data.day.toString().padLeft(2, '0')}/${pending.data.month.toString().padLeft(2, '0')}';
    }
    final horaStr = '${pending.data.hour.toString().padLeft(2, '0')}:${pending.data.minute.toString().padLeft(2, '0')}';

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: AppColors.roxo, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ],
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
