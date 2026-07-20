import 'package:flutter/material.dart';

import '../../models/memoria_do_dia.dart';
import '../../theme/app_theme.dart';

/// Sprint M — Card de "Memória do Dia" exibido na Home.
///
/// Dois botões sutis (decisão confirmada com o usuário):
///   * "Relembrar" — abre a `MemoriaDetalheScreen` (revisita fotos,
///     vídeos, contribuições, evolução).
///   * "Continuar história" — abre a `CuradorScreen` no modo
///     complemento (Sprint I), já funcional. O Curador pergunta
///     algo como "Hoje faz X anos que esse momento aconteceu.
///     O que aconteceu depois?".
class MemoriaDoDiaCard extends StatelessWidget {
  const MemoriaDoDiaCard({
    required this.item,
    required this.onRelembrar,
    required this.onContinuar,
    super.key,
  });

  final MemoriaDoDia item;
  final VoidCallback onRelembrar;
  final VoidCallback onContinuar;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.dourado.withValues(alpha: 0.4),
          width: 1.4,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Imagem de capa (se houver) + texto sobreposto
          if (item.fotoPrincipal != null && item.fotoPrincipal!.isNotEmpty)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Image.network(
                  item.fotoPrincipal!,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  errorBuilder: (_, _, _) => Container(
                    color: const Color(0xFFEDE8DC),
                    child: const Center(
                      child: Icon(Icons.history_edu,
                          color: AppColors.dourado, size: 36),
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEDE8DC),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: Icon(Icons.history_edu,
                    color: AppColors.dourado, size: 36),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0x1AD4A84F),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        item.rotuloTempo,
                        style: const TextStyle(
                          color: AppColors.dourado,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Hoje na sua história',
                  style: TextStyle(
                    color: AppColors.roxo.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.titulo,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
                if (item.totalPessoas > 0 || item.totalMidias > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    _formatarSubInfo(),
                    style: const TextStyle(
                      color: Color(0xFF7A7280),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: onRelembrar,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7A7280),
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                      ),
                      icon: const Icon(Icons.photo_outlined, size: 14),
                      label: const Text(
                        'Relembrar',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.icon(
                      onPressed: onContinuar,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.roxo,
                        foregroundColor: Colors.white,
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      icon: const Icon(Icons.auto_awesome, size: 14),
                      label: const Text(
                        'Continuar história',
                        style: TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatarSubInfo() {
    final parts = <String>[];
    if (item.totalMidias > 0) {
      parts.add('${item.totalMidias} mídias');
    }
    if (item.totalPessoas > 0) {
      parts.add(
          '${item.totalPessoas} ${item.totalPessoas == 1 ? 'pessoa' : 'pessoas'}');
    }
    if (item.possuiRelacionamentos) {
      parts.add('conectada a outras histórias');
    }
    if (parts.isEmpty) return '';
    return parts.join(' · ');
  }
}
