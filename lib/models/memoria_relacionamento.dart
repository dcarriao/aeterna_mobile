/// Sprint K — Modelos de relacionamento entre memórias.
///
/// Não duplicam o conteúdo das memórias — guardam apenas metadados
/// (origem, destino, score, motivos) que apontam para `memorias(id)`.

/// Status de uma relação entre memórias.
/// - `pendente` (default): heurística sugeriu, usuário ainda não viu.
/// - `confirmado`: usuário aceitou — a relação aparece em todas as telas.
/// - `ignorado`: usuário rejeitou — a heurística não sugerirá de novo.
enum RelacionamentoStatus {
  pendente,
  confirmado,
  ignorado;

  String get valor => name;

  static RelacionamentoStatus fromValor(String? v) {
    switch (v) {
      case 'confirmado':
        return RelacionamentoStatus.confirmado;
      case 'ignorado':
        return RelacionamentoStatus.ignorado;
      case 'pendente':
      default:
        return RelacionamentoStatus.pendente;
    }
  }
}

/// Uma relação entre duas memórias (calculada por heurística client-side
/// e persistida em `memoria_relacionamentos`).
class MemoriaRelacionamento {
  const MemoriaRelacionamento({
    this.id,
    required this.usuarioId,
    required this.memoriaOrigemId,
    required this.memoriaDestinoId,
    required this.score,
    required this.motivos,
    this.status = RelacionamentoStatus.pendente,
    this.criadoEm,
    this.atualizadoEm,
    this.tituloOrigem,
    this.tituloDestino,
  });

  final int? id;
  final int usuarioId;
  final int memoriaOrigemId;
  final int memoriaDestinoId;
  final int score;
  final RelacionamentoMotivos motivos;
  final RelacionamentoStatus status;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  // Campos opcionais preenchidos quando a relação vem do join com
  // `memorias` (para exibir na UI).
  final String? tituloOrigem;
  final String? tituloDestino;

  factory MemoriaRelacionamento.fromMap(Map<String, dynamic> map) {
    final motivosMap = (map['motivos'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return MemoriaRelacionamento(
      id: (map['id'] as num?)?.toInt(),
      usuarioId: (map['usuario_id'] as num? ?? 0).toInt(),
      memoriaOrigemId: (map['memoria_origem_id'] as num).toInt(),
      memoriaDestinoId: (map['memoria_destino_id'] as num).toInt(),
      score: (map['score'] as num? ?? 0).toInt(),
      motivos: RelacionamentoMotivos.fromMap(motivosMap),
      status:
          RelacionamentoStatus.fromValor(map['status'] as String?),
      criadoEm: map['criado_em'] != null
          ? DateTime.tryParse('${map['criado_em']}')
          : null,
      atualizadoEm: map['atualizado_em'] != null
          ? DateTime.tryParse('${map['atualizado_em']}')
          : null,
      tituloOrigem: map['titulo_origem'] as String?,
      tituloDestino: map['titulo_destino'] as String?,
    );
  }
}

/// Motivos pelos quais 2 memórias foram consideradas relacionadas.
/// Cada campo é uma flag (true se aplicou ao score).
class RelacionamentoMotivos {
  const RelacionamentoMotivos({
    this.mesmaPessoa = false,
    this.mesmoMes = false,
    this.mesmoLocal = false,
    this.mesmoTitulo = false,
    this.mesmaCategoria = false,
    this.mesmoContexto = false,
    this.datasProximas = false,
    this.totalPessoasEmComum = 0,
    this.totalSinais = 0,
  });

  final bool mesmaPessoa;
  final bool mesmoMes;
  final bool mesmoLocal;
  final bool mesmoTitulo;
  final bool mesmaCategoria;
  final bool mesmoContexto;
  final bool datasProximas;
  final int totalPessoasEmComum;
  final int totalSinais;

  /// 1-2 frases curtas para a UI ("Relacionada porque: ...").
  List<String> get legendasHumanas {
    final saidas = <String>[];
    if (mesmoTitulo) {
      saidas.add('Mesmo título');
    }
    if (mesmaPessoa) {
      saidas.add(
        totalPessoasEmComum > 1
            ? '$totalPessoasEmComum pessoas em comum'
            : 'Participaram das mesmas pessoas',
      );
    } else if (totalPessoasEmComum > 0) {
      saidas.add('Alguma pessoa em comum');
    }
    if (mesmoMes) {
      saidas.add('Mesmo mês');
    } else if (datasProximas) {
      saidas.add('Datas próximas');
    }
    if (mesmaCategoria) {
      saidas.add('Mesma categoria');
    }
    if (mesmoLocal) {
      saidas.add('Mesmo local');
    }
    if (mesmoContexto) {
      saidas.add('Contexto semelhante');
    }
    return saidas;
  }

  factory RelacionamentoMotivos.fromMap(Map<String, dynamic> map) {
    return RelacionamentoMotivos(
      mesmaPessoa: map['mesma_pessoa'] == true,
      mesmoMes: map['mesmo_mes'] == true,
      mesmoLocal: map['mesmo_local'] == true,
      mesmoTitulo: map['mesmo_titulo'] == true,
      mesmaCategoria: map['mesma_categoria'] == true,
      mesmoContexto: map['mesmo_contexto'] == true,
      datasProximas: map['datas_proximas'] == true,
      totalPessoasEmComum:
          (map['total_pessoas_em_comum'] as num?)?.toInt() ?? 0,
      totalSinais: (map['total_sinais'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'mesma_pessoa': mesmaPessoa,
      'mesmo_mes': mesmoMes,
      'mesmo_local': mesmoLocal,
      'mesmo_titulo': mesmoTitulo,
      'mesma_categoria': mesmaCategoria,
      'mesmo_contexto': mesmoContexto,
      'datas_proximas': datasProximas,
      'total_pessoas_em_comum': totalPessoasEmComum,
      'total_sinais': totalSinais,
    };
  }
}

/// Candidata retornada pela RPC `buscar_candidatas_relacionamento`.
/// Contém os sinais pré-computados no servidor (pessoas em comum,
/// proximidade temporal, match de título). O client usa isso para
/// calcular o score fino.
class MemoriaCandidata {
  const MemoriaCandidata({
    required this.id,
    required this.titulo,
    this.categoria,
    this.dataEvento,
    this.criadaEm,
    required this.pessoasEmComum,
    this.diasDiferencaEvento,
    required this.mesmoTitulo,
  });

  final int id;
  final String titulo;
  final String? categoria;
  final DateTime? dataEvento;
  final DateTime? criadaEm;
  final int pessoasEmComum;
  final int? diasDiferencaEvento;
  final bool mesmoTitulo;

  factory MemoriaCandidata.fromMap(Map<String, dynamic> map) {
    return MemoriaCandidata(
      id: (map['id'] as num).toInt(),
      titulo: map['titulo'] as String? ?? '',
      categoria: map['categoria'] as String?,
      dataEvento: map['data_evento'] != null
          ? DateTime.tryParse('${map['data_evento']}')
          : null,
      criadaEm: map['criado_em'] != null
          ? DateTime.tryParse('${map['criado_em']}')
          : null,
      pessoasEmComum: (map['pessoas_em_comum'] as num? ?? 0).toInt(),
      diasDiferencaEvento: (map['dias_diferenca_evento'] as num?)?.toInt(),
      mesmoTitulo: map['mesmo_titulo'] == true,
    );
  }
}
