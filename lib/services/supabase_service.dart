import 'dart:typed_data';

import 'package:supabase/supabase.dart';

import '../models/memoria.dart';
import '../models/memorial.dart';
import '../models/contribuicao.dart';

class SupabaseService {
  SupabaseService._();

  static final instance = SupabaseService._();

  static const _url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://zfpvfljmnlgsqiqdxmka.supabase.co',
  );
  static const _anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
  static const _bucketFotos = 'fotos';

  // ID de usuário dinâmico para isolamento de dados
  static int usuarioId = 2;

  bool get isConfigured => _anonKey.isNotEmpty;

  SupabaseClient? _supabaseClient;

  SupabaseClient get _client {
    if (!isConfigured) {
      throw const SupabaseConfigurationException();
    }
    return _supabaseClient ??= SupabaseClient(_url, _anonKey);
  }

  static Future<void> initialize() async {
    final anonMasked = _anonKey.length > 8 ? '${_anonKey.substring(0, 8)}...' : '(vazio)';
    print('[Supabase] Inicializando SupabaseService...');
    print('[Supabase] URL: $_url');
    print('[Supabase] ANON_KEY: $anonMasked');
    if (!instance.isConfigured) {
      print('[Supabase] ALERTA: SUPABASE_ANON_KEY está vazia! O app funcionará em modo offline.');
    }
    if (!instance.isConfigured) return;
    instance._supabaseClient = SupabaseClient(_url, _anonKey);
  }

  Future<List<Memoria>> listarMemorias() async {
    if (!isConfigured) return const [];

    final memoriaRows = await _client
        .from('memorias')
        .select('id, titulo, conteudo, categoria, data_criacao, data_evento')
        .eq('usuario_id', usuarioId)
        .order('data_criacao', ascending: false);

    if (memoriaRows.isEmpty) return const [];

    final memoriaIds = memoriaRows.map<int>((row) => row['id'] as int).toList();
    final vinculoRows = await _client
        .from('memoria_fotos')
        .select('memoria_id, foto_id')
        .inFilter('memoria_id', memoriaIds);

    final fotoPorMemoria = <int, String>{};
    if (vinculoRows.isNotEmpty) {
      final fotoIds = vinculoRows
          .map<int>((row) => row['foto_id'] as int)
          .toSet()
          .toList();
      final fotoRows = await _client
          .from('fotos')
          .select('id, caminho_arquivo')
          .inFilter('id', fotoIds);
      final urlsPorFoto = <int, String>{
        for (final row in fotoRows)
          if (row['caminho_arquivo'] != null)
            row['id'] as int: row['caminho_arquivo'] as String,
      };

      for (final vinculo in vinculoRows) {
        final url = urlsPorFoto[vinculo['foto_id'] as int];
        if (url != null) {
          fotoPorMemoria.putIfAbsent(vinculo['memoria_id'] as int, () => url);
        }
      }
    }

    return memoriaRows.map<Memoria>((row) {
      final id = row['id'] as int;
      return Memoria.fromMap(row, fotoUrl: fotoPorMemoria[id]);
    }).toList();
  }

  Future<Memoria> salvarMemoriaComFoto(MemoriaRascunho rascunho) async {
    if (!isConfigured) {
      return Memoria(
        titulo: rascunho.titulo,
        contexto: rascunho.contexto,
        categoria: rascunho.categoria,
        criadaEm: DateTime.now(),
        foto: rascunho.foto,
      );
    }

    final agora = DateTime.now();
    int? memoriaId;
    int? fotoId;
    String? caminhoStorage;

    try {
      final memoria = await _client
          .from('memorias')
          .insert({
            'usuario_id': usuarioId,
            'categoria': rascunho.categoria,
            'titulo': rascunho.titulo,
            'conteudo': rascunho.contexto,
            'origem': 'app_mobile',
            'data_criacao': agora.toIso8601String(),
          })
          .select('id')
          .single();
      memoriaId = memoria['id'] as int;

      String? publicUrl;
      if (rascunho.foto != null) {
        caminhoStorage = _criarCaminhoArquivo(
          agora,
          rascunho.nomeArquivo ?? 'foto.jpg',
        );
        await _uploadFoto(
          caminho: caminhoStorage,
          bytes: rascunho.foto!,
          nomeArquivo: rascunho.nomeArquivo,
        );
        publicUrl = _client.storage
            .from(_bucketFotos)
            .getPublicUrl(caminhoStorage);

        final foto = await _client
            .from('fotos')
            .insert({
              'usuario_id': usuarioId,
              'titulo': rascunho.titulo,
              'descricao': rascunho.contexto,
              'categoria': rascunho.categoria,
              'caminho_arquivo': publicUrl,
              'data_criacao': agora.toIso8601String(),
            })
            .select('id')
            .single();
        fotoId = foto['id'] as int;

        await _client.from('memoria_fotos').insert({
          'memoria_id': memoriaId,
          'foto_id': fotoId,
        });
      }

      return Memoria(
        id: memoriaId,
        titulo: rascunho.titulo,
        contexto: rascunho.contexto,
        categoria: rascunho.categoria,
        criadaEm: agora,
        foto: rascunho.foto,
        fotoUrl: publicUrl,
      );
    } catch (_) {
      await _rollback(
        memoriaId: memoriaId,
        fotoId: fotoId,
        caminhoStorage: caminhoStorage,
      );
      rethrow;
    }
  }

  Future<void> _uploadFoto({
    required String caminho,
    required Uint8List bytes,
    String? nomeArquivo,
  }) async {
    await _client.storage
        .from(_bucketFotos)
        .uploadBinary(
          caminho,
          bytes,
          fileOptions: FileOptions(
            contentType: _contentType(nomeArquivo),
            upsert: false,
          ),
        );
  }

  String _criarCaminhoArquivo(DateTime data, String nomeOriginal) {
    final nomeSeguro = nomeOriginal.toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9._-]'),
      '_',
    );
    return 'usuario_$usuarioId/app_mobile/'
        '${data.microsecondsSinceEpoch}_$nomeSeguro';
  }

  String _contentType(String? nomeArquivo) {
    final nome = nomeArquivo?.toLowerCase() ?? '';
    if (nome.endsWith('.png')) return 'image/png';
    if (nome.endsWith('.webp')) return 'image/webp';
    if (nome.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _rollback({
    int? memoriaId,
    int? fotoId,
    String? caminhoStorage,
  }) async {
    try {
      if (memoriaId != null && fotoId != null) {
        await _client
            .from('memoria_fotos')
            .delete()
            .eq('memoria_id', memoriaId)
            .eq('foto_id', fotoId);
      }
      if (fotoId != null) {
        await _client.from('fotos').delete().eq('id', fotoId);
      }
      if (memoriaId != null) {
        await _client.from('memorias').delete().eq('id', memoriaId);
      }
      if (caminhoStorage != null) {
        await _client.storage.from(_bucketFotos).remove([caminhoStorage]);
      }
    } catch (_) {
      // Mantém o erro original; políticas RLS podem impedir a limpeza.
    }
  }

  // ── MEMORIAIS (Supabase) ──

  Future<List<Memorial>> listarMemoriais() async {
    if (!isConfigured) return const [];
    try {
      final rows = await _client
          .from('memoriais')
          .select('id, nome, parentesco, data_nascimento, data_falecimento, biografia, foto_perfil, contato_id, usuario_id, criado_em')
          .eq('usuario_id', usuarioId)
          .order('criado_em', ascending: false);
      return rows.map<Memorial>((row) => Memorial.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar memoriais: $e');
      return const [];
    }
  }

  Future<Memorial> salvarMemorial(Memorial memorial) async {
    if (!isConfigured) return memorial;
    final agora = DateTime.now();
    String? publicUrl = memorial.fotoUrl;

    if (memorial.fotoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'memorial_${agora.millisecondsSinceEpoch}.jpg',
      );
      await _uploadFoto(
        caminho: caminhoStorage,
        bytes: memorial.fotoBytes!,
        nomeArquivo: 'foto.jpg',
      );
      publicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    }

    final data = memorial.toMap();
    if (publicUrl != null) {
      data['foto_perfil'] = publicUrl;
    }

    final row = await _client
        .from('memoriais')
        .insert(data)
        .select('id, nome, parentesco, data_nascimento, data_falecimento, biografia, foto_perfil, contato_id, usuario_id, criado_em')
        .single();

    return Memorial.fromMap(row);
  }

  Future<void> excluirMemorial(int id) async {
    if (!isConfigured) return;
    try {
      await _client.from('contribuicoes').delete().eq('memorial_id', id);
    } catch (_) {}
    try {
      await _client.from('memoriais').delete().eq('id', id);
    } catch (_) {}
  }

  // ── CONTRIBUIÇÕES (Supabase) ──

  Future<List<Contribuicao>> listarContribuicoes(int memorialId, {bool apenasAprovadas = false}) async {
    if (!isConfigured) return const [];
    try {
      var query = _client
          .from('contribuicoes')
          .select('id, memorial_id, autor, relacao, conteudo, foto_url, video_url, aprovado, created_at')
          .eq('memorial_id', memorialId);
      
      if (apenasAprovadas) {
        query = query.eq('aprovado', true);
      }
      
      final rows = await query.order('created_at', ascending: false);
      return rows.map<Contribuicao>((row) => Contribuicao.fromMap(row)).toList();
    } catch (e) {
      print('Erro ao listar contribuicoes: $e');
      return const [];
    }
  }

  Future<Contribuicao> salvarContribuicao(Contribuicao contribuicao) async {
    if (!isConfigured) return contribuicao;
    final agora = DateTime.now();
    String? fotoPublicUrl = contribuicao.fotoUrl;
    String? videoPublicUrl = contribuicao.videoUrl;

    if (contribuicao.fotoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'contrib_foto_${agora.millisecondsSinceEpoch}.jpg',
      );
      await _uploadFoto(
        caminho: caminhoStorage,
        bytes: contribuicao.fotoBytes!,
        nomeArquivo: 'foto.jpg',
      );
      fotoPublicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    }

    if (contribuicao.videoBytes != null) {
      final caminhoStorage = _criarCaminhoArquivo(
        agora,
        'contrib_video_${agora.millisecondsSinceEpoch}.mp4',
      );
      await _client.storage.from(_bucketFotos).uploadBinary(
        caminhoStorage,
        contribuicao.videoBytes!,
        fileOptions: const FileOptions(contentType: 'video/mp4'),
      );
      videoPublicUrl = _client.storage
          .from(_bucketFotos)
          .getPublicUrl(caminhoStorage);
    }

    final data = contribuicao.toMap();
    if (fotoPublicUrl != null) data['foto_url'] = fotoPublicUrl;
    if (videoPublicUrl != null) data['video_url'] = videoPublicUrl;

    final row = await _client
        .from('contribuicoes')
        .insert(data)
        .select('id, memorial_id, autor, relacao, conteudo, foto_url, video_url, aprovado, created_at')
        .single();

    return Contribuicao.fromMap(row);
  }

  Future<void> moderarContribuicao(int id, bool aprovado) async {
    if (!isConfigured) return;
    try {
      if (aprovado) {
        await _client.from('contribuicoes').update({'aprovado': true}).eq('id', id);
      } else {
        await _client.from('contribuicoes').delete().eq('id', id);
      }
    } catch (e) {
      print('Erro ao moderar contribuicao: $e');
    }
  }
}

class SupabaseConfigurationException implements Exception {
  const SupabaseConfigurationException();

  @override
  String toString() => 'SUPABASE_ANON_KEY não configurada.';
}
