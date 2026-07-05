class QuemSouEuRegistro {
  QuemSouEuRegistro({
    this.id,
    required this.perguntaChave,
    required this.resposta,
    this.createdAt,
    this.updatedAt,
  });

  final int? id;
  String perguntaChave;
  String resposta;
  DateTime? createdAt;
  DateTime? updatedAt;

  factory QuemSouEuRegistro.fromMap(Map<String, dynamic> map) {
    return QuemSouEuRegistro(
      id: map['id'] as int?,
      perguntaChave: map['pergunta_chave'] as String? ?? '',
      resposta: map['resposta'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.tryParse(map['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'pergunta_chave': perguntaChave,
        'resposta': resposta,
      };
}
