/// Sprint I — Resumo de uma memória para a heurística "pode crescer".
/// Espelha os campos da VIEW `memorias_evolucao_resumo` no Supabase.
class MemoriaPodeCrescer {
  const MemoriaPodeCrescer({
    required this.memoriaId,
    required this.titulo,
    required this.categoria,
    this.dataEvento,
    required this.ultimaAtualizacaoEm,
    required this.diasDesdeUltimaAtualizacao,
    required this.totalPessoas,
    required this.totalContribuicoes,
    required this.totalContribuicoesPendentes,
    required this.totalFotos,
    required this.totalVideos,
    required this.temColaboradores,
    required this.totalColaboradores,
    required this.contribuidoresUnicos,
  });

  final int memoriaId;
  final String titulo;
  final String categoria;
  final DateTime? dataEvento;
  final DateTime ultimaAtualizacaoEm;
  final double diasDesdeUltimaAtualizacao;
  final int totalPessoas;
  final int totalContribuicoes;
  final int totalContribuicoesPendentes;
  final int totalFotos;
  final int totalVideos;
  final bool temColaboradores;
  final int totalColaboradores;
  final int contribuidoresUnicos;

  factory MemoriaPodeCrescer.fromMap(Map<String, dynamic> map) {
    return MemoriaPodeCrescer(
      memoriaId: (map['memoria_id'] as num).toInt(),
      titulo: map['titulo'] as String? ?? '',
      categoria: map['categoria'] as String? ?? 'momentos',
      dataEvento: map['data_evento'] != null
          ? DateTime.tryParse('${map['data_evento']}')
          : null,
      ultimaAtualizacaoEm:
          DateTime.tryParse('${map['ultima_atualizacao_em']}') ?? DateTime.now(),
      diasDesdeUltimaAtualizacao:
          (map['dias_desde_ultima_atualizacao'] as num?)?.toDouble() ?? 0,
      totalPessoas: (map['total_pessoas'] as num?)?.toInt() ?? 0,
      totalContribuicoes: (map['total_contribuicoes'] as num?)?.toInt() ?? 0,
      totalContribuicoesPendentes:
          (map['total_contribuicoes_pendentes'] as num?)?.toInt() ?? 0,
      totalFotos: (map['total_fotos'] as num?)?.toInt() ?? 0,
      totalVideos: (map['total_videos'] as num?)?.toInt() ?? 0,
      temColaboradores: (map['tem_colaboradores'] as bool?) ?? false,
      totalColaboradores: (map['total_colaboradores'] as num?)?.toInt() ?? 0,
      contribuidoresUnicos: (map['contribuidores_unicos'] as num?)?.toInt() ?? 0,
    );
  }
}
