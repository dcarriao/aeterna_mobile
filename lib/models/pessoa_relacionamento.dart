/// Sprint L — Modelos do grafo pessoa-pessoa.

/// Status de uma relação pessoa-pessoa.
enum RelacionamentoPessoaStatus {
  /// Foi confirmada (ou criada via trigger de compatibilidade).
  ativo,

  /// O usuário marcou como "não tenho certeza" (sai do grafo).
  pendente,

  /// O usuário marcou como "ex-irmão" / "falecido" (mantém histórico
  /// mas sai da visualização padrão).
  inativo,
}

/// Uma relação entre duas pessoas. Espelha a tabela
/// `pessoas_relacionamentos` do Supabase. Note que a relação é
/// simétrica por design: existe 1 linha por par (A, B) e tipo,
/// com rótulos explícitos por direção (`relacaoA`, `relacaoB`).
class PessoaRelacionamento {
  const PessoaRelacionamento({
    this.id,
    required this.usuarioId,
    required this.pessoaAId,
    required this.pessoaBId,
    required this.tipo,
    required this.relacaoA,
    required this.relacaoB,
    this.confirmado = true,
    this.observacoes,
    this.dataInicio,
    this.dataFim,
    this.criadoEm,
    this.atualizadoEm,
    this.nomeA,
    this.nomeB,
  });

  final int? id;
  final int usuarioId;
  final int pessoaAId;
  final int pessoaBId;
  final String tipo;
  final String relacaoA;
  final String relacaoB;
  final bool confirmado;
  final String? observacoes;
  final DateTime? dataInicio;
  final DateTime? dataFim;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  // Campos opcionais preenchidos quando o resultado vem do join com
  // `contatos` (para a UI).
  final String? nomeA;
  final String? nomeB;

  /// O ID da "outra pessoa" na direção `pessoaReferenciaId`.
  /// Usado pela UI para navegar para o detalhe da pessoa.
  int outraPessoaId(int pessoaReferenciaId) {
    return pessoaReferenciaId == pessoaAId ? pessoaBId : pessoaAId;
  }

  /// Rótulo que a pessoa em `pessoaReferenciaId` daria para a outra.
  String rotuloPara(int pessoaReferenciaId) {
    if (pessoaReferenciaId == pessoaAId) return relacaoA;
    return relacaoB;
  }

  /// Rótulo que a OUTRA pessoa daria para a pessoa em
  /// `pessoaReferenciaId`.
  String rotuloDe(int pessoaReferenciaId) {
    if (pessoaReferenciaId == pessoaAId) return relacaoB;
    return relacaoA;
  }

  factory PessoaRelacionamento.fromMap(Map<String, dynamic> map) {
    return PessoaRelacionamento(
      id: (map['id'] as num?)?.toInt(),
      usuarioId: (map['usuario_id'] as num? ?? 0).toInt(),
      pessoaAId: (map['pessoa_a_id'] as num? ?? 0).toInt(),
      pessoaBId: (map['pessoa_b_id'] as num? ?? 0).toInt(),
      tipo: map['tipo'] as String? ?? 'OUTRO',
      relacaoA: map['relacao_a_para_b'] as String? ?? 'Conhecido(a)',
      relacaoB: map['relacao_b_para_a'] as String? ?? 'Conhecido(a)',
      confirmado: map['confirmado'] as bool? ?? true,
      observacoes: map['observacoes'] as String?,
      dataInicio: map['data_inicio'] != null
          ? DateTime.tryParse('${map['data_inicio']}')
          : null,
      dataFim: map['data_fim'] != null
          ? DateTime.tryParse('${map['data_fim']}')
          : null,
      criadoEm: map['criado_em'] != null
          ? DateTime.tryParse('${map['criado_em']}')
          : null,
      atualizadoEm: map['atualizado_em'] != null
          ? DateTime.tryParse('${map['atualizado_em']}')
          : null,
      nomeA: map['nome_a'] as String?,
      nomeB: map['nome_b'] as String?,
    );
  }
}

/// O nó "outra pessoa" que aparece na seção Família da
/// PessoaDetalheScreen. Resultado de `listar_relacionamentos_pessoa`.
class OutraPessoaNaFamilia {
  const OutraPessoaNaFamilia({
    required this.relacionamentoId,
    required this.outraPessoaId,
    required this.outraPessoaNome,
    required this.tipo,
    required this.rotuloDaOutraParaMim,
    required this.rotuloDeMimParaAOutra,
    this.observacoes,
    this.dataInicio,
    this.dataFim,
  });

  final int relacionamentoId;
  final int outraPessoaId;
  final String outraPessoaNome;
  final String tipo;
  final String rotuloDaOutraParaMim;
  final String rotuloDeMimParaAOutra;
  final String? observacoes;
  final DateTime? dataInicio;
  final DateTime? dataFim;

  factory OutraPessoaNaFamilia.fromMap(Map<String, dynamic> map) {
    return OutraPessoaNaFamilia(
      relacionamentoId: (map['relacionamento_id'] as num).toInt(),
      outraPessoaId: (map['outra_pessoa_id'] as num).toInt(),
      outraPessoaNome: map['outra_pessoa_nome'] as String? ?? '',
      tipo: map['tipo'] as String? ?? 'OUTRO',
      rotuloDaOutraParaMim:
          map['rotulo_da_outra_para_mim'] as String? ?? 'Conhecido(a)',
      rotuloDeMimParaAOutra:
          map['rotulo_de_mim_para_outra'] as String? ?? 'Conhecido(a)',
      observacoes: map['observacoes'] as String?,
      dataInicio: map['data_inicio'] != null
          ? DateTime.tryParse('${map['data_inicio']}')
          : null,
      dataFim: map['data_fim'] != null
          ? DateTime.tryParse('${map['data_fim']}')
          : null,
    );
  }
}
