/// Convite real e bilateral entre contas (Sprint — Vínculos Familiares).
///
/// Diferente do "contato por e-mail" antigo (frágil: se o e-mail estivesse
/// errado ou a pessoa já tivesse conta, o vínculo nunca se formava), este
/// convite tem um ciclo de vida controlado: pendente -> aceito/recusado.
/// Quando aceito, gera um vínculo bilateral real (ver `PessoaRepository.
/// aceitarConviteFamiliar`).
class ConviteFamiliar {
  const ConviteFamiliar({
    this.id,
    required this.usuarioOrigemId,
    this.pessoaId,
    required this.emailDestino,
    this.usuarioDestinoId,
    this.status = 'pendente',
    this.token,
    this.papelSugerido,
    this.tipoConteudoAlvo,
    this.conteudoIdAlvo,
    required this.criadoEm,
    this.aceitoEm,
    this.nomeOrigem,
  });

  final int? id;
  final int usuarioOrigemId;
  final int? pessoaId;
  final String emailDestino;
  final int? usuarioDestinoId;

  /// 'pendente' | 'aceito' | 'recusado' | 'expirado'
  final String status;
  final String? token;

  /// Papel sugerido (editor/colaborador/leitor) caso o convite já nasça
  /// vinculado a um conteúdo específico (memorial/memória).
  final String? papelSugerido;
  final String? tipoConteudoAlvo;
  final int? conteudoIdAlvo;

  final DateTime criadoEm;
  final DateTime? aceitoEm;

  /// Preenchido apenas ao listar convites RECEBIDOS, para exibição
  /// ("Fulano convidou você").
  final String? nomeOrigem;

  bool get pendente => status == 'pendente';
  bool get aceito => status == 'aceito';
  bool get recusado => status == 'recusado';

  factory ConviteFamiliar.fromMap(Map<String, dynamic> map, {String? nomeOrigem}) {
    return ConviteFamiliar(
      id: (map['id'] as num?)?.toInt(),
      usuarioOrigemId: (map['usuario_origem_id'] as num? ?? 0).toInt(),
      pessoaId: (map['pessoa_id'] as num?)?.toInt(),
      emailDestino: map['email_destino'] as String? ?? '',
      usuarioDestinoId: (map['usuario_destino_id'] as num?)?.toInt(),
      status: map['status'] as String? ?? 'pendente',
      token: map['token'] as String?,
      papelSugerido: map['papel_sugerido'] as String?,
      tipoConteudoAlvo: map['tipo_conteudo_alvo'] as String?,
      conteudoIdAlvo: (map['conteudo_id_alvo'] as num?)?.toInt(),
      criadoEm: DateTime.tryParse('${map['criado_em']}') ?? DateTime.now(),
      aceitoEm: map['aceito_em'] != null
          ? DateTime.tryParse('${map['aceito_em']}')
          : null,
      nomeOrigem: nomeOrigem,
    );
  }
}

/// Papéis de colaboração suportados em conteúdo compartilhado (memória ou
/// memorial). "dono" não é um valor desta enum — é sempre inferido da coluna
/// `usuario_id` do próprio conteúdo (memorias.usuario_id/memoriais.usuario_id).
enum PapelColaborador {
  editor,
  colaborador,
  leitor;

  String get valor => name;

  static PapelColaborador? fromValor(String? valor) {
    switch (valor) {
      case 'editor':
        return PapelColaborador.editor;
      case 'colaborador':
        return PapelColaborador.colaborador;
      case 'leitor':
        return PapelColaborador.leitor;
      default:
        return null;
    }
  }

  String get rotulo {
    switch (this) {
      case PapelColaborador.editor:
        return 'Editor';
      case PapelColaborador.colaborador:
        return 'Colaborador';
      case PapelColaborador.leitor:
        return 'Leitor';
    }
  }

  String get descricao {
    switch (this) {
      case PapelColaborador.editor:
        return 'Pode alterar o conteúdo (ex.: biografia do memorial).';
      case PapelColaborador.colaborador:
        return 'Pode adicionar fotos, vídeos e histórias.';
      case PapelColaborador.leitor:
        return 'Pode apenas visualizar.';
    }
  }
}

/// Um familiar (conta real) vinculado bilateralmente ao usuário logado.
class VinculoFamiliar {
  const VinculoFamiliar({
    required this.usuarioId,
    required this.nome,
    this.fotoUrl,
    this.email,
  });

  final int usuarioId;
  final String nome;
  final String? fotoUrl;
  final String? email;
}

/// Um colaborador (conta real) com permissão concedida sobre um
/// conteúdo específico (memória ou memorial).
class Colaborador {
  const Colaborador({
    required this.usuarioId,
    required this.nome,
    required this.papel,
  });

  final int usuarioId;
  final String nome;
  final PapelColaborador papel;
}
