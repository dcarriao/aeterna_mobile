import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../models/media_group.dart';
import '../../theme/app_theme.dart';

class MediaSuggestionsCard extends StatelessWidget {
  const MediaSuggestionsCard({
    required this.sugestoes,
    required this.onCriarMemoria,
    super.key,
  });

  final List<MediaGroup> sugestoes;
  final void Function(MediaGroup grupo) onCriarMemoria;

  @override
  Widget build(BuildContext context) {
    if (sugestoes.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borda),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0x1AD4A84F),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  color: AppColors.dourado,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vale a pena guardar estes momentos?',
                      style: TextStyle(
                        color: AppColors.roxo,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Ainda não encontramos histórias para estas mídias.',
                      style: TextStyle(
                        color: Color(0xFF7A7280),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sugestoes.length,
            separatorBuilder: (_, _) => const Divider(height: 24, color: AppColors.borda),
            itemBuilder: (context, index) {
              final grupo = sugestoes[index];
              return _buildGrupoRow(grupo);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildGrupoRow(MediaGroup grupo) {
    final hasPhotos = grupo.totalFotos > 0;
    final hasVideos = grupo.totalVideos > 0;
    
    String labelCount = '';
    if (hasPhotos && hasVideos) {
      labelCount = '${grupo.totalFotos} ${grupo.totalFotos == 1 ? 'foto' : 'fotos'} e ${grupo.totalVideos} ${grupo.totalVideos == 1 ? 'vídeo' : 'vídeos'}';
    } else if (hasPhotos) {
      labelCount = '${grupo.totalFotos} ${grupo.totalFotos == 1 ? 'foto' : 'fotos'}';
    } else {
      labelCount = '${grupo.totalVideos} ${grupo.totalVideos == 1 ? 'vídeo' : 'vídeos'}';
    }

    return Row(
      children: [
        // Miniatura
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.fundo,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.borda),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FutureBuilder<Uint8List?>(
              future: grupo.midias.first.asset.thumbnailDataWithSize(const ThumbnailSize(120, 120)),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes != null) {
                  return Image.memory(bytes, fit: BoxFit.cover);
                }
                return const Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.roxo),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 16),
        // Detalhes do Grupo
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    hasVideos ? Icons.videocam_outlined : Icons.photo_library_outlined,
                    size: 14,
                    color: AppColors.dourado,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    grupo.dataLabel,
                    style: const TextStyle(
                      color: AppColors.roxo,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                labelCount,
                style: const TextStyle(
                  color: Color(0xFF9B949D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        // Botão de Ação
        FilledButton(
          onPressed: () => onCriarMemoria(grupo),
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.roxo,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: const Text(
            'Criar memória',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
