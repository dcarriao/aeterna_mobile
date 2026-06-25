import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../theme/app_theme.dart';

class MemoryCard extends StatelessWidget {
  const MemoryCard({
    required this.memoria,
    this.onLer,
    super.key,
  });

  final Memoria memoria;
  final VoidCallback? onLer;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borda),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (memoria.foto != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.memory(memoria.foto!, fit: BoxFit.cover),
            )
          else if (memoria.fotoUrl != null)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                memoria.fotoUrl!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const ColoredBox(
                  color: Color(0xFFF0EAF5),
                  child: Center(
                    child: Icon(
                      Icons.image_not_supported_outlined,
                      color: AppColors.roxo,
                    ),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  memoria.titulo,
                  style: const TextStyle(
                    color: AppColors.roxo,
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  memoria.contexto,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF625B67),
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 13),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 15,
                          color: AppColors.dourado,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          DateFormat('dd/MM/yyyy').format(memoria.criadaEm),
                          style: const TextStyle(
                            color: Color(0xFF817987),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.label_outline,
                          size: 15,
                          color: AppColors.verdeApoio,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          _categoriaLabel(memoria.categoria),
                          style: const TextStyle(
                            color: Color(0xFF817987),
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (onLer != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onLer,
                      icon: const Icon(Icons.menu_book_outlined, size: 18),
                      label: const Text('Ler memória'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _categoriaLabel(String categoria) {
    return switch (categoria) {
      'familia' => 'Família',
      'aprendizados' => 'Aprendizados',
      'viagens' => 'Viagens',
      'tradicoes' => 'Tradições',
      _ => 'Momentos',
    };
  }
}
