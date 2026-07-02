import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:supabase/supabase.dart';

class Pessoa {
  Pessoa({
    required this.nome,
    required this.parentesco,
    this.apelido,
    this.dataNascimento,
    this.fotoBase64,
    DateTime? createdAt,
    int? id,
  })  : id = id ?? DateTime.now().millisecondsSinceEpoch,
        createdAt = createdAt ?? DateTime.now();

  final int id;
  final String nome;
  final String? apelido;
  final String parentesco;
  final DateTime? dataNascimento;
  final String? fotoBase64;
  final DateTime createdAt;

  Uint8List? get fotoBytes {
    if (fotoBase64 == null || fotoBase64!.isEmpty) return null;
    if (fotoBase64!.startsWith('http')) return null;
    try {
      return base64Decode(fotoBase64!);
    } catch (_) {
      return null;
    }
  }

  String? get fotoUrl =>
      fotoBase64 != null && fotoBase64!.startsWith('http')
          ? fotoBase64
          : null;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'nome': nome,
      'apelido': apelido,
      'parentesco': parentesco,
      'dataNascimento': dataNascimento?.toIso8601String(),
      'fotoBase64': fotoBase64,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Pessoa.fromMap(Map<String, dynamic> map) {
    return Pessoa(
      id: map['id'] is int ? map['id'] as int : int.tryParse('${map['id']}'),
      nome: (map['nome'] as String?) ?? '',
      apelido: map['apelido'] as String?,
      parentesco: (map['parentesco'] as String?) ?? 'Outro',
      dataNascimento: map['data_nascimento'] != null
          ? DateTime.tryParse('${map['data_nascimento']}')
          : null,
      fotoBase64: (map['foto_perfil'] as String?) ?? (map['fotoBase64'] as String?),
      createdAt: map['data_criacao'] != null
          ? DateTime.tryParse('${map['data_criacao']}') ?? DateTime.now()
          : DateTime.now(),
    );
  }
}

class PessoaRepository {
  PessoaRepository._();

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfpvfljmnlgsqiqdxmka.supabase.co',
  );
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  
  // ID de usuário dinâmico para isolamento de dados
  static int usuarioId = 2;

  static bool get isConfigured => _anonKey.isNotEmpty;

  static SupabaseClient? _client;

  static SupabaseClient get _supabase {
    if (!isConfigured) {
      throw Exception('SUPABASE_ANON_KEY não configurada.');
    }
    return _client ??= SupabaseClient(_url, _anonKey);
  }

  static Future<int?> obterUsuarioIdPorEmail(String email) async {
    final anonMasked = _anonKey.length > 8 ? '${_anonKey.substring(0, 8)}...' : '(vazio)';
    print('[PessoaRepo] obterUsuarioIdPorEmail: email=$email');
    print('[PessoaRepo] SUPABASE_ANON_KEY: $anonMasked');
    if (!isConfigured) {
      print('[PessoaRepo] ALERTA: SUPABASE_ANON_KEY está vazia! Não é possível conectar ao Supabase.');
      return null;
    }
    try {
      final rows = await _supabase
          .from('usuarios')
          .select('id')
          .eq('email', email.trim().toLowerCase());
      if (rows.isEmpty) return null;
      return (rows.first['id'] as num).toInt();
    } catch (_) {
      return null;
    }
  }

  static Future<int?> autenticarUsuario(String email, String senha) async {
    if (!isConfigured) return null;
    try {
      final rows = await _supabase
          .from('usuarios')
          .select('id, senha_hash, salt')
          .eq('email', email.trim().toLowerCase());
      if (rows.isEmpty) return null;

      final user = rows.first;
      final uid = (user['id'] as num).toInt();
      final hashDb = user['senha_hash'] as String?;
      final salt = user['salt'] as String?;

      if (hashDb == null || salt == null) return null;

      // Calcular hash SHA-256 de (senha + salt)
      final bytes = utf8.encode(senha + salt);
      final hashCalculado = sha256.convert(bytes).toString();

      if (hashCalculado == hashDb) {
        return uid;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // ── CONTATOS (Supabase) ──

  static Future<List<Pessoa>> listar() async {
    if (!isConfigured) return [];

    print('[PessoaRepo] listar() -> consultando Supabase contatos');
    try {
      final rows = await _supabase
          .from('contatos')
          .select('id, nome, sobrenome, parentesco, data_nascimento, foto_perfil, data_criacao')
          .eq('usuario_id', usuarioId)
          .order('nome');
      print('[PessoaRepo] listar() -> ${rows.length} contatos recebidos');
      for (final r in rows) {
        print('[PessoaRepo]   contato: id=${r["id"]} nome=${r["nome"]} parentesco=${r["parentesco"]}');
      }
      return rows.map((r) => Pessoa.fromMap(r)).toList();
    } catch (e) {
      print('[PessoaRepo] listar() ERRO: $e');
      return [];
    }
  }

  static Future<void> salvar(Pessoa pessoa, {bool isUpdate = false}) async {
    if (!isConfigured) return;

    print('[PessoaRepo] salvar() isUpdate=$isUpdate nome=${pessoa.nome} id=${pessoa.id}');
    final data = <String, dynamic>{
      'usuario_id': usuarioId,
      'nome': pessoa.nome,
      'parentesco': pessoa.parentesco,
    };
    if (pessoa.apelido != null && pessoa.apelido!.isNotEmpty) {
      data['sobrenome'] = pessoa.apelido;
    }
    if (pessoa.dataNascimento != null) {
      data['data_nascimento'] =
          '${pessoa.dataNascimento!.year}-${pessoa.dataNascimento!.month.toString().padLeft(2, '0')}-${pessoa.dataNascimento!.day.toString().padLeft(2, '0')}';
    }

    try {
      if (isUpdate) {
        await _supabase
            .from('contatos')
            .update(data)
            .eq('id', pessoa.id);
        print('[PessoaRepo] salvar() -> update concluido');
      } else {
        data['data_criacao'] = pessoa.createdAt.toIso8601String();
        await _supabase.from('contatos').insert(data);
        print('[PessoaRepo] salvar() -> insert concluido');
      }
    } catch (e) {
      print('[PessoaRepo] salvar() ERRO: $e');
    }
  }

  static Future<void> remover(int pessoaId) async {
    if (!isConfigured) return;
    try {
      await _supabase.from('conteudo_permissoes').delete().eq('contato_id', pessoaId);
      await _supabase
          .from('contatos')
          .delete()
          .eq('id', pessoaId)
          .eq('usuario_id', usuarioId);
    } catch (_) {
      rethrow;
    }
  }

  static Future<void> limparVinculosMemoria(int memoriaId) async {
    if (!isConfigured) return;
    try {
      await _supabase
          .from('conteudo_permissoes')
          .delete()
          .eq('conteudo_id', memoriaId)
          .eq('tipo_conteudo', 'memoria');
    } catch (_) {}
  }

  static Future<void> atualizarMemoria({
    required int memoriaId,
    required String titulo,
    required String contexto,
    required String categoria,
    DateTime? dataEvento,
    bool? isCompartilhada,
  }) async {
    if (!isConfigured) return;
    final data = <String, dynamic>{
      'titulo': titulo,
      'conteudo': contexto,
      'categoria': categoria,
    };
    if (dataEvento != null) {
      data['data_evento'] =
          '${dataEvento.year}-${dataEvento.month.toString().padLeft(2, '0')}-${dataEvento.day.toString().padLeft(2, '0')}';
    }
    if (isCompartilhada != null) {
      data['visibilidade'] = isCompartilhada ? 'contatos' : 'privado';
    }
    await _supabase.from('memorias').update(data).eq('id', memoriaId);
  }

  static Future<String?> uploadFotoMemoria({
    required int memoriaId,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    await _supabase.storage.from('fotos').uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(
            contentType: nomeArquivo.endsWith('.png') ? 'image/png' : 'image/jpeg',
            upsert: false,
          ),
        );

    final publicUrl =
        _supabase.storage.from('fotos').getPublicUrl(caminho);

    final foto = await _supabase.from('fotos').insert({
      'usuario_id': usuarioId,
      'titulo': 'Foto da memória',
      'caminho_arquivo': publicUrl,
    }).select('id').single();

    final fotoId = (foto['id'] as num).toInt();

    await _supabase.from('memoria_fotos').insert({
      'memoria_id': memoriaId,
      'foto_id': fotoId,
    });

    return publicUrl;
  }

  static Future<void> removerFotosDaMemoria(int memoriaId) async {
    if (!isConfigured) return;
    final vinculos = await _supabase
        .from('memoria_fotos')
        .select('foto_id')
        .eq('memoria_id', memoriaId);
    for (final v in vinculos) {
      final fotoId = (v['foto_id'] as num).toInt();
      await _supabase.from('memoria_fotos').delete().eq('foto_id', fotoId);
      await _supabase.from('fotos').delete().eq('id', fotoId);
    }
  }

  static Future<String?> uploadVideoMemoria({
    required int memoriaId,
    required Uint8List bytes,
    required String nomeArquivo,
  }) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    try {
      await _supabase.storage.from('fotos').uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          );

      final publicUrl =
          _supabase.storage.from('fotos').getPublicUrl(caminho);

      final video = await _supabase.from('videos').insert({
        'usuario_id': usuarioId,
        'titulo': 'Vídeo da memória',
        'caminho_arquivo': publicUrl,
      }).select('id').single();

      final videoId = (video['id'] as num).toInt();

      await _supabase.from('memoria_videos').insert({
        'memoria_id': memoriaId,
        'video_id': videoId,
      });

      return publicUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<void> removerVideosDaMemoria(int memoriaId) async {
    if (!isConfigured) return;
    try {
      final vinculos = await _supabase
          .from('memoria_videos')
          .select('video_id')
          .eq('memoria_id', memoriaId);
      for (final v in vinculos) {
        final videoId = (v['video_id'] as num).toInt();
        await _supabase.from('memoria_videos').delete().eq('video_id', videoId);
        await _supabase.from('videos').delete().eq('id', videoId);
      }
    } catch (_) {}
  }

  // ── USUÁRIO (Supabase usuarios) ──

  static Future<Map<String, dynamic>?> obterUsuario() async {
    if (!isConfigured) return null;
    try {
      final rows = await _supabase
          .from('usuarios')
          .select('nome, sobrenome, email, telefone, data_nascimento, foto_perfil')
          .eq('id', usuarioId);
      if (rows.isEmpty) return null;
      return rows.first as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> salvarUsuario(Map<String, dynamic> data) async {
    if (!isConfigured) return;
    try {
      await _supabase.from('usuarios').update(data).eq('id', usuarioId);
    } catch (_) {}
  }

  static Future<String?> uploadFotoPerfil(Uint8List bytes, String nomeArquivo) async {
    if (!isConfigured) return null;

    final nomeSeguro = nomeArquivo.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'), '_',
    );
    final caminho =
        'usuario_$usuarioId/app_mobile/perfil_${DateTime.now().millisecondsSinceEpoch}_$nomeSeguro';

    try {
      await _supabase.storage.from('fotos').uploadBinary(
            caminho,
            bytes,
            fileOptions: FileOptions(
              contentType: nomeArquivo.endsWith('.png') ? 'image/png' : 'image/jpeg',
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage.from('fotos').getPublicUrl(caminho);
      await salvarUsuario({'foto_perfil': publicUrl});
      return publicUrl;
    } catch (_) {
      return null;
    }
  }

  static Future<void> excluirMemoriaCompleta(int memoriaId) async {
    if (!isConfigured) return;
    // 1. Remover fotos e mídias vinculadas
    await removerFotosDaMemoria(memoriaId);
    // 2. Remover vídeos vinculados
    await removerVideosDaMemoria(memoriaId);
    // 3. Limpar vínculos de contatos e compartilhamento
    await limparVinculosMemoria(memoriaId);
    // 4. Deletar o registro da memória em si
    await _supabase.from('memorias').delete().eq('id', memoriaId);
  }

  static Future<void> recuperarSenha(String email) async {
    if (!isConfigured) return;
    await _supabase.auth.resetPasswordForEmail(email);
  }

  static Future<String?> obterVideoDaMemoria(int? memoriaId) async {
    if (!isConfigured || memoriaId == null) return null;
    try {
      final rows = await _supabase
          .from('memoria_videos')
          .select('video_id')
          .eq('memoria_id', memoriaId);
      if (rows.isEmpty) return null;
      final videoId = (rows.first['video_id'] as num).toInt();
      final videoRows = await _supabase
          .from('videos')
          .select('caminho_arquivo')
          .eq('id', videoId);
      if (videoRows.isEmpty) return null;
      return videoRows.first['caminho_arquivo'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> atualizarVisibilidadeMemoria(
    int memoriaId,
    bool isCompartilhada,
  ) async {
    if (!isConfigured) return;
    await _supabase
        .from('memorias')
        .update({'visibilidade': isCompartilhada ? 'contatos' : 'privado'})
        .eq('id', memoriaId);
  }

  // ── VÍNCULOS (Supabase conteudo_permissoes) ──

  static Future<Map<int, List<int>>> listarVinculos() async {
    if (!isConfigured) return {};

    try {
      final rows = await _supabase
          .from('conteudo_permissoes')
          .select('conteudo_id, contato_id')
          .eq('tipo_conteudo', 'memoria');
      final map = <int, List<int>>{};
      for (final r in rows) {
        final memId = (r['conteudo_id'] as num).toInt();
        final contatoId = (r['contato_id'] as num).toInt();
        map.putIfAbsent(memId, () => []).add(contatoId);
      }
      return map;
    } catch (_) {
      return {};
    }
  }

  static Future<void> salvarVinculo(int memoriaId, List<int> pessoaIds) async {
    if (!isConfigured) return;
    await _supabase
        .from('conteudo_permissoes')
        .delete()
        .eq('conteudo_id', memoriaId)
        .eq('tipo_conteudo', 'memoria');
    for (final contatoId in pessoaIds) {
      await _supabase.from('conteudo_permissoes').insert({
        'tipo_conteudo': 'memoria',
        'conteudo_id': memoriaId,
        'contato_id': contatoId,
      });
    }
  }

  static Future<List<int>> obterPessoasDaMemoria(int? memoriaId) async {
    if (memoriaId == null) return [];
    final vinculos = await listarVinculos();
    return vinculos[memoriaId] ?? [];
  }

  // ── COMPARTILHAMENTO = VÍNCULOS (mesma tabela conteudo_permissoes) ──

  static Future<Map<int, List<int>>> listarCompartilhamentos() =>
      listarVinculos();

  static Future<void> salvarCompartilhamento(
    int memoriaId,
    List<int> familiaresIds,
  ) =>
      salvarVinculo(memoriaId, familiaresIds);

  static Future<List<int>> obterFamiliaresDaMemoria(int? memoriaId) =>
      obterPessoasDaMemoria(memoriaId);

  // ── DATAS DE MEMÓRIA (Supabase memorias.data_evento) ──

  static Future<void> salvarDataMemoria(int memoriaId, DateTime data) async {
    if (!isConfigured) return;
    final dateStr =
        '${data.year}-${data.month.toString().padLeft(2, '0')}-${data.day.toString().padLeft(2, '0')}';
    await _supabase
        .from('memorias')
        .update({'data_evento': dateStr})
        .eq('id', memoriaId);
  }

  static Future<Map<int, DateTime>> carregarDatasMemorias() async {
    if (!isConfigured) return {};
    try {
      final rows = await _supabase
          .from('memorias')
          .select('id, data_evento')
          .not('data_evento', 'is', null);
      final result = <int, DateTime>{};
      for (final r in rows) {
        final dt = DateTime.tryParse('${r['data_evento']}');
        if (dt != null) result[(r['id'] as num).toInt()] = dt;
      }
      return result;
    } catch (_) {
      return {};
    }
  }
}

const parentescos = [
  'Pai',
  'Mãe',
  'Avô',
  'Avó',
  'Bisavô',
  'Bisavó',
  'Irmão',
  'Irmã',
  'Filho',
  'Filha',
  'Tio',
  'Tia',
  'Primo',
  'Prima',
  'Amigo',
  'Outro',
];
