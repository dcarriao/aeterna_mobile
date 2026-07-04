import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/memoria_pode_crescer.dart';
import '../../services/memory_growth_invitation_service.dart';
import '../../services/memory_growth_scoring_service.dart';
import '../../theme/app_theme.dart';

/// Sprint I — Card discreto "Memória que pode crescer" exibido na Home.
/// Mostra a memória, idade desde a última atualização, número de
/// pessoas/contribuições e 2 botões sutis: "Criar complemento" e
/// "Agora não".
class MemoriaPodeCrescerCard extends StatelessWidget {
  const MemoriaPodeCrescerCard({
    required this.item,
    required this.onAbrirMemoria,
    required this.onAbrirCurador,
    required this.onDispensar,
    super.key,
  });

  final MemoriaComScore item;
  final void Function(int memoriaId) onAbrirMemoria;
  final VoidCallback onAbrirCurador;
  final VoidCallback onDispensar;

  String _formatarIdade(double dias) {
    if (dias < 1) return 'hoje';
    if (dias < 30) return 'há ${dias.toInt()} dias';
    if (dias < 365) return 'há ${(dias / 30).floor()} meses';
    return 'há ${(dias / 365).floor()} anos';
  }

  @override
  Widget build(BuildContext context) {
    final m = item.memoria;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.dourado.withValues(alpha: 0.4), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER (clique → abre memória)
          InkWell(
            onTap: () => onAbrirMemoria(m.memoriaId),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.auto_awesome, color: AppColors.dourado, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          m.titulo,
                          style: const TextStyle(
                            color: AppColors.roxo,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Atualizada ${_formatarIdade(m.diasDesdeUltimaAtualizacao)}'
                          ' · ${m.totalContribuicoes} ${m.totalContribuicoes == 1 ? "contribuição" : "contribuições"}'
                          ' · ${m.totalPessoas} ${m.totalPessoas == 1 ? "pessoa" : "pessoas"}',
                          style: const TextStyle(
                            color: Color(0xFF7A7280),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
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
          // Razão do convite (1 critério + simples)
          if (item.score.criterios.any((c) => c.pontos > 0))
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                _motivoConvite(item),
                style: const TextStyle(
                  color: Color(0xFF625B67),
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
          // AÇÕES
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onDispensar,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF7A7280),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: const Text(
                    'Agora não',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 6),
                FilledButton.icon(
                  onPressed: onAbrirCurador,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  icon: const Icon(Icons.auto_awesome, size: 14),
                  label: const Text(
                    'Complementar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _motivoConvite(MemoriaComScore item) {
    final positivos = item.score.criterios
        .where((c) => c.pontos > 0)
        .map((c) => c.nome.toLowerCase())
        .toList();
    if (positivos.isEmpty) return 'Convite do Curador: sua história pode crescer.';
    if (positivos.any((p) => p.contains('colaborador'))) {
      return 'Existem familiares cadastrados para essa história que ainda não contribuíram.';
    }
    if (positivos.any((p) => p.contains('autor único'))) {
      return 'Essa história foi escrita só por você. Convidar outra pessoa pode enriquecê-la.';
    }
    if (positivos.any((p) => p.contains('muitas mídias'))) {
      return 'Vimos mídias na galeria que ainda não foram associadas a essa história.';
    }
    if (positivos.any((p) => p.contains('poucas mídias'))) {
      return 'Sua história tem poucas mídias. Adicionar fotos e vídeos pode torná-la mais viva.';
    }
    return 'Convite do Curador: sua história pode crescer.';
  }
}
