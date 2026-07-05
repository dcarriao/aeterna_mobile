class CofreItem {
  CofreItem({
    this.id,
    required this.titulo,
    required this.tipo,
    this.conteudo,
    this.urlArquivo,
    this.createdAt,
  });

  final int? id;
  String titulo;
  String tipo; // 'texto' | 'documento'
  String? conteudo;
  String? urlArquivo;
  DateTime? createdAt;

  factory CofreItem.fromMap(Map<String, dynamic> map) {
    return CofreItem(
      id: map['id'] as int?,
      titulo: map['titulo'] as String? ?? '',
      tipo: map['tipo'] as String? ?? 'texto',
      conteudo: map['conteudo'] as String?,
      urlArquivo: map['url_arquivo'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.tryParse(map['created_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'titulo': titulo,
        'tipo': tipo,
        if (conteudo != null) 'conteudo': conteudo,
        if (urlArquivo != null) 'url_arquivo': urlArquivo,
      };
}
