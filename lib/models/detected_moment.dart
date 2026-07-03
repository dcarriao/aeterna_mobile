import 'dart:typed_data';
import 'package:photo_manager/photo_manager.dart';

class DetectedMoment {
  const DetectedMoment({
    required this.id,
    required this.inicio,
    required this.fim,
    required this.fotos,
    required this.videos,
    this.capa,
    this.utilizado = false,
  });

  final String id;
  final DateTime inicio;
  final DateTime fim;
  final List<AssetEntity> fotos;
  final List<AssetEntity> videos;
  final Uint8List? capa;
  final bool utilizado;

  int get quantidadeFotos => fotos.length;
  int get quantidadeVideos => videos.length;
}
