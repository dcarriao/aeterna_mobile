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
    this.temVideo = false,
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
  final bool temVideo;

  // Preenchidos para identificar o dono (pessoas.id = memorias.usuario_id).
  // Em memórias RECEBIDAS, compartilhadaPorNome também vem preenchido.
  final int? donoUsuarioId;
  final String? compartilhadaPorNome;

  /// True só quando veio de outra conta (share), não quando é memória própria
  /// com donoUsuarioId preenchido.
  bool get isRecebidaDeOutraConta => compartilhadaPorNome != null;

  factory Memoria.fromMap(
    Map<String, dynamic> map, {
    String? fotoUrl,
    String? videoUrl,
    bool temVideo = false,
    int? donoUsuarioId,
    String? compartilhadaPorNome,
  }) {
    final dataEventoStr = map['data_evento'] as String?;
    final dataEvento = dataEventoStr != null ? DateTime.tryParse(dataEventoStr) : null;
    final criadaEm = dataEvento ??
        DateTime.tryParse(map['data_criacao'] as String? ?? '') ??
        DateTime.now();

    return Memoria(
      id: map['id'] is num ? (map['id'] as num).toInt() : map['id'] as int?,
      titulo: map['titulo'] as String? ?? '',
      contexto: map['conteudo'] as String? ?? '',
      categoria: map['categoria'] as String? ?? 'momentos',
      criadaEm: criadaEm,
      fotoUrl: fotoUrl,
      videoUrl: videoUrl,
      temVideo: temVideo,
      dataMemoria: dataEvento,
      donoUsuarioId: donoUsuarioId ??
          (map['usuario_id'] is num
              ? (map['usuario_id'] as num).toInt()
              : map['usuario_id'] as int?),
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
