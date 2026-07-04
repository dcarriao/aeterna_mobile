import 'package:shared_preferences/shared_preferences.dart';

import '../models/detected_moment.dart';
import 'curator_decision_log_service.dart';

/// SPRINT F — Sensibilidade dos Convites do Curador.
///
/// Pesos centralizados do sistema de pontuação. NENHUM outro arquivo deve
/// conter números mágicos relacionados a esta decisão — qualquer ajuste de
/// sensibilidade deve ser feito exclusivamente aqui.
class CuratorScoringWeights {
  const CuratorScoringWeights._();

  static const int possuiVideo = 30;
  static const int maisDe5Fotos = 20;
  static const int maisDe15Fotos = 35;
  static const int midiasEmIntervaloCurto = 20;
  static const int momentoRecente = 25;
  static const int jaExisteMemoriaParaMidia = -100;
  static const int usuarioIgnorouSugestaoSemelhante = -30;
  static const int jaHouveConviteHoje = -100;
  static const int jaHouve2ConvitesNaSemana = -100;

  /// Somente momentos com score >= este limite podem virar convite
  /// (banner na Home ou notificação push).
  static const int minimumInvitationScore = 60;

  /// Intervalo entre a 1ª e a última mídia considerado "curto" o bastante
  /// para sugerir um evento único e contínuo.
  static const Duration intervaloCurto = Duration(minutes: 30);

  /// Janela para considerar o momento "recente" a partir de agora.
  static const Duration janelaRecente = Duration(hours: 24);

  /// Por quanto tempo um momento ignorado continua penalizando sugestões
  /// semelhantes.
  static const Duration validadeIgnorado = Duration(days: 14);

  /// Gate explícito adicional só para NOTIFICAÇÕES (não afeta o score usado
  /// pela Home): se o usuário ignorou muitas sugestões recentemente, para
  /// de notificar por push mesmo que um momento pontue bem isoladamente.
  static const int maxIgnoradosRecentesParaNotificar = 3;
  static const Duration janelaIgnoradosParaNotificar = Duration(days: 7);
}

/// Um critério individual aplicado (nome + pontuação), usado para montar o
/// motivo legível da decisão (log de auditoria).
class CriterioScore {
  const CriterioScore(this.nome, this.pontos);

  final String nome;
  final int pontos;
}

/// Resultado completo do cálculo de pontuação de um momento detectado.
class CuratorInvitationScore {
  const CuratorInvitationScore({
    required this.momentoId,
    required this.total,
    required this.criterios,
  });

  final String momentoId;
  final int total;
  final List<CriterioScore> criterios;

  /// Regra central da sprint: `score >= minimumInvitationScore`.
  bool get atingiuLimite => total >= CuratorScoringWeights.minimumInvitationScore;

  /// Texto legível do motivo da decisão, usado no log de auditoria.
  String get motivoResumido {
    final positivos =
        criterios.where((c) => c.pontos > 0).map((c) => '${c.nome} (+${c.pontos})');
    final negativos =
        criterios.where((c) => c.pontos < 0).map((c) => '${c.nome} (${c.pontos})');
    final partes = <String>[];
    if (positivos.isNotEmpty) partes.add(positivos.join(', '));
    if (negativos.isNotEmpty) partes.add(negativos.join(', '));
    partes.add(
      'Score final: $total (limite mínimo: ${CuratorScoringWeights.minimumInvitationScore})',
    );
    return partes.join(' | ');
  }
}

class CuratorInvitationScoringService {
  CuratorInvitationScoringService._();

  static final instance = CuratorInvitationScoringService._();

  // Mesma chave usada por MediaSuggestionService/MomentDetectionService —
  // reaproveitada aqui apenas para leitura (defesa em profundidade: a
  // detecção de momentos já filtra mídias usadas antes de chegar aqui).
  static const _usedAssetsKey = 'used_gallery_asset_ids';

  static const _ignoredMomentsKey = 'curator_ignored_moments';

  // Mesmas chaves usadas por CuratorInvitationService (envio de push) —
  // lidas aqui para que o mesmo limite diário/semanal valha tanto para a
  // notificação quanto para o banner da Home (evita "dupla cutucada" no
  // mesmo dia por dois canais diferentes).
  static const _lastInviteDateKey = 'last_curator_invitation_date';
  static const _weeklyInvitesKey = 'weekly_curator_invitations_dates';

  /// Calcula a pontuação de um momento detectado. Não possui efeitos
  /// colaterais (não registra nada) — quem chama decide o que fazer com o
  /// resultado e é responsável por registrar a decisão via
  /// [CuratorDecisionLogService].
  Future<CuratorInvitationScore> calcularScore(DetectedMoment momento) async {
    final prefs = await SharedPreferences.getInstance();
    final criterios = <CriterioScore>[];

    // ── Sinais positivos de relevância do conteúdo ──
    if (momento.quantidadeVideos > 0) {
      criterios.add(
        const CriterioScore('Possui vídeo', CuratorScoringWeights.possuiVideo),
      );
    }
    if (momento.quantidadeFotos > 5) {
      criterios.add(
        const CriterioScore('Mais de 5 fotos', CuratorScoringWeights.maisDe5Fotos),
      );
    }
    if (momento.quantidadeFotos > 15) {
      criterios.add(
        const CriterioScore('Mais de 15 fotos', CuratorScoringWeights.maisDe15Fotos),
      );
    }

    final totalMidias = momento.quantidadeFotos + momento.quantidadeVideos;
    if (totalMidias >= 2 &&
        momento.fim.difference(momento.inicio) <= CuratorScoringWeights.intervaloCurto) {
      criterios.add(
        const CriterioScore(
            'Mídias em intervalo curto', CuratorScoringWeights.midiasEmIntervaloCurto),
      );
    }

    if (DateTime.now().difference(momento.fim) <= CuratorScoringWeights.janelaRecente) {
      criterios.add(
        const CriterioScore('Momento recente', CuratorScoringWeights.momentoRecente),
      );
    }

    // ── Sinais negativos ──
    final usedIds = prefs.getStringList(_usedAssetsKey)?.toSet() ?? <String>{};
    final todosAssets = [...momento.fotos, ...momento.videos];
    if (todosAssets.any((a) => usedIds.contains(a.id))) {
      criterios.add(
        const CriterioScore(
            'Já existe memória para mídia', CuratorScoringWeights.jaExisteMemoriaParaMidia),
      );
    }

    if (await _foiIgnoradoRecentemente(momento.id, prefs)) {
      criterios.add(
        const CriterioScore('Usuário ignorou sugestão semelhante',
            CuratorScoringWeights.usuarioIgnorouSugestaoSemelhante),
      );
    }

    if (_jaConvidouHoje(prefs)) {
      criterios.add(
        const CriterioScore('Já houve convite hoje', CuratorScoringWeights.jaHouveConviteHoje),
      );
    }

    if (_jaConvidou2VezesNaSemana(prefs)) {
      criterios.add(
        const CriterioScore(
            'Já houve 2 convites na semana', CuratorScoringWeights.jaHouve2ConvitesNaSemana),
      );
    }

    final total = criterios.fold<int>(0, (soma, c) => soma + c.pontos);

    return CuratorInvitationScore(
      momentoId: momento.id,
      total: total,
      criterios: criterios,
    );
  }

  bool _jaConvidouHoje(SharedPreferences prefs) {
    final ultimaDataStr = prefs.getString(_lastInviteDateKey);
    if (ultimaDataStr == null) return false;
    final ultimaData = DateTime.tryParse(ultimaDataStr);
    if (ultimaData == null) return false;
    final agora = DateTime.now();
    return ultimaData.year == agora.year &&
        ultimaData.month == agora.month &&
        ultimaData.day == agora.day;
  }

  bool _jaConvidou2VezesNaSemana(SharedPreferences prefs) {
    final enviosSemana = prefs.getStringList(_weeklyInvitesKey) ?? <String>[];
    final seteDiasAtras = DateTime.now().subtract(const Duration(days: 7));
    final enviosValidos = enviosSemana
        .map((s) => DateTime.tryParse(s))
        .where((d) => d != null && d.isAfter(seteDiasAtras))
        .length;
    return enviosValidos >= 2;
  }

  /// Registra que o usuário descartou ("Agora não") um momento — usado para
  /// penalizar sugestões semelhantes no futuro (critério
  /// `usuarioIgnorouSugestaoSemelhante`).
  Future<void> registrarMomentoIgnorado(String momentoId) async {
    final prefs = await SharedPreferences.getInstance();
    final ignorados = prefs.getStringList(_ignoredMomentsKey) ?? <String>[];
    // Formato: "<momentoId>|<timestampIso>"
    ignorados.add('$momentoId|${DateTime.now().toIso8601String()}');
    await prefs.setStringList(_ignoredMomentsKey, ignorados);
  }

  /// Gate adicional específico para NOTIFICAÇÕES: usuário recusou/ignorou
  /// muitas sugestões na última semana (independente de serem "a mesma"
  /// sugestão ou não).
  Future<bool> usuarioRecusouMuitasVezesRecentemente() async {
    final prefs = await SharedPreferences.getInstance();
    final ignorados = prefs.getStringList(_ignoredMomentsKey) ?? <String>[];
    final agora = DateTime.now();
    final recentes = ignorados.where((entrada) {
      final partes = entrada.split('|');
      if (partes.length != 2) return false;
      final quando = DateTime.tryParse(partes[1]);
      if (quando == null) return false;
      return agora.difference(quando) <= CuratorScoringWeights.janelaIgnoradosParaNotificar;
    }).length;
    return recentes >= CuratorScoringWeights.maxIgnoradosRecentesParaNotificar;
  }

  Future<bool> _foiIgnoradoRecentemente(String momentoId, SharedPreferences prefs) async {
    final ignorados = prefs.getStringList(_ignoredMomentsKey) ?? <String>[];
    final agora = DateTime.now();
    for (final entrada in ignorados) {
      final partes = entrada.split('|');
      if (partes.length != 2) continue;
      if (partes[0] != momentoId) continue;
      final quando = DateTime.tryParse(partes[1]);
      if (quando == null) continue;
      if (agora.difference(quando) <= CuratorScoringWeights.validadeIgnorado) {
        return true;
      }
    }
    return false;
  }
}
