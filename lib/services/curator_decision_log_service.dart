import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/detected_moment.dart';
import 'curator_invitation_scoring_service.dart';

/// SPRINT F — Registro local de decisões do Curador (auditoria).
///
/// Guarda, para cada momento detectado avaliado: o score calculado, se um
/// convite foi criado (banner/notificação), o motivo textual da decisão,
/// data/hora e a ação do usuário (abriu, ignorou, recusou, criou memória).
///
/// Justificativa para NÃO usar Supabase (ver auditoria da sprint): toda a
/// cadeia de detecção de mídia/momentos (`MediaSuggestionService`,
/// `MomentDetectionService`, `PendingMemoryService`) já é 100% local
/// (photo_manager + SharedPreferences), por decisão de arquitetura anterior
/// registrada no projeto — os IDs de asset da galeria (`AssetEntity.id`) só
/// fazem sentido no aparelho onde foram gerados, não são portáveis entre
/// dispositivos, e a conta de usuário só existe no Supabase, criando um
/// descasamento de escopo. Persistir esse log localmente mantém a mesma
/// decisão de arquitetura já adotada para todo o pipeline de detecção.
class CuratorDecisionLogService {
  CuratorDecisionLogService._();

  static final instance = CuratorDecisionLogService._();

  static const _key = 'curator_decision_log';
  static const _maxEntries = 100;

  Future<void> registrarDecisao({
    required DetectedMoment momento,
    required CuratorInvitationScore score,
    required bool conviteCriado,
    String acaoUsuario = 'pendente',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = await _carregarBruto(prefs);

    lista.insert(0, {
      'momentoId': momento.id,
      'score': score.total,
      'conviteCriado': conviteCriado,
      'motivo': score.motivoResumido,
      'dataHora': DateTime.now().toIso8601String(),
      'acaoUsuario': acaoUsuario,
      'quantidadeFotos': momento.quantidadeFotos,
      'quantidadeVideos': momento.quantidadeVideos,
    });

    if (lista.length > _maxEntries) {
      lista.removeRange(_maxEntries, lista.length);
    }

    await prefs.setString(_key, jsonEncode(lista));
  }

  /// Atualiza a ação do usuário para a decisão mais recente daquele
  /// [momentoId] (ex.: 'ignorou', 'abriu', 'criou_memoria').
  Future<void> atualizarAcaoUsuario(String momentoId, String acao) async {
    final prefs = await SharedPreferences.getInstance();
    final lista = await _carregarBruto(prefs);
    final index = lista.indexWhere((e) => e['momentoId'] == momentoId);
    if (index != -1) {
      lista[index]['acaoUsuario'] = acao;
      await prefs.setString(_key, jsonEncode(lista));
    }
  }

  Future<List<Map<String, dynamic>>> listarDecisoes() async {
    final prefs = await SharedPreferences.getInstance();
    return _carregarBruto(prefs);
  }

  Future<List<Map<String, dynamic>>> _carregarBruto(SharedPreferences prefs) async {
    final raw = prefs.getString(_key);
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }
}
