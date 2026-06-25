import 'dart:typed_data';

class Memoria {
  const Memoria({
    required this.titulo,
    required this.contexto,
    required this.categoria,
    required this.criadaEm,
    this.id,
    this.foto,
    this.fotoUrl,
    this.pessoasIds,
    this.isCompartilhada = false,
    this.familiaresIds,
    this.dataMemoria,
  });

  final int? id;
  final String titulo;
  final String contexto;
  final String categoria;
  final DateTime criadaEm;
  final Uint8List? foto;
  final String? fotoUrl;
  final List<int>? pessoasIds;
  final bool isCompartilhada;
  final List<int>? familiaresIds;
  final DateTime? dataMemoria;

  factory Memoria.fromMap(Map<String, dynamic> map, {String? fotoUrl}) {
    return Memoria(
      id: map['id'] as int?,
      titulo: map['titulo'] as String? ?? '',
      contexto: map['conteudo'] as String? ?? '',
      categoria: map['categoria'] as String? ?? 'momentos',
      criadaEm:
          DateTime.tryParse(map['data_criacao'] as String? ?? '') ??
          DateTime.now(),
      fotoUrl: fotoUrl,
    );
  }
}

class MemoriaRascunho {
  const MemoriaRascunho({
    required this.titulo,
    required this.contexto,
    required this.categoria,
    this.foto,
    this.nomeArquivo,
    this.pessoasIds,
    this.isCompartilhada = false,
    this.familiaresIds,
    this.dataMemoria,
  });

  final String titulo;
  final String contexto;
  final String categoria;
  final Uint8List? foto;
  final String? nomeArquivo;
  final List<int>? pessoasIds;
  final bool isCompartilhada;
  final List<int>? familiaresIds;
  final DateTime? dataMemoria;
}
