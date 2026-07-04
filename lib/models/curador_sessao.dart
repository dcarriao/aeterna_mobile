/// Sprint J — Modelos do Curador Contextual.
/// Sessões e histórico de mensagens persistidos no Supabase.

enum CuradorMensagemRole {
  user,
  assistant,
  system;

  String get valor => name;

  static CuradorMensagemRole fromValor(String? v) {
    switch (v) {
      case 'user':
        return CuradorMensagemRole.user;
      case 'system':
        return CuradorMensagemRole.system;
      case 'assistant':
      default:
        return CuradorMensagemRole.assistant;
    }
  }
}

/// Tipo da mensagem no contexto do Curador. Não vai ao LLM; é só
/// classificação client-side para a UI.
enum CuradorMensagemTipo {
  inicial, // primeira mensagem do usuário ao abrir o Curador
  pergunta, // pergunta feita pela IA
  resposta, // resposta do usuário a uma pergunta
  finalizacao, // pergunta "quer acrescentar mais?" da IA
  fechamento, // "não, pode encerrar" do usuário
}

class CuradorMensagem {
  const CuradorMensagem({
    this.id,
    required this.sessaoId,
    required this.role,
    required this.conteudo,
    required this.ordem,
    this.tipo,
    this.criadoEm,
  });

  final int? id;
  final int sessaoId;
  final CuradorMensagemRole role;
  final String conteudo;
  final int ordem;
  final CuradorMensagemTipo? tipo;
  final DateTime? criadoEm;

  factory CuradorMensagem.fromMap(Map<String, dynamic> map) {
    return CuradorMensagem(
      id: (map['id'] as num?)?.toInt(),
      sessaoId: (map['sessao_id'] as num).toInt(),
      role: CuradorMensagemRole.fromValor(map['role'] as String?),
      conteudo: map['conteudo'] as String? ?? '',
      ordem: (map['ordem'] as num).toInt(),
      tipo: _tipoFromString(map['tipo'] as String?),
      criadoEm: map['criado_em'] != null
          ? DateTime.tryParse('${map['criado_em']}')
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'sessao_id': sessaoId,
      'role': role.valor,
      'conteudo': conteudo,
      'ordem': ordem,
      if (tipo != null) 'tipo': tipo!.name,
    };
  }

  static CuradorMensagemTipo? _tipoFromString(String? v) {
    switch (v) {
      case 'inicial':
        return CuradorMensagemTipo.inicial;
      case 'pergunta':
        return CuradorMensagemTipo.pergunta;
      case 'resposta':
        return CuradorMensagemTipo.resposta;
      case 'finalizacao':
        return CuradorMensagemTipo.finalizacao;
      case 'fechamento':
        return CuradorMensagemTipo.fechamento;
      default:
        return null;
    }
  }
}

class CuradorSessao {
  const CuradorSessao({
    this.id,
    this.usuarioId,
    this.titulo,
    this.contextoInicial = '',
    this.contextoAtual = '',
    this.status = 'em_andamento',
    this.etapa = 'conversa',
    this.totalTurnos = 0,
    this.memoriaId,
    this.dataEvento,
    this.pessoas = const [],
    this.criadoEm,
    this.atualizadoEm,
  });

  final int? id;
  final int? usuarioId;
  final String? titulo;
  final String contextoInicial;
  final String contextoAtual;
  final String status; // 'em_andamento' | 'concluida' | 'cancelada'
  final String etapa;
  final int totalTurnos;
  final int? memoriaId;
  final DateTime? dataEvento;
  final List<Map<String, String>> pessoas;
  final DateTime? criadoEm;
  final DateTime? atualizadoEm;

  bool get emAndamento => status == 'em_andamento';
  bool get concluida => status == 'concluida';

  /// Resumo curto do estado atual para exibir no card "Continuar
  /// conversa" da Home.
  String get resumoParaCard {
    final total = totalTurnos;
    if (total == 0) {
      return 'Conversa recém-iniciada';
    }
    if (total == 1) {
      return '1 pergunta respondida';
    }
    return '$total perguntas respondidas';
  }

  factory CuradorSessao.fromMap(Map<String, dynamic> map) {
    final pessoasRaw = map['pessoas_json'];
    final pessoasList = <Map<String, String>>[];
    if (pessoasRaw is List) {
      for (final p in pessoasRaw) {
        if (p is Map) {
          pessoasList.add({
            'nome': (p['nome'] as String?) ?? '',
            'parentesco': (p['parentesco'] as String?) ?? 'Outro',
          });
        }
      }
    }
    return CuradorSessao(
      id: (map['sessao_id'] as num?)?.toInt() ?? (map['id'] as num?)?.toInt(),
      usuarioId: (map['usuario_id'] as num?)?.toInt(),
      titulo: map['titulo'] as String?,
      contextoInicial: map['contexto_inicial'] as String? ?? '',
      contextoAtual: map['contexto_atual'] as String? ?? '',
      status: map['status'] as String? ?? 'em_andamento',
      etapa: map['etapa'] as String? ?? 'conversa',
      totalTurnos: (map['total_turnos'] as num?)?.toInt() ?? 0,
      memoriaId: (map['memoria_id'] as num?)?.toInt(),
      dataEvento: map['data_evento'] != null
          ? DateTime.tryParse('${map['data_evento']}')
          : null,
      pessoas: pessoasList,
      criadoEm: map['criado_em'] != null
          ? DateTime.tryParse('${map['criado_em']}')
          : null,
      atualizadoEm: map['atualizado_em'] != null
          ? DateTime.tryParse('${map['atualizado_em']}')
          : null,
    );
  }
}
