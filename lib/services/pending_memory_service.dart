import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import '../models/pending_memory.dart';
import 'media_suggestion_service.dart';

class PendingMemoryService {
  PendingMemoryService._();

  static final instance = PendingMemoryService._();

  Future<List<PendingMemory>> obterMemoriasPendentes() async {
    try {
      final grupos = await MediaSuggestionService.instance.obterSugestoes();
      if (grupos.isEmpty) return [];

      final pendentes = <PendingMemory>[];

      for (final grupo in grupos) {
        final fotos = grupo.midias.where((m) => m.tipo == AssetType.image).map((m) => m.asset).toList();
        final videos = grupo.midias.where((m) => m.tipo == AssetType.video).map((m) => m.asset).toList();
        
        fotos.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
        videos.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));

        Uint8List? capaBytes;
        if (videos.isNotEmpty) {
          capaBytes = await videos.first.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        } else if (fotos.isNotEmpty) {
          capaBytes = await fotos.first.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        }

        pendentes.add(PendingMemory(
          id: grupo.data.millisecondsSinceEpoch.toString(),
          data: grupo.data,
          fotos: fotos,
          videos: videos,
          capa: capaBytes,
          quantidadeFotos: fotos.length,
          quantidadeVideos: videos.length,
          criadaEm: DateTime.now(),
        ));
      }

      return pendentes;
    } catch (e) {
      print('[PendingMemoryService] Erro ao obter memórias pendentes: $e');
      return [];
    }
  }
}
