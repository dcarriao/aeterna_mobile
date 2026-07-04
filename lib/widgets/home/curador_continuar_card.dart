import 'package:flutter/material.dart';

import '../../models/curador_sessao.dart';
import '../../theme/app_theme.dart';

/// Sprint J — Card "Continuar conversa do Curador" exibido na Home
/// quando o usuário tem uma sessão ativa (em_andamento) do Curador
/// Contextual.
class CuradorContinuarCard extends StatelessWidget {
  const CuradorContinuarCard({
    required this.sessao,
    required this.onContinuar,
    required this.onDescartar,
    super.key,
  });

  final CuradorSessao sessao;
  final VoidCallback onContinuar;
  final VoidCallback onDescartar;

  String get _tituloCurto {
    final t = (sessao.titulo ?? '').trim();
    if (t.isNotEmpty) return t;
    final ctx = (sessao.contextoInicial).trim();
    if (ctx.isEmpty) return 'Conversa com o Curador';
    if (ctx.length <= 60) return ctx;
    return '${ctx.substring(0, 60).trim()}...';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F6F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.dourado.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppColors.dourado, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Você começou uma história',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sessao.resumoParaCard,
                      style: const TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.borda),
            ),
            child: Text(
              _tituloCurto,
              style: const TextStyle(
                color: AppColors.roxo,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onDescartar,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7A7280),
                    side: const BorderSide(color: AppColors.borda),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text('Descartar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onContinuar,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.roxo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('Continuar',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
