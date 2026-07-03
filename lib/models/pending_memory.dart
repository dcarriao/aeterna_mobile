import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

class PendingMemory {
  const PendingMemory({
    required this.id,
    required this.data,
    required this.fotos,
    required this.videos,
    this.capa,
    required this.quantidadeFotos,
    required this.quantidadeVideos,
    this.utilizada = false,
    required this.criadaEm,
  });

  final String id;
  final DateTime data;
  final List<AssetEntity> fotos;
  final List<AssetEntity> videos;
  final Uint8List? capa;
  final int quantidadeFotos;
  final int quantidadeVideos;
  final bool utilizada;
  final DateTime criadaEm;
}
