import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/proactive_opportunity.dart';
import '../../theme/app_theme.dart';

class ProactiveOpportunityCard extends StatelessWidget {
  const ProactiveOpportunityCard({
    required this.opportunity,
    required this.onTransformar,
    required this.onDispensar,
    super.key,
  });

  final ProactiveOpportunity opportunity;
  final VoidCallback onTransformar;
  final VoidCallback onDispensar;

  @override
  Widget build(BuildContext context) {
    // Miniatura já pronta em DetectedMoment.capa (thumbnail do vídeo/foto).
    final Uint8List? capa = opportunity.detectedMoment?.capa;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF8F0), Color(0xFFFFF0E0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: AppColors.dourado.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.dourado.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    opportunity.icone,
                    color: AppColors.dourado,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        opportunity.titulo,
                        style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        opportunity.descricao,
                        style: const TextStyle(
                          color: Color(0xFF7A7280),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (capa != null) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.memory(capa,
                        height: 160, width: double.infinity, fit: BoxFit.cover),
                    if (opportunity.temVideo)
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.play_arrow_rounded,
                            color: Colors.white, size: 34),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton(
                      onPressed: onDispensar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF7A7280),
                        side: const BorderSide(color: Color(0xFFE5DED2)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      child: const Text('Agora não',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: onTransformar,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.roxo,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text('Transformar em história',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
