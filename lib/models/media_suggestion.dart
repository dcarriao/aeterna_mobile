import 'package:photo_manager/photo_manager.dart';

class MediaSuggestion {
  const MediaSuggestion({
    required this.id,
    required this.tipo,
    required this.data,
    required this.asset,
    this.thumbnailPath,
    this.utilizada = false,
  });

  final String id;
  final AssetType tipo;
  final DateTime data;
  final String? thumbnailPath;
  final AssetEntity asset;
  final bool utilizada;
}
