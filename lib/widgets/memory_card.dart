import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/memoria.dart';
import '../theme/app_theme.dart';

class MemoryCard extends StatefulWidget {
  const MemoryCard({
    required this.memoria,
    this.onLer,
    this.compartilhadaPorNome,
    super.key,
  });

  final Memoria memoria;
  final VoidCallback? onLer;
  final String? compartilhadaPorNome;

  @override
  State<MemoryCard> createState() => _MemoryCardState();
}

class _MemoryCardState extends State<MemoryCard> {

  @override
  Widget build(BuildContext context) {
    final m = widget.memoria;

    final renderer = m.foto != null || m.fotoUrl != null
        ? 'foto'
        : (m.temVideo && m.videoUrl != null)
            ? 'video'
            : (m.temVideo)
                ? 'video_sem_url'
                : 'sem_midia';

    print('[HOME_MEDIA] memoria_id=${m.id ?? -1} '
        'titulo="${m.titulo}" '
        'fotos=${m.fotoUrl != null ? 1 : 0} '
        'videos=${m.temVideo ? 1 : 0} '
        'video_url=${m.videoUrl ?? "NULL"} '
        'thumbnail=NULL '
        'renderer=$renderer');

    return GestureDetector(
      onTap: widget.onLer,
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
            if (widget.compartilhadaPorNome != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_outlined,
                        size: 14, color: AppColors.roxo),
                    const SizedBox(width: 6),
                    Text(
                      'Compartilhada por ${widget.compartilhadaPorNome}',
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            if (widget.compartilhadaPorNome != null)
              const SizedBox(height: 10),
            if (m.foto != null)
              _buildFotoMemory(m.foto!)
            else if (m.fotoUrl != null)
              _buildFotoNetwork(m.fotoUrl!)
            else if (m.temVideo && m.videoUrl != null)
              _buildVideoPreview()
            else if (m.temVideo)
              _buildVideoSemUrl()
            else
              const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.titulo,
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
                      Text(DateFormat('dd/MM/yyyy').format(m.criadaEm),
                          style: const TextStyle(
                              color: Color(0xFF817987), fontSize: 12)),
                      const SizedBox(width: 12),
                      _CategoriaChip(categoria: m.categoria),
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

  Widget _buildFotoMemory(Uint8List bytes) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.memory(bytes, fit: BoxFit.cover),
      ),
    );
  }

  Widget _buildFotoNetwork(String url) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Image.network(url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
                  color: const Color(0xFFF0EAF5),
                  child: const Center(
                      child: Icon(Icons.image_outlined,
                          color: AppColors.roxo, size: 32)),
                )),
      ),
    );
  }

  Widget _buildVideoPreview() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF3D1D6A), Color(0xFF1A0A2E)],
                ),
              ),
            ),
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.black45,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 36,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoSemUrl() {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
      child: Container(
        height: 200,
        width: double.infinity,
        color: const Color(0xFF2B1747),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_outlined, color: Colors.white38, size: 32),
              SizedBox(height: 8),
              Text('Video indisponivel',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoriaChip extends StatelessWidget {
  const _CategoriaChip({required this.categoria});
  final String categoria;

  String get _label => switch (categoria) {
        'familia' => 'Familia',
        'aprendizados' => 'Aprendizados',
        'viagens' => 'Viagens',
        'tradicoes' => 'Tradicoes',
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
