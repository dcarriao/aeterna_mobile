class MensagemFuturo {
  MensagemFuturo({
    this.id,
    required this.titulo,
    required this.conteudo,
    this.dataAgendamento,
    this.entregue = false,
    this.createdAt,
  });

  final int? id;
  String titulo;
  String conteudo;
  DateTime? dataAgendamento;
  bool entregue;
  DateTime? createdAt;

  factory MensagemFuturo.fromMap(Map<String, dynamic> map) {
    return MensagemFuturo(
      id: map['id'] as int?,
      titulo: map['titulo'] as String? ?? '',
      conteudo: map['conteudo'] as String? ?? '',
      dataAgendamento: map['data_agendamento'] != null
          ? DateTime.tryParse(map['data_agendamento'] as String)
          : null,
      entregue: map['entregue'] as bool? ?? false,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'titulo': titulo,
        'conteudo': conteudo,
        'data_agendamento': dataAgendamento?.toIso8601String(),
        'entregue': entregue,
      };
}
