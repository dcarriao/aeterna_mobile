import 'package:flutter/material.dart';

import '../models/memoria.dart';
import '../theme/app_theme.dart';
import '../widgets/memory_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({
    required this.onRegistrar,
    required this.onMinhaHistoria,
    required this.onAbrirMemoria,
    required this.onPessoas,
    required this.onTimeline,
    required this.onCompartilhadas,
    required this.onPerfil,
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
  final List<Memoria> memorias;

  @override
  Widget build(BuildContext context) {
    final recentes = memorias.take(3).toList();

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
                    onTap: onPessoas),
                _NavItem(
                    icon: Icons.timeline_outlined,
                    label: 'Timeline',
                    onTap: onTimeline),
                _NavItem(
                    icon: Icons.share_outlined,
                    label: 'Compartilhadas',
                    onTap: onCompartilhadas),
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
                    GestureDetector(
                      onTap: onPerfil,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0EAF5),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(Icons.person_outline,
                            color: AppColors.roxo, size: 20),
                      ),
                    ),
                  ],
                ),
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
                            memorias.isEmpty
                                ? 'Nenhuma ainda'
                                : '${memorias.length} ${memorias.length == 1 ? 'registro' : 'registros'}',
                            style: const TextStyle(
                                color: Color(0xFF9B949D), fontSize: 14),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: onRegistrar,
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
                if (memorias.isEmpty)
                  _EstadoVazio(onRegistrar: onRegistrar)
                else ...[
                  ...recentes.map(
                    (memoria) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: MemoryCard(
                        memoria: memoria,
                        onLer: () => onAbrirMemoria(memoria),
                      ),
                    ),
                  ),
                  if (memorias.length > 3)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, bottom: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: onMinhaHistoria,
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
