import 'package:photo_manager/photo_manager.dart';
import 'media_suggestion.dart';

class MediaGroup {
  const MediaGroup({
    required this.dataLabel,
    required this.data,
    required this.midias,
  });

  final String dataLabel;
  final DateTime data;
  final List<MediaSuggestion> midias;

  int get totalFotos => midias.where((m) => m.tipo == AssetType.image).length;
  int get totalVideos => midias.where((m) => m.tipo == AssetType.video).length;
}
