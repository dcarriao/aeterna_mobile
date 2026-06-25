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
    this.memorias = const [],
    super.key,
  });

  final VoidCallback onRegistrar;
  final VoidCallback onMinhaHistoria;
  final void Function(Memoria memoria) onAbrirMemoria;
  final VoidCallback onPessoas;
  final VoidCallback onTimeline;
  final VoidCallback onCompartilhadas;
  final List<Memoria> memorias;

  @override
  Widget build(BuildContext context) {
    final ultimasMemorias = memorias.take(3).toList();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.all_inclusive,
                      color: AppColors.dourado,
                      size: 30,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'aEterna',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 27,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),
                const Text(
                  'Suas histórias merecem durar para sempre',
                  style: TextStyle(
                    color: AppColors.roxo,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Preserve memórias, aprendizados e momentos importantes '
                  'da sua família.',
                  style: TextStyle(
                    color: AppColors.textoSuave,
                    fontSize: 15,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.roxo,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x242B1747),
                        blurRadius: 24,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: const BoxDecoration(
                          color: Color(0x26D4A84F),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.photo_camera_outlined,
                          color: AppColors.dourado,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'O que aconteceu hoje?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Registre fotos, histórias e pequenos momentos antes '
                        'que eles se percam no tempo.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                          fontSize: 16,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: onRegistrar,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.dourado,
                          foregroundColor: AppColors.roxo,
                        ),
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: const Text('Registrar nova memória'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      memorias.isEmpty
                          ? 'Seu espaço'
                          : '${memorias.length} ${memorias.length == 1 ? 'memória' : 'memórias'}',
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    TextButton(
                      onPressed: onMinhaHistoria,
                      child: const Text('Ver todas'),
                    ),
                  ],
                ),
                if (ultimasMemorias.isEmpty) ...[
                  const SizedBox(height: 14),
                  _Atalho(
                    icon: Icons.auto_stories_outlined,
                    titulo: 'Minha História',
                    descricao: 'Relembre os momentos que você guardou',
                    onTap: onMinhaHistoria,
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  ...ultimasMemorias.map(
                    (memoria) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: MemoryCard(
                        memoria: memoria,
                        onLer: () => onAbrirMemoria(memoria),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                _Atalho(
                  icon: Icons.people_outline,
                  titulo: 'Pessoas importantes',
                  descricao: 'Conheça quem faz parte da sua história',
                  onTap: onPessoas,
                ),
                const SizedBox(height: 10),
                _Atalho(
                  icon: Icons.timeline_outlined,
                  titulo: 'Linha do Tempo',
                  descricao: 'Veja sua história ao longo dos anos',
                  onTap: onTimeline,
                ),
                const SizedBox(height: 10),
                _Atalho(
                  icon: Icons.share_outlined,
                  titulo: 'Compartilhadas',
                  descricao: 'Memórias compartilhadas com familiares',
                  onTap: onCompartilhadas,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Atalho extends StatelessWidget {
  const _Atalho({
    required this.icon,
    required this.titulo,
    required this.descricao,
    this.onTap,
  });

  final IconData icon;
  final String titulo;
  final String descricao;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EAF5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.roxo),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      descricao,
                      style: const TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 13,
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
    );
  }
}
