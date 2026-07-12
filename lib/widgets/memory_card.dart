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
    return GestureDetector(
      onTap: onLer,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEDE8DC)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x102B1747),
              blurRadius: 12,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (memoria.foto != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child:
                      Image.memory(memoria.foto!, fit: BoxFit.cover),
                ),
              )
            else if (memoria.fotoUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: SizedBox(
                  height: 200,
                  width: double.infinity,
                  child: Image.network(memoria.fotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFF0EAF5),
                            child: const Center(
                                child: Icon(Icons.image_outlined,
                                    color: AppColors.roxo, size: 32)),
                          )),
                ),
              )
            // S.9.4b (Item 3) — memória com vídeo e sem foto: mostra o
            // bloco de vídeo com ícone de play (o player abre no detalhe).
            else if (memoria.videoUrl != null)
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(15)),
                child: Container(
                  height: 200,
                  width: double.infinity,
                  color: const Color(0xFF2B1747),
                  child: const Center(
                    child: Icon(Icons.play_circle_outline,
                        color: Colors.white70, size: 56),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(memoria.titulo,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: AppColors.roxo,
                          fontSize: 18,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined,
                          size: 13, color: AppColors.dourado),
                      const SizedBox(width: 5),
                      Text(DateFormat('dd/MM/yyyy').format(memoria.criadaEm),
                          style: const TextStyle(
                              color: Color(0xFF817987), fontSize: 12)),
                      const SizedBox(width: 12),
                      _CategoriaChip(categoria: memoria.categoria),
                      const Spacer(),
                      Icon(Icons.arrow_forward_ios,
                          size: 12, color: Colors.grey.shade400),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoriaChip extends StatelessWidget {
  const _CategoriaChip({required this.categoria});
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6E8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(_label,
          style: const TextStyle(
              color: Color(0xFF8B5E6B),
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
