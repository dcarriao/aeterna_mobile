/// Sprint M — "Memórias do Dia".
///
/// Resultado da RPC `memorias_do_dia(usuario, limite)`: memória cujo
/// `data_evento` (fallback `criada_em`) coincide com o dia/mês de
/// HOJE, em anos anteriores. Sem IA — match determinístico.
class MemoriaDoDia {
  const MemoriaDoDia({
    required this.id,
    required this.titulo,
    this.fotoPrincipal,
    required this.totalPessoas,
    required this.totalContribuicoes,
    required this.totalMidias,
    required this.possuiRelacionamentos,
    required this.anosDecorridos,
    required this.dataReferencia,
  });

  final int id;
  final String titulo;
  final String? fotoPrincipal;
  final int totalPessoas;
  final int totalContribuicoes;
  final int totalMidias;
  final bool possuiRelacionamentos;
  final int anosDecorridos;
  final DateTime dataReferencia;

  /// Rótulo humano do tempo decorrido: "Há 3 anos", "Há 1 ano",
  /// "Há 11 meses", "Há 5 dias".
  String get rotuloTempo {
    final agora = DateTime.now();
    final delta = agora.difference(dataReferencia);
    if (delta.inDays < 1) return 'Há pouco';
    if (delta.inDays < 30) return 'Há ${delta.inDays} dias';
    if (delta.inDays < 365) {
      final meses = (delta.inDays / 30).floor();
      return 'Há $meses ${meses == 1 ? 'mês' : 'meses'}';
    }
    final anos = anosDecorridos;
    return 'Há $anos ${anos == 1 ? 'ano' : 'anos'}';
  }

  factory MemoriaDoDia.fromMap(Map<String, dynamic> map) {
    return MemoriaDoDia(
      id: (map['id'] as num).toInt(),
      titulo: map['titulo'] as String? ?? '',
      fotoPrincipal: map['foto_principal'] as String?,
      totalPessoas: (map['total_pessoas'] as num?)?.toInt() ?? 0,
      totalContribuicoes:
          (map['total_contribuicoes'] as num?)?.toInt() ?? 0,
      totalMidias: (map['total_midias'] as num?)?.toInt() ?? 0,
      possuiRelacionamentos:
          map['possui_relacionamentos'] == true,
      anosDecorridos: (map['anos_decorridos'] as num?)?.toInt() ?? 0,
      dataReferencia: DateTime.tryParse('${map['data_referencia']}') ??
          DateTime.now(),
    );
  }
}
