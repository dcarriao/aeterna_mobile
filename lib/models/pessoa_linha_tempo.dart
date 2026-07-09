/// Sprint H — Modelos da "Linha do Tempo da Pessoa".
///
/// Cada pessoa (contato cadastrado) passa a ter uma "linha do tempo"
/// agregada, construída a partir de memórias, fotos, vídeos e
/// contribuições em que ela aparece. Os modelos abaixo são as estruturas
/// client-side espelhando a view `public.pessoa_linha_tempo` do Supabase.

/// Tipos de evento que podem aparecer na linha do tempo da pessoa.
enum PessoaTimelineTipo {
  memoria,
  foto,
  contribuicao,
  video;

  String get rotulo {
    switch (this) {
      case PessoaTimelineTipo.memoria:
        return 'Memória';
      case PessoaTimelineTipo.foto:
        return 'Foto';
      case PessoaTimelineTipo.contribuicao:
        return 'Contribuição';
      case PessoaTimelineTipo.video:
        return 'Vídeo';
    }
  }
}

class PessoaTimelineEvento {
  const PessoaTimelineEvento({
    required this.tipo,
    required this.conteudoId,
    required this.titulo,
    required this.data,
    this.memoriaOrigemId,
    this.contribuicaoId,
    this.autorContribuicao,
    this.fotoUrl,
    this.videoUrl,
  });

  final PessoaTimelineTipo tipo;
  final int conteudoId;
  final String titulo;
  final DateTime data;
  final int? memoriaOrigemId;
  final int? contribuicaoId;
  final String? autorContribuicao;
  final String? fotoUrl;
  final String? videoUrl;

  factory PessoaTimelineEvento.fromMap(Map<String, dynamic> map) {
    final tipoStr = map['tipo'] as String? ?? 'memoria';
    final tipo = PessoaTimelineTipo.values.firstWhere(
      (t) => t.name == tipoStr,
      orElse: () => PessoaTimelineTipo.memoria,
    );
    return PessoaTimelineEvento(
      tipo: tipo,
      conteudoId: (map['conteudo_id'] as num).toInt(),
      titulo: map['titulo'] as String? ?? '',
      data: DateTime.tryParse('${map['data_ordem']}') ?? DateTime.now(),
      memoriaOrigemId: (map['memoria_origem_id'] as num?)?.toInt(),
      contribuicaoId: (map['contribuicao_id'] as num?)?.toInt(),
      autorContribuicao: map['autor_contribuicao'] as String?,
      // fotoUrl e videoUrl são enriquecidos depois (segunda query), não
      // vêm da view (que só traz IDs).
    );
  }
}

/// Contadores agregados da pessoa.
class PessoaEstatisticas {
  const PessoaEstatisticas({
    required this.totalMemorias,
    required this.totalFotos,
    required this.totalVideos,
    required this.totalContribuicoes,
    this.primeiraData,
    this.ultimaData,
  });

  final int totalMemorias;
  final int totalFotos;
  final int totalVideos;
  final int totalContribuicoes;
  final DateTime? primeiraData;
  final DateTime? ultimaData;

  int get totalEventos => totalMemorias + totalFotos + totalVideos + totalContribuicoes;

  factory PessoaEstatisticas.fromMap(Map<String, dynamic> map) {
    return PessoaEstatisticas(
      totalMemorias: (map['total_memorias'] as num?)?.toInt() ?? 0,
      totalFotos: (map['total_fotos'] as num?)?.toInt() ?? 0,
      totalVideos: (map['total_videos'] as num?)?.toInt() ?? 0,
      totalContribuicoes: (map['total_contribuicoes'] as num?)?.toInt() ?? 0,
      primeiraData: map['primeira_data'] != null
          ? DateTime.tryParse('${map['primeira_data']}')
          : null,
      ultimaData: map['ultima_data'] != null
          ? DateTime.tryParse('${map['ultima_data']}')
          : null,
    );
  }
}

/// "Pessoa recente" para a Home — pessoa com a maior "última interação"
/// recente. Diferente de `Pessoa` (model do cadastro) porque é uma
/// projeção leve com apenas os campos de exibição.
class PessoaVivaResumo {
  const PessoaVivaResumo({
    required this.id,
    required this.nome,
    required this.parentesco,
    this.email,
    this.fotoUrl,
    this.ultimaInteracao,
    required this.totalEventos,
  });

  final int id;
  final String nome;
  final String parentesco;
  final String? email;
  final String? fotoUrl;
  final DateTime? ultimaInteracao;
  final int totalEventos;

  String get nomeCompleto {
    if (parentesco.isEmpty) return nome;
    return '$nome · $parentesco';
  }

  String get ultimaInteracaoHumana {
    if (ultimaInteracao == null) return 'Nenhuma memória';
    final diff = DateTime.now().difference(ultimaInteracao);
    if (diff.inMinutes < 1) return 'agora';
    if (diff.inHours < 1) return 'há ${diff.inMinutes} min';
    if (diff.inDays < 1) return 'há ${diff.inHours} h';
    if (diff.inDays == 1) return 'ontem';
    if (diff.inDays < 7) return 'há ${diff.inDays} dias';
    if (diff.inDays < 30) return 'há ${(diff.inDays / 7).floor()} sem';
    return '${ultimaInteracao.day.toString().padLeft(2, '0')}/'
        '${ultimaInteracao.month.toString().padLeft(2, '0')}/'
        '${ultimaInteracao.year}';
  }

  factory PessoaVivaResumo.fromMap(Map<String, dynamic> map) {
    return PessoaVivaResumo(
      id: (map['id'] as num).toInt(),
      nome: (map['nome'] as String? ?? '') +
          (map['sobrenome'] != null && (map['sobrenome'] as String).isNotEmpty
              ? ' ${map['sobrenome']}'
              : ''),
      parentesco: map['parentesco'] as String? ?? 'Outro',
      email: map['email'] as String?,
      fotoUrl: map['foto_perfil'] as String?,
      ultimaInteracao: DateTime.tryParse('${map['ultima_interacao']}'),
      totalEventos: (map['total_eventos'] as num?)?.toInt() ?? 0,
    );
  }
}

/// "Pessoa sugerida" para descoberta automática — nome que aparece em
/// memórias mas ainda não foi cadastrado.
class PessoaSugerida {
  const PessoaSugerida({
    required this.nome,
    required this.ocorrencias,
  });

  final String nome;
  final int ocorrencias;

  factory PessoaSugerida.fromMap(Map<String, dynamic> map) {
    return PessoaSugerida(
      nome: map['nome_sugerido'] as String? ?? '',
      ocorrencias: (map['ocorrencias'] as num?)?.toInt() ?? 0,
    );
  }
}

/// "Memorial da pessoa" — vínculo Pessoa → Memorial.
class MemorialResumo {
  const MemorialResumo({required this.id, required this.nome});

  final int id;
  final String nome;

  factory MemorialResumo.fromMap(Map<String, dynamic> map) {
    return MemorialResumo(
      id: (map['memorial_id'] as num).toInt(),
      nome: map['nome'] as String? ?? '',
    );
  }
}
