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
    this.video,
    this.videoUrl,
    this.donoUsuarioId,
    this.compartilhadaPorNome,
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
  final Uint8List? video;
  final String? videoUrl;

  // Preenchidos apenas para memórias RECEBIDAS de outra conta (Bug 1):
  // identifica o dono real da memória (pessoas.id) e seu nome, para exibir
  // "Compartilhado por Fulano" na tela Compartilhadas.
  final int? donoUsuarioId;
  final String? compartilhadaPorNome;

  bool get isRecebidaDeOutraConta => donoUsuarioId != null;

  factory Memoria.fromMap(
    Map<String, dynamic> map, {
    String? fotoUrl,
    int? donoUsuarioId,
    String? compartilhadaPorNome,
  }) {
    final dataEventoStr = map['data_evento'] as String?;
    final dataEvento = dataEventoStr != null ? DateTime.tryParse(dataEventoStr) : null;
    final criadaEm = dataEvento ??
        DateTime.tryParse(map['data_criacao'] as String? ?? '') ??
        DateTime.now();

    return Memoria(
      id: map['id'] as int?,
      titulo: map['titulo'] as String? ?? '',
      contexto: map['conteudo'] as String? ?? '',
      categoria: map['categoria'] as String? ?? 'momentos',
      criadaEm: criadaEm,
      fotoUrl: fotoUrl,
      dataMemoria: dataEvento,
      donoUsuarioId: donoUsuarioId,
      compartilhadaPorNome: compartilhadaPorNome,
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
    this.video,
    this.nomeVideo,
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
  final Uint8List? video;
  final String? nomeVideo;
}
