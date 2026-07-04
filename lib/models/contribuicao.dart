import 'dart:typed_data';

/// Representa uma contribuição de terceiros a um memorial (foto, vídeo ou
/// texto de homenagem).
///
/// IMPORTANTE (correção de bug estrutural): os campos deste model foram
/// reescritos para corresponder ao schema REAL da tabela `contribuicoes`
/// no Supabase de produção (criada por `D:\aeterna\utils\migrar_contribuicoes.py`
/// e `migrar_contribuicoes_midia.py`), que é diferente do schema que este
/// model usava antes (autor/relacao/conteudo/foto_url/video_url/aprovado/
/// created_at — colunas que NÃO existem na tabela real). Antes desta
/// correção, qualquer tentativa de enviar uma contribuição pelo app mobile
/// falhava contra o Supabase real.
class Contribuicao {
  const Contribuicao({
    this.id,
    this.memorialId,
    required this.tipoConteudo,
    required this.conteudoId,
    required this.usuarioDonoId,
    required this.usuarioContribuidorEmail,
    required this.usuarioContribuidorNome,
    required this.tipoContribuicao,
    this.texto,
    this.arquivoUrl,
    this.fotoBytes,
    this.videoBytes,
    this.status = 'pendente',
    required this.createdAt,
    this.avaliadoEm,
    this.avaliadoPor,
  });

  final int? id;

  /// FK dedicada para o memorial (coluna adicionada por `migrar_memoriais.py`).
  final int? memorialId;

  /// 'memoria' | 'foto' | 'video' | 'memorial' (FK polimórfica genérica,
  /// mesma convenção de `conteudo_permissoes`/`conteudo_colaboradores`).
  final String tipoConteudo;
  final int conteudoId;

  /// Dono do conteúdo/memorial que está sendo enriquecido.
  final int usuarioDonoId;

  /// Identidade real de quem contribuiu (conta logada no app — não é mais
  /// texto livre, evita contribuições anônimas/não rastreáveis).
  final String usuarioContribuidorEmail;
  final String usuarioContribuidorNome;

  /// 'texto' | 'foto' | 'video'
  final String tipoContribuicao;
  final String? texto;
  final String? arquivoUrl;

  // Apenas para upload local antes de virar `arquivoUrl`.
  final Uint8List? fotoBytes;
  final Uint8List? videoBytes;

  /// 'pendente' | 'aprovado' | 'rejeitado'
  final String status;
  final DateTime createdAt;
  final DateTime? avaliadoEm;
  final int? avaliadoPor;

  bool get aprovado => status == 'aprovado';
  bool get pendente => status == 'pendente';
  bool get rejeitado => status == 'rejeitado';

  factory Contribuicao.fromMap(Map<String, dynamic> map) {
    return Contribuicao(
      id: map['id'] as int?,
      memorialId: (map['memorial_id'] as num?)?.toInt(),
      tipoConteudo: map['tipo_conteudo'] as String? ?? 'memorial',
      conteudoId: (map['conteudo_id'] as num? ?? 0).toInt(),
      usuarioDonoId: (map['usuario_dono_id'] as num? ?? 0).toInt(),
      usuarioContribuidorEmail:
          map['usuario_contribuidor_email'] as String? ?? '',
      usuarioContribuidorNome:
          map['usuario_contribuidor_nome'] as String? ?? 'Familiar',
      tipoContribuicao: map['tipo_contribuicao'] as String? ?? 'texto',
      texto: map['texto'] as String?,
      arquivoUrl: map['arquivo_url'] as String?,
      status: map['status'] as String? ?? 'pendente',
      createdAt:
          DateTime.tryParse(map['criado_em'] as String? ?? '') ?? DateTime.now(),
      avaliadoEm: map['avaliado_em'] != null
          ? DateTime.tryParse('${map['avaliado_em']}')
          : null,
      avaliadoPor: (map['avaliado_por'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (memorialId != null) 'memorial_id': memorialId,
      'tipo_conteudo': tipoConteudo,
      'conteudo_id': conteudoId,
      'usuario_dono_id': usuarioDonoId,
      'usuario_contribuidor_email': usuarioContribuidorEmail,
      'usuario_contribuidor_nome': usuarioContribuidorNome,
      'tipo_contribuicao': tipoContribuicao,
      if (texto != null) 'texto': texto,
      if (arquivoUrl != null) 'arquivo_url': arquivoUrl,
      'status': status,
      'criado_em': createdAt.toIso8601String(),
    };
  }
}
