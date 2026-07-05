import 'package:flutter/material.dart';

import 'detected_moment.dart';
import 'memoria_do_dia.dart';

enum ProactiveOpportunityType {
  videoNovo,
  grupoDeFotos,
  midiasEmIntervalo,
  memoriaDoDia,
}

class ProactiveOpportunity {
  const ProactiveOpportunity({
    required this.type,
    required this.priority,
    required this.titulo,
    required this.descricao,
    required this.icone,
    this.detectedMoment,
    this.memoriaDoDia,
    this.quantidadeFotos = 0,
    this.quantidadeVideos = 0,
    this.dataRef,
    this.temVideo = false,
  });

  final ProactiveOpportunityType type;
  final int priority;
  final String titulo;
  final String descricao;
  final IconData icone;
  final DetectedMoment? detectedMoment;
  final MemoriaDoDia? memoriaDoDia;
  final int quantidadeFotos;
  final int quantidadeVideos;
  final DateTime? dataRef;
  final bool temVideo;

  String get oportunidadeId {
    if (detectedMoment != null) return 'detected_${detectedMoment!.id}';
    if (memoriaDoDia != null) return 'diaria_${memoriaDoDia!.id}';
    return '${type.name}_${DateTime.now().millisecondsSinceEpoch}';
  }

  bool get temMidias => quantidadeFotos > 0 || quantidadeVideos > 0;
}
