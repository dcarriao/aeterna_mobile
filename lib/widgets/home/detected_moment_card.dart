import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/detected_moment.dart';
import '../../theme/app_theme.dart';

class DetectedMomentCard extends StatelessWidget {
  const DetectedMomentCard({
    required this.sugestoes,
    required this.onCriarHistoria,
    super.key,
  });

  final List<DetectedMoment> sugestoes;
  final void Function(DetectedMoment momento) onCriarHistoria;

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
                      'Vale a pena guardar este momento?',
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
              final momento = sugestoes[index];
              return _buildMomentRow(momento);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMomentRow(DetectedMoment momento) {
    final hasPhotos = momento.quantidadeFotos > 0;
    final hasVideos = momento.quantidadeVideos > 0;

    final hoje = DateTime.now();
    final ontem = hoje.subtract(const Duration(days: 1));
    
    String diaStr;
    if (momento.inicio.year == hoje.year && momento.inicio.month == hoje.month && momento.inicio.day == hoje.day) {
      diaStr = 'Hoje';
    } else if (momento.inicio.year == ontem.year && momento.inicio.month == ontem.month && momento.inicio.day == ontem.day) {
      diaStr = 'Ontem';
    } else if (hoje.difference(momento.inicio).inDays < 7) {
      diaStr = _diaDaSemanaLabel(momento.inicio.weekday);
    } else {
      diaStr = '${momento.inicio.day.toString().padLeft(2, '0')}/${momento.inicio.month.toString().padLeft(2, '0')}/${momento.inicio.year}';
    }
    
    final horaInicioStr = '${momento.inicio.hour.toString().padLeft(2, '0')}:${momento.inicio.minute.toString().padLeft(2, '0')}';
    final horaFimStr = '${momento.fim.hour.toString().padLeft(2, '0')}:${momento.fim.minute.toString().padLeft(2, '0')}';
    final dataHoraLabel = '$diaStr • $horaInicioStr até $horaFimStr';

    return Row(
      children: [
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
            child: momento.capa != null
                ? Image.memory(momento.capa!, fit: BoxFit.cover)
                : const Icon(Icons.image_outlined, color: AppColors.roxo, size: 24),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPhotos)
                Row(
                  children: [
                    const Icon(Icons.photo_library_outlined, size: 13, color: AppColors.dourado),
                    const SizedBox(width: 6),
                    Text(
                      '${momento.quantidadeFotos} ${momento.quantidadeFotos == 1 ? 'foto' : 'fotos'}',
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              if (hasPhotos && hasVideos) const SizedBox(height: 2),
              if (hasVideos)
                Row(
                  children: [
                    const Icon(Icons.videocam_outlined, size: 13, color: AppColors.dourado),
                    const SizedBox(width: 6),
                    Text(
                      '${momento.quantidadeVideos} ${momento.quantidadeVideos == 1 ? 'vídeo' : 'vídeos'}',
                      style: const TextStyle(
                        color: AppColors.roxo,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 4),
              Text(
                dataHoraLabel,
                style: const TextStyle(
                  color: Color(0xFF9B949D),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        FilledButton(
          onPressed: () => onCriarHistoria(momento),
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
            'Criar história',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }

  String _diaDaSemanaLabel(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'Segunda-feira';
      case DateTime.tuesday: return 'Terça-feira';
      case DateTime.wednesday: return 'Quarta-feira';
      case DateTime.thursday: return 'Quinta-feira';
      case DateTime.friday: return 'Sexta-feira';
      case DateTime.saturday: return 'Sábado';
      case DateTime.sunday: return 'Domingo';
      default: return '';
    }
  }
}
