import 'dart:typed_data';

class Contribuicao {
  const Contribuicao({
    this.id,
    required this.memorialId,
    required this.autor,
    required this.relacao,
    required this.conteudo,
    this.fotoUrl,
    this.fotoBytes,
    this.videoUrl,
    this.videoBytes,
    this.aprovado = false,
    required this.createdAt,
  });

  final int? id;
  final int memorialId;
  final String autor;
  final String relacao;
  final String conteudo;
  final String? fotoUrl;
  final Uint8List? fotoBytes;
  final String? videoUrl;
  final Uint8List? videoBytes;
  final bool aprovado;
  final DateTime createdAt;

  factory Contribuicao.fromMap(Map<String, dynamic> map) {
    return Contribuicao(
      id: map['id'] as int?,
      memorialId: (map['memorial_id'] as num? ?? 0).toInt(),
      autor: map['autor'] as String? ?? '',
      relacao: map['relacao'] as String? ?? '',
      conteudo: map['conteudo'] as String? ?? '',
      fotoUrl: map['foto_url'] as String?,
      videoUrl: map['video_url'] as String?,
      aprovado: map['aprovado'] as bool? ?? false,
      createdAt: DateTime.tryParse(map['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'memorial_id': memorialId,
      'autor': autor,
      'relacao': relacao,
      'conteudo': conteudo,
      if (fotoUrl != null) 'foto_url': fotoUrl,
      if (videoUrl != null) 'video_url': videoUrl,
      'aprovado': aprovado,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
