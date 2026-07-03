import 'package:photo_manager/photo_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/media_group.dart';
import '../models/media_suggestion.dart';

class MediaSuggestionService {
  MediaSuggestionService._();

  static final instance = MediaSuggestionService._();

  static const _usedAssetsKey = 'used_gallery_asset_ids';

  Future<void> registrarAssetComoUtilizado(String assetId) async {
    final prefs = await SharedPreferences.getInstance();
    final used = prefs.getStringList(_usedAssetsKey)?.toSet() ?? <String>{};
    used.add(assetId);
    await prefs.setStringList(_usedAssetsKey, used.toList());
  }

  Future<Set<String>> _obterAssetsUtilizados() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_usedAssetsKey)?.toSet() ?? <String>{};
  }

  Future<List<MediaGroup>> obterSugestoes() async {
    try {
      final permission = await PhotoManager.requestPermissionExtend();
      if (!permission.isAuth) {
        print('[MediaSuggestionService] Permissão negada para acessar galeria.');
        return [];
      }

      final paths = await PhotoManager.getAssetPathList(
        type: RequestType.common,
        hasAll: true,
      );
      if (paths.isEmpty) return [];

      final recentAssets = await paths.first.getAssetListRange(start: 0, end: 80);
      if (recentAssets.isEmpty) return [];

      final usedIds = await _obterAssetsUtilizados();
      final filteredAssets = recentAssets.where((a) => !usedIds.contains(a.id)).toList();
      if (filteredAssets.isEmpty) return [];

      final gruposMap = <String, List<MediaSuggestion>>{};
      final datasDeReferencia = <String, DateTime>{};

      for (final asset in filteredAssets) {
        final data = asset.createDateTime;
        final dataKey = '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
        
        gruposMap.putIfAbsent(dataKey, () => []);
        datasDeReferencia.putIfAbsent(dataKey, () => DateTime(data.year, data.month, data.day));

        gruposMap[dataKey]!.add(MediaSuggestion(
          id: asset.id,
          tipo: asset.type,
          data: data,
          asset: asset,
        ));
      }

      final listaGrupos = <MediaGroup>[];
      final hoje = DateTime.now();
      final ontem = hoje.subtract(const Duration(days: 1));

      gruposMap.forEach((key, midias) {
        final refDate = datasDeReferencia[key]!;
        String label;

        if (refDate.year == hoje.year && refDate.month == hoje.month && refDate.day == hoje.day) {
          label = 'Hoje';
        } else if (refDate.year == ontem.year && refDate.month == ontem.month && refDate.day == ontem.day) {
          label = 'Ontem';
        } else if (hoje.difference(refDate).inDays < 7) {
          label = _diaDaSemanaLabel(refDate.weekday);
        } else {
          label = '${refDate.day.toString().padLeft(2, '0')}/${refDate.month.toString().padLeft(2, '0')}/${refDate.year}';
        }

        listaGrupos.add(MediaGroup(
          dataLabel: label,
          data: refDate,
          midias: midias,
        ));
      });

      listaGrupos.sort((a, b) => b.data.compareTo(a.data));
      return listaGrupos;
    } catch (e) {
      print('[MediaSuggestionService] Erro ao obter sugestões: $e');
      return [];
    }
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
