import 'dart:io' as io;
import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/detected_moment.dart';
import 'media_suggestion_service.dart';

class MomentDetectionService {
  MomentDetectionService._();

  static final instance = MomentDetectionService._();

  // Configuração centralizada da janela de agrupamento (90 minutos)
  static const int agrupamentoMinutos = 90;

  Future<List<DetectedMoment>> obterMomentosDetectados() async {
    try {
      // 1. Verificar permissões da galeria
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        print('[MomentDetectionService] Permissão negada para acessar galeria.');
        return [];
      }

      // 2. Obter caminhos de fotos e vídeos
      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );
      if (paths.isEmpty) return [];

      // 3. Buscar as últimas 80 mídias
      final recentAssets = await paths.first.getAssetListRange(start: 0, end: 80);
      if (recentAssets.isEmpty) return [];

      // 4. Filtrar mídias já utilizadas
      final prefs = await SharedPreferences.getInstance();
      final usedIds = prefs.getStringList('used_gallery_asset_ids')?.toSet() ?? <String>{};
      final filteredAssets = recentAssets.where((a) => !usedIds.contains(a.id)).toList();
      if (filteredAssets.isEmpty) return [];

      // 5. Ordenar mídias cronologicamente de forma crescente (mais antiga para mais recente)
      filteredAssets.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));

      // 6. Agrupamento por proximidade temporal (Janela de 90 minutos)
      final grupos = <List<AssetEntity>>[];
      List<AssetEntity>? grupoAtual;

      for (final asset in filteredAssets) {
        if (grupoAtual == null) {
          grupoAtual = [asset];
          grupos.add(grupoAtual);
        } else {
          final ultimoAsset = grupoAtual.last;
          final diferencaMinutos = asset.createDateTime.difference(ultimoAsset.createDateTime).inMinutes.abs();
          
          if (diferencaMinutos <= agrupamentoMinutos) {
            grupoAtual.add(asset);
          } else {
            grupoAtual = [asset];
            grupos.add(grupoAtual);
          }
        }
      }

      // 7. Compilar grupos encontrados em DetectedMoment
      final momentos = <DetectedMoment>[];

      for (final grupo in grupos) {
        final fotos = grupo.where((a) => a.type == AssetType.image).toList();
        final videos = grupo.where((a) => a.type == AssetType.video).toList();

        if (fotos.isEmpty && videos.isEmpty) continue;

        // Ordenação cronológica garantida dentro de fotos e vídeos
        fotos.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));
        videos.sort((a, b) => a.createDateTime.compareTo(b.createDateTime));

        // Obter capa localmente (Vídeo primeiro, senão foto)
        Uint8List? capaBytes;
        if (videos.isNotEmpty) {
          capaBytes = await videos.first.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        } else if (fotos.isNotEmpty) {
          capaBytes = await fotos.first.thumbnailDataWithSize(const ThumbnailSize(200, 200));
        }

        final inicio = grupo.first.createDateTime;
        final fim = grupo.last.createDateTime;

        momentos.add(DetectedMoment(
          id: inicio.millisecondsSinceEpoch.toString(),
          inicio: inicio,
          fim: fim,
          fotos: fotos,
          videos: videos,
          capa: capaBytes,
        ));
      }

      // Ordenar decrescente (momentos mais recentes primeiro)
      momentos.sort((a, b) => b.inicio.compareTo(a.inicio));
      return momentos;
    } catch (e) {
      print('[MomentDetectionService] Erro ao obter momentos detectados: $e');
      return [];
    }
  }

  Future<io.File?> obterMidiaMaisRecente(DetectedMoment momento) async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) return null;
      final todas = [...momento.videos, ...momento.fotos];
      if (todas.isEmpty) return null;
      todas.sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      return await todas.first.file;
    } catch (e) {
      print('[MomentDetectionService] Erro ao obter midia: $e');
      return null;
    }
  }
}
