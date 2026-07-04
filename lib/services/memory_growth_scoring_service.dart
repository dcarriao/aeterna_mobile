import 'package:shared_preferences/shared_preferences.dart';

import '../models/memoria_pode_crescer.dart';
import '../models/pessoa.dart';

/// SPRINT I — Pesos centralizados do score "essa memória pode crescer".
///
/// Toda decisão da sprint (banner da Home, banner da MemoriaDetalhe,
/// notificação push) usa este serviço. Os pesos são inalterados
/// em outras partes do código — ajuste aqui para mudar a
/// sensibilidade em uma única linha.
class MemoryGrowthWeights {
  const MemoryGrowthWeights._();

  // ── Sinais positivos ──
  /// Existem mídias (fotos/vídeos) na memória que o Curador não
  /// inventariou (placeholder heurístico: muitas fotos, mas nenhuma
  /// contribuição complementar vinculada).
  static const int haMuitasMidias = 40;

  /// Existe pelo menos um colaborador autorizado que ainda não
  /// contribuiu.
  static const int colaboradorNaoContribuiu = 30;

  /// A memória foi escrita por um único autor (sem outros
  /// participantes cadastrados).
  static const int autorUnico = 20;

  /// Última atualização há mais de 90 dias — sinal de "carente".
  static const int ultimaAtualizacaoAntiga = 15;

  /// Poucas mídias (≤2 fotos e nenhum vídeo) — sinal de "incompleta".
  static const int poucasMidias = 10;

  // ── Sinais negativos ──
  /// Já existe convite pendente para esta memória (apenas dono, mas
  /// o sistema de pontuação filtra esses por padrão).
  static const int jaTemConvitePendente = -100;

  /// O usuário recusou recentemente um convite semelhante (não
  /// implementado nesta sprint — placeholder para evolução).
  static const int usuarioRecusouRecentemente = -100;

  // ── Limite mínimo (regra central da sprint) ──
  static const int minimumInvitationScore = 50;

  // ── Janela de "antiga" (em dias) ──
  static const int janelaAntigaDias = 90;

  // ── Identifica "muitas mídias" para pontuar +40 ──
  static const int totalMidiasParaBonus = 5;
}

class CriterioScoreCrescimento {
  const CriterioScoreCrescimento(this.nome, this.pontos);
  final String nome;
  final int pontos;
}

class MemoryGrowthScore {
  const MemoryGrowthScore({
    required this.memoriaId,
    required this.total,
    required this.criterios,
  });

  final int memoriaId;
  final int total;
  final List<CriterioScoreCrescimento> criterios;

  bool get atingiuLimite => total >= MemoryGrowthWeights.minimumInvitationScore;

  String get motivoResumido {
    final positivos = criterios
        .where((c) => c.pontos > 0)
        .map((c) => '${c.nome} (+${c.pontos})');
    final negativos = criterios
        .where((c) => c.pontos < 0)
        .map((c) => '${c.nome} (${c.pontos})');
    final partes = <String>[];
    if (positivos.isNotEmpty) partes.add(positivos.join(', '));
    if (negativos.isNotEmpty) partes.add(negativos.join(', '));
    partes.add('Score: $total (limite ${MemoryGrowthWeights.minimumInvitationScore})');
    return partes.join(' | ');
  }
}

class MemoryGrowthScoringService {
  MemoryGrowthScoringService._();
  static final instance = MemoryGrowthScoringService._();

  // Chave de tracking local (memorias cujo convite foi dispensado).
  static const _dispensadasKey = 'memory_growth_dispensadas';

  /// Calcula o score de uma memória. Sem efeitos colaterais.
  Future<MemoryGrowthScore> calcularScore(MemoriaPodeCrescer m) async {
    final criterios = <CriterioScoreCrescimento>[];

    // +40: muitas mídias (≥5 fotos/vídeos)
    final totalMidias = m.totalFotos + m.totalVideos;
    if (totalMidias >= MemoryGrowthWeights.totalMidiasParaBonus) {
      criterios.add(const CriterioScoreCrescimento(
          'Muitas mídias ainda sem contribuição', MemoryGrowthWeights.haMuitasMidias));
    }

    // +30: existe colaborador autorizado que nunca contribuiu
    if (m.temColaboradores &&
        m.contribuidoresUnicos < m.totalColaboradores) {
      criterios.add(const CriterioScoreCrescimento(
          'Colaborador que ainda não contribuiu', MemoryGrowthWeights.colaboradorNaoContribuiu));
    }

    // +20: autor único (sem outros participantes)
    if (m.totalPessoas <= 1) {
      criterios.add(const CriterioScoreCrescimento(
          'Memória com autor único', MemoryGrowthWeights.autorUnico));
    }

    // +15: última atualização > 90 dias
    if (m.diasDesdeUltimaAtualizacao > MemoryGrowthWeights.janelaAntigaDias) {
      criterios.add(const CriterioScoreCrescimento(
          'Última atualização há mais de 90 dias', MemoryGrowthWeights.ultimaAtualizacaoAntiga));
    }

    // +10: poucas mídias (≤2 fotos e nenhum vídeo)
    if (m.totalFotos <= 2 && m.totalVideos == 0) {
      criterios.add(const CriterioScoreCrescimento(
          'Poucas mídias vinculadas', MemoryGrowthWeights.poucasMidias));
    }

    // -100: já tem convite pendente (não bloqueia o score, mas o serviço
    // chamador filtra esses fora antes de calcular)
    if (m.totalContribuicoesPendentes > 0) {
      criterios.add(const CriterioScoreCrescimento(
          'Convite pendente', MemoryGrowthWeights.jaTemConvitePendente));
    }

    final total = criterios.fold<int>(0, (s, c) => s + c.pontos);
    return MemoryGrowthScore(memoriaId: m.memoriaId, total: total, criterios: criterios);
  }

  /// Registra que o usuário dispensou o convite desta memória
  /// (clique em "Agora não" / "Mais tarde"). Penaliza sugestões
  /// futuras: a memória só volta a aparecer após o TTL expirar.
  Future<void> dispensarConvite(int memoriaId,
      {Duration ttl = const Duration(days: 7)}) async {
    final prefs = await SharedPreferences.getInstance();
    final dispensadas = prefs.getStringList(_dispensadasKey) ?? <String>[];
    // formato: "<memoriaId>|<timestampIso>"
    final expiracao = DateTime.now().add(ttl);
    dispensadas.removeWhere((e) {
      final parts = e.split('|');
      if (parts.length != 2) return true;
      final exp = DateTime.tryParse(parts[1]);
      return exp == null || exp.isBefore(DateTime.now());
    });
    dispensadas.add('$memoriaId|${expiracao.toIso8601String()}');
    await prefs.setStringList(_dispensadasKey, dispensadas);
  }

  Future<bool> foiDispensadaRecentemente(int memoriaId) async {
    final prefs = await SharedPreferences.getInstance();
    final dispensadas = prefs.getStringList(_dispensadasKey) ?? <String>[];
    for (final e in dispensadas) {
      final parts = e.split('|');
      if (parts.length != 2) continue;
      if (parts[0] != memoriaId.toString()) continue;
      final exp = DateTime.tryParse(parts[1]);
      if (exp == null) continue;
      if (exp.isAfter(DateTime.now())) return true;
    }
    return false;
  }
}
