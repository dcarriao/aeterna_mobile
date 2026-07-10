import 'dart:typed_data';

class Memorial {
  const Memorial({
    this.id,
    required this.nome,
    required this.parentesco,
    required this.dataNascimento,
    required this.dataFalecimento,
    required this.biografia,
    this.fotoUrl,
    this.fotoBytes,
    this.pessoaId,
    required this.usuarioId,
    required this.createdAt,
  });

  final int? id;
  final String nome;
  final String parentesco;
  final DateTime dataNascimento;
  final DateTime dataFalecimento;
  final String biografia;
  final String? fotoUrl;
  final Uint8List? fotoBytes;
  final int? pessoaId;
  final int usuarioId;
  final DateTime createdAt;

  factory Memorial.fromMap(Map<String, dynamic> map) {
    return Memorial(
      id: map['id'] as int?,
      nome: map['nome'] as String? ?? '',
      parentesco: map['parentesco'] as String? ?? '',
      dataNascimento: DateTime.tryParse(map['data_nascimento'] as String? ?? '') ?? DateTime.now(),
      dataFalecimento: DateTime.tryParse(map['data_falecimento'] as String? ?? '') ?? DateTime.now(),
      biografia: map['biografia'] as String? ?? '',
      fotoUrl: map['foto_perfil'] as String?,
      pessoaId: (map['pessoa_id'] as num?)?.toInt(),
      usuarioId: (map['usuario_id'] as num? ?? 0).toInt(),
      createdAt: DateTime.tryParse(map['criado_em'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'nome': nome,
      'parentesco': parentesco,
      'data_nascimento': '${dataNascimento.year}-${dataNascimento.month.toString().padLeft(2, '0')}-${dataNascimento.day.toString().padLeft(2, '0')}',
      'data_falecimento': '${dataFalecimento.year}-${dataFalecimento.month.toString().padLeft(2, '0')}-${dataFalecimento.day.toString().padLeft(2, '0')}',
      'biografia': biografia,
      if (fotoUrl != null) 'foto_perfil': fotoUrl,
      if (pessoaId != null) 'pessoa_id': pessoaId,
      'usuario_id': usuarioId,
      'criado_em': createdAt.toIso8601String(),
    };
  }
}
