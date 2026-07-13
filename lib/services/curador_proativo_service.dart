import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/detected_moment.dart';
import '../models/proactive_opportunity.dart';
import 'memorias_do_dia_service.dart';
import 'moment_detection_service.dart';

class CuradorProativoService {
  CuradorProativoService._();
  static final instance = CuradorProativoService._();

  static const _dismissedKey = 'proactive_dismissed';
  static const _lastProactiveDateKey = 'last_proactive_date';
  static const _weeklyProactiveKey = 'weekly_proactive_dates';

  static const _maxPerDay = 1;
  static const _maxPerWeek = 2;

  Future<ProactiveOpportunity?> obterMelhorOportunidade() async {
    final oportunidades = <ProactiveOpportunity>[];

    // Prioridade 1: videos novos
    final momentoVideo = await _buscarMomentoComVideo();
    if (momentoVideo != null) {
      oportunidades.add(momentoVideo);
    }

    // Prioridade 2: grupo de fotos
    if (oportunidades.isEmpty) {
      final grupoFotos = await _buscarGrupoDeFotos();
      if (grupoFotos != null) {
        oportunidades.add(grupoFotos);
      }
    }

    // Prioridade 3: varias midias em curto intervalo
    if (oportunidades.isEmpty) {
      final intervalo = await _buscarIntervaloCurto();
      if (intervalo != null) {
        oportunidades.add(intervalo);
      }
    }

    // Prioridade 5: memoria do dia
    if (oportunidades.isEmpty) {
      final diaria = await _buscarMemoriaDoDia();
      if (diaria != null) {
        oportunidades.add(diaria);
      }
    }

    return oportunidades.isNotEmpty ? oportunidades.first : null;
  }

  Future<ProactiveOpportunity?> _buscarMomentoComVideo() async {
    final momentos = await MomentDetectionService.instance.obterMomentosDetectados();
    for (final m in momentos) {
      if (m.quantidadeVideos > 0) {
        return ProactiveOpportunity(
          type: ProactiveOpportunityType.videoNovo,
          priority: 1,
          titulo: 'Video encontrado',
          descricao: 'Video ${_formatarTempo(m.inicio)}',
          icone: Icons.videocam_outlined,
          detectedMoment: m,
          quantidadeFotos: m.quantidadeFotos,
          quantidadeVideos: m.quantidadeVideos,
          dataRef: m.inicio,
          temVideo: true,
        );
      }
    }
    return null;
  }

  Future<ProactiveOpportunity?> _buscarGrupoDeFotos() async {
    final momentos = await MomentDetectionService.instance.obterMomentosDetectados();
    for (final m in momentos) {
      if (m.quantidadeFotos >= 5 && m.quantidadeVideos == 0) {
        return ProactiveOpportunity(
          type: ProactiveOpportunityType.grupoDeFotos,
          priority: 2,
          titulo: 'Fotos do momento',
          descricao: '${m.quantidadeFotos} fotos ${_formatarTempo(m.inicio)}',
          icone: Icons.photo_library_outlined,
          detectedMoment: m,
          quantidadeFotos: m.quantidadeFotos,
          quantidadeVideos: m.quantidadeVideos,
          dataRef: m.inicio,
        );
      }
    }
    return null;
  }

  Future<ProactiveOpportunity?> _buscarIntervaloCurto() async {
    final momentos = await MomentDetectionService.instance.obterMomentosDetectados();
    for (final m in momentos) {
      final total = m.quantidadeFotos + m.quantidadeVideos;
      if (total >= 3) {
        return ProactiveOpportunity(
          type: ProactiveOpportunityType.midiasEmIntervalo,
          priority: 3,
          titulo: 'Momento especial',
          descricao: '${m.quantidadeFotos} fotos e ${m.quantidadeVideos} vídeos ${_formatarTempo(m.inicio)}',
          icone: Icons.auto_awesome_outlined,
          detectedMoment: m,
          quantidadeFotos: m.quantidadeFotos,
          quantidadeVideos: m.quantidadeVideos,
          dataRef: m.inicio,
        );
      }
    }
    return null;
  }

  Future<ProactiveOpportunity?> _buscarMemoriaDoDia() async {
    final diarias = await MemoriasDoDiaService.instance.listarParaHome(limite: 1);
    if (diarias.isNotEmpty) {
      final d = diarias.first;
      return ProactiveOpportunity(
        type: ProactiveOpportunityType.memoriaDoDia,
        priority: 5,
        titulo: d.titulo,
        descricao: d.rotuloTempo,
        icone: Icons.auto_stories_outlined,
        memoriaDoDia: d,
        dataRef: d.dataReferencia,
      );
    }
    return null;
  }

  Future<void> registrarExibicao() async {
    final prefs = await SharedPreferences.getInstance();
    final agora = DateTime.now();
    await prefs.setString(_lastProactiveDateKey, agora.toIso8601String());
    final semana = prefs.getStringList(_weeklyProactiveKey) ?? [];
    semana.add(agora.toIso8601String());
    await prefs.setStringList(_weeklyProactiveKey, semana);
  }

  Future<void> registrarDispensa(String oportunidadeId) async {
    final prefs = await SharedPreferences.getInstance();
    final dispensados = prefs.getStringList(_dismissedKey) ?? [];
    dispensados.add('$oportunidadeId|${DateTime.now().toIso8601String()}');
    await prefs.setStringList(_dismissedKey, dispensados);
  }

  bool _atingiuLimiteDiario(SharedPreferences prefs) {
    final ultima = prefs.getString(_lastProactiveDateKey);
    if (ultima == null) return false;
    final data = DateTime.tryParse(ultima);
    if (data == null) return false;
    final hoje = DateTime.now();
    return data.year == hoje.year &&
        data.month == hoje.month &&
        data.day == hoje.day;
  }

  bool _atingiuLimiteSemanal(SharedPreferences prefs) {
    final datas = prefs.getStringList(_weeklyProactiveKey) ?? [];
    final semanaAtras = DateTime.now().subtract(const Duration(days: 7));
    final validos = datas
        .map((s) => DateTime.tryParse(s))
        .where((d) => d != null && d.isAfter(semanaAtras))
        .length;
    return validos >= _maxPerWeek;
  }

  Set<String> _carregarDispensados(SharedPreferences prefs) {
    final dispensados = prefs.getStringList(_dismissedKey) ?? [];
    final agora = DateTime.now();
    final ativos = <String>{};
    for (final entrada in dispensados) {
      final partes = entrada.split('|');
      if (partes.length != 2) continue;
      final quando = DateTime.tryParse(partes[1]);
      if (quando == null) continue;
      // Expira apos 7 dias
      if (agora.difference(quando).inDays < 7) {
        ativos.add(partes[0]);
      }
    }
    return ativos;
  }

  String _formatarTempo(DateTime data) {
    final agora = DateTime.now();
    final diff = agora.difference(data);
    if (diff.inMinutes < 60) return 'há ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'há ${diff.inHours}h';
    if (diff.inDays == 1) return 'ontem';
    return 'há ${diff.inDays} dias';
  }
}
